module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name               = "k8s-infra-${var.environment}"
  cidr               = local.vpc_cidr
  enable_nat_gateway = true
  single_nat_gateway = true

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 64)]

  # Tagging required for Karpenter and EKS discovery
  tags = {
    "karpenter.sh/discovery"                                          = "${local.cluster_prefix}-cluster"
    "kubernetes.io/cluster/${local.cluster_prefix}-cluster"           = "owned"
  }

  private_subnet_tags = {
    "karpenter.sh/discovery"                                          = "${local.cluster_prefix}-cluster"
    "kubernetes.io/role/internal-elb"                                 = "1"
    "kubernetes.io/cluster/${local.cluster_prefix}-cluster"           = "owned"
  }

  public_subnet_tags = {
    "karpenter.sh/discovery"                                          = "${local.cluster_prefix}-cluster"
    "kubernetes.io/role/elb"                                          = "1"
    "kubernetes.io/cluster/${local.cluster_prefix}-cluster"           = "owned"
  }
}
