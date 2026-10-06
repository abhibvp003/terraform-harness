###############################################################################
# Reusable customer-managed KMS key.
#
# Every encrypted resource in this project gets its own CMK so that blast
# radius and key policies stay narrow: one key for control plane secrets, one
# for CloudWatch log groups, one for EBS volumes.
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_root = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
}

data "aws_iam_policy_document" "key" {
  # Without this the key becomes unmanageable - IAM policies alone cannot
  # grant access to a CMK.
  statement {
    sid    = "EnableAccountRootPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [local.account_root]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(var.key_administrator_arns) > 0 ? [1] : []

    content {
      sid    = "AllowKeyAdministration"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.key_administrator_arns
      }

      actions = [
        "kms:Create*",
        "kms:Describe*",
        "kms:Enable*",
        "kms:List*",
        "kms:Put*",
        "kms:Update*",
        "kms:Revoke*",
        "kms:Disable*",
        "kms:Get*",
        "kms:Delete*",
        "kms:TagResource",
        "kms:UntagResource",
        "kms:ScheduleKeyDeletion",
        "kms:CancelKeyDeletion",
      ]

      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = length(var.key_user_arns) > 0 ? [1] : []

    content {
      sid    = "AllowKeyUsage"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.key_user_arns
      }

      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]

      resources = ["*"]
    }
  }

  # Required so EKS and the autoscaling service-linked role can create grants
  # on your behalf. The condition keeps it limited to AWS-managed grants.
  dynamic "statement" {
    for_each = length(var.key_user_arns) > 0 ? [1] : []

    content {
      sid    = "AllowAwsResourceGrants"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.key_user_arns
      }

      actions = [
        "kms:CreateGrant",
        "kms:ListGrants",
        "kms:RevokeGrant",
      ]

      resources = ["*"]

      condition {
        test     = "Bool"
        variable = "kms:GrantIsForAWSResource"
        values   = ["true"]
      }
    }
  }

  dynamic "statement" {
    for_each = { for s in var.service_principals : s.sid => s }

    content {
      sid    = statement.value.sid
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = [statement.value.principal]
      }

      actions   = statement.value.actions
      resources = ["*"]

      dynamic "condition" {
        for_each = statement.value.conditions

        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

resource "aws_kms_key" "this" {
  description              = var.description
  deletion_window_in_days  = var.deletion_window_in_days
  enable_key_rotation      = var.enable_key_rotation
  multi_region             = var.multi_region
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  policy                   = data.aws_iam_policy_document.key.json

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.this.key_id
}
