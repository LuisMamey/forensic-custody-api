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
- Positive: no certificate-management complexity is introduced in a
  learning project; the design matches the real production pattern (TLS
  termination at the network edge).
- Negative / accepted risk: no TLS-terminating load balancer exists yet.
  Phase 1's Terraform work provisioned only S3 (evidence storage) and IAM
  (least-privilege access) — provisioning real compute and a load balancer
  was explicitly scoped out (see the project's decision log) as a separate,
  optional extension, not something this ADR blocks on. Traffic between an
  external client and this API would travel unencrypted if ever deployed
  as-is. Acceptable today because the service is only run on `localhost`
  or in ephemeral CI containers, never exposed to an untrusted network.

## Update note
This ADR originally implied the load balancer was "pending" as part of
Phase 1. Phase 1 is now complete and did not include one — deploying real
compute (ECS/EC2 + ALB) remains unscoped, future work, not a pending step.
