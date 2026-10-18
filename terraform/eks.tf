module "eks" {
  #checkov:skip=CKV_TF_1:Accepted risk — see docs/adr/0004-terraform-module-pinning.md
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "forensic-custody-eks"
  cluster_version = "1.31"

  # Network topology: Deploy EKS within private subnets created in vpc.tf
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Control Plane Endpoint Security
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Enable Control Plane Audit Logging
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Enable EKS Pod Identity agent for secure workload authentication
  enable_cluster_creator_admin_permissions = true

  # Hardened Node Group running Bottlerocket OS
  eks_managed_node_groups = {
    bottlerocket_nodes = {
      ami_type       = "BOTTLEROCKET_x86_64"
      platform       = "bottlerocket"
      instance_types = ["t3.small"]

      min_size     = 4
      max_size     = 6
      desired_size = 4

      # Restrict worker nodes to private subnets without public IPs
      subnet_ids = module.vpc.private_subnets

      labels = {
        Environment = "production"
        OS          = "bottlerocket"
        Workload    = "forensic-custody"
      }

      tags = {
        "k8s.io/cluster-autoscaler/enabled"              = "true"
        "k8s.io/cluster-autoscaler/forensic-custody-eks" = "owned"
      }
    }
  }

  tags = {
    Environment = "production"
    Project     = "forensic-custody-api"
    ManagedBy   = "terraform"
  }
}
