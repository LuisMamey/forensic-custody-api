# ADR 0006: Terraform Remote State Backend Hardening Scope

## Status
Accepted

## Context
Checkov policy suite flags five configurations against the Terraform state backend infrastructure in `terraform/backend_infra.tf`:
- `aws_s3_bucket.terraform_state`:
  - `CKV_AWS_18`: access logging is not enabled.
  - `CKV_AWS_144`: cross-region replication is not enabled.
  - `CKV_AWS_145`: bucket is not encrypted with a customer-managed KMS key (KMS CMK).
  - `CKV2_AWS_62`: event notifications are not enabled.
- `aws_dynamodb_table.terraform_locks`:
  - `CKV_AWS_119`: table is not encrypted using a customer-managed KMS CMK.

## Decision
We deliberately accept suppressing these controls for the backend management infrastructure:

- **Access Logging (`CKV_AWS_18`) & Event Notifications (`CKV2_AWS_62`):** The remote state bucket holds transient state snapshots and is strictly accessible only by authenticated Terraform CLI runners. There are no downstream consumers (Lambda, SQS) requiring bucket events, and access is monitored through AWS CloudTrail management events.
- **Cross-Region Replication (`CKV_AWS_144`):** The project operates in a single region (`us-east-1`). S3 provides 99.999999999% (11 9s) of durability across multiple Availability Zones natively. Cross-region replication introduces unnecessary multi-region egress costs and operational complexity without business disaster-recovery necessity.
- **KMS Customer-Managed Keys (`CKV_AWS_145`, `CKV_AWS_119`):** Both the S3 state bucket and DynamoDB lock table are securely encrypted at rest using AWS native server-side encryption (`AES256` / AWS managed key). Dedicated KMS CMKs incur monthly per-key costs and per-request cryptographic charges on every Terraform plan/apply operation. For transient state locks (where lock IDs contain only md5 hashes and UUIDs) and remote state, AWS-managed encryption satisfies zero-plaintext compliance.

## Consequences
- **Positive:** Minimizes operational cost while maintaining zero-plaintext encrypted storage and multi-AZ durability for state files.
- **Negative / Accepted Risk:** State is not replicated to a second geographical AWS region; access analysis relies on CloudTrail rather than S3 access logs.
- **Suppression:** Suppressed via `#checkov:skip=<rule>:Accepted risk — see docs/adr/0006-backend-state-hardening-scope.md` across `terraform/backend_infra.tf`.
