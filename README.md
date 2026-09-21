# forensic-custody-api

A small REST API in Go for tracking the chain of custody of digital forensic evidence: cases, evidence items, and an append-only log of every transfer or action taken on that evidence.

The API itself is the pretext. The real purpose of this project is a hands-on, end-to-end DevSecOps pipeline built around it — every tool below was chosen, configured, and verified by hand, not copied from a template.

## Domain model

- **Case** — an investigation, identified by a case number and a lead investigator.
- **EvidenceItem** — a piece of digital evidence (disk image, memory dump, network capture, system logs) belonging to a case, with a SHA-256 hash and a storage location.
- **CustodyLog** — an immutable record of who transferred an evidence item to whom, what action was taken, and whether integrity was verified.

## Running it

```bash
go run ./cmd/api
```

or as a container:

```bash
docker build -t forensic-custody-api .
docker run -p 8080:8080 forensic-custody-api
```

The server listens on `:8080`.

## API

| Method | Path | Purpose |
|---|---|---|
| `GET`  | `/health` | Liveness check |
| `POST` | `/cases` | Create a case |
| `GET`  | `/cases` | List cases |
| `POST` | `/cases/{caseID}/evidence` | Add evidence to a case |
| `GET`  | `/cases/{caseID}/evidence` | List evidence for a case |
| `POST` | `/evidence/{evidenceID}/custody-logs` | Append a custody log entry |
| `GET`  | `/evidence/{evidenceID}/custody-logs` | List an evidence item's chain of custody |

Storage is in-memory (`internal/storage`) — data does not persist across restarts. IDs are generated server-side with `crypto/rand`, never client-supplied.

## The DevSecOps pipeline

Two GitHub Actions workflows, both built from pinned, directly-invoked tool binaries rather than third-party Marketplace Actions, to avoid adding unnecessary supply-chain trust to the CI itself.

**`.github/workflows/security.yml`** — runs on every push and pull request:

| Job | Tool | Checks |
|---|---|---|
| Secret Scanning | Gitleaks | Credentials/keys committed to Git history |
| SAST | Semgrep | Insecure code patterns |
| SCA | Govulncheck | Reachable vulnerabilities in Go and its dependencies |
| Container Security | Trivy | Vulnerabilities in the built image |
| IaC Security | Checkov | Terraform misconfigurations |
| Policy as Code | Conftest | Custom Rego policies (`terraform/policy/`) |
| DAST | OWASP ZAP | The running API, attacked from the outside |

**`.github/workflows/supply-chain.yml`** — runs on push to `main`: builds the image, generates an SBOM (Syft), scans it (Grype) as a gate before publishing, pushes to GHCR, then signs the image and attests the SBOM with Cosign using keyless signing (no private key ever stored).

## Infrastructure

`terraform/` provisions the AWS side: an S3 bucket for evidence with Object Lock (WORM) enabled, a separate bucket for access logs, and an IAM role/policy scoped to exactly what the API needs — nothing more.

## Documented decisions

Security and architecture decisions with real trade-offs are written up as ADRs in [`docs/adr/`](docs/adr/):

- [0001 — TLS termination at the load balancer, not the app](docs/adr/0001-tls-termination.md)
- [0002 — Deferred S3 hardening controls](docs/adr/0002-s3-security-scope.md)
- [0003 — Object Lock retention mode](docs/adr/0003-object-lock-retention-mode.md)

Obvious remediations (a dependency bump for a known CVE, for example) live in their commit messages instead — not every fix needs an ADR.

## How this was built

The full narrative — what each tool is, who built it, why it was chosen here, and the real bugs and gotchas hit along the way — is written up in two case files:

- [`docs/PHASE1_HISTORY.md`](docs/PHASE1_HISTORY.md) — the base stack (Go, Docker, Trivy, Gitleaks, Semgrep, Govulncheck, Terraform, Checkov, GitHub Actions).
- [`docs/PHASE2_HISTORY.md`](docs/PHASE2_HISTORY.md) — Supply Chain Security, Policy as Code, and DAST.
