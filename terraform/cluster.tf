resource "aws_eks_cluster" "cluster" {
  name     = "${local.cluster_prefix}-cluster"
  role_arn = aws_iam_role.cluster_control_plane.arn
  version  = var.kubernetes_version

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }
  vpc_config {
    subnet_ids = concat(module.vpc.private_subnets, module.vpc.public_subnets)
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Cluster handling.
  # Otherwise, EKS will not be able to properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.cluster_control_plane
  ]
}

# Tag the cluster security group for Karpenter discovery
resource "aws_ec2_tag" "cluster_security_group_discovery" {
  resource_id = aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = aws_eks_cluster.cluster.name
}

resource "aws_ec2_tag" "cluster_security_group_cluster_tag" {
  resource_id = aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id
  key         = "kubernetes.io/cluster/${aws_eks_cluster.cluster.name}"
  value       = "owned"
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "cluster_control_plane" {
  name                 = "${local.cluster_prefix}-cluster-control-plane"
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  permissions_boundary = var.permissions_boundary
}

resource "aws_iam_role_policy_attachment" "cluster_control_plane" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster_control_plane.name
}

# Parse the OIDC issuer TLS certificate so we can setup IRSA correctly
data "tls_certificate" "cluster_oidc_certificate" {
  url = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster_oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = data.tls_certificate.cluster_oidc_certificate.certificates[*].sha1_fingerprint
  url             = data.tls_certificate.cluster_oidc_certificate.url
}

# https://github.com/kubernetes/autoscaler/blob/87a67e3aa0c831695f60408605d71f8e6ecdf90a/cluster-autoscaler/cloudprovider/aws/README.md?plain=1#L20
data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    effect = "Allow"

    actions = [
      "autoscaling:DescribeTags",
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "eks:DescribeNodegroup"
    ]

    resources = ["*"]
  }
  statement {
    effect = "Allow"

    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup"
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/kubernetes.io/cluster/${aws_eks_cluster.cluster.id}"
      values   = ["owned"]
    }
  }
}

resource "aws_iam_role" "cluster_autoscaler" {
  name                 = "${local.cluster_prefix}-cluster-autoscaler"
  assume_role_policy   = data.aws_iam_policy_document.assume_role_with_oidc.json
  permissions_boundary = var.permissions_boundary
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name   = "${local.cluster_prefix}-ClusterAutoscalerPolicy"
  policy = data.aws_iam_policy_document.cluster_autoscaler.json
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

resource "aws_eks_access_entry" "admin_access" {
  count = length(local.cluster_admins)

  cluster_name      = aws_eks_cluster.cluster.name
  principal_arn     = local.cluster_admins[count.index]
  kubernetes_groups = ["cluster-admin"]
}

resource "aws_eks_access_policy_association" "admin_policy" {
  count = length(local.cluster_admins)

  cluster_name  = aws_eks_cluster.cluster.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = local.cluster_admins[count.index]

  access_scope {
    type = "cluster"
  }
}
