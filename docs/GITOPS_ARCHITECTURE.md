# Forensic Custody API — Continuous Delivery with GitOps (ArgoCD)

## 1. Executive Summary & Architecture Paradigm
In traditional CI/CD pipelines ("Push-based model"), external runners (e.g., GitHub Actions) require administrative cluster credentials (`kubeconfig` or AWS IAM credentials with `cluster-admin` RBAC) to reach into the private Kubernetes cluster and execute `kubectl apply`. 

In high-assurance digital forensics and regulated infrastructure, this constitutes an unacceptable supply chain risk: compromising a CI runner or pipeline step allows an attacker to exfiltrate cluster credentials and hijack the entire runtime plane.

`forensic-custody-api` adopts the **GitOps Pull-based Delivery Model** powered by **ArgoCD** (CNCF Graduated Project).

```mermaid
flowchart LR
    Dev["Developer"] -->|git push| GH["GitHub Repository<br/>(Single Source of Truth)"]
    GH -->|CI Security Gate| CI["GitHub Actions<br/>(SAST, SCA, k6, Cosign)"]
    CI -->|Push Signed Digest| Registry["GitHub Container Registry<br/>(ghcr.io)"]
    
    subgraph EKS["AWS EKS Private Cluster (No Inbound CI Access)"]
        Argo["ArgoCD Controller<br/>(In-Cluster Agent)"]
        K8s["Kubernetes Workloads<br/>(forensic-custody-api)"]
    end
    
    Argo -->|1. Poll / Webhook (Outbound)| GH
    Argo -->|2. Detect Drift / Reconcile| K8s
```

---

## 2. Push vs. Pull Model Comparison

| Dimension | Traditional CI/CD (Push Model) | GitOps with ArgoCD (Pull Model) |
|---|---|---|
| **Credentials Location** | Stored inside GitHub Secrets / CI Runner. | Zero cluster credentials outside the private network. |
| **Cluster Firewall** | Requires opening inbound access from CI runners. | Purely outbound connections; cluster API stays private. |
| **Single Source of Truth** | Ambiguous: cluster state can diverge from Git. | Absolute: Git is the single, versioned declaration of truth. |
| **Drift Detection** | None: manual `kubectl` changes go undetected. | Real-time: detects out-of-sync resources within seconds. |
| **Self-Healing** | Requires manual redeployment or pipeline rerun. | Automated: rolls back unauthorized manual cluster changes. |
| **Auditability & Forensics** | Dependent on ephemeral CI logs. | Complete cryptographic git commit log with signed commits. |

---

## 3. ArgoCD Application Topology & Configuration

The deployment lifecycle is managed via a declarative Custom Resource Definition (`kind: Application` in `k8s/gitops/argocd-application.yaml`):

* **Source Repository:** `https://github.com/LuisMamey/forensic-custody-api.git`
* **Target Revision:** `main` branch.
* **Manifests Directory:** `k8s/apps/forensic-custody-api` (Deployment, Service, ServiceAccount).
* **Destination Cluster:** Local EKS control plane (`https://kubernetes.default.svc`).
* **Automated Sync Policy:**
  - `prune: true`: Automatically deletes resources removed from Git to prevent zombie or orphaned objects.
  - `selfHeal: true`: If an operator or malicious process attempts an ad-hoc mutation (`kubectl edit`), ArgoCD instantly overrides it with the Git-declared state.
  - `retry`: Exponential backoff (5 retries, 5s initial, factor 2) ensuring resilient recovery during transient network blips.

---

## 4. Alignment with Defense-in-Depth & Admission Control

ArgoCD operates cooperatively with our previously established security controls:

1. **Kyverno Admission Enforcement:**
   When ArgoCD applies the manifests from `k8s/apps/forensic-custody-api`, the Kubernetes API Server routes the admission request to **Kyverno**. Kyverno validates that:
   - The container runs as non-root (`UID 65532`).
   - The root filesystem is strictly read-only (`readOnlyRootFilesystem: true`).
   - The container image is cryptographically verified against the **Sigstore / Rekor** transparency log using Cosign keyless signatures.
2. **Falco Runtime Monitoring:**
   Once pods are scheduled by ArgoCD on our immutable **Bottlerocket OS** nodes, **Falco eBPF** kernel probes monitor syscalls in real time.
3. **Prometheus Telemetry:**
   Pods declare Prometheus annotations (`prometheus.io/scrape: "true"`), allowing automatic metrics scraping on port 8080 to measure the established SLIs/SLOs.
   