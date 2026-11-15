# Chaos Engineering & SRE Game Day Report

**Date:** 2026-11-14  
**Environment:** AWS EKS (`forensic-custody-eks`, `us-east-1`, Kubernetes v1.31.14 on 4× Bottlerocket OS nodes)  
**Baseline Stability:** `2d10h` continuous uptime (39/39 pods `Running`, `0` spontaneous restarts)

---

## 1. Executive Summary & Cluster Baseline

This Game Day validated the resilience, observability, and admission security of `forensic-custody-api` under simulated production failures. Rather than relying on static CPU/memory thresholds, experiments measured real user-facing **SLIs/SLOs** (99.9% Availability and p99 < 250ms GET Latency) and verified **Zero-Trust Supply Chain Enforcement** at the Kubernetes admission boundary.

![EKS Bottlerocket Nodes Uptime](assets/chaos-game-day/eks-nodes-uptime.png)

![Platform Operators Uptime](assets/chaos-game-day/platform-pods-uptime.png)

After collecting all metrics and forensic timestamps, the ephemeral AWS compute/network stack was cleanly decommissioned (`69` resources destroyed via `./scripts/platform.sh down`) to restore hourly billing to `$0.00/hr` while preserving the S3/DynamoDB Terraform remote state.

---

## 2. Experiment 1: Pod Termination & Self-Healing Under Peak Load

### Hypothesis
If an active `forensic-custody-api` replica is terminated during sustained concurrent traffic (200 VUs), Kubernetes will reconcile the ReplicaSet and spin up a healthy replacement within seconds without causing HTTP 5xx errors or violating the 99.9% availability SLO.

### Execution
1. **Sustained Load Generation (`k6`):**
   ```bash
   AUTH_TOKEN="<jwt-investigator>" ./bin/k6 run --duration 2m --vus 200 tests/load/k6-slo-test.js
   ```
2. **Chaos Injection (mid-test at `16:53:44 -0600`):**
   ```bash
   kubectl delete pod $(kubectl get pods -l app.kubernetes.io/name=forensic-custody-api -o jsonpath='{.items[0].metadata.name}')
   ```

### Observed Results & Forensic Correlation
* **Traffic Window (Grafana / Prometheus):** Sustained throughput peaked at **222 req/s (`status="200"`)** between `16:52:30` and `16:55:30 -0600` (`sum(rate(forensic_http_requests_total[1m])) by (status)`).

![Grafana Peak 222 req/s](assets/chaos-game-day/grafana-peak-222rps.png)

* **Exact Pod Replacement Timestamp:**
  * Surviving replica (`forensic-custody-api-7645689fb9-zb6ng`): `Start Time: Thu, 12 Nov 2026 07:22:52 -0600`
  * Replacement replica (`forensic-custody-api-7645689fb9-lpnlv`): `Start Time: Sat, 14 Nov 2026 16:53:44 -0600` (`Started: 16:53:45 -0600` — 1 second container startup).

![Pod Replacement Timestamps](assets/chaos-game-day/pod-replacement-timestamps.png)

* **k6 Summary Metrics:**
  * **Total HTTP Requests:** `75,657` (`~625 req/s` aggregate across checks)
  * **Availability (`http_req_failed`):** `0.00%` (`0` failed out of `75,657` requests)
  * **Functional Checks:** `100.00%` (`126,095` / `126,095` passed)
  * **Latency (`http_req_duration`):** `avg=284.58ms`, `med=265.21ms`, `p(90)=426.28ms`, `p(95)=489.13ms`, `max=1.15s` (crossed the strict `p(99) < 250ms` threshold due to single-tunnel contention + cross-region RTT to `us-east-1`).

![k6 Load Test Summary](assets/chaos-game-day/k6-load-test-200vus.png)

* **GitOps Topology & SLO Alert Rules:**

![ArgoCD Application Tree](assets/chaos-game-day/argocd-gitops-tree.png)

![Prometheus SLO Alert Rules](assets/chaos-game-day/prometheus-slo-alerts.png)

### Key Takeaways
* Go's `net/http` `Graceful Shutdown` (`srv.Shutdown` trapping `SIGTERM`) prevented dropped sockets on the terminating replica.
* **Tooling Nuance:** `kubectl port-forward svc/...` pins a single TCP tunnel to one backing pod (`zb6ng`). While this proved that `zb6ng` absorbed 222 req/s alone without dropping a request, true multi-replica load distribution in chaos tests should target the Ingress/ALB or run `k6` as an in-cluster Job against the `ClusterIP` Service.

---

## 3. Experiment 2: Admission Control & Supply Chain Governance Chaos

### Hypothesis
Attempting to deploy a privileged/root container or patch the production Deployment with an unsigned container image will be intercepted and denied at the Kubernetes API admission boundary before any pod is scheduled onto Bottlerocket nodes.

### Execution & Results

#### 2A. Malicious / Root Container Injection
* **Action:** `kubectl apply -f k8s/policies/resources/invalid-root-pod.yaml`
* **Result:** Denied by Kyverno `ClusterPolicy/disallow-root-and-privileged` (`Action=Enforce`).

![Kyverno Blocking Invalid Root Pod](assets/chaos-game-day/kyverno-block-root-pod.png)

#### 2B. Unsigned Image Rollout ("Broken Friday Deploy")
* **Action:**
  ```bash
  kubectl set image deployment/forensic-custody-api api=ghcr.io/luismamey/forensic-custody-api:broken-v999 -n default
  ```
* **Result:** Blocked at admission by Kyverno `ClusterPolicy/verify-image-cosign` (`autogen-verify-forensic-api-signature`), preventing unverified code from ever reaching the cluster.
* **Impact:** Zero production disruption; the existing signed replicas remained `2/2 Running` with `0` downtime.

![Kyverno Cosign Blocking Unsigned Image](assets/chaos-game-day/kyverno-block-unsigned-image.png)

---

## 4. Telemetry Fixes & Architectural Findings

### Fixes Applied During Game Day
1. **Prometheus Operator Discovery (`k8s/apps/forensic-custody-api/servicemonitor.yaml`):** Added the missing `ServiceMonitor` CRD with label `release: kube-prometheus-stack` so Prometheus actively scrapes `/metrics` every `10s`.
2. **SLO Alert Rule Loading (`k8s/monitoring/prometheus-slo-rules.yaml`):** Added `release: kube-prometheus-stack` to `PrometheusRule` metadata so `ForensicApiAvailabilityHighBurnRate` (14.4× Burn Rate) and `ForensicApiLatencyP99Breached` (`p99 > 250ms` over `5m`) are loaded by Prometheus.
3. **Resilient k6 Assertions (`tests/load/k6-slo-test.js`):** Guarded `r.body` against `null`/`undefined` on abrupt TCP connection drops so network failures are recorded cleanly as failed HTTP metrics instead of throwing a JS `TypeError`.

### Architectural Backlog Identified (Next Iteration)
* **In-Memory Split-Brain:** `MemoryStorage` (`internal/storage/storage.go`) is process-local while `deployment.yaml` runs `replicas: 2`. Multi-pod write/read flows require a shared persistent backend (e.g., PostgreSQL/DynamoDB) to prevent intermittent `404` responses across replicas.
* **Prometheus Label Cardinality:** `internal/telemetry/middleware.go` currently records raw `r.URL.Path`; normalizing path parameters (e.g., `/cases/{caseID}/evidence`) will prevent high-cardinality time-series growth under dynamic IDs.
* **Deep Health Probes:** `/health` currently returns a static `200 ok`; adding storage/dependency readiness checks will improve Kubernetes probe accuracy.
