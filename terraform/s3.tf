resource "aws_s3_bucket" "data_stores" {
  for_each = toset(var.bucket_names)
  bucket = each.key
}

resource "aws_iam_policy" "eks_s3_access" {
  count      = length(var.bucket_names) > 0 ? 1 : 0
  name   = "EKSS3AccessPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*"
        ]
        Effect   = "Allow"
        Resource = concat(
          [for bucketname in var.bucket_names : "arn:aws:s3:::${bucketname}"],
          [for bucketname in var.bucket_names : "arn:aws:s3:::${bucketname}/*"]
        )
      }
    ]
  })
}

locals {
  s3_policy_arn = length(var.bucket_names) > 0 ? aws_iam_policy.eks_s3_access[0].arn : ""
}

resource "aws_iam_role_policy_attachment" "s3_access" {
  count      = length(var.bucket_names) > 0 ? 1 : 0
  role       = aws_iam_role.nodegroup.name
  policy_arn = local.s3_policy_arn
}