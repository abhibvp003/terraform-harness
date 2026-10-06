output "addon_versions" {
  description = "Installed version of each addon."
  value       = { for k, a in aws_eks_addon.this : k => a.addon_version }
}

output "addon_arns" {
  description = "ARN of each addon."
  value       = { for k, a in aws_eks_addon.this : k => a.arn }
}
