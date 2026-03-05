variable "environment" {
  type        = string
  default     = "development"
  description = <<-EOT
  Deploy environment
  EOT
}

variable "region" {
  type        = string
  description = <<-EOT
  AWS region to perform all our operations in.
  EOT
}

variable "state_bucket" {
  type        = string
  default     = ""
  description = <<-EOT
  S3 bucket for remote state backend
  EOT
}

variable "lock_table" {
  type        = string
  default     = ""
  description = <<-EOT
  Dynamo table to use for consistency checks (when using an s3 backend)
  EOT
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = <<-EOT
  (Optional) AWS resource tags.
  EOT
}

variable "permissions_boundary" {
  type        = string
  default     = null
  sensitive   = true
  description = <<-EOT
  (Optional) ARN of the policy that is used to set the permissions boundary for
  the role.
  EOT
}

variable "bucket_names" {
  description = <<-EOT
  list of s3 buckets to create that you might need the nodes to have access to
  EOT
  type        = list(string)
  default     = []
}

variable "zenml_server" {
  description = <<-EOT
  URL for the zenml instance
  EOT
  type        = string
  default     = "https://zenml.ai.hotosm.org"
}

variable "oidc_arn" {
  description = <<-EOT
  ARN for the cluster OIDC connect provider
  EOT
  type        = string
  default     = "arn:aws:iam::670261699094:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/6C1C4902845266176B6D3D16899B4665"
}

variable "sentry_key" {
  description = <<-EOT
  Sentry API key for zenml project
  EOT
  type        = string
  sensitive   = true
  default     = ""
}

variable "sentry_endpoint" {
  description = <<-EOT
  URL for the sentry access
  EOT
  type        = string
  default     = ""
}

variable "mlflow_tracking_uri" {
  description = <<-EOT
  internal URL for the mlflow setup
  EOT
  type        = string
  default     = ""
}

variable "mlflow_tracking_username" {
  description = <<-EOT
  mlflow basic auth username
  EOT
  type        = string
  default     = ""
}

variable "mlflow_tracking_password" {
  description = <<-EOT
  mlflow basic auth password
  EOT
  type        = string
  sensitive   = true
  default     = ""
}