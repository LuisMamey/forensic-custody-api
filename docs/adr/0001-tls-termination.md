# ADR 0001: TLS termination at the load balancer, not the application

## Status
Accepted

## Context
Semgrep (SAST) flagged a blocking finding: `cmd/api/main.go` runs an HTTP
server without TLS (rule `go.lang.security.audit.net.use-tls.use-tls`).
Implementing TLS at the application level would require managing
certificates (self-signed for development), which:
- Cannot be done inside the final Docker image, since it is `distroless`
  (no shell, no tooling to generate or manage certificates at runtime).
- Would break the local testing workflow (clients reject a self-signed
  certificate by default).
- Would be throwaway work: this project's plan includes provisioning a
  load balancer with Terraform, which is the standard place in the industry
  to terminate TLS with a real certificate (AWS Certificate Manager).

## Decision
TLS is not implemented in the application code. The server keeps listening
on plain HTTP on port 8080. The Semgrep finding is explicitly suppressed
with `// nosemgrep` in `main.go`, referencing this ADR.

## Consequences
- Positive: no certificate-management complexity is introduced inside the
  container image; the design matches the enterprise production pattern (TLS
  termination at the network edge).
- Negative / accepted risk: traffic between the ALB and the Kubernetes pods
  travels over plain HTTP within the isolated private VPC subnets
  (`10.0.10.0/24`, `10.0.20.0/24`). External internet traffic is restricted to
  HTTPS (port 443) at the ALB security group boundary (`terraform/alb.tf`).

## Update note
Originally written in Sprint 1 prior to compute and ingress provisioning. In
Sprint 3, the external Application Load Balancer (`terraform/alb.tf`), AWS WAF v2
(`terraform/waf.tf`), and private AWS EKS cluster (`terraform/eks.tf`) were
provisioned, completing the edge TLS termination architecture described here.
