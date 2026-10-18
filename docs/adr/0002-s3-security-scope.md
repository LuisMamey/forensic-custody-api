# ADR 0002: Deferred S3 hardening controls (replication, notifications, lifecycle, KMS)

## Status
Accepted

## Context
Checkov flagged four recurring findings against both S3 buckets
(`aws_s3_bucket.evidence` and `aws_s3_bucket.evidence_logs`):
- `CKV_AWS_144`: cross-region replication is not enabled.
- `CKV2_AWS_62`: event notifications are not enabled.
- `CKV2_AWS_61`: no lifecycle configuration exists.
- `CKV_AWS_145`: buckets are not encrypted with a customer-managed KMS key.

## Decision
None of these are implemented at this stage, for reasons specific to each:

- **Cross-region replication**: adds ongoing storage cost (duplicate data in
  a second region) and operational complexity, with no disaster-recovery
  requirement in a learning project to justify it.
- **Event notifications**: no consumer (Lambda, SQS, SNS) exists yet to react
  to bucket events. Enabling notifications with nothing subscribed provides
  no value and would be revisited if such a consumer is ever built.
- **Lifecycle configuration**: lifecycle rules typically transition or expire
  objects over time. Automatically deleting or downgrading forensic evidence
  contradicts the purpose of a chain-of-custody system, where evidence must
  remain intact and retrievable indefinitely. Skipping this is a deliberate
  fit to the domain, not an oversight.
- **KMS encryption**: both buckets satisfy `CKV_AWS_19` (encrypted at rest).
  In Sprint 2 (`terraform/kms.tf` and `terraform/s3.tf`), a dedicated
  Customer-Managed KMS Key (`aws_kms_key.evidence`) with automatic rotation was
  provisioned and bound to `aws_s3_bucket.evidence`, while `evidence_logs`
  retains default SSE-S3 encryption.

## Consequences
- Positive: avoids unnecessary cross-region replication cost and operational
  complexity; the lifecycle decision specifically reinforces the project's
  chain-of-custody design intent (evidence never auto-expires).
- Negative / accepted risk: data in both buckets is not geographically
  replicated across regions, there is no automated Lambda/SQS reaction to new
  uploads, and storage grows without automatic expiration.
- These findings are suppressed in Checkov with `#checkov:skip=<rule>:<reason>`
  comments referencing this ADR.
