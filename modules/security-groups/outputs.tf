output "cluster_security_group_id" {
  description = "Additional security group attached to the control plane ENIs."
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "Security group attached to worker node ENIs."
  value       = aws_security_group.node.id
}

output "cluster_security_group_arn" {
  description = "ARN of the control plane security group."
  value       = aws_security_group.cluster.arn
}

output "node_security_group_arn" {
  description = "ARN of the node security group."
  value       = aws_security_group.node.arn
}
