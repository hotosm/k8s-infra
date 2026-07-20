# Create the S3 Buckets
resource "aws_s3_bucket" "data_stores" {
  for_each = toset(var.bucket_names)
  bucket   = each.key
}

# DEVSECOPS: Enforce Public Access Block
resource "aws_s3_bucket_public_access_block" "data_stores_public_block" {
  for_each = aws_s3_bucket.data_stores

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DEVSECOPS: Enable Versioning for ML Model rollback
resource "aws_s3_bucket_versioning" "data_stores_versioning" {
  for_each = aws_s3_bucket.data_stores

  bucket = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

# DEVSECOPS: Enforce Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "data_stores_encryption" {
  for_each = aws_s3_bucket.data_stores

  bucket = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Define the IAM Policy for S3 Access
resource "aws_iam_policy" "eks_s3_access" {
  count = length(var.bucket_names) > 0 ? 1 : 0
  name  = "EKSS3ZenMLAccessPolicy-${var.environment}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetBucketVersioning"
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

# Define the OIDC Trust Relationship
data "aws_iam_policy_document" "assume_role_with_oidc" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    # DEVSECOPS: Scoping down the trust relationship
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_arn, "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # NOTE: For strict isolation, uncomment the block below and replace <SERVICE_ACCOUNT_NAME> 
    # to restrict access only to the specific ZenML service account in your cluster.
    # condition {
    #   test     = "StringEquals"
    #   variable = "${replace(var.oidc_arn, "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/", "")}:sub"
    #   values   = ["system:serviceaccount:${var.zenml_pipeline_namespace}:<SERVICE_ACCOUNT_NAME>"]
    # }
  }
}

# Create the IAM Role
resource "aws_iam_role" "bucket_access" {
  name                 = "hotosm-fair-models-bucket-access-${var.environment}"
  assume_role_policy   = data.aws_iam_policy_document.assume_role_with_oidc.json
  permissions_boundary = var.permissions_boundary
}

# Attach the Policy to the Role
resource "aws_iam_role_policy_attachment" "s3_access" {
  count      = length(var.bucket_names) > 0 ? 1 : 0
  role       = aws_iam_role.bucket_access.name
  policy_arn = local.s3_policy_arn
}