###############################################################################
# EKS control plane.
#
# Notable defaults:
#   - private API endpoint only
#   - secrets in etcd encrypted with a customer-managed CMK (envelope encryption)
#   - all five control plane log streams on, to an encrypted log group
#   - authorisation through access entries instead of the aws-auth ConfigMap
#   - IAM OIDC provider created so workloads use IRSA, never node credentials
###############################################################################

data "aws_partition" "current" {}

###############################################################################
# Control plane log group
#
# Created ahead of the cluster. If EKS creates it implicitly it lands with
# "never expire" retention and no CMK.
###############################################################################

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = merge(var.tags, { Name = "${var.cluster_name}-control-plane-logs" })
}

###############################################################################
# Cluster
###############################################################################

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = var.cluster_role_arn

  enabled_cluster_log_types = var.log_types

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = var.security_group_ids
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.public_access_cidrs : null
  }

  access_config {
    authentication_mode = var.authentication_mode

    # The identity that runs terraform apply would otherwise silently become a
    # cluster admin. Grant admin explicitly through admin_principal_arns.
    bootstrap_cluster_creator_admin_permissions = false
  }

  # Envelope encryption cannot be added or removed after creation - changing
  # this forces a replacement of the cluster.
  dynamic "encryption_config" {
    for_each = var.secrets_kms_key_arn != null ? [1] : []

    content {
      provider {
        key_arn = var.secrets_kms_key_arn
      }
      resources = ["secrets"]
    }
  }

  kubernetes_network_config {
    ip_family         = var.ip_family
    service_ipv4_cidr = var.ip_family == "ipv4" ? var.service_ipv4_cidr : null
  }

  upgrade_policy {
    support_type = var.support_type
  }

  tags = merge(var.tags, { Name = var.cluster_name })

  depends_on = [aws_cloudwatch_log_group.cluster]

  lifecycle {
    precondition {
      condition     = var.endpoint_private_access || var.endpoint_public_access
      error_message = "At least one of endpoint_private_access or endpoint_public_access must be true, otherwise the API server is unreachable."
    }

    precondition {
      condition     = !var.endpoint_public_access || length(var.public_access_cidrs) > 0
      error_message = "endpoint_public_access is true but public_access_cidrs is empty, which would default to 0.0.0.0/0. List explicit administrative CIDRs."
    }
  }
}

###############################################################################
# IRSA - IAM OIDC identity provider
###############################################################################

data "tls_certificate" "oidc" {
  count = var.enable_irsa ? 1 : 0

  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  count = var.enable_irsa ? 1 : 0

  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc[0].certificates[0].sha1_fingerprint]

  tags = merge(var.tags, { Name = "${var.cluster_name}-oidc" })
}

###############################################################################
# Access entries
#
# Replaces hand-editing the aws-auth ConfigMap. Each principal gets an entry
# plus an explicit policy association, so cluster access is reviewable in a
# merge request.
###############################################################################

resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = each.value
  type              = "STANDARD"
  kubernetes_groups = []

  tags = merge(var.tags, { Name = "${var.cluster_name}-admin-access" })
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}
