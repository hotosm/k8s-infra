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

# Add storage classes that reference the aws-ebs-csi-driver
# Default GP3 (its faster and cheaper than gp2 in almost all scenarios)
resource "kubernetes_storage_class" "ebs_gp3_csi" {
  metadata {
    name = "ebs-gp3-csi"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type      = "gp3"
    fsType    = "ext4"
    encrypted = "true"
  }
  depends_on = [aws_eks_addon.ebs_provisioner]
}

# FIXME
# FIXME
# Legacy GP2 provider (temporary, to be deleted post-migration)
# This is used by eoAPI currently
# If we migrate the CrunchyDB --> CloudNativeDB, then update vars
# we can probably delete this after
# https://github.com/hotosm/k8s-infra/issues/38
resource "kubernetes_storage_class" "gp2" {
  metadata {
    name = "gp2"
  }
  storage_provisioner = "kubernetes.io/aws-ebs"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"
  parameters = {
    type   = "gp2"
    fsType = "ext4"
  }
}
