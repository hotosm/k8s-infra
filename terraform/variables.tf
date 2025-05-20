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


variable "instance_type" {
  default     = "t3.large"
  description = <<-EOT
  AWS Instance type used for nodes.
  EOT
}

variable "capacity_type" {
  default     = "ON_DEMAND"
  description = <<-EOT
  Whether to use ON_DEMAND or SPOT instances.
  EOT

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "The capacity_type value must be ON_DEMAND or SPOT."
  }
}

variable "max_instances" {
  default     = 10
  type        = number
  description = <<-EOT
  Maximum number of instances the autoscaler will scale the cluster up to.
  EOT
}

variable "prometheus_disk_size" {
  default     = "16Gi"
  description = <<-EOT
  Amount of space to allocate to the disk storing prometheus metrics.
  EOT
}

variable "prometheus_metrics_retention_days" {
  default     = 180
  type        = number
  description = <<-EOT
  Number of days to retain all prometheus metrics for
  EOT
}

variable "prometheus_hostname" {
  default     = ""
  description = <<-EOT
  The DNS host at which the prometheus server should be reachable.

  Is just passed along to prometheus.server.ingress.hosts.
  EOT
}

variable "kubernetes_version" {
  type        = string
  default     = "1.32"
  description = <<-EOT
  A version string that we append to certain resources to make them unique
  EOT
}

variable "ebs_driver_version" {
  type        = string
  default     = "v1.41.0-eksbuild.1"
  description = <<-EOT
  EBS CSI Driver version
  cmd: aws eks describe-addon-versions --kubernetes-version <kubernetes-version>
  EOT
}

variable "cluster_autoscaler_version" {
  default     = "9.46.6"
  description = <<-EOT
  Version of cluster autoscaler helm chart to install.
  EOT
}

variable "cert_manager_version" {
  default     = "1.17.1"
  description = <<-EOT
  Version of cert-manager helm chart to install.
  EOT
}

variable "nginx_ingress_version" {
  default     = "4.12.1"
  description = <<-EOT
  Version of the nginx ingress controller chart to install
  EOT
}

variable "enable_support_helm_charts" {
  default = false
  type    = bool
}

variable "prometheus_version" {
  default     = "25.3.1"
  description = <<-EOT
  Version of the grafana helm chart to install
  EOT
}

variable "metrics_server_version" {
  default     = "7.2.8"
  description = <<-EOT
  Version of the metrics-server
  EOT
}

variable "cluster_admin_access_role_arns" {
  type        = list(string)
  default     = []
  sensitive   = true
  description = <<-EOT
  (Optional) Roles allowed admin access to cluster
  EOT
}