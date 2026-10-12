# Phase 5 Case File — Cloud Platform, Edge Hardening & Zero-Trust Secrets

Continuation of [PHASE4_HISTORY.md](PHASE4_HISTORY.md), documenting Sprint 3, Phase 1 of `forensic-custody-api`: multi-tier network isolation, hardened Kubernetes orchestration on Bottlerocket OS, Layer 7 Application Load Balancing with AWS WAF v2 edge protection, and Zero-Trust secrets synchronization via External Secrets Operator (ESO) with EKS Pod Identity. Exhibit numbering continues from Phase 4 (which concluded at Exhibit 27).

---

## 1. Network Topology & Container OS Hardening

### Exhibit 28 — Multi-Tier VPC Segmentation (`terraform/vpc.tf`)
**Role:** Logical network boundary and blast radius containment across availability zones.

Created by **AWS** (2009) to replace flat-network topologies with software-defined routing, subnets, and gateways.

**Why here:** Configured in `terraform/vpc.tf` using CIDR `10.0.0.0/16` across two Availability Zones:
* **Public Subnets (10.0.1.0/24, 10.0.2.0/24):** DMZ reserved exclusively for external Application Load Balancers. Tagged with `kubernetes.io/role/elb = 1`.
* **Private Subnets (10.0.10.0/24, 10.0.20.0/24):** Compute tier hosting EKS worker nodes and forensic API pods. Outbound internet egress routed via a single NAT Gateway. Tagged with `kubernetes.io/role/internal-elb = 1`.
* **Intra Subnets (10.0.100.0/24, 10.0.200.0/24):** Isolated persistence tier with zero internet routing or NAT gateways.

**Real architectural decision (ADR 0004):** Verified module usage via the official Terraform AWS Registry (`~> 5.0`) over unpinned raw git commit URLs, balancing automated Dependabot updates with `.terraform.lock.hcl` cryptographic pinning.

---

### Exhibit 29 — Hardened Kubernetes Cluster & Bottlerocket OS (`terraform/eks.tf`)
**Role:** Minimalist, immutable Linux operating system engineered specifically for hosting containers.

Created by **Amazon Web Services (AWS)** in 2020 as an open-source container-optimized OS (`bottlerocket-os/bottlerocket`).

**Why here:** Configured in `terraform/eks.tf` running Kubernetes v1.31 control plane with all audit logging enabled (`api`, `audit`, `authenticator`, etc.). Worker nodes run on `t3.small` instances under `ami_type = "BOTTLEROCKET_x86_64"`:
* **Read-Only Root Filesystem (`dm-verity`):** System binaries cannot be modified or replaced by runtime processes.
* **No Shells or Package Managers:** Contains no `bash`, `sh`, `yum`, or `apt`, depriving attackers of living-off-the-land binaries.
* **SELinux in Enforcing Mode:** Native mandatory access control isolating container runtimes from host kernel primitives.
* **Atomic Partition Updates:** OS updates occur as full A/B partition swaps with automatic rollback on boot failure.

---

## 2. Perimeter Defense & Zero-Trust Secrets

### Exhibit 30 — Edge Ingress & AWS WAF v2 Mitigation (`terraform/alb.tf`, `terraform/waf.tf`)
**Role:** Layer 7 traffic scrubbing, anti-DDoS, and OWASP Top 10 perimeter enforcement.

Created by **AWS** (ALB in 2016; WAF v2 in 2019).

**Why here:** Deployed across public DMZ subnets terminating TLS 1.3:
* **Security Group Hardening:** Closed insecure port 80; strictly permits port 443 (HTTPS) ingress, mitigating `CKV_AWS_260`.
* **WAF v2 Web ACL:** Enforces Layer 7 Rate Limiting (500 requests per 5 minutes per IP), `AWSManagedRulesCommonRuleSet` (OWASP Top 10), and `AWSManagedRulesKnownBadInputsRuleSet`.
* **Centralized Audit Logging:** Forwards inspection logs to CloudWatch Log Group `aws-waf-logs-forensic-custody` encrypted with our KMS CMK and retained for 365 days.

**Real architectural decision (ADR 0005):** Documented trade-offs for suppressing ELB access logging, deletion protection, and Log4j-specific rules (`CKV2_AWS_76`) due to Go runtime architectural immunity (zero Java/JVM dependencies).

---

### Exhibit 31 — External Secrets Operator (ESO) & EKS Pod Identity (`terraform/secrets.tf`)
**Role:** Secure retrieval and in-memory Kubernetes Secret injection without disk credentials.

Created by the **CNCF Community** (~2020).

**Why here:** Configured in `terraform/secrets.tf`. Integrates **AWS Secrets Manager** (`forensic-custody/api/jwt-secret` encrypted via KMS CMK) with Kubernetes:
* **EKS Pod Identity:** Grants IAM permissions to the `external-secrets-sa` ServiceAccount using temporary AWS STS credentials (`pods.eks.amazonaws.com`), eliminating static access keys from nodes.
* **Least-Privilege IAM Policy:** Restricts access strictly to `secretsmanager:GetSecretValue` on the specific secret ARN and `kms:Decrypt` on the evidence KMS key.
* **Secret Hygiene:** Eliminated literal secret values from Terraform code (`CKV_SECRET_6`), managing sensitive values outside Git history.

**Real architectural decision (ADR 0008):** Deferred standalone Lambda-based automated rotation for symmetric JWT verification keys, relying on operator-driven polling synchronization.
