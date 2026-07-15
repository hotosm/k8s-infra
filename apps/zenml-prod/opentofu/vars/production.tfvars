environment  = "production"
region       = "us-east-1"
state_bucket = "hotosm-terraform"
bucket_names = ["hotosm-fair-models-production"] # Ensure this bucket name is globally unique in AWS

tags = {
  project = "fair"
  tool    = "fair"
  env     = "production"
}

zenml_server             = "https://zenml-production.ai.hotosm.org" # Update if your prod URL is different
zenml_pipeline_namespace = "zenml-pipelines-prod"             # Isolating prod pipelines
mlflow_tracking_uri      = "http://mlflow-prod.mlflow-prod.svc.cluster.local:5000" # Update to match your MLflow prod service