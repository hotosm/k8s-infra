# 1. S3 Bucket for Production Frontend Static Hosting
resource "aws_s3_bucket" "frontend" {
  bucket = "hotosm-fair-frontend-production"

  tags = merge(var.tags, {
    Name        = "hotosm-fair-frontend-production"
    environment = var.environment
    project     = "fair"
  })
}

# 2. Block All Public Access to the S3 Bucket (Security Best Practice)
resource "aws_s3_bucket_public_access_block" "frontend_public_block" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 3. Enable Versioning
resource "aws_s3_bucket_versioning" "frontend_versioning" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 4. Default Server-Side Encryption (AES256)
resource "aws_s3_bucket_server_side_encryption_configuration" "frontend_encryption" {
  bucket = aws_s3_bucket.frontend.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 5. CloudFront Origin Access Control (OAC)
resource "aws_cloudfront_origin_access_control" "frontend_oac" {
  name                              = "hotosm-fair-frontend-oac-${var.environment}"
  description                       = "OAC for fAIr Production Frontend S3 Bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 6. CloudFront Distribution
resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "fAIr Production Frontend CDN"
  default_root_object = "index.html"
  aliases             = ["ai.hotosm.org"]

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.frontend.bucket}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend_oac.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.frontend.bucket}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
  }

  # SPA Routing Rule: Redirect 403 and 404 to index.html for React Router
  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.frontend_acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = merge(var.tags, {
    environment = var.environment
    project     = "fair"
  })

  # The fAIr chart's deploy Job owns `origin_path`, repointing this at
  # s3://<bucket>/<appVersion>/ each release; an apply would reset it to "".
  lifecycle {
    ignore_changes = [origin]
  }
}

# 7. S3 Bucket Policy (Restricts S3 Access EXCLUSIVELY to CloudFront)
resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipalReadOnly"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
          }
        }
      }
    ]
  })
}

# 7b. DNS. external-dns only watches Ingress/Service, so a CloudFront alias has
# to be declared here (drone.hotosm.org is the same shape, created by hand).
data "aws_route53_zone" "hotosm" {
  name         = "hotosm.org."
  private_zone = false
}

resource "aws_route53_record" "frontend_alias" {
  for_each = toset(["A", "AAAA"])

  zone_id = data.aws_route53_zone.hotosm.zone_id
  name    = one(aws_cloudfront_distribution.frontend.aliases)
  type    = each.key

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}

# Outputs
output "frontend_s3_bucket_name" {
  value       = aws_s3_bucket.frontend.bucket
  description = "Production Frontend S3 Bucket Name"
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.frontend.id
  description = "Production Frontend CloudFront Distribution ID"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.frontend.domain_name
  description = "Production Frontend CloudFront Domain Name"
}

# 8. Fetch the existing GitHub OIDC Role
data "aws_iam_role" "github_oidc_role" {
  name = "Github-AWS-OIDC"
}

# 9. Define the CI/CD Deployment Policy
data "aws_iam_policy_document" "frontend_ci_policy" {
  statement {
    sid    = "FrontendS3Sync"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = [
      aws_s3_bucket.frontend.arn,
      "${aws_s3_bucket.frontend.arn}/*"
    ]
  }

  statement {
    sid    = "CloudFrontInvalidation"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation"
    ]
    # Restricts invalidation strictly to the fAIr distribution
    resources = [aws_cloudfront_distribution.frontend.arn]
  }

  statement {
    sid    = "CloudFrontList"
    effect = "Allow"
    actions = [
      "cloudfront:ListDistributions"
    ]
    # List commands require the wildcard resource in AWS
    resources = ["*"]
  }

}

# 10. Attach the Policy to the GitHub OIDC Role
resource "aws_iam_role_policy" "github_oidc_frontend_policy" {
  name   = "fAIr-Frontend-Deploy-Policy-${var.environment}"
  role   = data.aws_iam_role.github_oidc_role.name
  policy = data.aws_iam_policy_document.frontend_ci_policy.json
}

# 11. IRSA role for the fAIr chart's in-cluster frontend deploy Job.
# No CreateDistribution/CreateOriginAccessControl/PutBucketPolicy on purpose:
# the infra above is managed here, so a failed lookup errors rather than duplicates.
data "aws_iam_policy_document" "fair_frontend_deploy_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster_oidc.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster_oidc.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:fair-prod:fair-model-deployer"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster_oidc.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "fair_frontend_deploy" {
  statement {
    sid    = "FrontendS3Sync"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = [
      aws_s3_bucket.frontend.arn,
      "${aws_s3_bucket.frontend.arn}/*"
    ]
  }

  statement {
    sid    = "CloudFrontOriginPathAndInvalidate"
    effect = "Allow"
    actions = [
      "cloudfront:GetDistribution",
      "cloudfront:GetDistributionConfig",
      "cloudfront:UpdateDistribution",
      "cloudfront:CreateInvalidation"
    ]
    resources = [aws_cloudfront_distribution.frontend.arn]
  }

  statement {
    sid    = "CloudFrontLookup"
    effect = "Allow"
    actions = [
      "cloudfront:ListDistributions",
      "cloudfront:ListOriginAccessControls"
    ]
    # List commands require the wildcard resource in AWS
    resources = ["*"]
  }
}

resource "aws_iam_role" "fair_frontend_deploy" {
  name                 = "${local.cluster_prefix}-fair-frontend-deploy"
  assume_role_policy   = data.aws_iam_policy_document.fair_frontend_deploy_assume_role.json
  permissions_boundary = var.permissions_boundary

  tags = merge(var.tags, {
    environment = var.environment
    project     = "fair"
  })
}

resource "aws_iam_role_policy" "fair_frontend_deploy" {
  name   = "${local.cluster_prefix}-fair-frontend-deploy"
  role   = aws_iam_role.fair_frontend_deploy.name
  policy = data.aws_iam_policy_document.fair_frontend_deploy.json
}

output "fair_frontend_deploy_role_arn" {
  value       = aws_iam_role.fair_frontend_deploy.arn
  description = "IRSA role assumed by the fAIr chart's CloudFront deploy Job"
}
