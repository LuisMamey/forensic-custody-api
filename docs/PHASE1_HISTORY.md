# Phase 1 Case File — History of the DevSecOps Stack

Narrative record of the 9 pieces implemented in Phase 1 of `forensic-custody-api`: what each tool is, who created it and why, why it was used in this project, and what real problems came up while implementing it. Meant to be reread to cement the knowledge, not as technical documentation of the repo (that's what the ADRs in `docs/adr/` are for).

---

## Exhibit 1 — Go

**Role:** language and runtime for the API.

Go was created by Google in 2007 (Robert Griesemer, Rob Pike, Ken Thompson), public since 2009, to solve a very concrete internal problem: compiling C++ across Google's massive systems took minutes or hours, and they wanted a compiled language with native concurrency (goroutines), strong typing, but near-instant compile times.

**Why here:** strict typing, low memory footprint, compiles to a static binary — ideal for the distroless Docker image. Only the standard library was used (`net/http`, the Go 1.22+ `ServeMux`) to minimize dependencies to audit, consistent with the goal of learning SCA.

**Real problem:** upgrading Go from 1.26.5 to 1.27.0 (to close the CVEs found by Govulncheck) broke Govulncheck itself — it had been compiled with the old Go and its internal analysis packages couldn't parse the new code. Fixed by reinstalling it (`go install .../govulncheck@latest`) so it rebuilt against the updated toolchain.

---

## Exhibit 2 — Docker

**Role:** packaging the API into a minimal, unprivileged image.

Docker was launched by dotCloud (later Docker Inc.) in 2013, popularizing Linux containers (the underlying technology — cgroups, namespaces — already existed but was hard to use) with a simple interface.

**Why here:** a multi-stage build — a `builder` stage with the full Go toolchain (compiles the binary), and a final stage on `gcr.io/distroless/static-debian12:nonroot` (from Google) that only contains the binary, with no shell and no package manager, running as a non-root user (UID 65532). Result: a ~5.6MB final image.

**Real problem:** the Dockerfile stayed pinned to `golang:1.26-alpine` while `go.mod` already required `go 1.27.0` — a silent drift that Trivy exposed in CI months later (`go.mod requires go >= 1.27.0`). Fixed by pinning `golang:1.27.0-alpine` (an exact version, not a floating tag).

---

## Exhibit 3 — Trivy (Image Scan)

**Role:** SCA + vulnerability scanning of the Docker image.

Created by **Aqua Security** in 2019, as a direct response to **Clair** (from CoreOS/Quay), which required standing up a server with a Postgres database — heavy to set up. Trivy is a single static binary, no server required.

**Why here:** scans every layer of the image (OS packages + Go binary metadata) against a CVE database. Today it's part of the CNCF and has expanded far beyond Docker images (`trivy config` for IaC, `trivy fs` for filesystems, SBOM generation).

**Result:** 0 vulnerabilities — confirms in practice the value of a distroless image.

---

## Exhibit 4 — Gitleaks

**Role:** secret scanning over Git history.

Created by **Zachary Rice** (`zricethezav`) around 2017–2019 as a personal project, to tackle a common problem: people accidentally pushing AWS credentials/API keys to a repo. Over time it moved to live under the `gitleaks` organization on GitHub (the Go module path, however, still remains `zricethezav/gitleaks` — a trace of that migration).

**How it detects:** regex patterns for known formats (AWS, GitHub, Slack...) plus Shannon entropy analysis (how "random" a string looks).

**Real problem (and deliberate experiment):** testing with AWS's own official example key (`AKIAIOSFODNN7EXAMPLE`) — Gitleaks **did not** flag it. It's such a famous placeholder that its low "randomness" (containing the word "EXAMPLE") keeps it from tripping the rule. A randomly generated GitHub token (`ghp_...`, entropy 4.65) was detected instantly — a real lesson on what does and doesn't read as a "believable" secret to these tools.

---

## Exhibit 5 — Semgrep

**Role:** SAST (Static Application Security Testing) over the Go code.

SAST as a category emerged in the late 90s/2000s (ITS4 in 1998, Fortify in 2003, Coverity in 2002) as a response to functional QA not catching security flaws — code can pass every test and still be exploitable.

Semgrep specifically was created by **r2c** (a startup founded by former Facebook/Coinbase security engineers, later renamed Semgrep Inc.) in 2018. Its differentiator: rules written almost like example code (matched against the syntax tree), not a complicated proprietary query language.

**Result:** 1 real finding — `go.lang.security.audit.net.use-tls.use-tls` (HTTP server without TLS). Documented in **ADR 0001** (TLS is terminated at the load balancer, not the app) and suppressed with `// nosemgrep`.

**Real problem:** the first attempt to suppress the finding didn't work — `nosemgrep` only associates with the same line or the line **immediately above**, and there were 3 lines of explanatory comment in between. Fixed by reordering: explanation first, `// nosemgrep` right above the code.

---

## Exhibit 6 — Govulncheck

**Role:** precision SCA for Go and its standard library.

An **official tool from the Go team**. Its differentiator versus Trivy: it doesn't just look at which dependencies exist, it analyzes your code's **call graph** — if you have a vulnerable dependency but never call the affected function, it won't alert you.

**Real result (not simulated):** found 3 genuine vulnerabilities in the Go 1.26.5 standard library (`crypto/tls`, `net/http`, `encoding/asn1`), fixed in 1.26.6. The toolchain was upgraded to 1.27.0 — the only one of the 5 tools that forced a real remediation, not just a documented decision.

---

## Exhibit 7 — Terraform

**Role:** Infrastructure as Code — S3 + IAM on AWS.

Created by **HashiCorp** (Mitchell Hashimoto and Armon Dadgar), launched in 2014, to declare infrastructure as versionable text instead of manual clicks in a console or imperative scripts.

**What was built:**
- `aws_s3_bucket.evidence` — the evidence bucket, with Object Lock (WORM) enabled.
- `aws_s3_bucket.evidence_logs` — a separate access-log bucket, kept apart from the evidence bucket.
- An IAM Role + Policy with **real least privilege**: two separate `statement` blocks (reading/writing objects vs. listing the bucket — two different resource levels in S3's hierarchy).

**Real problem and important finding:** `object_lock_enabled = true` **does not lock anything by itself** — it only enables the capability. An `aws_s3_bucket_object_lock_configuration` with a default retention rule was needed (`GOVERNANCE`, not `COMPLIANCE`, documented in **ADR 0003** — Compliance is irreversible even for AWS Support, a bad idea while still learning). And since Object Lock can only be enabled at bucket creation, adding it to the (already existing) logs bucket forced destroying and recreating that bucket entirely.

---

## Exhibit 8 — Checkov

**Role:** IaC Security over the `.tf` files.

Created by **Bridgecrew** (~2019), acquired by **Palo Alto Networks** in 2021 (today part of Prisma Cloud), but remains open source and independent. Preferred over **tfsec** because tfsec (from Aqua Security, the same company behind Trivy) is being absorbed into Trivy itself (`trivy config`) — Checkov has more staying power going forward.

**Real timeline:**
1. 1st run: 24 passed, 7 failed — IAM passed cleanly (real least privilege), the S3 bucket failed 7 checks.
2. Fixed: explicit versioning, Public Access Block, and access logging (with a second bucket + a policy restricted by `aws:SourceArn`/`aws:SourceAccount`).
3. 2nd run (now with 2 buckets): 53 passed, 9 failed.
4. Documented in **ADR 0002** why cross-region replication, event notifications, lifecycle config, and KMS are NOT implemented (cost, scope, or directly contradicting the project's purpose — forensic evidence shouldn't expire on its own).
5. Final run: **54 passed, 0 failed, 8 skipped** (the 8 documented in the ADR).

---

## Exhibit 9 — GitHub Actions

**Role:** orchestration — the security gate that runs everything above automatically.

GitHub launched Actions in 2019, expanding what started as PR automation into a full CI/CD platform.

**Design decision:** direct commands with an exact pinned version for each tool (Gitleaks v8.30.1, Semgrep 1.175.0, Govulncheck v1.8.0, Trivy 0.74.0, Checkov 3.3.16), instead of tool-specific Marketplace Actions — to avoid adding third-party trust surface to the CI itself. `actions/checkout` and `actions/setup-go` are still used (first-party, from GitHub itself).

**Result:** 5 parallel jobs, all green on the first successful push (the first attempt failed due to the Go version drift in the Dockerfile — see Exhibit 2).

**Scope agreed on purpose:** only "run and report." No branch protection blocking merges, no Dependabot — avoiding the complexity the user had already experienced in another project when mixing both.

---

## Documented Decisions (ADRs)

| ADR | Decision | Why it isn't an "obvious fix" |
|---|---|---|
| 0001 | TLS is terminated at the Load Balancer (Terraform), not the app | A self-signed cert would be throwaway work; distroless has no shell to manage it |
| 0002 | No replication/notifications/lifecycle/KMS on S3 | Cost and complexity unjustified for a learning project; lifecycle contradicts "evidence that doesn't expire" |
| 0003 | Object Lock in GOVERNANCE mode, not COMPLIANCE | Compliance is irreversible even for AWS Support — an unacceptable risk while still experimenting |

**Lesson learned on when a decision deserves an ADR:** only decisions with real trade-offs and alternatives. An obvious remediation (like upgrading Go for a Govulncheck CVE) belongs in the commit message, not an ADR — avoid "ADR fatigue."

---

## The Pattern That Repeats

Each tool looks at a different layer of the same system: Gitleaks looks at **history** (past commits), Semgrep looks at the code's **logic**, Govulncheck looks at the **actual usage** of dependencies, Trivy looks at the **built artifact**, Checkov looks at the **declared infrastructure**. No single one covers everything — that's why a DevSecOps pipeline chains several together instead of trusting just one.
