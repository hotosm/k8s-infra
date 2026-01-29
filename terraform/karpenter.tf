data "aws_caller_identity" "current" {}

# Trust policy for Karpenter controller using IRSA
data "aws_iam_policy_document" "karpenter_controller_assume_role" {
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
      values   = ["system:serviceaccount:kube-system:karpenter"]
    }
  }
}

# IAM policy for Karpenter controller
# Based on upstream KarpenterControllerPolicy, scoped to this cluster where practical.
data "aws_iam_policy_document" "karpenter_controller" {
  # Core Karpenter controller permissions based on the official migration guide:
  # https://karpenter.sh/docs/getting-started/migrating-from-cas/
  statement {
    sid    = "KarpenterReadWrite"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ec2:DescribeImages",
      "ec2:RunInstances",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DeleteLaunchTemplate",
      "ec2:CreateTags",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateFleet",
      "ec2:DescribeSpotPriceHistory",
      "pricing:GetProducts",
      "iam:ListInstanceProfiles"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ConditionalEC2Termination"
    effect = "Allow"
    actions = [
      "ec2:TerminateInstances"
    ]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "ec2:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid    = "PassNodeIAMRole"
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/KarpenterNodeRole-${aws_eks_cluster.cluster.name}"
    ]
  }

  statement {
    sid    = "EKSClusterEndpointLookup"
    effect = "Allow"
    actions = [
      "eks:DescribeCluster"
    ]
    resources = [
      "arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${aws_eks_cluster.cluster.name}"
    ]
  }

  # SQS permissions for interruption handling (not in the base guide but required when using interruptionQueue)
  statement {
    sid    = "SQSPolling"
    effect = "Allow"
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage"
    ]
    resources = [aws_sqs_queue.karpenter_interruption_queue.arn]
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name                 = "${local.cluster_prefix}-karpenter-controller"
  assume_role_policy   = data.aws_iam_policy_document.karpenter_controller_assume_role.json
  permissions_boundary = var.permissions_boundary
}

resource "aws_iam_policy" "karpenter_controller" {
  name   = "${local.cluster_prefix}-KarpenterControllerPolicy"
  policy = data.aws_iam_policy_document.karpenter_controller.json
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

# SQS queue used by Karpenter for interruption handling
resource "aws_sqs_queue" "karpenter_interruption_queue" {
  name = aws_eks_cluster.cluster.name
}

