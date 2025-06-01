environment   = "production"
region        = "us-east-1"
state_bucket  = "hotosm-terraform"
lock_table    = "k8s-infra"
instance_type = "t3.xlarge"
bucket_names  = ["pgstac-backup", ]
tags = {
  project = "k8s-control"
}