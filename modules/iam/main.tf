###############################################################################
# IAM roles the EKS service and the worker nodes assume.
#
# These are the two roles that must exist before a cluster can be created.
# Roles for workloads are not defined here - those live in modules/irsa and are
# trusted through the cluster's OIDC provider.
###############################################################################

data "aws_partition" "current" {}

locals {
  partition = data.aws_partition.current.partition

  cluster_policy_arns = concat(
    [
      # Lets EKS manage ENIs, load balancers and other cluster resources.
      "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy",
      # Required for security groups for pods.
      "arn:${local.partition}:iam::aws:policy/AmazonEKSVPCResourceController",
    ],
    var.additional_cluster_policy_arns,
  )

  node_policy_arns = concat(
    [
      "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
      # Pull-only. Nodes have no business pushing images.
      "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    ],
    var.enable_ssm_access ? ["arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"] : [],
    var.attach_cni_policy_to_node_role ? ["arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"] : [],
    var.additional_node_policy_arns,
  )
}

###############################################################################
# Cluster role
###############################################################################

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    sid     = "EksServiceAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name                  = "${var.name}-cluster-role"
  description           = "Assumed by the EKS control plane for ${var.name}"
  assume_role_policy    = data.aws_iam_policy_document.cluster_assume.json
  permissions_boundary  = var.permissions_boundary_arn
  force_detach_policies = true

  tags = merge(var.tags, { Name = "${var.name}-cluster-role" })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  for_each = toset(local.cluster_policy_arns)

  role       = aws_iam_role.cluster.name
  policy_arn = each.value
}

###############################################################################
# Node role
###############################################################################

data "aws_iam_policy_document" "node_assume" {
  statement {
    sid     = "Ec2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name                  = "${var.name}-node-role"
  description           = "Instance role for ${var.name} worker nodes"
  assume_role_policy    = data.aws_iam_policy_document.node_assume.json
  permissions_boundary  = var.permissions_boundary_arn
  force_detach_policies = true

  tags = merge(var.tags, { Name = "${var.name}-node-role" })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset(local.node_policy_arns)

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.name}-node-profile"
  role = aws_iam_role.node.name

  tags = merge(var.tags, { Name = "${var.name}-node-profile" })

  lifecycle {
    create_before_destroy = true
  }
}
