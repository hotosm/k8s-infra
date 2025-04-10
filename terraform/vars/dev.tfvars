environment         = "dev"
region              = "us-east-1"
cluster_name        = "hotosm"
prometheus_hostname = ""
instance_type       = "t3.xlarge"
bucket_names        = ["eoapidb-dev-backup",]
default_tags        = {
  project = "k8s-infra"
}