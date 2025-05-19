provider "aws" {
  region = var.region
  default_tags { tags = var.default_tags }
}

locals {
  cluster_prefix = "${var.cluster_name}-${var.environment}"
}