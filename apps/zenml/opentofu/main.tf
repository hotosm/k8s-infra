# terraform {
#     required_providers {
#         aws = {
#             source  = "hashicorp/aws"
#         }
#         zenml = {
#             source = "zenml-io/zenml"
#         }
#     }
# }

provider "zenml" {
    server_url = var.zenml_server
    # For ZenML Pro users, this should be your Workspace URL from the dashboard
    # api_key = <taken from the ZENML_API_KEY environment variable if not set here>
    ## TODO sealed secret for API_KEY
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Create S3 bucket for ZenML artifacts
resource "aws_s3_bucket" "artifacts" {
  bucket = "${data.aws_caller_identity.current.account_id}-zenml-artifacts-${var.environment}"
}

### TODO: Redo with a service role
resource "aws_iam_user" "iam_user" {
  name = "zenml-${var.environment}"
}

resource "aws_iam_user_policy" "assume_role_policy" {
  name = "AssumeRole"
  user = aws_iam_user.iam_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_access_key" "iam_user_access_key" {
  user = aws_iam_user.iam_user.name
}

resource "aws_iam_role" "zenml" {
  name               = "zenml-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_user.iam_user.arn
        }
        Action = "sts:AssumeRole"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}


resource "aws_iam_role_policy" "s3_policy" {
  name = "S3Policy"
  role = aws_iam_role.zenml.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      }
    ]
  })
}

# ZenML Service Connector for AWS
resource "zenml_service_connector" "aws" {
  name           = "aws-${var.environment}"
  type           = "aws"
  auth_method    = "iam-role"

  configuration = {
    region   = var.region
    role_arn = aws_iam_role.zenml.arn
    aws_access_key_id = aws_iam_access_key.iam_user_access_key.id
    aws_secret_access_key = aws_iam_access_key.iam_user_access_key.secret
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# Artifact Store Component
resource "zenml_stack_component" "artifact_store" {
  name      = "s3-${var.environment}"
  type      = "artifact_store"
  flavor    = "s3"

  configuration = {
    path = "s3://${aws_s3_bucket.artifacts.bucket}/artifacts"
  }

  connector_id = zenml_service_connector.aws.id

  labels = {
    environment = var.environment
  }
}

# Container Registry Component
resource "zenml_stack_component" "container_registry" {
  name      = "gcr-${var.environment}"
  type      = "container_registry"
  flavor    = "github"

  configuration = {
    uri = "ghcr.io/hotosm"
    default_repository = "fAIr-models" ## todo: parameterize
  }

  connector_id = zenml_service_connector.aws.id

  labels = {
    environment = var.environment
  }
}

# custom k8s Orchestrator
resource "zenml_stack_component" "orchestrator" {
  name      = "kubernetes-${var.environment}"
  type      = "orchestrator"
  flavor    = "kubernetes"

  configuration = {
      region = data.aws_region.current.name
      execution_role = aws_iam_role.zenml.arn
      output_data_s3_uri = "s3://${aws_s3_bucket.artifacts.bucket}/kubernetes"
      incluster = true

  }

  connector_id = zenml_service_connector.aws.id

  labels = {
    environment = var.environment
  }
}

# Experiment Tracker: MLFlow (already in cluster, for tracking experiments / how you got a model)
resource "zenml_stack_component" "experiment_tracker" {
  name      = "kubernetes-${var.environment}"
  type      = "experiment_tracker"
  flavor    = "mlflow"

  configuration = {
      region = data.aws_region.current.name
      execution_role = aws_iam_role.zenml.arn
      ## https://docs.zenml.io/stacks/stack-components/experiment-trackers/mlflow
      tracking_uri = "${var.mlflow_tracking_uri}"
      tracking_username = "${var.mlflow_tracking_username}"
      tracking_password = "${var.mlflow_tracking_password}"
  }

  connector_id = zenml_service_connector.aws.id

  labels = {
    environment = var.environment
  }
}

# Model Registry: MLFlow (already in cluster, for versioning and lineage of prod models) +- WandB (Weights & Biases)
resource "zenml_stack_component" "model_registry" {
  name      = "kubernetes-${var.environment}"
  type      = "model_registry"
  flavor    = "mlflow"

  configuration = {
      region = data.aws_region.current.name
      execution_role = aws_iam_role.zenml.arn
  }

  connector_id = zenml_service_connector.aws.id

  labels = {
    environment = var.environment
  }
}

# Log Store: OTEL (to store logs and traces for pipelines - connect Sentry for now)
resource "zenml_stack_component" "log_store" {
  name      = "kubernetes-${var.environment}"
  type      = "log_store"
  flavor    = "otel"

  configuration = {
      region = data.aws_region.current.name
      execution_role = aws_iam_role.zenml.arn
      endpoint = "${var.sentry_endpoint}"
      headers = "{'x-sentry-auth': 'sentry sentry_key=${var.sentry_key}'}"
      ## https://docs.zenml.io/stacks/stack-components/log-stores/otel
  }

  connector_id = zenml_service_connector.aws.id

  labels = {
    environment = var.environment
  }
}

# Complete Stack
resource "zenml_stack" "aws_stack" {
  name = "aws-${var.environment}"

  components = {
    artifact_store      = zenml_stack_component.artifact_store.id
    container_registry  = zenml_stack_component.container_registry.id
    orchestrator        = zenml_stack_component.orchestrator.id
    experiment_tracker  = zenml_stack_component.experiment_tracker.id
    model_registry      = zenml_stack_component.model_registry.id
    log_store           = zenml_stack_component.log_store.id
    ## add more as they get configured properly
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}


# output "zenml_stack_id" {
#   value = aws_stack.zenml_stack_id
# }
# output "zenml_stack_name" {
#   value = aws_stack.zenml_stack_name
# }