environment  = "production"
region       = "us-east-1"
state_bucket = "hotosm-terraform"
bucket_names = ["hotosm-fair-models-production"] 

tags = {
  project = "fair"
  tool    = "fair"
  env     = "production"
}

zenml_server             = "https://zenml.ai.hotosm.org" 
zenml_pipeline_namespace = "zenml-pipelines-prod"             
mlflow_tracking_uri      = "http://mlflow-prod.mlflow-prod.svc.cluster.local:5000" 
mlflow_tracking_username = "fair_mlflow_admin_ops"