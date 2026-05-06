environment  = "staging"
region       = "us-east-1"
state_bucket = "hotosm-terraform"
bucket_names = ["hotosm-fair-models-staging"]
tags = {
  project = "fair"
  tool    = "fair"
}
cluster_name              = "hotosm-production-cluster"
zenml_server              = "https://zenml.ai.hotosm.org"
zenml_pipeline_namespace  = "zenml-pipelines"
connector_id              = "b0f2a264-952b-4cc7-bdb0-46b917c0d48b"
