terraform {
  backend "s3" {
    region         = var.region
    bucket         = var.state_bucket
    key            = "${var.environment}/k8s-infra/terraform.tfstate"
    dynamodb_table = var.lock_table
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.8"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~>2.17.0"
    }
  }
}