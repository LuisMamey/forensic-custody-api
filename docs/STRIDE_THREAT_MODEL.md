# STRIDE Threat Model: Forensic Custody API

## 1. System Overview & Trust Boundaries
The **forensic-custody-api** handles digital forensic evidence (disk images, logs, memory dumps) and tracks chain of custody records. Evidence integrity and non-repudiation are paramount for admissibility in legal proceedings.

### Trust Boundaries:
* **External Client <--> API Boundary:** Untrusted network boundary over HTTP.
* **API <--> Storage Boundary:** Internal API logic accessing in-memory store and AWS S3 buckets.
* **Cloud Infrastructure Boundary:** IAM principals interacting with AWS S3 Object Lock.

---

## 2. STRIDE Threat Analysis

| Threat Category | Specific Threat in Context | Current Mitigation Status | Recommended / Future Mitigation |
|---|---|---|---|
| **Spoofing (Identity)** | Malicious actor poses as a certified forensic investigator and creates fake cases. | **Unmitigated:** API currently lacks authentication (accepted scope limit). | Implement OAuth2/OIDC JWT validation or mutual TLS (mTLS) for client verification. |
| **Tampering (Data)** | Attacker alters raw evidence files or overwrites historical custody records. | **Partially Mitigated:** AWS S3 Object Lock (WORM) prevents object modification; custody logs are append-only. | Switch S3 Object Lock from GOVERNANCE to COMPLIANCE mode; implement database-backed append-only ledger. |
| **Repudiation (Audit)** | Investigator denies having transferred evidence or received an evidence item. | **Mitigated:** `CustodyLog` captures transfer parties, action taken, and verification flags. | Digitally sign custody logs using investigator cryptographic keypairs (e.g., Cosign / X.509). |
| **Information Disclosure** | Eavesdropper intercepts forensic evidence metadata and hashes in transit. | **Partially Mitigated:** S3 buckets use SSE-S3 encryption at rest. HTTP is plain locally. | Enforce TLS 1.3 termination at the AWS Application Load Balancer (ALB) as defined in ADR 0001. |
| **Denial of Service** | Flooding the API with POST requests causes Out-Of-Memory (OOM) crashes. | **Unmitigated:** In-memory map storage with no body size limits or rate limits. | Add IP/Token Rate Limiting middleware and `http.MaxBytesReader` body size bounds. |
| **Elevation of Privilege** | IAM principal abuses `s3:BypassGovernanceRetention` to wipe locked evidence. | **Mitigated:** Current IAM policy (`iam.tf`) restricts permissions strictly to least-privilege. | Enforce AWS SCPs (Service Control Policies) preventing governance bypass across the AWS Organization. |

---

## 3. Residual Risk & Architectural Decisions
1. **Plain HTTP on Container:** Documented in [ADR 0001](adr/0001-tls-termination.md). TLS is strictly delegated to the edge Load Balancer.
2. **Object Lock Governance Mode:** Documented in [ADR 0003](adr/0003-object-lock-retention-mode.md). Accepted for learning flexibility; COMPLIANCE required for true WORM guarantees.
