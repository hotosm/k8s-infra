output "cluster_name" {
  value = aws_eks_cluster.cluster.name
}

output "s3_backup_role" {
  value = aws_iam_role.bucket_access.arn
}