environment                    = "production"
region                         = "us-east-1"
instance_type                  = "t3.xlarge"
bucket_names                   = ["pgstac-backup", ]
tags = {
  project = "k8s-control"
}