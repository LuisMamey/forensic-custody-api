# Phase 3 Case File — Threat Modeling, Infrastructure Baseline & Forensic Cryptography

Continuation of [PHASE2_HISTORY.md](PHASE2_HISTORY.md), documenting the core cryptographic and domain engineering journey of `forensic-custody-api`: threat modeling, state persistence, envelope encryption, streaming dual-hashing, chained immutable ledgers, trusted timestamping, and forensic access control. Exhibit numbering continues from Phase 2 (which concluded at Exhibit 15).

---

## 1. Threat Modeling & Infrastructure Baseline

### Exhibit 16 — STRIDE Threat Model
**Role:** Formal security-by-design framework for the forensic custody domain.

Created by **Praerit Garg and Loren Kohnfelder at Microsoft** in 1999, formalized in Adam Shostack's threat modeling methodology. Developed to identify architectural design flaws *before* writing code, categorizing threats into Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, and Elevation of Privilege.

**Why here:** Digital forensics requires non-repudiation and evidential integrity acceptable in court. Documented in `docs/STRIDE_THREAT_MODEL.md`, identifying attack vectors on evidence tampering, unauthorized hash mutation, and state drift.

**Real architectural mitigation:** STRIDE directly dictated the implementation of chained ledgers, dual-stream cryptographic hashing, and dedicated role separation (`AUDITOR` vs `EVIDENCE_CUSTODIAN`).

---

### Exhibit 17 — Terraform S3 Remote State & DynamoDB Distributed Locking
**Role:** Concurrency protection and encrypted state persistence for cloud infrastructure.

Created by **HashiCorp** (~2014) to enable multi-engineer infrastructure management without race conditions or state clobbering.

**Why here:** Configured in `terraform/backend.tf` and `terraform/backend_infra.tf`. Uses an isolated S3 bucket (`forensic-custody-tfstate-737710548831`) with native server-side encryption (SSE-S3), versioning, and an atomic DynamoDB state locking table (`forensic-custody-tfstate-locks`) using `LockID`.

**Real problem caught:** Creating the state backend with Terraform requires bootstrapping the bucket and table *before* pointing Terraform to them, preventing self-referential initialization cycles.

---

### Exhibit 18 — AWS KMS Customer Managed Keys (CMK)
**Role:** Envelope encryption and administrative separation of duties.

Created by **Amazon Web Services** in 2014.

**Why here:** Implemented in `terraform/kms.tf`. S3 evidence buckets are encrypted with a dedicated KMS Customer Managed Key (`alias/forensic-custody-evidence-key`) with automatic 365-day rotation. Enforces separation of duties: S3 bucket administrators cannot decrypt evidence without explicit KMS Key Policy `kms:Decrypt` grants.

---

## 2. Forensic Domain Cryptography (The Core Product)

### Exhibit 19 — Dual-Stream Hashing (`io.MultiWriter`)
**Role:** Constant-memory streaming evidence ingestion calculating SHA-256 and SHA-512 concurrently.

Native Go cryptography (`crypto/sha256`, `crypto/sha512`) orchestrated via `io.MultiWriter`.

**Why here:** Implemented in `internal/crypto/hasher.go`. In forensic evidence handling, evidence files (disk dumps, memory images) often exceed available server RAM. Streaming via a 32KB buffer directly through `io.MultiWriter` calculates cryptographic hashes in a single read pass with $O(1)$ memory complexity, preventing Denial of Service (DoS) memory exhaustion.

---

### Exhibit 20 — Chained Ledger (Cryptographic Audit Trail)
**Role:** Mathematical proof of tamper-evident state transitions.

Inspired by Merkle trees and immutable ledger topologies.

**Why here:** Implemented in `internal/crypto/ledger.go` and verified via `/evidence/{evidenceID}/custody-logs/verify`. Each custody transfer (`SEIZED -> IN_TRANSIT -> LAB_ANALYSIS -> VAULT_STORED`) calculates its state hash chained strictly to the preceding entry:
$$\text{BlockHash}_n = \text{SHA256}(\text{Payload}_n + \text{BlockHash}_{n-1})$$
Any retroactive record alteration immediately breaks the mathematical chain.

---

### Exhibit 21 — RFC 3161 Trusted Timestamping Authority (TSA)
**Role:** External temporal non-repudiation proof for court admissibility.

Standardized by the **IETF** in 2001 (RFC 3161) using ASN.1 DER-encoded requests.

**Why here:** Implemented in `internal/crypto/timestamp.go`. Sends the evidence SHA-256 digest alongside a cryptographically random 64-bit nonce to a trusted public TSA (FreeTSA) to obtain an authenticated timestamp token (`application/timestamp-reply`).

**Real problem caught:** Raw HTTP TSA endpoints return binary ASN.1 DER data requiring strict MIME headers (`Content-Type: application/timestamp-query`), and responses must be parsed as binary tokens, not string payloads.

---

### Exhibit 22 — Forensic RBAC Middleware & Token Matrix
**Role:** Zero-trust domain authorization and non-repudiation.

Implemented natively in Go using role matrix mapping in `internal/auth/roles.go` and HTTP middleware in `internal/auth/middleware.go`.

**Why here:** Strictly enforces separation of privileges:
* `INVESTIGATOR`: Initial evidence seizure and case creation.
* `LAB_ANALYST`: Forensic extraction and laboratory analysis records.
* `EVIDENCE_CUSTODIAN`: Physical warehouse and vault storage transfers.
* `AUDITOR`: Read-only verification of integrity logs (`/verify`).
