environment   = "production"
region        = "us-east-1"
state_bucket  = "hotosm-terraform"
lock_table    = "zenml"
bucket_names  = ["hotosm-fair-models-prod", ]
tags = {
  project = "fair"
  tool    = "fair"
}
cluster_admin_access_role_arns = [
  "arn:aws:iam::670261699094:role/aws-reserved/sso.amazonaws.com/eu-west-1/AWSReservedSSO_AdministratorAccess_5f15c01bb91071f4",
]
