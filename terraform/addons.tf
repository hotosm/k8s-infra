# Allow roles to assume permissions with their OIDC credentials for use with IRSA
data "aws_iam_policy_document" "assume_role_with_oidc" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster_oidc.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]
  }
}

# Setup the EBS CSI Driver addon - https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html
# Required for EBS volumes to be provisioned and attached
resource "aws_iam_role" "ebs_provisioner" {
  name                 = "${local.cluster_prefix}-eks-ebs-provisioner"
  assume_role_policy   = data.aws_iam_policy_document.assume_role_with_oidc.json
  permissions_boundary = var.permissions_boundary
}

resource "aws_iam_role_policy_attachment" "ebs_provisioner" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_provisioner.name
}

resource "aws_eks_addon" "ebs_provisioner" {
  cluster_name                = aws_eks_cluster.cluster.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.ebs_driver_version
  resolve_conflicts_on_create = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.ebs_provisioner.arn
  depends_on = [
    aws_iam_role_policy_attachment.ebs_provisioner
  ]
}

# Setup the Amazon VPC CNI addon (pod networking).
# Adopted from the self-managed default with `resolve_conflicts_on_create = OVERWRITE`.
data "aws_iam_policy_document" "vpc_cni_assume_role" {
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
      values   = ["system:serviceaccount:kube-system:aws-node"]
    }
  }
}

resource "aws_iam_role" "vpc_cni" {
  name                 = "${local.cluster_prefix}-eks-vpc-cni"
  assume_role_policy   = data.aws_iam_policy_document.vpc_cni_assume_role.json
  permissions_boundary = var.permissions_boundary

  # Required by the CI role's IAM policy (aws:RequestTag/project must be k8s-control)
  tags = {
    project = "k8s-control"
  }
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni.name
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.cluster.name
  addon_name                  = "vpc-cni"
  addon_version               = var.vpc_cni_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.vpc_cni.arn

  tags = {
    project = "k8s-control"
  }

  depends_on = [
    aws_iam_role_policy_attachment.vpc_cni
  ]
}

# CoreDNS managed add-on (cluster DNS).
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.cluster.name
  addon_name                  = "coredns"
  addon_version               = var.coredns_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    project = "k8s-control"
  }
}

# kube-proxy managed add-on (per-node service proxy).
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.cluster.name
  addon_name                  = "kube-proxy"
  addon_version               = var.kube_proxy_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    project = "k8s-control"
  }
}
