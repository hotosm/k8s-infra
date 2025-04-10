resource "aws_iam_role" "nodegroup" {
  name = "${local.cluster_prefix}-nodegroup-role"
  permissions_boundary = var.permissions_boundary

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "node_worker_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.nodegroup.name
}

resource "aws_iam_role_policy_attachment" "node_worker_cni_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.nodegroup.name
}

resource "aws_iam_role_policy_attachment" "node_worker_ecr_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.nodegroup.name
}

resource "aws_eks_node_group" "core_nodes" {
  cluster_name    = aws_eks_cluster.cluster.name
  node_group_name = "core"
  node_role_arn   = aws_iam_role.nodegroup.arn

  subnet_ids = module.vpc.private_subnets

  instance_types = [var.instance_type]

  capacity_type = var.capacity_type

  scaling_config {
    desired_size = 1
    max_size     = var.max_instances
    min_size     = 0
  }

  lifecycle {
    # Allow cluster-autoscaler to change the size of nodepool without messing up terraform
    ignore_changes = [scaling_config[0].desired_size]
  }
  update_config {
    max_unavailable = 1
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    module.vpc,
    aws_iam_role_policy_attachment.node_worker_policy_attachment,
    aws_iam_role_policy_attachment.node_worker_cni_policy_attachment,
    aws_iam_role_policy_attachment.node_worker_ecr_policy_attachment
  ]
}
