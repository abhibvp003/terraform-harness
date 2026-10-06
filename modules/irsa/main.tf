###############################################################################
# IAM Roles for Service Accounts (IRSA).
#
# Workloads get AWS permissions by exchanging a projected Kubernetes service
# account token for STS credentials. Nothing needs the node instance role, so a
# compromised pod cannot borrow node-wide permissions.
###############################################################################

locals {
  # Flatten role -> policy ARN pairs so each attachment gets a stable address.
  role_policy_attachments = merge([
    for role_key, role in var.roles : {
      for policy_arn in role.policy_arns :
      "${role_key}:${policy_arn}" => {
        role_key   = role_key
        policy_arn = policy_arn
      }
    }
  ]...)

  inline_policies = {
    for role_key, role in var.roles : role_key => role.inline_policy
    if role.inline_policy != null
  }
}

data "aws_iam_policy_document" "assume" {
  for_each = var.roles

  statement {
    sid     = "AllowOidcAssumeRoleWithWebIdentity"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    # Pinning the audience blocks tokens minted for any other relying party.
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Pinning the subject binds the role to one service account in one namespace.
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = var.roles

  name = "${var.name_prefix}-${each.key}"
  description = (
    each.value.description != ""
    ? each.value.description
    : "IRSA role for ${each.value.namespace}/${each.value.service_account}"
  )

  assume_role_policy    = data.aws_iam_policy_document.assume[each.key].json
  permissions_boundary  = var.permissions_boundary_arn
  max_session_duration  = var.max_session_duration
  force_detach_policies = true

  tags = merge(var.tags, {
    Name           = "${var.name_prefix}-${each.key}"
    Namespace      = each.value.namespace
    ServiceAccount = each.value.service_account
  })
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = local.role_policy_attachments

  role       = aws_iam_role.this[each.value.role_key].name
  policy_arn = each.value.policy_arn
}

resource "aws_iam_role_policy" "inline" {
  for_each = local.inline_policies

  name   = "${var.name_prefix}-${each.key}-inline"
  role   = aws_iam_role.this[each.key].id
  policy = each.value
}
