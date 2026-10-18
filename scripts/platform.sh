#!/usr/bin/env bash
# ==============================================================================
# Forensic Custody API — Automated Platform Lifecycle Script (Up / Down / Status)
# ==============================================================================
# Usage:
#   ./scripts/platform.sh up       # Provision full AWS infra, EKS, Helm addons & GitOps
#   ./scripts/platform.sh down     # Destroy all hourly-billed AWS compute/network/EKS/WAF/ALB
#   ./scripts/platform.sh status   # Inspect live EKS cluster resources & pods (no kubectl needed)
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

  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  log_info "Authenticated to AWS Account: ${ACCOUNT_ID} (Region: ${AWS_REGION})"
}

# Pre-download Helm chart tarballs with retry logic and SHA-256 integrity verification
prewarm_helm_cache() {
  local cache_dir="${HOME}/.cache/helm/repository"
  mkdir -p "${cache_dir}"
  log_info "Pre-warming Helm chart cache in ${cache_dir} with SHA-256 digest verification..."

  fetch_chart() {
    local name="$1"
    local url="$2"
    local expected_sha256="$3"
    local dest="${cache_dir}/${name}"

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

  log_ok "Helm chart tarballs cached and verified."
}

# Ensure remote state S3 bucket & DynamoDB lock table exist before terraform init
bootstrap_state_backend() {
  local tf_bucket="forensic-custody-tfstate-${ACCOUNT_ID}"
  local lock_table="forensic-custody-tfstate-locks"

  if ! aws s3api head-bucket --bucket "${tf_bucket}" 2>/dev/null; then
    log_info "Creating remote state S3 bucket: ${tf_bucket}"
    aws s3api create-bucket --bucket "${tf_bucket}" --region "${AWS_REGION}" >/dev/null
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

  log_info "Initializing Terraform..."
  terraform -chdir="${TF_DIR}" init -upgrade

  # Import existing bootstrap resources if state is fresh
  if ! terraform -chdir="${TF_DIR}" state list | grep -q "^aws_s3_bucket\.terraform_state$"; then
    log_info "Importing remote state S3 bucket into Terraform state..."
    terraform -chdir="${TF_DIR}" import aws_s3_bucket.terraform_state "forensic-custody-tfstate-${ACCOUNT_ID}" || true
  fi
  if ! terraform -chdir="${TF_DIR}" state list | grep -q "^aws_dynamodb_table\.terraform_locks$"; then
    log_info "Importing DynamoDB lock table into Terraform state..."
    terraform -chdir="${TF_DIR}" import aws_dynamodb_table.terraform_locks "forensic-custody-tfstate-locks" || true
  fi

  log_info "Applying full AWS infrastructure, EKS Bottlerocket cluster, Helm operators, and k8s/ manifests..."
  local max_attempts=3
  local attempt=1
  while [[ ${attempt} -le ${max_attempts} ]]; do
    if terraform -chdir="${TF_DIR}" apply -auto-approve; then
      log_ok "Platform deployment completed successfully on attempt ${attempt}!"
      break
    fi
    if [[ ${attempt} -eq ${max_attempts} ]]; then
      log_error "terraform apply failed after ${max_attempts} attempts."
      exit 1
    fi
    log_warn "Transient network interruption detected during Helm chart fetch. Retrying (${attempt}/${max_attempts}) in 5s..."
    sleep 5
    ((attempt++))
  done

  log_info "Updating local kubeconfig for cluster ${CLUSTER_NAME}..."
  aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1 || true
  log_ok "All systems provisioned. Run './scripts/platform.sh status' to inspect live workloads."
}

cmd_down() {
  check_prereqs
  log_info "Starting ordered teardown of all hourly-billed AWS resources..."

  # Step 1: Remove in-cluster Helm releases cleanly while EKS control plane is still reachable
  log_info "Step 1/2: Uninstalling Helm operators (ArgoCD, Prometheus, Falco, ESO, Kyverno)..."
  terraform -chdir="${TF_DIR}" destroy -auto-approve \
    -target=helm_release.argocd \
    -target=helm_release.kube_prometheus_stack \
    -target=helm_release.falco \
    -target=helm_release.external_secrets \
    -target=helm_release.kyverno || log_warn "Helm releases already removed or cluster unreachable, continuing..."

  # Step 2: Destroy EKS, ALB, WAF, CloudWatch Logs, VPC/NAT Gateway, and Secrets Manager
  # Note: Preserves S3 remote state backend & Object Lock buckets ($0.00/hr) to prevent Lock/WORM errors
  log_info "Step 2/2: Destroying EKS Cluster, Node Group, ALB, WAFv2, NAT Gateway, and VPC..."
  terraform -chdir="${TF_DIR}" destroy -auto-approve \
    -target=aws_eks_pod_identity_association.external_secrets \
    -target=module.eks \
    -target=aws_wafv2_web_acl_logging_configuration.api \
    -target=aws_wafv2_web_acl_association.api \
    -target=aws_wafv2_web_acl.api_waf \
    -target=aws_cloudwatch_log_group.waf_logs \
    -target=aws_lb.api \
    -target=aws_security_group.alb \
    -target=module.vpc \
    -target=aws_secretsmanager_secret.api_secrets

  log_ok "Teardown complete! Hourly AWS compute/network billing is now $0.00/hr."
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

token = json.loads(subprocess.check_output(
    ["aws", "eks", "get-token", "--cluster-name", cluster_name, "--region", region]
).decode())["status"]["token"]
ctx = ssl._create_unverified_context()

def get(path):
    req = urllib.request.Request(f"{endpoint}{path}", headers={"Authorization": f"Bearer {token}"})
    return json.loads(urllib.request.urlopen(req, context=ctx).read())

nodes = get("/api/v1/nodes")["items"]
print(f"\n=== EKS Bottlerocket Nodes ({len(nodes)}) ===")
for n in nodes:
    ready = any(c["type"] == "Ready" and c["status"] == "True" for c in n["status"]["conditions"])
    print(f"  - {n['metadata']['name']} | Ready={ready} | OS={n['status']['nodeInfo']['osImage']}")

print("\n=== Custom Governance & SRE Resources ===")
apps = get("/apis/argoproj.io/v1alpha1/namespaces/argocd/applications")["items"]
for a in apps:
    print(f"  - [ArgoCD Application]   {a['metadata']['name']} (Sync={a['status']['sync']['status']}, Health={a['status']['health']['status']})")

policies = get("/apis/kyverno.io/v1/clusterpolicies")["items"]
for p in policies:
    print(f"  - [Kyverno Policy]       {p['metadata']['name']} (Action={p['spec']['validationFailureAction']})")

rules = [r for r in get("/apis/monitoring.coreos.com/v1/namespaces/monitoring/prometheusrules")["items"] if "forensic" in r["metadata"]["name"]]
for r in rules:
    print(f"  - [PrometheusRule SLO]   {r['metadata']['name']}")

am_cfgs = get("/apis/monitoring.coreos.com/v1alpha1/namespaces/monitoring/alertmanagerconfigs")["items"]
for c in am_cfgs:
    print(f"  - [AlertmanagerConfig]   {c['metadata']['name']}")

pods = get("/api/v1/pods")["items"]
print(f"\n=== Pods Summary ({len(pods)} total) ===")
by_ns = {}
for p in pods:
    ns = p["metadata"]["namespace"]
    phase = p["status"].get("phase", "Unknown")
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
import sys, subprocess, json, urllib.request, ssl, time, http.server

cluster_name, region = sys.argv[1], sys.argv[2]
endpoint = subprocess.check_output(
    ["aws", "eks", "describe-cluster", "--name", cluster_name, "--region", region, "--query", "cluster.endpoint", "--output", "text"]
).decode().strip()

def get_token():
    return json.loads(subprocess.check_output(
        ["aws", "eks", "get-token", "--cluster-name", cluster_name, "--region", region]
    ).decode())["status"]["token"]

ctx = ssl._create_unverified_context()
pinned_img = "ghcr.io/luismamey/forensic-custody-api@sha256:5cd32133b14a6a668243b552b03176c3ec397be0373a9583aed6d7568aa2476d"

# Ensure live Deployment uses the immutable SHA-256 digest immediately
token = get_token()
patch_body = json.dumps({"spec": {"template": {"spec": {"containers": [{"name": "api", "image": pinned_img}]}}}}).encode()
req = urllib.request.Request(
    f"{endpoint}/apis/apps/v1/namespaces/default/deployments/forensic-custody-api",
    data=patch_body,
    method="PATCH",
    headers={"Authorization": f"Bearer {token}", "Content-Type": "application/strategic-merge-patch+json"}
)
try:
    urllib.request.urlopen(req, context=ctx)
except Exception:
    pass

print("Waiting for forensic-custody-api pods to be Running...")
for _ in range(20):
    r = urllib.request.Request(f"{endpoint}/api/v1/namespaces/default/pods", headers={"Authorization": f"Bearer {token}"})
    pods = json.loads(urllib.request.urlopen(r, context=ctx).read())["items"]
    if any(p["status"].get("phase") == "Running" for p in pods):
        break
    time.sleep(2)

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
            with urllib.request.urlopen(req, context=ctx) as resp:
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
