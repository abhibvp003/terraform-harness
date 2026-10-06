output "cluster_role_arn" {
  description = "ARN of the role the EKS control plane assumes."
  value       = aws_iam_role.cluster.arn
}

output "cluster_role_name" {
  description = "Name of the cluster role."
  value       = aws_iam_role.cluster.name
}

output "node_role_arn" {
  description = "ARN of the worker node instance role."
  value       = aws_iam_role.node.arn
}

output "node_role_name" {
  description = "Name of the worker node instance role."
  value       = aws_iam_role.node.name
}

output "node_instance_profile_name" {
  description = "Instance profile wrapping the node role."
  value       = aws_iam_instance_profile.node.name
}

output "node_instance_profile_arn" {
  description = "ARN of the node instance profile."
  value       = aws_iam_instance_profile.node.arn
}
