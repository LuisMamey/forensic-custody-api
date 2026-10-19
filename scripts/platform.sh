#!/usr/bin/env bash
# ==============================================================================
# Forensic Custody API — Automated Platform Lifecycle Script (Up / Down / Status)
# ==============================================================================
# Usage:
#   ./scripts/platform.sh up       # Provision full AWS infra, EKS, Helm addons & GitOps
#   ./scripts/platform.sh down     # Destroy all hourly-billed AWS compute/network/EKS/WAF/ALB
#   ./scripts/platform.sh status   # Inspect live EKS cluster resources & pods (no kubectl needed)
#   ./scripts/platform.sh tunnel   # Connect local proxy tunnel to forensic-custody-api
# ==============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform"
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="forensic-custody-eks"

log_info()  { printf "\033[1;34m[INFO]\033[0m  %s\n" "$*"; }
log_ok()    { printf "\033[1;32m[OK]\033[0m    %s\n" "$*"; }
log_warn()  { printf "\033[1;33m[WARN]\033[0m  %s\n" "$*"; }
log_error() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$*" >&2; }

check_prereqs() {
  for cmd in terraform aws curl python3; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      log_error "Required binary '${cmd}' is not installed."
      exit 1
    fi
  done

  if ! ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"; then
    log_error "AWS credentials are missing, invalid, or expired."
    log_error "Please run 'aws configure', 'aws sso login', or export AWS credentials before continuing."
    exit 1
  fi
  log_info "Authenticated to AWS Account: ${ACCOUNT_ID} (Region: ${AWS_REGION})"
}

ensure_kubectl() {
  local bin_dir="${ROOT_DIR}/bin"
  mkdir -p "${bin_dir}"
  export PATH="${bin_dir}:${PATH}"

  if ! command -v kubectl >/dev/null 2>&1; then
    log_info "Downloading kubectl v1.31.0 into ${bin_dir}..."
    curl -sSL -o "${bin_dir}/kubectl" "https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl"
    chmod +x "${bin_dir}/kubectl"
    log_ok "kubectl ready at ${bin_dir}/kubectl."
  fi
}

# Pre-download Helm chart tarballs with cache reuse and SHA-256 integrity verification
prewarm_helm_cache() {
  local cache_dir="${ROOT_DIR}/charts"
  mkdir -p "${cache_dir}"
  log_info "Verifying local Helm chart cache in ${cache_dir}..."

  fetch_chart() {
    local name="$1"
    local url="$2"
    local expected_sha256="$3"
    local dest="${cache_dir}/${name}"

    if [[ -f "${dest}" ]]; then
      local current_sha256
      current_sha256="$(sha256sum "${dest}" | awk '{print $1}')"
      if [[ "${current_sha256}" == "${expected_sha256}" ]] && gzip -t "${dest}" 2>/dev/null; then
        log_ok "Using verified cached chart: ${name}"
        return 0
      fi
      log_warn "Cache invalid or corrupted for ${name}, re-downloading..."
      rm -f "${dest}"
    fi

    log_info "Fetching ${name} from remote repository..."
    curl -sSL --retry 5 -o "${dest}" "${url}"
    if ! gzip -t "${dest}" 2>/dev/null; then
      log_error "Corrupted gzip archive downloaded for ${name}"
      rm -f "${dest}"
      exit 1
    fi
    if [[ -n "${expected_sha256}" ]]; then
      local actual_sha256
      actual_sha256="$(sha256sum "${dest}" | awk '{print $1}')"
      if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
        log_error "SHA-256 mismatch for ${name}! Expected ${expected_sha256}, got ${actual_sha256}"
        rm -f "${dest}"
        exit 1
      fi
    fi
    log_ok "Cached and verified: ${name}"
  }

  fetch_chart "argo-cd-7.7.7.tgz" \
    "https://github.com/argoproj/argo-helm/releases/download/argo-cd-7.7.7/argo-cd-7.7.7.tgz" \
    "7e0106a75960be21ec39ee2c0de9bae51dc546f5077fdb89b3e1dab1e746899e"
  fetch_chart "kyverno-3.3.4.tgz" \
    "https://kyverno.github.io/kyverno/kyverno-3.3.4.tgz" \
    "a8e858e3d4159423f13b9a8ef1be4f285b2c5eff5e63be56da1e51d28ae01d12"
  fetch_chart "falco-4.18.0.tgz" \
    "https://github.com/falcosecurity/charts/releases/download/falco-4.18.0/falco-4.18.0.tgz" \
    "b2d0846ca521c01bc23bfe91c9b370e0cac52dd78e9aec8149e1afa7d9f5c8ff"
  fetch_chart "external-secrets-0.10.5.tgz" \
    "https://github.com/external-secrets/external-secrets/releases/download/helm-chart-0.10.5/external-secrets-0.10.5.tgz" \
    "5cf78ad97d7f3dfe596bbc1b58afc5043d7ee34f80b1354941bc4f0741442811"
  fetch_chart "kube-prometheus-stack-66.3.0.tgz" \
    "https://github.com/prometheus-community/helm-charts/releases/download/kube-prometheus-stack-66.3.0/kube-prometheus-stack-66.3.0.tgz" \
    "4f8078ca5ce2c119b597cecfa4797b76be25bcb12d50885bf84f27dca0346420"

  log_ok "All Helm chart tarballs ready."
}

# Ensure remote state S3 bucket & DynamoDB lock table exist before terraform init
bootstrap_state_backend() {
  local tf_bucket="forensic-custody-tfstate-${ACCOUNT_ID}"
  local lock_table="forensic-custody-tfstate-locks"

  if ! aws s3api head-bucket --bucket "${tf_bucket}" 2>/dev/null; then
    log_info "Creating remote state S3 bucket: ${tf_bucket}"
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
      aws s3api create-bucket --bucket "${tf_bucket}" --region "${AWS_REGION}" >/dev/null
    else
      aws s3api create-bucket --bucket "${tf_bucket}" --region "${AWS_REGION}" \
        --create-bucket-configuration LocationConstraint="${AWS_REGION}" >/dev/null
    fi
    aws s3api wait bucket-exists --bucket "${tf_bucket}"
    aws s3api put-bucket-versioning --bucket "${tf_bucket}" \
      --versioning-configuration Status=Enabled >/dev/null
  fi

  if ! aws dynamodb describe-table --table-name "${lock_table}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    log_info "Creating DynamoDB state lock table: ${lock_table}"
    aws dynamodb create-table \
      --table-name "${lock_table}" \
      --attribute-definitions AttributeName=LockID,AttributeType=S \
      --key-schema AttributeName=LockID,KeyType=HASH \
      --billing-mode PAY_PER_REQUEST \
      --region "${AWS_REGION}" >/dev/null
    aws dynamodb wait table-exists --table-name "${lock_table}" --region "${AWS_REGION}"
  fi
}

cmd_up() {
  check_prereqs
  bootstrap_state_backend
  prewarm_helm_cache

  # Auto-recover from any interrupted previous run
  if [[ -f "${TF_DIR}/errored.tfstate" ]]; then
    log_warn "Detected local 'errored.tfstate' from a previous interrupted run. Restoring state to S3 backend..."
    terraform -chdir="${TF_DIR}" state push "${TF_DIR}/errored.tfstate" && rm -f "${TF_DIR}/errored.tfstate"
    log_ok "Remote state successfully restored from errored.tfstate."
  fi

  log_info "Initializing Terraform with dynamic backend config..."
  terraform -chdir="${TF_DIR}" init -upgrade \
    -backend-config="bucket=forensic-custody-tfstate-${ACCOUNT_ID}" \
    -backend-config="region=${AWS_REGION}"

  # Import existing bootstrap resources if state is fresh
  if ! terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -q "^aws_s3_bucket\.terraform_state$"; then
    log_info "Importing remote state S3 bucket into Terraform state..."
    terraform -chdir="${TF_DIR}" import aws_s3_bucket.terraform_state "forensic-custody-tfstate-${ACCOUNT_ID}" || true
  fi
  if ! terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -q "^aws_dynamodb_table\.terraform_locks$"; then
    log_info "Importing DynamoDB lock table into Terraform state..."
    terraform -chdir="${TF_DIR}" import aws_dynamodb_table.terraform_locks "forensic-custody-tfstate-locks" || true
  fi

  log_info "Applying full AWS infrastructure, EKS Bottlerocket cluster, and Helm operators..."
  local max_attempts=3
  local attempt=1
  while [[ ${attempt} -le ${max_attempts} ]]; do
    if terraform -chdir="${TF_DIR}" apply -auto-approve; then
      log_ok "Core infrastructure and operators provisioned on attempt ${attempt}!"
      break
    fi
    if [[ ${attempt} -eq ${max_attempts} ]]; then
      log_error "terraform apply failed after ${max_attempts} attempts."
      exit 1
    fi
    log_warn "Transient interruption detected. Retrying (${attempt}/${max_attempts}) in 5s..."
    sleep 5
    ((attempt++))
  done

  log_info "Updating local kubeconfig for cluster ${CLUSTER_NAME}..."
  aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1 || true

  ensure_kubectl

  log_info "Bootstrapping Kyverno admission policies and ArgoCD GitOps application..."
  local max_crd_wait=60
  local crd_timer=0
  while ! kubectl get crd clusterpolicies.kyverno.io applications.argoproj.io >/dev/null 2>&1; do
    if [[ ${crd_timer} -ge ${max_crd_wait} ]]; then
      log_warn "Timeout waiting for CRDs to register. Attempting apply anyway..."
      break
    fi
    sleep 3
    ((crd_timer+=3))
  done

  kubectl apply -f "${ROOT_DIR}/k8s/policies/disallow-root-and-privileged.yaml"
  kubectl apply -f "${ROOT_DIR}/k8s/policies/verify-image-cosign.yaml"
  kubectl apply -f "${ROOT_DIR}/k8s/gitops/argocd-application.yaml"
  log_ok "Platform deployment completed successfully!"
  log_ok "Run './scripts/platform.sh status' to inspect live workloads."
}

cmd_down() {
  check_prereqs
  log_info "Starting ordered teardown of all hourly-billed AWS resources..."

  ensure_kubectl
  log_info "Step 1/3: Removing GitOps application and stripping finalizers..."
  if kubectl get application -n argocd forensic-custody-api >/dev/null 2>&1; then
    kubectl patch application -n argocd forensic-custody-api -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
    kubectl delete application -n argocd forensic-custody-api --timeout=30s 2>/dev/null || true
  fi

  log_info "Step 2/3: Deregistering in-cluster Helm releases and legacy OIDC from Terraform state..."
  local in_cluster_items
  in_cluster_items="$(terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -E "^(helm_release\.|module\.eks\.aws_iam_openid_connect_provider\.)" || true)"
  if [[ -n "${in_cluster_items}" ]]; then
    for item in ${in_cluster_items}; do
      log_info "Deregistering ${item}..."
      terraform -chdir="${TF_DIR}" state rm "${item}" || true
    done
  fi

  log_info "Step 3/3: Destroying EKS Cluster, Node Group, ALB, WAFv2, NAT Gateway, and VPC..."
  local max_attempts=3
  local attempt=1
  while [[ ${attempt} -le ${max_attempts} ]]; do
    if terraform -chdir="${TF_DIR}" destroy -auto-approve \
      -target=aws_eks_pod_identity_association.external_secrets \
      -target=module.eks \
      -target=aws_wafv2_web_acl_logging_configuration.api \
      -target=aws_wafv2_web_acl_association.api \
      -target=aws_wafv2_web_acl.api_waf \
      -target=aws_cloudwatch_log_group.waf_logs \
      -target=aws_lb.api \
      -target=aws_security_group.alb \
      -target=module.vpc; then
      log_ok "All compute and network resources destroyed successfully on attempt ${attempt}!"
      break
    fi
    if [[ ${attempt} -eq ${max_attempts} ]]; then
      log_error "terraform destroy failed after ${max_attempts} attempts."
      exit 1
    fi
    log_warn "Transient interruption detected during teardown. Retrying (${attempt}/${max_attempts}) in 5s..."
    sleep 5
    ((attempt++))
  done

  log_ok "Teardown complete! Hourly AWS compute/network billing is now \$0.00/hr."
  log_info "Remote state S3 bucket & DynamoDB lock table were preserved so you can run './scripts/platform.sh up' anytime."
}

cmd_status() {
  check_prereqs
  log_info "Querying live EKS cluster '${CLUSTER_NAME}' in ${AWS_REGION}..."
  python3 - "${CLUSTER_NAME}" "${AWS_REGION}" <<'PYEOF'
import sys, subprocess, json, urllib.request, ssl

cluster_name, region = sys.argv[1], sys.argv[2]
try:
    endpoint = subprocess.check_output(
        ["aws", "eks", "describe-cluster", "--name", cluster_name, "--region", region, "--query", "cluster.endpoint", "--output", "text"],
        stderr=subprocess.DEVNULL
    ).decode().strip()
except subprocess.CalledProcessError:
    print(f"Cluster '{cluster_name}' is not currently running (destroyed).")
    sys.exit(0)

try:
    token = json.loads(subprocess.check_output(
        ["aws", "eks", "get-token", "--cluster-name", cluster_name, "--region", region]
    ).decode())["status"]["token"]
except Exception as e:
    print(f"Error obtaining EKS bearer token: {e}")
    sys.exit(1)

ctx = ssl._create_unverified_context()

def get(path):
    req = urllib.request.Request(f"{endpoint}{path}", headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=10) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        return {"items": [], "error": str(e)}

nodes_data = get("/api/v1/nodes")
nodes = nodes_data.get("items", [])
print(f"\n=== EKS Bottlerocket Nodes ({len(nodes)}) ===")
for n in nodes:
    ready = any(c["type"] == "Ready" and c["status"] == "True" for c in n.get("status", {}).get("conditions", []))
    os_img = n.get("status", {}).get("nodeInfo", {}).get("osImage", "Unknown")
    print(f"  - {n['metadata']['name']} | Ready={ready} | OS={os_img}")

print("\n=== Custom Governance & SRE Resources ===")
apps = get("/apis/argoproj.io/v1alpha1/namespaces/argocd/applications").get("items", [])
if not apps:
    print("  - [ArgoCD Application]   None found")
for a in apps:
    sync_status = a.get("status", {}).get("sync", {}).get("status", "Unknown")
    health_status = a.get("status", {}).get("health", {}).get("status", "Unknown")
    print(f"  - [ArgoCD Application]   {a['metadata']['name']} (Sync={sync_status}, Health={health_status})")

policies = get("/apis/kyverno.io/v1/clusterpolicies").get("items", [])
if not policies:
    print("  - [Kyverno Policy]       None found")
for p in policies:
    act = p.get("spec", {}).get("validationFailureAction", "Audit")
    print(f"  - [Kyverno Policy]       {p['metadata']['name']} (Action={act})")

rules = [r for r in get("/apis/monitoring.coreos.com/v1/namespaces/monitoring/prometheusrules").get("items", []) if "forensic" in r.get("metadata", {}).get("name", "")]
if not rules:
    print("  - [PrometheusRule SLO]   None found")
for r in rules:
    print(f"  - [PrometheusRule SLO]   {r['metadata']['name']}")

am_cfgs = get("/apis/monitoring.coreos.com/v1alpha1/namespaces/monitoring/alertmanagerconfigs").get("items", [])
if not am_cfgs:
    print("  - [AlertmanagerConfig]   None found")
for c in am_cfgs:
    print(f"  - [AlertmanagerConfig]   {c['metadata']['name']}")

pods = get("/api/v1/pods").get("items", [])
print(f"\n=== Pods Summary ({len(pods)} total) ===")
by_ns = {}
for p in pods:
    ns = p["metadata"]["namespace"]
    phase = p.get("status", {}).get("phase", "Unknown")
    by_ns.setdefault(ns, []).append((p["metadata"]["name"], phase))

for ns, plist in sorted(by_ns.items()):
    running = sum(1 for _, ph in plist if ph == "Running")
    print(f"  [{ns}] {running}/{len(plist)} Running")
    for name, ph in plist:
        if ph != "Running":
            print(f"    ! {name}: {ph}")
PYEOF
}

cmd_tunnel() {
  check_prereqs
  log_info "Connecting live tunnel to 'forensic-custody-api' inside EKS cluster '${CLUSTER_NAME}'..."
  python3 - "${CLUSTER_NAME}" "${AWS_REGION}" <<'PYEOF'
import sys, subprocess, json, urllib.request, ssl, http.server

cluster_name, region = sys.argv[1], sys.argv[2]
endpoint = subprocess.check_output(
    ["aws", "eks", "describe-cluster", "--name", cluster_name, "--region", region, "--query", "cluster.endpoint", "--output", "text"]
).decode().strip()

def get_token():
    return json.loads(subprocess.check_output(
        ["aws", "eks", "get-token", "--cluster-name", cluster_name, "--region", region]
    ).decode())["status"]["token"]

ctx = ssl._create_unverified_context()

class EKSProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self._proxy("GET")
    def do_POST(self):
        self._proxy("POST")
    def _proxy(self, method):
        tok = get_token()
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length > 0 else None
        target_url = f"{endpoint}/api/v1/namespaces/default/services/http:forensic-custody-api:8080/proxy{self.path}"
        headers = {"Authorization": f"Bearer {tok}"}
        for k, v in self.headers.items():
            if k.lower() not in ("host", "authorization"):
                headers[k] = v
        req = urllib.request.Request(target_url, data=body, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, context=ctx, timeout=10) as resp:
                data = resp.read()
                self.send_response(resp.status)
                self.send_header("Content-Type", resp.headers.get("Content-Type", "application/json"))
                self.end_headers()
                self.wfile.write(data)
        except urllib.error.HTTPError as e:
            data = e.read()
            self.send_response(e.code)
            self.end_headers()
            self.wfile.write(data)
        except Exception as e:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(str(e).encode())

print("\n======================================================================")
print("  LIVE EKS TUNNEL READY! Open in your browser or curl:")
print("    Health Check : http://localhost:8080/health")
print("    Prometheus   : http://localhost:8080/metrics")
print("  (Press Ctrl+C to close the tunnel)")
print("======================================================================\n")
http.server.HTTPServer(("127.0.0.1", 8080), EKSProxyHandler).serve_forever()
PYEOF
}

case "${1:-}" in
  up)     cmd_up ;;
  down)   cmd_down ;;
  status) cmd_status ;;
  tunnel) cmd_tunnel ;;
  *)
    echo "Usage: $0 {up|down|status|tunnel}"
    exit 1
    ;;
esac
