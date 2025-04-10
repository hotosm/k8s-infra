terraform {
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.8"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~>2.17.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~>2.24.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags { tags = var.default_tags }
}

locals {
  cluster_prefix = "${var.cluster_name}-${var.environment}"
}