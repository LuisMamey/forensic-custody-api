# Phase 2 Case File — Supply Chain, Policy as Code, and DAST

Continuation of [PHASE1_HISTORY.md](PHASE1_HISTORY.md), covering the three Phase 2 sprints: Supply Chain Security (SBOM + signing), Policy as Code (custom Rego rules), and DAST (attacking the running API). Exhibit numbering continues from Phase 1 (which ended at 9).

---

## Sprint 1 — Supply Chain Security

**A workflow ordering bug caught before it ever ran, not after:** the first draft of `.github/workflows/supply-chain.yml` pushed the image to GHCR *before* running the Syft/Grype gate — meaning a vulnerable image would already be public by the time anything checked it. Caught on review, not in a failed run: Syft can read a locally-built image directly, without it being published first, so there was never a reason to publish before scanning. Fixed by reordering: build → SBOM → scan (gate) → push → sign.

### Exhibit 10 — Syft

**Role:** generates a Software Bill of Materials (SBOM) from the built Docker image.

Created by **Anchore**, a container security company (founded ~2016), released open source alongside its sibling tool Grype around 2019-2020 — lighter, simpler alternatives to Anchore's full enterprise product, built to drop into any CI pipeline.

**Why here:** points at the image and produces a complete inventory (every OS package, every Go module, exact versions) in a standard format (CycloneDX, chosen for its stronger tooling support for vulnerability scanning downstream).

**Real problem caught along the way:** the local image tagged `:latest` was stale — `stdlib go1.26.7` showed up instead of 1.27.x, because the image was never rebuilt after the Dockerfile's Go version fix from Phase 1. Rebuilt before generating the real SBOM.

---

### Exhibit 11 — Grype

**Role:** scans the SBOM for known vulnerabilities.

Also from Anchore, Grype's job is to compare a SBOM (or an image directly) against a vulnerability database — same category as Trivy, but working from a pre-generated SBOM instead of the image itself.

**Result:** 0 vulnerabilities — but with an important caveat exposed by a `WARN` in the output: *"go binary packages were found but none carry function symbols; go vulnerability matching falls back to module granularity."* This means Grype, for Go binaries specifically, has the **same precision limit as Trivy** — it can't confirm whether a vulnerable function is actually called, unlike Govulncheck's call-graph analysis. Real, live proof of why Govulncheck stays necessary even with Syft/Grype in the pipeline.

---

### Exhibit 12 — Cosign

**Role:** signs the image and its SBOM without ever handling a private key.

Created by **Sigstore** (backed by Google, Red Hat, and the Linux Foundation, ~2021), to solve the classic code-signing problem: a long-lived private key is something you have to protect forever, and if it leaks, everything signed with it is suspect.

**How keyless signing actually works, step by step:**
1. The CI job generates a fresh key pair in memory, used once, never saved to disk.
2. It asks **Fulcio** (Sigstore's certificate authority) for a certificate, proving its identity with the OIDC token GitHub Actions already issued it — cryptographically signed by GitHub, verified by Fulcio against GitHub's own published public keys.
3. Fulcio issues a certificate binding that ephemeral key to a specific identity (this repo, this workflow, this ref) — valid for minutes.
4. Cosign signs the image digest with that key.
5. The signature, certificate, and a record of the whole exchange go into **Rekor**, a public, append-only, tamper-evident log — permanently.
6. The key is discarded immediately.

**Verified externally, as a real outside party would:** made the GHCR package public, then ran `cosign verify` with the exact expected identity (`--certificate-identity-regexp` + `--certificate-oidc-issuer`) — it printed the full certificate, matching the repo, workflow, and commit exactly, and confirmed the digest matched the one `docker pull` reported. Also confirmed the failure mode: verifying a tag that was never published by the real pipeline (`:latest`, `:prueba-sin-firma`) fails outright — nothing that skips the real CI can produce a valid signature.

---

## Sprint 2 — Policy as Code

### Exhibit 13 — OPA & Rego

**Role:** the policy engine and language underneath Conftest.

**OPA (Open Policy Agent)** was created by **Styra** (Torin Sandall and Tim Hinrichs, ~2016) and donated to the CNCF, where it became one of the most successful graduated projects — used for API authorization, Kubernetes admission control, and CI/CD gates, not just IaC. **Rego** is its declarative language for reasoning over structured (JSON-like) data.

**Real syntax lesson:** the OPA engine bundled with Conftest (1.20.2) defaults to **Rego v1**, which requires explicit `if` and `contains` keywords. The older `deny[msg] { ... }` form fails to parse — the correct form is `deny contains msg if { ... }`.

---

### Exhibit 14 — Conftest

**Role:** runs custom Rego policies against the Terraform files directly.

Created by **Gareth Rushgrove** (~2018-2019) as a thin layer over OPA specifically for testing config files (Terraform, Kubernetes YAML, Dockerfiles) without standing up a full OPA server.

**The core distinction from Checkov:** Checkov ships **rules written by someone else** (1000+, maintained by Bridgecrew/Palo Alto). With Conftest, **you write your own** — rules specific to what actually matters to you, that no generic ruleset could know to check.

**Three custom policies written**, each demonstrating a different kind of rule Checkov can't provide:
1. **`object_lock.rego`** — every `aws_s3_bucket` must have Object Lock enabled. A domain-specific requirement (evidence integrity), not a general security best practice.
2. **`required_tags.rego`** — every bucket must carry `Project = "forensic-custody-api"`. Purely organizational. Found a **real gap**: neither bucket had any tags at all — fixed and applied for real.
3. **`iam_naming.rego`** — every `aws_iam_role` name must start with `forensic-custody-`. Written from scratch as an exercise (given the requirement in plain language, translated to Rego without help). First attempt had inverted logic (`startswith(...)` without `not` — flagged the *correctly* named resource as the violation), a very common logic mistake; corrected after a hint.

**Two real Rego gotchas hit along the way, both non-obvious:**
- The HCL2 parser wraps every `resource` block in a **one-element list**, not a bare object — indexing needs `[name][_]`, not just `[name]`, or every field lookup silently resolves to nothing (proven by testing against a deliberately "bad" resource that still passed until this was fixed).
- Accessing a field that doesn't exist (`bucket.tags.Project` when there's no `tags` block) returns `undefined` in Rego, not `false` — and `undefined != x` stays `undefined`, so the rule never fires. Fixed with `object.get(bucket, ["tags", "Project"], "")` for a safe default.

**A real slip along the way:** when fixing the tags policy, the user overwrote `object_lock.rego`'s content instead of creating the new file — caught by listing the policy directory (`find policy -type f` showed only one file) rather than assuming the earlier work was still intact.

**Confirmed in CI:** Conftest's own test count is `(number of policies) × (number of files evaluated)` — 3 policies × 4 `.tf` files = "12 tests, 12 passed."

---

## Sprint 3 — DAST

### Exhibit 15 — OWASP ZAP

**Role:** attacks the running API from the outside, the only tool in the whole pipeline that never looks at source code.

Created by **Simon Bennetts** (~2010, forked from an earlier project called Paros Proxy), donated to OWASP, and became one of its flagship projects. Follows the same industry-consolidation pattern already seen with Checkov and tfsec: in 2023, governance moved from OWASP to a new entity led by Bennetts, backed by Checkmarx, because OWASP no longer had enough active volunteer maintainers.

**Baseline vs full scan:** baseline is passive — crawls the target and analyzes each response it sees, without ever sending an attack payload. Full scan actively sends real attack attempts (SQLi, XSS) against everything it finds — slower, more disruptive.

**A real limitation, expected going in:** this API is pure JSON, no HTML pages with links — ZAP's spider (built to follow links) found almost nothing on its own. The real value came from passive analysis of the responses it did see, not from automatic discovery.

**Three real findings from the first run**, all fixed with a small `securityHeaders` middleware wrapping the mux in `main.go`:
- `X-Content-Type-Options Header Missing`
- `Storable and Cacheable Content` (no `Cache-Control` at all)
- `Cross-Origin-Resource-Policy Header Missing`

**A finding that flipped, not a new problem:** after adding `Cache-Control: no-store`, the same rule ID (`10049`) reported **"Non-Storable Content"** instead — confirming the fix worked, not flagging something new. Suppressed with a `.zap/rules.tsv` entry (`10049 IGNORE <reason>`), same pattern as `nosemgrep` and `checkov:skip`.

**A Docker networking gotcha, environment-specific:** locally, on Docker Desktop (Windows), `--network host` doesn't behave like it does on Linux (Docker Desktop runs in a VM) — had to use the special `host.docker.internal` hostname instead. In CI (native Linux runners), `--network host` works exactly as expected. A genuine, concrete example of local vs. CI environment differences.

**A generated file that leaked into the repo:** mounting `.zap/` as writable so ZAP could read `rules.tsv` also let ZAP write its own internally-generated Automation Framework plan (`zap.yaml`) into the same folder — a derived artifact, not authored, added to `.gitignore` (only `rules.tsv`, the authored file, gets committed).

**CI job pinned by digest, not tag:** `zaproxy/zap-stable@sha256:781a2bd...` — even more precise than a version number, same immutability concept as Cosign's digest-based verification in Sprint 1.

**Final result, local and in CI:** 66 passed, 0 warnings, 1 documented and ignored.

---

## Recurring Lessons Across Phase 2

A pattern worth naming explicitly: almost every real bug in this phase was a **silent one** — not a crash, not an error message, just a rule that quietly never fired (Rego's `undefined`, the HCL2 array-wrapping, a tag policy that "passed" for the wrong reason) or a step that ran in the wrong order without complaint (publishing before scanning). None of these were caught by "it obviously broke" — they were caught by **deliberately testing against a case designed to fail**, and checking that it actually did. That habit — prove the check catches something before trusting that it passed — mattered more this phase than any single tool.
