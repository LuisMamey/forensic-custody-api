# Infrastructure as Code (IaC) Scanning vs. CSPM & Drift Detection

## 1. The Core Distinction: Intent vs. Reality

| Dimension | IaC Security (Checkov) | Cloud Security Posture Management (CSPM / Prowler) |
|---|---|---|
| **Lifecycle Phase** | **Pre-deployment (Shift-Left):** Evaluated inside Git / CI pipeline. | **Post-deployment (Runtime):** Evaluated continuously against live AWS APIs. |
| **Analyzed Target** | Static HCL code (`terraform/*.tf`) and plan files. | Real cloud resources in the AWS Account (via Read-Only IAM role). |
| **What it Verifies** | **Declarative Intent:** Are policies, tags, and encryption defined in code? | **Actual State:** Are resources deployed securely and compliant in production? |
| **Blind Spots** | Cannot detect out-of-band manual changes made via AWS Console or CLI. | Cannot prevent insecure code from being merged into `main`. |
| **Tool in this Stack** | **Checkov** (`bridgecrew/checkov:3.3.16` in `security.yml`). | **Prowler / AWS Security Hub** (audits live S3 buckets & IAM roles). |

---

## 2. Configuration Drift in the Forensic Context

### What is Drift?
**Configuration Drift** occurs when the live state of cloud infrastructure diverges from the state defined in Git version control.

### Forensic Risk Scenario:
1. `terraform/s3.tf` defines S3 Object Lock and denies unauthenticated public access. Checkov passes with exit code 0 in CI.
2. An AWS account operator manually modifies the S3 bucket via the AWS Console to disable access logging or grants temporary permissions (`s3:BypassGovernanceRetention`).
3. **The Failure Mode:** The Git repository remains unchanged. Future CI runs with Checkov **will still report 0 errors** because the source code is clean, while production evidence is actively compromised.

---

## 3. Defense-in-Depth Architecture

To guarantee total posture integrity:
1. **Preventive Gate (CI/CD):** Checkov blocks insecure Terraform definitions before merge.
2. **Drift Detection (Scheduled CI / Terraform Cloud):** Scheduled daily runs of `terraform plan -detailed-exitcode` flag out-of-band changes.
3. **Continuous Auditing (CSPM):** Prowler or AWS Security Hub continuously scans the live AWS environment against CIS AWS Foundations Benchmarks, alerting security teams if S3 or IAM drifts from baseline.
