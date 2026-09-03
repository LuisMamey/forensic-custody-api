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
- Negative / accepted risk: until the TLS-terminating load balancer exists
  (pending in Phase 1's Terraform step), traffic between an external client
  and this API travels unencrypted. Acceptable today because the service is
  only tested on `localhost`, never exposed to an untrusted network.
