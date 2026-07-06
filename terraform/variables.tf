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

variable "core_nodegroup_size" {
  default     = 5
  type        = number
  description = <<-EOT
  Fixed size of the managed "core" nodegroup (min = max = desired).
  Karpenter provisions any additional capacity above this baseline via
  its own NodePools.
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
  default     = "1.34"
  description = <<-EOT
  A version string that we append to certain resources to make them unique
  EOT
}

variable "ebs_driver_version" {
  type        = string
  default     = "v1.62.0-eksbuild.1"
  description = <<-EOT
  EBS CSI Driver version
  cmd: aws eks describe-addon-versions --kubernetes-version <kubernetes-version>
  EOT
}

variable "vpc_cni_version" {
  type        = string
  default     = "v1.22.2-eksbuild.1"
  description = <<-EOT
  Amazon VPC CNI add-on version. Compatible with Kubernetes 1.29-1.36.
  cmd: aws eks describe-addon-versions --addon-name vpc-cni --kubernetes-version <kubernetes-version>
  EOT
}

variable "coredns_version" {
  type        = string
  default     = "v1.12.4-eksbuild.18"
  description = <<-EOT
  CoreDNS add-on version. Compatible with Kubernetes 1.34.
  cmd: aws eks describe-addon-versions --addon-name coredns --kubernetes-version <kubernetes-version>
  EOT
}

variable "kube_proxy_version" {
  type        = string
  default     = "v1.34.6-eksbuild.11"
  description = <<-EOT
  kube-proxy add-on version. Must match the control plane's minor version
  (or be at most 1 behind).
  cmd: aws eks describe-addon-versions --addon-name kube-proxy --kubernetes-version <kubernetes-version>
  EOT
}

variable "nginx_ingress_version" {
  default     = "4.12.1"
  description = <<-EOT
  Version of the nginx ingress controller chart to install
  EOT
}

variable "enable_support_helm_charts" {
  default     = false
  type        = bool
  description = <<-EOT
  Whether to install the optional support helm charts managed by this module.
  EOT
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

variable "cluster_ci_access_role_arn" {
  type        = string
  sensitive   = true
  description = <<-EOT
  CI deployer role to provide cluster access entry
  EOT
}
