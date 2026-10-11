# ADR 0005: Application Load Balancer security scope (logging, deletion protection, and Log4j WAF rule applicability)

## Status
Accepted

## Context
Checkov policy suite flags three configurations against the Application Load Balancer resource (`aws_lb.api` in `terraform/alb.tf`):
- `CKV_AWS_91`: "Ensure the ELBv2 has access logging enabled".
- `CKV_AWS_150`: "Ensure that Load Balancer has deletion protection enabled".
- `CKV2_AWS_76`: "Ensure AWS ALB attached WAFv2 WebACL is configured with AMR for Log4j Vulnerability".

## Decision
We deliberately accept suppressing these controls for the project's current deployment lifecycle:

- **ELB Access Logging (`CKV_AWS_91`):** Enabling ALB access logging requires provisioning and maintaining a dedicated S3 bucket configured with AWS ELB Service Account permissions (`us-east-1` ELB account ID `127311923021`). In our current architecture, edge traffic inspection, IP metrics, and request sampling are already captured in real-time by **AWS WAF v2** (`aws_wafv2_web_acl.api_waf`). Adding duplicate S3 access logging introduces architectural overhead and recurring storage costs without providing incremental security value for a single-tenant laboratory environment.
- **Deletion Protection (`CKV_AWS_150`):** In high-availability multi-tenant corporate production, deletion protection prevents catastrophic accidental teardown. However, in our CI/CD learning and automated testing environment, infrastructure must remain fully ephemeral and cleanable via standard `terraform destroy` workflows. Enabling deletion protection causes automated pipeline destructions to fail with access denied errors until manual console intervention occurs.
- **Log4j Vulnerability Mitigation AMR (`CKV2_AWS_76`):** The forensic custody API application is compiled natively in **Go 1.27** (`net/http`) packaged into an unprivileged Google Distroless runtime image. The application stack contains zero Java Virtual Machine (JVM) runtimes, Java classpath dependencies, or Apache Log4j libraries. Consequently, the JNDI remote code execution attack vector (CVE-2021-44228 / Log4Shell) is completely inapplicable to this system's architecture. The attached AWS WAF already enforces generic Layer 7 protections via `AWSManagedRulesCommonRuleSet` and rate limiting.

## Consequences
- **Positive:** Preserves clean ephemeral infrastructure automation; avoids circular AWS service-account bucket permission overhead; documents application runtime immunity against JVM-specific exploit chains.
- **Negative / Accepted Risk:** Historical raw HTTP access logs are not indefinitely archived to S3; the load balancer can be destroyed if `terraform destroy` is explicitly invoked by an authorized administrator.
- **Suppression:** Suppressed via:
  - `#checkov:skip=CKV_AWS_91:Accepted risk — see docs/adr/0005-alb-security-scope.md`
  - `#checkov:skip=CKV_AWS_150:Accepted risk — see docs/adr/0005-alb-security-scope.md`
  - `#checkov:skip=CKV2_AWS_76:Accepted risk — see docs/adr/0005-alb-security-scope.md`
