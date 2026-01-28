output "cluster_name" {
  value = aws_eks_cluster.cluster.name
}

output "s3_backup_role" {
  value = aws_iam_role.bucket_access.arn
}

output "karpenter_controller_role_arn" {
  value = aws_iam_role.karpenter_controller.arn
}

output "karpenter_node_instance_profile_name" {
  value = aws_iam_instance_profile.karpenter_node.name
}

output "karpenter_interruption_queue_name" {
  value = aws_sqs_queue.karpenter_interruption_queue.name
}