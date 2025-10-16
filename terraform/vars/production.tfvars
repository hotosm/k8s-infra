environment   = "production"
region        = "us-east-1"
state_bucket  = "hotosm-terraform"
lock_table    = "k8s-infra"
instance_type = "t3.xlarge"
bucket_names  = ["hotosm-pgstac-backup", ]
tags = {
  project = "k8s-control"
}
cluster_admin_access_role_arns  = [
  "arn:aws:iam::670261699094:role/aws-reserved/sso.amazonaws.com/eu-west-1/AWSReservedSSO_AdministratorAccess_5f15c01bb91071f4",
  "arn:aws:iam::670261699094:role/NAXA_cross_account_role"
]
cluster_ci_access_role_arn      = "arn:aws:iam::670261699094:role/Github-AWS-OIDC"