data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  #checkov:skip=CKV_TF_1:Accepted risk — see docs/adr/0004-terraform-module-pinning.md
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "forensic-custody-vpc"
  cidr = "10.0.0.0/16"

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Public Subnets: DMZ reserved exclusively for external Application Load Balancers
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  # Private Subnets: Compute tier hosting EKS worker nodes and forensic API pods
  private_subnets = ["10.0.10.0/24", "10.0.20.0/24"]

  # Isolated Subnets: Persistence tier without internet routing or NAT gateways
  intra_subnets = ["10.0.100.0/24", "10.0.200.0/24"]

  # Egress connectivity for private compute nodes
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Discovery tags required by AWS Load Balancer Controller for Kubernetes
  public_subnet_tags = {
    "kubernetes.io/role/elb"                     = "1"
    "kubernetes.io/cluster/forensic-custody-eks" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"            = "1"
    "kubernetes.io/cluster/forensic-custody-eks" = "shared"
  }

  tags = {
    Environment = "production"
    Project     = "forensic-custody-api"
    ManagedBy   = "terraform"
  }
}
