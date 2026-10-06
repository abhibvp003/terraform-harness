###############################################################################
# EKS managed addons.
#
# EKS pre-installs vpc-cni, coredns and kube-proxy when the cluster is created.
# Declaring them here takes ownership: versions, configuration and the IRSA
# role each addon runs as all become part of the plan instead of drifting
# silently behind AWS defaults.
###############################################################################

resource "aws_eks_addon" "this" {
  for_each = var.addons

  cluster_name = var.cluster_name
  addon_name   = each.key

  # Omitting addon_version lets EKS pick the default for the cluster version.
  addon_version = each.value.version

  service_account_role_arn = each.value.service_account_role_arn
  configuration_values     = each.value.configuration_values

  resolve_conflicts_on_create = each.value.resolve_conflicts_on_create
  resolve_conflicts_on_update = each.value.resolve_conflicts_on_update

  preserve = each.value.preserve

  tags = merge(var.tags, { Name = "${var.cluster_name}-${each.key}" })

  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }
}
