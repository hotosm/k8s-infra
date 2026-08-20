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
      "pricing:GetProducts"
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

  statement {
    sid    = "AllowScopedInstanceProfileCreationActions"
    effect = "Allow"
    actions = [
      "iam:CreateInstanceProfile"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${aws_eks_cluster.cluster.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowScopedInstanceProfileTagActions"
    effect = "Allow"
    actions = [
      "iam:TagInstanceProfile"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${aws_eks_cluster.cluster.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${aws_eks_cluster.cluster.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowScopedInstanceProfileActions"
    effect = "Allow"
    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:DeleteInstanceProfile"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${aws_eks_cluster.cluster.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowInstanceProfileReadListActions"
    effect = "Allow"
    actions = [
      "iam:ListInstanceProfiles",
      "iam:GetInstanceProfile"
    ]
    resources = ["*"]
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

# SQS queue used by Karpenter for interruption handling.
# Settings match Karpenter's upstream CloudFormation reference.
resource "aws_sqs_queue" "karpenter_interruption_queue" {
  name = aws_eks_cluster.cluster.name

  # Interruption events are only actionable inside the ~2min warning window;
  # anything older is noise on controller restart.
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
}


# ---------------------------------------------------------------------------
# Interruption event routing
#
# The SQS queue above is polled by Karpenter, but nothing published to it until
# these rules existed - so interruption handling was silently inert (see
# incident-report.md). EventBridge delivers spot interruption warnings, rebalance
# recommendations, instance state changes and AWS Health scheduled events, giving
# Karpenter time to cordon + drain a node before it goes away.
#
# Covers Karpenter-managed nodes only. The `core` managed nodegroup is ON_DEMAND
# and is not in scope here.
# ---------------------------------------------------------------------------

# Allow EventBridge to publish into the interruption queue.
data "aws_iam_policy_document" "karpenter_interruption_queue" {
  statement {
    sid       = "EventBridgeSendMessage"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.karpenter_interruption_queue.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
  }

  statement {
    sid       = "DenyHTTP"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.karpenter_interruption_queue.arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "karpenter_interruption_queue" {
  queue_url = aws_sqs_queue.karpenter_interruption_queue.id
  policy    = data.aws_iam_policy_document.karpenter_interruption_queue.json
}

locals {
  karpenter_interruption_events = {
    health_event = {
      description   = "AWS Health scheduled change (maintenance, retirement, reboot)"
      event_pattern = { source = ["aws.health"], detail-type = ["AWS Health Event"] }
    }
    spot_interruption = {
      description   = "EC2 spot instance interruption warning"
      event_pattern = { source = ["aws.ec2"], detail-type = ["EC2 Spot Instance Interruption Warning"] }
    }
    rebalance = {
      description   = "EC2 instance rebalance recommendation"
      event_pattern = { source = ["aws.ec2"], detail-type = ["EC2 Instance Rebalance Recommendation"] }
    }
    state_change = {
      description   = "EC2 instance state-change notification"
      event_pattern = { source = ["aws.ec2"], detail-type = ["EC2 Instance State-change Notification"] }
    }
  }
}

resource "aws_cloudwatch_event_rule" "karpenter_interruption" {
  for_each = local.karpenter_interruption_events

  name          = "${local.cluster_prefix}-karpenter-${each.key}"
  description   = each.value.description
  event_pattern = jsonencode(each.value.event_pattern)

  # Required by the CI role's IAM policy (aws:RequestTag/project must be k8s-control)
  tags = {
    project = "k8s-control"
  }
}

resource "aws_cloudwatch_event_target" "karpenter_interruption" {
  for_each = local.karpenter_interruption_events

  rule      = aws_cloudwatch_event_rule.karpenter_interruption[each.key].name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter_interruption_queue.arn
}
