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
- **KMS encryption**: both buckets already satisfy `CKV_AWS_19` (encrypted
  at rest) via S3's default SSE-S3 encryption. A customer-managed KMS key
  adds per-request and per-key cost plus key-management overhead (rotation,
  key policies) that isn't justified without a specific compliance
  requirement driving it.

## Consequences
- Positive: avoids unnecessary cost and operational complexity for a
  learning project; the lifecycle decision specifically reinforces the
  project's chain-of-custody design intent.
- Negative / accepted risk: data in both buckets is not geographically
  replicated (a single-region outage makes evidence temporarily or
  permanently unavailable), there is no automated reaction to new uploads,
  storage costs grow unbounded over time (no expiration), and encryption
  relies on AWS-managed keys rather than customer-managed ones (less control
  over key access and rotation).
- These findings are suppressed in Checkov with `#checkov:skip=<rule>:<reason>`
  comments referencing this ADR, one per rule per bucket.
