environment  = "production"
region       = "us-east-1"
state_bucket = "hotosm-terraform"
bucket_names = ["hotosm-fair-models-prod"]
tags = {
  project = "fair"
  tool    = "fair"
}
zenml_server             = "https://zenml.ai.hotosm.org"
zenml_pipeline_namespace = "zenml-pipelines"
