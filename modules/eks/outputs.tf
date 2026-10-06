output "cluster_name" {
  description = "Cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "Cluster ARN."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_version" {
  description = "Running control plane version."
  value       = aws_eks_cluster.this.version
}

output "cluster_platform_version" {
  description = "EKS platform version of the control plane."
  value       = aws_eks_cluster.this.platform_version
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA bundle for the API server. Needed to build a kubeconfig."
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group EKS created and attached to the control plane and managed nodes."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider, or null when IRSA is disabled."
  value       = var.enable_irsa ? aws_iam_openid_connect_provider.this[0].arn : null
}

output "oidc_provider_url" {
  description = "OIDC issuer URL without the https:// scheme, for IRSA trust conditions."
  value       = var.enable_irsa ? replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "") : null
}

output "oidc_issuer_url" {
  description = "Full OIDC issuer URL."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "cluster_log_group_name" {
  description = "CloudWatch log group holding control plane logs."
  value       = aws_cloudwatch_log_group.cluster.name
}
