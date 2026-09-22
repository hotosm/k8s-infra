# Must differ from prod: AWS/ZenML names derive from `environment`.
environment  = "staging"
region       = "us-east-1"
state_bucket = "hotosm-terraform"
bucket_names = ["hotosm-fair-models-staging"]
tags = {
  project = "fair"
  tool    = "fair"
}
zenml_server             = "https://zenml.stage.ai.hotosm.org"
zenml_pipeline_namespace = "zenml-pipelines-stage"
