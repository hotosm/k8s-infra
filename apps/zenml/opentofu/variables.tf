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
