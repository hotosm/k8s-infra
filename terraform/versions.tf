terraform {
  backend "s3" {
    region         = var.region
    bucket         = "hotosm-terraform"
    key            = "${var.environment}/k8s-infra/terraform.tfstate"
    dynamodb_table = "k8s-infra"
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