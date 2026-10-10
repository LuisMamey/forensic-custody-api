# ADR 0004: Terraform module sourcing from official registry vs Git commit hash

## Status
Accepted

## Context
Checkov policy `CKV_TF_1` flagged the `module.vpc` declaration in `terraform/vpc.tf`:
- `CKV_TF_1`: "Ensure Terraform module sources use a commit hash".
Checkov recommends referencing third-party modules directly via full Git URLs with immutable commit revisions (e.g. `git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=...`).

## Decision
We accept the use of the official Terraform Registry source (`terraform-aws-modules/vpc/aws`) constrained by semantic versioning (`~> 5.0`), rather than direct Git commit hashes, for the following reasons:

- **Official Registry Integration:** `terraform-aws-modules/vpc/aws` is the AWS community-maintained, verified module standard for enterprise VPC architectures.
- **Dependency & Lockfile Parity:** The Terraform Registry protocol allows Terraform to automatically fetch, verify checksums, and lock module dependencies deterministically in `.terraform.lock.hcl` and the local `.terraform/` module cache.
- **Maintenance & Patching Lifecycle:** Direct Git URL commit hashing prevents standard automated semantic dependency tooling (like Dependabot's Terraform package ecosystem) from detecting minor bug fixes or security patches within the `5.x` series.
- **Checkov Policy Balance:** The module satisfies `CKV_TF_2` ("Ensure Terraform module sources use a tag with a version number"), proving that unversioned floating sources are strictly prevented.

## Consequences
- **Positive:** Leverages canonical, battle-tested cloud-native infrastructure modules; enables automated SemVer updates via Dependabot; reduces URL maintenance complexity.
- **Negative / Accepted Risk:** If upstream registry metadata or tag pointers were ever compromised, an upstream package could theoretically be altered. This is mitigated by Terraform's provider lockfile hashes and CI gate validations.
- **Suppression:** Suppressed via `#checkov:skip=CKV_TF_1:Accepted risk — see docs/adr/0004-terraform-module-pinning.md` inside `terraform/vpc.tf`.
