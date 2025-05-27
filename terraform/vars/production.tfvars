environment                    = "production"
region                         = "us-east-1"
instance_type                  = "t3.xlarge"
bucket_names                   = ["pgstac-backup", ]
cluster_admin_access_role_arns = ["DEPLOY_ROLE", ]
tags = {
  project = "k8s-control"
}