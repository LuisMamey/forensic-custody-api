# STRIDE Threat Model: Forensic Custody API

## 1. System Overview & Trust Boundaries
The **forensic-custody-api** manages digital forensic evidence (disk images, memory dumps, network captures, system logs) and maintains a cryptographically verifiable chain-of-custody ledger. Evidence integrity, confidentiality, and non-repudiation are strictly enforced for legal admissibility.

### Trust Boundaries:
* **External Client <--> Edge Boundary:** Untrusted internet traffic scrubbed by **AWS WAF v2** and terminated over TLS 1.3 at the **AWS Application Load Balancer (ALB)**.
* **Ingress <--> Compute Boundary:** Private VPC subnets hosting **AWS EKS** worker nodes running immutable **Bottlerocket OS**, governed by **Kyverno** admission webhooks and monitored in kernel space by **Falco eBPF**.
* **Application <--> Cloud Persistence Boundary:** Least-privilege IAM roles and **EKS Pod Identity** interacting with **AWS S3 Object Lock (WORM)**, **AWS KMS Customer Managed Keys (CMK)**, and **AWS Secrets Manager**.

---

## 2. STRIDE Threat Analysis & Implemented Controls

| Threat Category | Specific Threat in Context | Mitigation Status | Implemented Architectural Controls |
|---|---|---|---|
| **Spoofing (Identity)** | Malicious actor poses as a certified forensic investigator to create fake cases or contaminate evidence. | **Mitigated** | Stateless HMAC-SHA256 **JWT Authentication** and strict **Forensic RBAC** middleware (`internal/auth/`) enforcing `INVESTIGATOR`, `LAB_ANALYST`, `EVIDENCE_CUSTODIAN`, and `AUDITOR` role boundaries. Container supply chain spoofing blocked by **Cosign Keyless OIDC** verification in **Kyverno**. |
| **Tampering (Data)** | Attacker alters raw evidence payloads or rewrites historical chain-of-custody records. | **Mitigated** | Single-pass dual streaming hashes (**SHA-256 + SHA-512** in `internal/crypto/hasher.go`), cryptographic block chaining (`internal/crypto/ledger.go`), **S3 Object Lock (WORM)** (`terraform/s3.tf`), and read-only root filesystems enforced at container and node levels. |
| **Repudiation (Audit)** | Investigator or analyst denies having transferred evidence or altered custody state at a given time. | **Mitigated** | Append-only `CustodyLog` chained hashes paired with **RFC 3161 Trusted Timestamping** (`internal/crypto/timestamp.go`), immutable **Rekor** transparency log entries for builds, and 365-day KMS-encrypted CloudWatch audit logs. |
| **Information Disclosure** | Eavesdropper intercepts forensic evidence payloads, metadata, or signing secrets. | **Mitigated** | Edge TLS termination at the ALB ([ADR 0001](adr/0001-tls-termination.md)), envelope encryption at rest using a dedicated **AWS KMS CMK** with automatic rotation (`terraform/kms.tf`), and zero-trust secret injection via **External Secrets Operator (ESO)** (`terraform/secrets.tf`). |
| **Denial of Service** | Flooding the API or opening slow connections (Slowloris) causes resource exhaustion or downtime. | **Mitigated** | Edge Layer 7 rate limiting (**500 req / 5 min per IP**) via **AWS WAF v2** (`terraform/waf.tf`), hardened Go `net/http` timeouts (`ReadHeaderTimeout: 5s`, `ReadTimeout: 15s`, `WriteTimeout: 30s`), graceful shutdown draining (`cmd/api/main.go`), and continuous **k6** SLO load validation. |
| **Elevation of Privilege** | Compromised process attempts container escape, root execution, or IAM privilege escalation. | **Mitigated** | Rootless **Distroless** container (`UID 65532`, `drop: ["ALL"]`, `allowPrivilegeEscalation: false`), **Kyverno** PSS Restricted enforcement, **Falco eBPF** syscall detection, and scoped IAM policies (`terraform/iam.tf`, `terraform/secrets.tf`). |

---

## 3. Residual Risk & Architectural Decisions
1. **Plain HTTP Inside Private Cluster Network:** Documented in [ADR 0001](adr/0001-tls-termination.md). External TLS is terminated at the AWS ALB; internal pod traffic resides within isolated private VPC subnets.
2. **Object Lock Governance Mode:** Documented in [ADR 0003](adr/0003-object-lock-retention-mode.md). Configured in `GOVERNANCE` mode for laboratory lifecycle management; `COMPLIANCE` mode is specified for irreversible multi-year legal retention.
