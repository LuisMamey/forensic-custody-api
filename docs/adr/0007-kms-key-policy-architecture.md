# ADR 0007: AWS KMS Key Policy Resource Wildcard and Delegation Constraints

## Status
Accepted

## Context
Checkov policy suite flags three configurations against the KMS Customer Managed Key policy document in `terraform/kms.tf`:
- `data.aws_iam_policy_document.kms_evidence_key_policy`:
  - `CKV_AWS_109`: IAM policies does not allow permissions management / resource exposure without constraints.
  - `CKV_AWS_111`: IAM policies does not allow write access without constraints.
  - `CKV_AWS_356`: IAM policies documents allow "*" as a statement's resource for restrictable actions.

## Decision
We deliberately accept suppressing these three rules due to native AWS KMS architectural constraints:

- **Resource Wildcard Requirement in Key Policies (`CKV_AWS_111`, `CKV_AWS_356`):** In AWS KMS, a Key Policy is a resource-based policy directly embedded into the specific KMS key itself. AWS KMS specification formally mandates that statements inside a Key Policy must use `"Resource": "*"` to refer to the key to which the policy is attached. Specifying the key ARN directly inside its own key policy is not supported during creation and fails validation.
- **Root Account Delegation (`CKV_AWS_109`):** Statement `EnableRootIAMManagement` grants full administrative delegation to the AWS account root principal (`arn:aws:iam::<account_id>:root`). This is an AWS mandatory best practice to ensure that account administrators can manage and delegate KMS permissions via IAM policies without permanently locking out access to the cryptographic key.

## Consequences
- **Positive:** Complies with AWS KMS official key policy specification; prevents irreversible administrative lockout.
- **Negative / Accepted Risk:** Automated static analysis tools flag wildcard resource strings, which is mitigated by the contextual fact that key policies only govern the key they are bound to.
- **Suppression:** Suppressed via `#checkov:skip=<rule>:Accepted risk — see docs/adr/0007-kms-key-policy-architecture.md` inside `terraform/kms.tf`.
