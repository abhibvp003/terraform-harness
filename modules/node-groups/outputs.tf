output "node_group_names" {
  description = "Node group names keyed by logical name."
  value       = { for k, g in aws_eks_node_group.this : k => g.node_group_name }
}

output "node_group_arns" {
  description = "Node group ARNs keyed by logical name."
  value       = { for k, g in aws_eks_node_group.this : k => g.arn }
}

output "node_group_statuses" {
  description = "Current status of each node group."
  value       = { for k, g in aws_eks_node_group.this : k => g.status }
}

output "autoscaling_group_names" {
  description = "Autoscaling groups backing each node group. Useful for scaling policies and alarms."
  value = {
    for k, g in aws_eks_node_group.this :
    k => [for r in g.resources : [for asg in r.autoscaling_groups : asg.name]]
  }
}

output "launch_template_ids" {
  description = "Launch template id per node group."
  value       = { for k, lt in aws_launch_template.this : k => lt.id }
}

output "launch_template_latest_versions" {
  description = "Latest launch template version per node group."
  value       = { for k, lt in aws_launch_template.this : k => lt.latest_version }
}
