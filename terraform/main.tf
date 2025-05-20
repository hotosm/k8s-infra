provider "aws" {
  region = var.region
  default_tags { tags = var.tags }
}

data "aws_availability_zones" "available" {
  state = "available"

  # https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html#cluster-subnets
  exclude_zone_ids = ["use1-az3", "usw1-az2", "cac1-az3"]
}

locals {
  cluster_prefix = "hotosm-${var.environment}"
  
  azs      = slice(sort(data.aws_availability_zones.available.names), 0, min(4, length(data.aws_availability_zones.available.names)))
  vpc_cidr = "10.0.0.0/16"
}