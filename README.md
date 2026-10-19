# forensic-custody-api

[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/LuisMamey/forensic-custody-api/badge)](https://scorecard.dev/viewer/?uri=github.com/LuisMamey/forensic-custody-api)

An enterprise-grade REST API in Go for tracking the digital forensic chain of custody, engineered alongside a full-lifecycle **DevSecOps, Cloud-Native Security, and SRE platform** on AWS and Kubernetes.

Every security gate, cryptographic control, infrastructure module, and observability rule in this repository was built, verified, and integrated from scratch without boilerplate templates.

---

## 📌 Executive Summary (For Recruiters & Hiring Managers)

### The Real-World Problem
In criminal litigation, corporate incident response, and regulatory compliance, **digital evidence (disk images, network dumps, memory captures) is only as good as its Chain of Custody**. If an organization cannot mathematically prove who handled an artifact, when it was analyzed, and that not a single bit was modified since seizure, **the evidence is inadmissible in court and legal cases collapse**.

### The Solution: `forensic-custody-api`
This project delivers an **end-to-end, tamper-evident digital evidence vault and custody ledger**:
1. **Mathematical Incorruptibility:** Computes dual cryptographic fingerprints (**SHA-256 & SHA-512**) in streaming memory and chains every custody handoff into an **immutable cryptographic ledger** (blockchain-style state transitions) validated by **RFC 3161** legal timestamps.
2. **Hardened Supply Chain (SLSA L3 Ready):** Runs inside a **non-root Google Distroless** container (~5.6MB, no shell) that is cryptographically signed keyless via **Sigstore Cosign**, attested in the **Rekor** transparency log, and SBOM-gated with **Syft & Grype**.
3. **Enterprise Cloud Runtime:** Deploys on **AWS EKS v1.31** with **AWS Bottlerocket OS** (immutable, read-only rootfs), admission-governed by **Kyverno** (enforcing Cosign signature verification before pod launch), monitored at the Linux kernel level by **Falco eBPF**, and synchronized via pull-based **ArgoCD GitOps**.
4. **FinOps & Platform Automation:** Fully automated via `./scripts/platform.sh` — cold-starts 74 AWS resources and 39 Kubernetes pods in **16m 41s**, and tears down to **$0.00/hr** compute cost in **15m 51s** when idle.

### Technical Competency Matrix
| Engineering Discipline | Real-World Implementation in this Repository |
| :--- | :--- |
| **Backend & Systems (Go)** | Standard library `net/http` (zero framework bloat), streaming I/O (`io.MultiWriter`), native mutation fuzzing (`go test -fuzz`), graceful shutdown. |
| **Applied Cryptography** | Dual streaming hashes (fixed RAM buffer), chained ledger verification (`/verify`), ASN.1 DER RFC 3161 TSA proofs, AWS KMS Customer Managed Keys. |
| **Cloud & IaC (Terraform)** | 3-tier VPC network segmentation, AWS EKS v1.31, Bottlerocket OS, AWS WAF v2 + HTTPS ALB, EKS Pod Identity (Zero-Trust IAM). |
| **DevSecOps & Supply Chain** | Distroless non-root (`UID 65532`), Cosign keyless signing, Rekor attestation, CycloneDX SBOM (`Syft`), Grype CVE gates, Semgrep SAST, Govulncheck SCA. |
| **Runtime Defense (CWPP)** | Kyverno admission controller (cryptographic signature verification), Falco eBPF kernel syscall monitoring (`execve`). |
| **SRE & Observability** | Prometheus + OpenTelemetry metrics, mathematically enforced SLOs (99.9% availability, p99 < 250ms latency) stress-tested via **k6**, Alertmanager hygiene. |
| **Progressive Delivery** | GitOps model via ArgoCD, single-command automated platform lifecycle (`platform.sh up/down`). |

---

## 1. Forensic Domain & Cryptographic Architecture

- **Case Management (`Case`)** — Investigation containers identified by case number, title, and lead investigator.
- **Streaming Evidence Intake (`EvidenceItem`)** — Single-pass `io.MultiWriter` streaming computation of dual **SHA-256** and **SHA-512** hashes (`internal/crypto/hasher.go`) without loading large forensic images into memory.
- **Immutable Chained Custody Ledger (`CustodyLog`)** — Cryptographically linked blocks (`internal/crypto/ledger.go`) where every custody transition binds the SHA-256 digest of the preceding block starting from a deterministic `GenesisHash`.
- **Trusted Timestamping (`RFC 3161`)** — ASN.1 DER timestamp requests (`internal/crypto/timestamp.go`) against a Time Stamping Authority (TSA) to establish mathematical proof of existence.
- **Forensic RBAC & Authentication (`internal/auth/`)** — Stateless HMAC-SHA256 JWT validation enforcing least-privilege domain roles:
  - `INVESTIGATOR` — Create and inspect cases and intake evidence.
  - `EVIDENCE_CUSTODIAN` — Intake evidence and execute custody transfers.
  - `LAB_ANALYST` — Execute custody transfers and record forensic analysis actions.
  - `AUDITOR` — Read-only inspection of cases, evidence, and cryptographic chain verification.
- **Hardened HTTP Server (`cmd/api/main.go`)** — Explicit Slowloris mitigation timeouts (`ReadHeaderTimeout`, `ReadTimeout`, `WriteTimeout`, `IdleTimeout`) and OS signal trapping (`SIGINT`/`SIGTERM`) for zero-downtime graceful connection draining.

---

## 2. API Endpoints

| Method | Path | Required Role(s) | Purpose |
|---|---|---|---|
| `GET` | `/health` | Public (Probe) | Liveness and readiness check |
| `GET` | `/metrics` | Public (Scraper) | Prometheus telemetry & SLI histograms |
| `POST` | `/cases` | `INVESTIGATOR` | Create a new forensic investigation case |
| `GET` | `/cases` | Any Authenticated | List all registered cases |
| `POST` | `/cases/{caseID}/evidence` | `INVESTIGATOR`, `EVIDENCE_CUSTODIAN` | Register evidence metadata for a case |
| `POST` | `/cases/{caseID}/evidence/upload` | `INVESTIGATOR`, `EVIDENCE_CUSTODIAN` | Stream binary evidence and compute dual SHA-256/512 |
| `GET` | `/cases/{caseID}/evidence` | Any Authenticated | List all evidence items for a case |
| `POST` | `/evidence/{evidenceID}/custody-logs` | `LAB_ANALYST`, `EVIDENCE_CUSTODIAN` | Append a cryptographically chained custody block |
| `GET` | `/evidence/{evidenceID}/custody-logs` | Any Authenticated | Retrieve full chain of custody history |
| `GET` | `/evidence/{evidenceID}/custody-logs/verify` | Any Authenticated | Recalculate and verify entire cryptographic ledger chain |

---

## 3. Running Locally

```bash
go run ./cmd/api
```

Or inside the rootless **Google Distroless Debian 12** container (`UID 65532`, ~5.6MB, no shell):

```bash
docker build -t forensic-custody-api .
docker run -p 8080:8080 forensic-custody-api
```

Run unit tests and native Go fuzzing targets:

```bash
go test -v ./...
go test -fuzz=FuzzVerifyToken -fuzztime=15s ./internal/auth/
go test -fuzz=FuzzVerifyLedgerChain -fuzztime=15s ./internal/crypto/
```

---

## 4. End-to-End DevSecOps & Supply Chain Pipelines

All GitHub Actions workflows enforce **SLSA Level 3 readiness** via full 40-character commit SHA pinning and restricted `permissions: contents: read` tokens:

### `.github/workflows/security.yml` (Continuous Security & SRE Gate on PR/Push)

| Job | Tool | Verification Scope |
|---|---|---|
| **Secret Scanning** | `Gitleaks` + `pre-commit` | Full Git history and local pre-commit secret detection |
| **SAST** | `Semgrep` | Static code analysis uploaded as SARIF to GitHub Security |
| **SCA** | `Govulncheck` | Call-graph reachability analysis of Go dependencies |
| **Fuzzing** | `go test -fuzz` | Automated mutation fuzzing on JWT and cryptographic ledger parsers |
| **Container Scan** | `Trivy` (`--ignore-unfixed`) | High/Critical CVE gate on built Distroless image |
| **IaC Security** | `Checkov` | AWS Terraform security misconfiguration scanning |
| **Policy as Code** | `Conftest (OPA Rego)` | Custom Rego v1 policies enforcing tags, naming, and S3 Object Lock |
| **DAST** | `OWASP ZAP API Scan` | Dynamic OpenAPI-driven active scan against live container |
| **Admission Control** | `Kyverno CLI` | Policy validation enforcing non-root pods and Cosign image signatures |
| **Runtime Security** | `Falco` | Kernel eBPF rule syntax validation (`falco -V`) |
| **SLO Load Testing** | `k6` | Concurrent stress test enforcing `p99 < 250ms` and `errors < 0.1%` |

### `.github/workflows/supply-chain.yml` (Artifact Attestation & Signing)
Builds the production image, generates a **CycloneDX SBOM** (`Syft`), audits OS vs. Go packages with `jq`, enforces a zero-high-CVE gate (`Grype --only-fixed`), publishes to GHCR, and performs **keyless OIDC cryptographic signing and SBOM attestation** via **Sigstore Cosign** recorded in the **Rekor** transparency log.

### `.github/workflows/cspm.yml` & `.github/workflows/scorecard.yml`
- **Live Cloud Posture (CSPM):** Scheduled **Prowler** audits authenticating to AWS via **IAM OIDC federation** (zero static keys).
- **Repository Hygiene:** Continuous **OpenSSF Scorecard** evaluation and **Dependabot** grouped SemVer updates.

---

## 5. Cloud-Native Infrastructure, Runtime Defense & SRE (`terraform/` & `k8s/`)

`terraform/` provisions a complete Defense-in-Depth AWS environment:
- **Network Segmentation (`vpc.tf`):** Multi-AZ VPC (`10.0.0.0/16`) with Public DMZ subnets (ALB), Private compute subnets (EKS), and Isolated persistence subnets.
- **Hardened Kubernetes (`eks.tf`):** **AWS EKS v1.31** control plane with full audit logging and private worker nodes running **AWS Bottlerocket OS** (read-only rootfs with `dm-verity`, no shell, SELinux enforcing).
- **Edge Protection (`alb.tf`, `waf.tf`):** Public HTTPS **Application Load Balancer** protected by **AWS WAF v2** (Rate limiting 500 req/5min, OWASP Common Rule Set, Known Bad Inputs, and KMS-encrypted CloudWatch audit logs).
- **Forensic Storage & Cryptography (`s3.tf`, `kms.tf`, `secrets.tf`):** WORM-compliant **S3 Object Lock**, dedicated **AWS KMS Customer Managed Key (CMK)** with automatic rotation, and **AWS Secrets Manager** bound via **EKS Pod Identity**.
- **In-Cluster Platform Bootstrap (`cluster_addons.tf`):** Automated Helm deployment of:
  1. **ArgoCD** — Pull-based GitOps controller reconciling `k8s/apps/forensic-custody-api`.
  2. **Kyverno** — Admission webhook enforcing Pod Security Standards (Restricted) and Rekor Cosign signature verification (`k8s/policies/`).
  3. **Falco** — Kernel-level eBPF intrusion detection (`modern_ebpf`) monitoring unauthorized binaries, network egress, and storage tampering (`k8s/falco/`).
  4. **External Secrets Operator (ESO)** — Zero-trust secret synchronization from AWS Secrets Manager.
  5. **kube-prometheus-stack** — Prometheus Operator & Alertmanager evaluating multi-window SLI/SLO burn-rate rules (`k8s/monitoring/`).
- **One-Command Platform Lifecycle (`scripts/platform.sh`):**
  ```bash
  ./scripts/platform.sh up      # Bootstrap S3/DynamoDB state, verify SHA-256 Helm charts, provision AWS/EKS & GitOps
  ./scripts/platform.sh status  # Inspect live EKS Bottlerocket nodes, CRDs, policies, and pods
  ./scripts/platform.sh tunnel  # Open authenticated localhost:8080 proxy tunnel to live EKS pods
  ./scripts/platform.sh down    # Ordered teardown of Helm operators & hourly-billed AWS infra ($0.00/hr)
  ```

---

## 6. Architecture Decision Records (ADRs) & Engineering Documentation

All architectural trade-offs and risk acceptances are documented in [`docs/adr/`](docs/adr/):
- [ADR 0001 — Edge TLS Termination at the Load Balancer](docs/adr/0001-tls-termination.md)
- [ADR 0002 — S3 Security Scope & Lifecycle Preservation](docs/adr/0002-s3-security-scope.md)
- [ADR 0003 — S3 Object Lock Retention Mode (Governance vs. Compliance)](docs/adr/0003-object-lock-retention-mode.md)
- [ADR 0004 — Terraform Official Registry Module Pinning](docs/adr/0004-terraform-module-pinning.md)
- [ADR 0005 — ALB Security Scope & JVM/Log4j Immunity](docs/adr/0005-alb-security-scope.md)
- [ADR 0006 — Remote State Backend Hardening Scope](docs/adr/0006-backend-state-hardening-scope.md)
- [ADR 0007 — AWS KMS Key Policy Wildcard Architecture](docs/adr/0007-kms-key-policy-architecture.md)
- [ADR 0008 — AWS Secrets Manager Rotation Scope with ESO](docs/adr/0008-secrets-manager-rotation-scope.md)

### Deep-Dive Engineering Guides & Case Files:
- **Platform & Infrastructure Operations:** [`PLATFORM_LIFECYCLE_TROUBLESHOOTING.md`](docs/PLATFORM_LIFECYCLE_TROUBLESHOOTING.md) | [`GITOPS_ARCHITECTURE.md`](docs/GITOPS_ARCHITECTURE.md) | [`SLO_FRAMEWORK.md`](docs/SLO_FRAMEWORK.md)
- **Architecture & Threat Modeling:** [`ROADMAP.md`](docs/ROADMAP.md) | [`STRIDE_THREAT_MODEL.md`](docs/STRIDE_THREAT_MODEL.md) | [`IAC_vs_CSPM.md`](docs/IAC_vs_CSPM.md) | [`ASPM_DEFECTDOJO_ARCHITECTURE.md`](docs/ASPM_DEFECTDOJO_ARCHITECTURE.md)
- **SRE Postmortems:** [`INCIDENT-2026-001 Postmortem`](docs/postmortems/INCIDENT-2026-001-K6-JWT-AUTH.md)
- **Chronological Build Case Files:** [`PHASE1_HISTORY.md`](docs/PHASE1_HISTORY.md) | [`PHASE2_HISTORY.md`](docs/PHASE2_HISTORY.md) | [`PHASE3_HISTORY.md`](docs/PHASE3_HISTORY.md) | [`PHASE4_HISTORY.md`](docs/PHASE4_HISTORY.md) | [`PHASE5_HISTORY.md`](docs/PHASE5_HISTORY.md) | [`PHASE6_HISTORY.md`](docs/PHASE6_HISTORY.md)
