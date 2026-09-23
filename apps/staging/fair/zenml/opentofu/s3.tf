# We want to create the hotosm-fair-models-prod bucket via this config

resource "aws_s3_bucket" "data_stores" {
  for_each = toset(var.bucket_names)
  bucket   = each.key
}

resource "aws_iam_policy" "eks_s3_access" {
  count = length(var.bucket_names) > 0 ? 1 : 0
  name  = "EKSS3ZenMLAccessPolicy-${var.environment}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*"
        ]
        Effect = "Allow"
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

data "aws_iam_policy_document" "assume_role_with_oidc" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_arn, "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only ZenML pipeline pods (IRSA on zenml-pod-account).
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_arn, "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/", "")}:sub"
      values   = ["system:serviceaccount:${var.zenml_pipeline_namespace}:zenml-pod-account"]
    }
  }
}

resource "aws_iam_role" "bucket_access" {
  name                 = "hotosm-fair-models-bucket-access-${var.environment}"
  assume_role_policy   = data.aws_iam_policy_document.assume_role_with_oidc.json
  permissions_boundary = var.permissions_boundary
}

resource "aws_iam_role_policy_attachment" "s3_access" {
  count      = length(var.bucket_names) > 0 ? 1 : 0
  role       = aws_iam_role.bucket_access.name
  policy_arn = local.s3_policy_arn
}
