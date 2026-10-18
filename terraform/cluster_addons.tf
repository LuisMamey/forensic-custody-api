# ==============================================================================
# Platform Cluster Addons (In-Cluster Engine & Policy Bootstrap via Helm)
# ==============================================================================

# 1. ArgoCD: GitOps reconciliation engine + automatic forensic-custody-api Application bootstrap
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

  # Automatically bootstrap the GitOps Application and Kyverno ClusterPolicy manifests
  values = [
    yamlencode({
      extraObjects = [
        yamldecode(file("${path.module}/../k8s/gitops/argocd-application.yaml")),
        yamldecode(file("${path.module}/../k8s/policies/disallow-root-and-privileged.yaml")),
        yamldecode(file("${path.module}/../k8s/policies/verify-image-cosign.yaml"))
      ]
    })
  ]

  depends_on = [module.eks, helm_release.kyverno]
}

# 2. Kyverno: Kubernetes Admission Controller + Pod Security & Cosign policies
resource "helm_release" "kyverno" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno/"
  chart            = "kyverno"
  version          = "3.3.4"
  namespace        = "kyverno"
  create_namespace = true

  values = [
    yamlencode({
      policyReportsCleanup = {
        image = {
          repository = "bitnamilegacy/kubectl"
        }
      }
      webhooksCleanup = {
        image = {
          repository = "bitnamilegacy/kubectl"
        }
      }
    })
  ]

  depends_on = [module.eks]
}

# 3. Falco: Runtime intrusion detection via kernel eBPF driver + custom forensic rules
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

  # Automatically load custom forensic syscall detection rules from k8s/falco/
  values = [
    yamlencode({
      customRules = {
        "forensic-api-rules.yaml" = file("${path.module}/../k8s/falco/forensic-api-rules.yaml")
      }
    })
  ]

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

# 5. kube-prometheus-stack: Prometheus Operator, Alertmanager, Exporters & SLO Rules
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "66.3.0"
  namespace        = "monitoring"
  create_namespace = true

  # Automatically deploy PrometheusRule SLOs and AlertmanagerConfig from k8s/monitoring/
  values = [
    yamlencode({
      extraManifests = [
        yamldecode(file("${path.module}/../k8s/monitoring/prometheus-slo-rules.yaml")),
        yamldecode(replace(file("${path.module}/../k8s/monitoring/alertmanager-config.yaml"), "{{", "{{ \"{{\" }}"))
      ]
    })
  ]

  depends_on = [module.eks]
}
