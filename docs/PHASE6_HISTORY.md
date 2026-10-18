# Phase 6 Case File — Runtime Security, SRE Observability & GitOps Platform

Continuation of [PHASE5_HISTORY.md](PHASE5_HISTORY.md), documenting Sprint 3, Phases 2 and 3 of `forensic-custody-api`: cryptographic Kubernetes admission governance with Kyverno, kernel-space eBPF intrusion detection with Falco, HTTP server resilience and graceful connection draining, Prometheus/OpenTelemetry instrumentation, formal SLI/SLO and Error Budget engineering, k6 load validation, Alertmanager multi-burn-rate routing with Blameless RCA postmortems, and Pull-based GitOps continuous delivery with ArgoCD and Helm cluster bootstrapping. Exhibit numbering continues from Phase 5 (which concluded at Exhibit 31).

---

## 1. Runtime Security & Admission Governance

### Exhibit 32 — Cryptographic Admission Control (`k8s/policies/`, `Kyverno`)
**Role:** Kubernetes Dynamic Admission Webhook validating Pod security posture and container supply chain provenance prior to scheduling.

Created by **Nirmata** in 2019 and donated to the **Cloud Native Computing Foundation (CNCF)** as a Kubernetes-native policy engine (`kyverno/kyverno`).

**Why here:** Enforced in `k8s/policies/disallow-root-and-privileged.yaml` and `k8s/policies/verify-image-cosign.yaml`, and tested in CI via `kyverno-cli` (`k8s/policies/kyverno-test.yaml`):
* **Pod Security Standards (Restricted):** Blocks any Pod attempting to run as root (`runAsNonRoot: true`), escalate privileges (`allowPrivilegeEscalation: false`), retain Linux capabilities (`drop: ["ALL"]`), or mount a writable root filesystem (`readOnlyRootFilesystem: true`).
* **Cryptographic Signature Verification (`verifyImages`):** Rejects any `forensic-custody-api` container image that lacks a valid keyless **Sigstore Cosign** signature attested by our GitHub Actions OIDC workflow (`supply-chain.yml`) and recorded in the immutable **Rekor** transparency log.

---

### Exhibit 33 — Kernel Syscall Anomaly Detection (`k8s/falco/forensic-api-rules.yaml`, `Falco eBPF`)
**Role:** Cloud-Native Runtime Security and Cloud Workload Protection Platform (CWPP) monitoring Linux kernel system calls in real time.

Created by **Sysdig** in 2016 and donated to the **CNCF** as the de facto runtime intrusion detection standard for Kubernetes (`falcosecurity/falco`, CNCF Graduated).

**Why here:** Configured in `k8s/falco/forensic-api-rules.yaml` (validated in CI with `falco -V`) and deployed to EKS via Helm using the `modern_ebpf` driver compatible with read-only **Bottlerocket OS** worker nodes:
1. **`Unauthorized Process in Forensic API Container` (`CRITICAL`):** Detects any `execve` syscall inside `forensic-custody-api` where the executed binary is not the compiled `/api` binary.
2. **`Unexpected Outbound Connection from Forensic Pod` (`WARNING`):** Flags unexpected outbound `connect`/`sendto` network calls to non-HTTPS ports.
3. **`Tamper Attempt on Evidence Storage Directory` (`ALERT`):** Alerts on any `unlink`, `rmdir`, or `rename` syscall targeting `/evidence`.

---

### Exhibit 34 — HTTP Server Hardening & Graceful Shutdown (`cmd/api/main.go`)
**Role:** Application-layer Denial-of-Service resilience and zero-downtime connection draining during rolling Kubernetes deployments.

Built into the **Go Standard Library** (`net/http`, `os/signal`, `context`).

**Why here:** Configured in `cmd/api/main.go`:
* **Slowloris & Socket Exhaustion Mitigation:** Explicit timeouts bound slow clients (`ReadHeaderTimeout: 5s`, `ReadTimeout: 15s`, `WriteTimeout: 30s`, `IdleTimeout: 60s`).
* **Graceful Connection Draining:** Traps `os.Interrupt` and `syscall.SIGTERM` via `signal.NotifyContext`. Upon pod termination, `srv.Shutdown(shutdownCtx)` stops accepting new requests while allowing active forensic uploads and cryptographic operations up to 15 seconds to complete cleanly before closing sockets.

---

## 2. Observability, SRE Operations & Progressive Delivery

### Exhibit 35 — Unified Telemetry & Prometheus Instrumentation (`internal/telemetry/`)
**Role:** White-box application instrumentation exporting Golden Signals (Traffic, Errors, Latency, Saturation).

Created at **SoundCloud** in 2012 (**Prometheus**, CNCF Graduated) and standardized alongside **OpenTelemetry (OTel)**.

**Why here:** Implemented in `internal/telemetry/metrics.go` and `internal/telemetry/middleware.go`, exposed at `GET /metrics`:
* `forensic_http_requests_total`: Counter partitioned by `method`, `path`, and `status`.
* `forensic_http_request_duration_seconds`: Histogram with SLI-aligned buckets (`5ms` to `5s`).
* `forensic_crypto_hashing_duration_seconds`: Histogram tracking streaming SHA-256/SHA-512 computation latency.
* `forensic_custody_transitions_total`: Counter auditing domain custody state transitions.

---

### Exhibit 36 — SRE SLI/SLO & Error Budget Framework (`docs/SLO_FRAMEWORK.md`, `k8s/monitoring/prometheus-slo-rules.yaml`)
**Role:** Mathematical reliability contract and automated burn-rate evaluation.

Originated by **Google SRE** (2003–2016).

**Why here:** Codified in `docs/SLO_FRAMEWORK.md` and enforced via `PrometheusRule` recording and alerting rules in `k8s/monitoring/prometheus-slo-rules.yaml`:
* **Availability SLO:** **99.9%** non-5xx responses over a 30-day window ($0.1\%$ Error Budget = 43.2 minutes/month).
* **Latency SLO:** **p99 < 250ms** for read operations (`GET`).
* **Fast-Burn Alerting:** Triggers `ForensicApiAvailabilityHighBurnRate` (`critical`) when the 1-hour error burn rate exceeds $14.4\times$ (consuming $2\%$ of the monthly budget in 1 hour).

---

### Exhibit 37 — Automated Load & SLO Threshold Testing (`tests/load/k6-slo-test.js`, `k6`)
**Role:** Developer-centric load testing and automated CI performance gate.

Created by **Load Impact / Grafana Labs** in 2017 (`grafana/k6`).

**Why here:** Configured in `tests/load/k6-slo-test.js` and executed automatically in `.github/workflows/security.yml` (`load-test` job):
* Simulates 20 concurrent forensic investigators ramping up and querying authenticated endpoints (`/cases`, `/health`, `/metrics`).
* Enforces hard pass/fail thresholds (`http_req_failed: ['rate<0.001']`, `http_req_duration: ['p(99)<250']`), achieving >320 req/s with $0\%$ error rate and $\text{p99} < 35\text{ms}$.

---

### Exhibit 38 — Alert Hygiene & Blameless Incident Postmortems (`k8s/monitoring/alertmanager-config.yaml`, `docs/postmortems/`)
**Role:** Deduplicated alert routing, inhibition rules, and structured Root Cause Analysis (RCA).

**Why here:**
* **Alertmanager (`alertmanager-config.yaml`):** Groups alerts by `['alertname', 'namespace', 'job']`, routes `critical` budget burns to PagerDuty and `warning` latency breaches to Slack, and enforces an `inhibitRule` suppressing secondary latency alerts when an availability outage is already active.
* **Blameless Postmortem (`docs/postmortems/INCIDENT-2026-001-K6-JWT-AUTH.md`):** Documents the 5-Whys RCA when k6 synthetic tests initially failed with HTTP 401 and Gitleaks intercepted a hardcoded test JWT, resolved by synthesizing ephemeral HMAC-SHA256 tokens dynamically via `__ENV.AUTH_TOKEN`.

---

### Exhibit 39 — Pull-Based GitOps & In-Cluster Platform Bootstrap (`k8s/gitops/`, `k8s/apps/`, `terraform/cluster_addons.tf`, `scripts/platform.sh`)
**Role:** Zero-privilege continuous reconciliation, automated Day-0 Helm operator and policy provisioning, and one-command platform lifecycle management.

Created by **Intuit** in 2018 (**ArgoCD**, CNCF Graduated).

**Why here:**
* **Day-0 Platform & Policy Bootstrap (`terraform/cluster_addons.tf`):** Uses the Terraform Helm provider (`terraform/main.tf`) with dynamic STS `exec` authentication (`aws eks get-token`) bound to `module.eks` to automatically install the 5 in-cluster engines (**ArgoCD**, **Kyverno**, **Falco** `modern_ebpf`, **External Secrets Operator**, and **kube-prometheus-stack**) and declaratively inject all governance/SRE manifests from `k8s/` (`argocd-application.yaml`, `disallow-root-and-privileged.yaml`, `verify-image-cosign.yaml`, `forensic-api-rules.yaml`, `prometheus-slo-rules.yaml`, and `alertmanager-config.yaml`).
* **Day-1 GitOps Delivery & Immutable Digest Pinning (`k8s/gitops/argocd-application.yaml`, `k8s/apps/forensic-custody-api/deployment.yaml`, `docs/GITOPS_ARCHITECTURE.md`):** Configures ArgoCD to continuously reconcile `k8s/apps/forensic-custody-api` pinned to its Cosign-signed `@sha256` manifest digest with `automated.prune: true` and `automated.selfHeal: true`, while `scripts/platform.sh` (`up`, `status`, `tunnel`, `down`) provides SHA-256 verified chart caching and ordered infrastructure teardown.

