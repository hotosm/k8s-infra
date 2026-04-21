provider "zenml" {
  server_url = var.zenml_server
  # api_key = <taken from the ZENML_API_KEY environment variable if not set here>
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
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_access_key" "iam_user_access_key" {
  user = aws_iam_user.iam_user.name
}

resource "aws_iam_role" "zenml" {
  name = "zenml-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_user.iam_user.arn
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

# --- Service Connectors ---

# AWS connector for S3 artifact store access
resource "zenml_service_connector" "aws" {
  name        = "aws-${var.environment}"
  type        = "aws"
  auth_method = "iam-role"

  configuration = {
    region                = var.region
    role_arn              = aws_iam_role.zenml.arn
    aws_access_key_id     = aws_iam_access_key.iam_user_access_key.id
    aws_secret_access_key = aws_iam_access_key.iam_user_access_key.secret
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# --- Stack Components ---

# Artifact Store: S3
resource "zenml_stack_component" "artifact_store" {
  name   = "s3-${var.environment}"
  type   = "artifact_store"
  flavor = "s3"

  configuration = {
    path = "s3://${aws_s3_bucket.artifacts.bucket}/artifacts"
  }

  # connector_id = zenml_service_connector.aws.id
  connector_id = "ce2e1b32-1a76-4ee6-be06-6fc42e0ef5f6"
  connector_resource_id = aws_s3_bucket.artifacts.bucket

  labels = {
    environment = var.environment
  }
}

# Container Registry: GitHub (GHCR)
resource "zenml_stack_component" "container_registry" {
  name   = "ghcr-${var.environment}"
  type   = "container_registry"
  flavor = "github"

  configuration = {
    uri = "ghcr.io/hotosm"
  }

  labels = {
    environment = var.environment
  }
}

# Orchestrator: Kubernetes
resource "zenml_stack_component" "orchestrator" {
  name   = "kubernetes-orchestrator-${var.environment}"
  type   = "orchestrator"
  flavor = "kubernetes"

  configuration = {
    # incluster            = "true"
    kubernetes_namespace = var.zenml_pipeline_namespace
  }

  # connector_id = zenml_service_connector.aws.id
  connector_id = "ce2e1b32-1a76-4ee6-be06-6fc42e0ef5f6"

  labels = {
    environment = var.environment
  }
}

# Step Operator: Kubernetes (for specific GPU steps)
resource "zenml_stack_component" "step_operator" {
  name   = "kubernetes-step-operator-${var.environment}"
  type   = "step_operator"
  flavor = "kubernetes"

  configuration = {
    incluster            = "true"
    kubernetes_namespace = var.zenml_pipeline_namespace
  }

  labels = {
    environment = var.environment
  }
}

# # Image Builder: Kaniko (builds container images in-cluster)
# resource "zenml_stack_component" "image_builder" {
#   name   = "kaniko-${var.environment}"
#   type   = "image_builder"
#   flavor = "kaniko"

#   configuration = {
#     kubernetes_namespace = var.zenml_pipeline_namespace
#   }

#   labels = {
#     environment = var.environment
#   }
# }

# Experiment Tracker: MLFlow
resource "zenml_stack_component" "experiment_tracker" {
  name   = "mlflow-experiment-tracker-${var.environment}"
  type   = "experiment_tracker"
  flavor = "mlflow"

  configuration = {
    tracking_uri      = var.mlflow_tracking_uri
    tracking_username = var.mlflow_tracking_username
    tracking_password = var.mlflow_tracking_password
  }

  labels = {
    environment = var.environment
  }
}

# Model Registry: MLFlow (inherits config from experiment tracker in same stack)
resource "zenml_stack_component" "model_registry" {
  name   = "mlflow-model-registry-${var.environment}"
  type   = "model_registry"
  flavor = "mlflow"

  configuration = {}

  labels = {
    environment = var.environment
  }
}

# Log Store: OTEL (connected to Sentry)
resource "zenml_stack_component" "log_store" {
  name   = "otel-log-store-${var.environment}"
  type   = "log_store"
  flavor = "otel"

  configuration = {
    endpoint = var.sentry_endpoint
    headers  = "{\"x-sentry-auth\": \"sentry sentry_key=${var.sentry_public_key}\"}"
  }

  labels = {
    environment = var.environment
  }
}

# --- Stack ---

resource "zenml_stack" "aws_stack" {
  name = "k8s-${var.environment}"

  components = {
    artifact_store     = zenml_stack_component.artifact_store.id
    container_registry = zenml_stack_component.container_registry.id
    orchestrator       = zenml_stack_component.orchestrator.id
    step_operator      = zenml_stack_component.step_operator.id
    # image_builder      = zenml_stack_component.image_builder.id
    experiment_tracker = zenml_stack_component.experiment_tracker.id
    model_registry     = zenml_stack_component.model_registry.id
    log_store          = zenml_stack_component.log_store.id
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

output "stack_id" {
  value = zenml_stack.aws_stack.id
}

output "stack_name" {
  value = zenml_stack.aws_stack.name
}
