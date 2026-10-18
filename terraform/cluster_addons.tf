# 1. ArgoCD: GitOps reconciliation engine for progressive delivery
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.7.7"
  namespace        = "argocd"
  create_namespace = true

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  depends_on = [module.eks]
}

# 2. Kyverno: Kubernetes Admission Controller for Cosign signatures and PSS
resource "helm_release" "kyverno" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno/"
  chart            = "kyverno"
  version          = "3.3.4"
  namespace        = "kyverno"
  create_namespace = true

  depends_on = [module.eks]
}

# 3. Falco: Runtime intrusion detection via kernel eBPF driver
resource "helm_release" "falco" {
  name             = "falco"
  repository       = "https://falcosecurity.github.io/charts"
  chart            = "falco"
  version          = "4.18.0"
  namespace        = "falco"
  create_namespace = true

  # Bottlerocket OS enforces modern_ebpf driver (runtime kernel module compilation disabled)
  set {
    name  = "driver.kind"
    value = "modern_ebpf"
  }

  set {
    name  = "tty"
    value = "true"
  }

  depends_on = [module.eks]
}

# 4. External Secrets Operator (ESO): Zero-Trust sync from AWS Secrets Manager
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.10.5"
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [module.eks]
}

# 5. kube-prometheus-stack: Prometheus Operator, Alertmanager and Exporters
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "66.3.0"
  namespace        = "monitoring"
  create_namespace = true

  depends_on = [module.eks]
}
