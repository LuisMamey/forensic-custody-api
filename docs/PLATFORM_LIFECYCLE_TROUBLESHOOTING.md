# Platform Lifecycle Engineering & Troubleshooting Guide

This document records the architectural root causes, edge cases, and engineering solutions discovered while hardening the automated platform lifecycle (`scripts/platform.sh up`, `down`, `status`, and `tunnel`) on AWS EKS with Bottlerocket OS and in-cluster Helm engines.

---

## 1. Executive Summary & Benchmark Metrics

The target of `scripts/platform.sh` is an **idempotent, single-command cold-start and teardown** of enterprise-grade cloud infrastructure, admitting zero manual interventions, zero dangling resources, and \$0.00/hr compute billing when destroyed.

| Operation | Real Execution Time | Resources Managed | Verified Cluster State |
| :--- | :--- | :--- | :--- |
| **`platform.sh up`** | **16m 41s** (1,001.80s) | 74 cloud resources | 39/39 pods running across 5 namespaces, ArgoCD Synced/Healthy, Kyverno Enforcing |
| **`platform.sh down`** | **15m 51s** (951.64s) | 69 destroyed resources | All hourly compute destroyed (\$0.00/hr); persistent S3/DynamoDB state preserved |

---

## 2. Issues Encountered & Architectural Solutions

### Issue 1: Helm CRD Discovery Deadlock (`Application` / `ClusterPolicy` Not Found)

#### Symptom
```text
Error: unable to build kubernetes objects from release manifest: resource mapping not found
for name: "forensic-custody-api" namespace: "argocd" from "":
no matches for kind "Application" in version "argoproj.io/v1alpha1"
ensure CRDs are installed first
  with helm_release.argocd,
  on cluster_addons.tf line 6, in resource "helm_release" "argocd"
```

#### Root Cause
In Terraform, `helm_release.argocd` declared an `extraObjects` block referencing `argocd-application.yaml` and Kyverno `ClusterPolicy` manifests. Helm client evaluation performs an OpenAPI validation against the Kubernetes API server cache **prior to applying any resources or CRDs in the chart**. Because the ArgoCD chart itself installs the `Application` CRD, Helm failed at pre-flight validation.

#### Solution
1. Removed `extraObjects` from `helm_release.argocd` in `terraform/cluster_addons.tf`.
2. Decoupled custom resource manifests into `scripts/platform.sh` post-bootstrap execution. The script polls the Kubernetes API server until CRDs are registered, then applies policies and GitOps manifests via `kubectl`:
```bash
while ! kubectl get crd clusterpolicies.kyverno.io applications.argoproj.io >/dev/null 2>&1; do
  sleep 3
done
kubectl apply -f "${ROOT_DIR}/k8s/policies/disallow-root-and-privileged.yaml"
kubectl apply -f "${ROOT_DIR}/k8s/policies/verify-image-cosign.yaml"
kubectl apply -f "${ROOT_DIR}/k8s/gitops/argocd-application.yaml"
```

---

### Issue 2: Teardown Deadlock via Asynchronous NAT Gateway Destruction

#### Symptom
```text
module.vpc.aws_nat_gateway.this[0]: Destruction complete after 1m2s
...
helm_release.kyverno: Still destroying... [id=kyverno, 05m00s elapsed]
Error: 1 error occurred:
    * timed out waiting for the condition
```

#### Root Cause
During `terraform destroy`, Terraform concurrently destroys unlinked resources. It destroyed `module.vpc.aws_nat_gateway` while simultaneously uninstalling `helm_release.kyverno`. Kyverno's Helm chart executes a pre-delete cleanup job (`webhooksCleanup` running `bitnamilegacy/kubectl`) to remove mutating and validating webhooks. Once the NAT Gateway was destroyed, private Bottlerocket worker nodes lost outbound internet connectivity; the cleanup pod failed to pull images and communicate, stalling Helm until a 5-minute timeout.

#### Solution
In-cluster resources (pods, webhooks, configmaps) are ephemeral and automatically terminated at the hypervisor level when AWS deletes the EKS cluster. In `platform.sh down`, all Helm releases are atomically deregistered from the Terraform state prior to AWS infrastructure destruction:
```bash
for item in $(terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep "^helm_release\." || true); do
  terraform -chdir="${TF_DIR}" state rm "${item}" || true
done
```
Terraform then terminates EKS and VPC resources directly without invoking in-cluster Kubernetes delete hooks.

---

### Issue 3: DNS Query Timeout on Legacy OIDC Data Source (`data.tls_certificate`)

#### Symptom
```text
Error: Failed to identify fetch peer certificates
  with module.eks.data.tls_certificate.this[0],
failed to fetch certificates from URL 'https': Get "https://oidc.eks.us-east-1.amazonaws.com:443/...":
dial tcp: lookup oidc.eks.us-east-1.amazonaws.com on 127.0.0.53:53: read udp ...: i/o timeout
```

#### Root Cause
The official `terraform-aws-modules/eks/aws` module defaults to `enable_irsa = true`. This instantiates a `data "tls_certificate" "this"` data source that queries `oidc.eks.us-east-1.amazonaws.com` on every plan, refresh, and destroy. Under packet loss or transient ISP drops, the DNS lookup times out.
Our architecture uses **EKS Pod Identity** (`aws_eks_pod_identity_association.external_secrets`), a modern native alternative to IRSA that does not require an OIDC issuer URL.

#### Solution
Explicitly disabled IRSA in `terraform/eks.tf`:
```hcl
module "eks" {
  ...
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = false
  ...
}
```
This eradicated external OIDC DNS queries and dependency timeouts.

---

### Issue 4: Remote Helm Index Timeouts (`context deadline exceeded`)

#### Symptom
```text
Error: could not download chart: looks like "https://kyverno.github.io/kyverno/" is not a valid chart repository:
Get "https://kyverno.github.io/kyverno/index.yaml": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
```

#### Root Cause
Specifying remote repository URLs (`repository = "https://..."`) forces Terraform to download repository indexes (such as Prometheus' 50MB index) on every run. Transient network latency caused HTTP read timeouts.

#### Solution (Offline-First Helm Architecture)
1. Chart archives were pre-downloaded to `charts/*.tgz` and verified via SHA-256 checksums in `scripts/platform.sh`:
   - `charts/argo-cd-7.7.7.tgz`
   - `charts/kyverno-3.3.4.tgz`
   - `charts/falco-4.18.0.tgz`
   - `charts/external-secrets-0.10.5.tgz`
   - `charts/kube-prometheus-stack-66.3.0.tgz`
2. `terraform/cluster_addons.tf` was reconfigured to load charts directly from the local filesystem:
   ```hcl
   resource "helm_release" "kyverno" {
     name  = "kyverno"
     chart = "${path.module}/../charts/kyverno-3.3.4.tgz"
   }
   ```
3. Excluded `charts/*.tgz` in `.gitignore` to keep git history lightweight while guaranteeing deterministic, offline-capable, and zero-network-dependency deployments.

---

### Issue 5: State Interruption & Orphaned DynamoDB Lock (`errored.tfstate`)

#### Symptom
```text
Error: failed to upload state: operation error S3: PutObject ... connection reset by peer
Error: Failed to persist state to backend ... written to the file "errored.tfstate"
Error: Error releasing the state lock ... lock ID "98440cfa-dfe9-8357-4f67-f612b4a4c590"
```

#### Root Cause
A network connection drop mid-apply prevented Terraform from uploading the updated state to S3 and releasing the DynamoDB lock. Terraform dumped state to `errored.tfstate` to prevent data loss.

#### Solution
1. Unlocked the orphaned lock:
   ```bash
   terraform force-unlock -force <LOCK_ID>
   ```
2. Synced local state back to S3:
   ```bash
   terraform state push errored.tfstate && rm -f errored.tfstate
   ```
3. Added automated recovery to `scripts/platform.sh` (`cmd_up`):
   ```bash
   if [ -f "${TF_DIR}/errored.tfstate" ]; then
     log_warn "Discovered leftover errored.tfstate. Attempting automatic recovery..."
     terraform -chdir="${TF_DIR}" state push errored.tfstate && rm -f "${TF_DIR}/errored.tfstate"
   fi
   ```

---

### Issue 6: Unbounded Socket Blocking in Python CLI Helpers (`status` / `tunnel`)

#### Symptom
`./scripts/platform.sh status` hung indefinitely when the cluster was down or an endpoint was unreachable.

#### Root Cause
Python's standard `urllib.request.urlopen()` defaults to `timeout=None`. If the TCP socket drops or is silently discarded by a firewall/NAT, the client hangs indefinitely waiting for OS TCP keepalive.

#### Solution
Added an explicit 10-second timeout and structured error handling to all internal Python inspection scripts:
```python
with urllib.request.urlopen(req, context=ctx, timeout=10) as resp:
    return json.loads(resp.read().decode())
```

---

### Issue 7: Kubernetes Finalizer Deadlock in GitOps Controller Deletion

#### Symptom
ArgoCD `Application` resource stalled in `Terminating` status during teardown.

#### Root Cause
The `Application` manifest specified `finalizers: [resources-finalizer.argocd.argoproj.io]`. When tearing down the platform, deleting the ArgoCD controller before the application resulted in no active controller to remove the finalizer.

#### Solution
In `scripts/platform.sh` (`cmd_down`), finalizers are stripped prior to teardown:
```bash
kubectl patch application -n argocd forensic-custody-api -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
kubectl delete application -n argocd forensic-custody-api --timeout=30s 2>/dev/null || true
```

---

## 3. Key Architectural Takeaways for SRE & Cloud Engineering

1. **Decouple CRDs from Custom Resources:** Never package custom resources (`ClusterPolicy`, `Application`) in the same Helm chart that introduces their CRDs.
2. **Decouple In-Cluster Workloads from Cloud Egress Teardown:** EKS compute nodes in private subnets depend on NAT Gateways. In automated teardowns, treat in-cluster workloads as disposable hypervisor state.
3. **Prefer Modern Cloud-Native IAM:** Use EKS Pod Identity over legacy OIDC/IRSA to eliminate external certificate lookups and DNS dependencies.
4. **Offline-First Helm:** Local chart archives eliminate remote HTTP flakes and guarantee reproducible, fast deployments.
