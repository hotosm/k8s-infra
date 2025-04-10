# TODO: swap out to no longer use module
module "vpc" {
  source = "git::https://github.com/hotosm/terraform-aws-vpc/"

  deployment_environment = var.environment

  default_tags = var.default_tags
  project_meta = var.project_meta
}
