terraform {
  backend "s3" {
    region         = var.region
    bucket         = var.state_bucket
    key            = "${var.environment}/zenml/terraform.tfstate"
    use_lockfile   = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.8"
    }
    zenml = {
      source  = "zenml-io/zenml"
      version = "~>3.0.4"
    }
  }
}