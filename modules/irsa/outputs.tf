output "role_arns" {
  description = "Role ARNs keyed by logical role name. Annotate the service account with eks.amazonaws.com/role-arn."
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}

output "role_names" {
  description = "Role names keyed by logical role name."
  value       = { for k, r in aws_iam_role.this : k => r.name }
}

output "service_account_annotations" {
  description = "Ready-to-use service account annotation per role."
  value = {
    for k, r in aws_iam_role.this : k => {
      namespace       = var.roles[k].namespace
      service_account = var.roles[k].service_account
      annotation      = "eks.amazonaws.com/role-arn: ${r.arn}"
    }
  }
}
