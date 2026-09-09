# ADR 0003: Object Lock retention mode (Governance, not Compliance)

## Status
Accepted

## Context
Both S3 buckets (`evidence` and `evidence_logs`) have Object Lock enabled
with a default retention rule (`aws_s3_bucket_object_lock_configuration`).
S3 Object Lock supports two retention modes:
- **GOVERNANCE**: protects objects from deletion/overwrite by default, but a
  principal explicitly granted the `s3:BypassGovernanceRetention` permission
  can override it.
- **COMPLIANCE**: no principal — not even the AWS account root user or AWS
  Support — can shorten or remove the retention period once applied. It is
  irreversible until the retention period expires.

## Decision
Use **GOVERNANCE** mode, not COMPLIANCE, with a short default retention
(1 day) while this project is in active learning/development.

This project is still being iterated on: test objects get uploaded,
inspected, and often need to be deleted or overwritten as part of normal
work. COMPLIANCE mode would make any mistake (wrong test data, wrong
bucket, wrong retention period) permanent and unrecoverable — potentially
for a long time, at ongoing storage cost, with no way to undo it through
any means, including AWS Support. GOVERNANCE still enforces the core
protection this project cares about (no *unprivileged* actor can delete or
alter evidence) while leaving an emergency escape hatch for whoever holds
the `s3:BypassGovernanceRetention` permission.

In a real production chain-of-custody system, **COMPLIANCE** is the
conceptually correct choice — the entire point is that *nobody*, including
administrators, should be able to alter evidence during its retention
period, matching regulatory retention requirements (e.g., SEC Rule
17a-4(f), which explicitly names S3 Object Lock Compliance mode as a way to
meet WORM — Write Once, Read Many — requirements). This project defers
COMPLIANCE mode until it moves beyond active learning/iteration.

## Consequences
- Positive: mistakes made while learning (wrong test uploads, wrong
  retention configuration) remain recoverable via
  `s3:BypassGovernanceRetention`, avoiding permanently stuck objects and
  unbounded storage cost from an irreversible mistake.
- Negative / accepted risk: GOVERNANCE mode is not equivalent to true
  immutability — any IAM principal explicitly granted
  `s3:BypassGovernanceRetention` could delete or overwrite "locked"
  evidence before its retention expires. The current IAM policy (`iam.tf`)
  does not grant this permission to any role, so in practice no one can
  bypass the lock today — this should be re-verified before treating this
  design as production-ready.
- The default retention period (1 day) is a placeholder for testing, not a
  real evidentiary retention period, and must be revisited (likely years,
  per applicable legal/regulatory requirements) before any real use.
