# ==============================================================================
# Platform Cluster Addons (In-Cluster Engine & Policy Bootstrap via Helm)
# ==============================================================================
# Uses pre-downloaded, SHA-256 verified local chart archives to eliminate
# external network dependencies and timeouts during terraform apply.
# ==============================================================================

# 1. ArgoCD: GitOps reconciliation engine
resource "helm_release" "argocd" {
  name             = "argocd"
  chart            = "${path.module}/../charts/argo-cd-7.7.7.tgz"
  namespace        = "argocd"
  create_namespace = true

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  depends_on = [module.eks, helm_release.kyverno]
}

# 2. Kyverno: Kubernetes Admission Controller + Pod Security & Cosign policies
resource "helm_release" "kyverno" {
  name             = "kyverno"
  chart            = "${path.module}/../charts/kyverno-3.3.4.tgz"
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
  chart            = "${path.module}/../charts/falco-4.18.0.tgz"
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
  chart            = "${path.module}/../charts/external-secrets-0.10.5.tgz"
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
  chart            = "${path.module}/../charts/kube-prometheus-stack-66.3.0.tgz"
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
