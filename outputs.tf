###############################################################################
# Cluster
###############################################################################

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint. Reachable from inside the VPC only, unless public access was enabled."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Running Kubernetes version."
  value       = module.eks.cluster_version
}

output "cluster_platform_version" {
  description = "EKS platform version."
  value       = module.eks.cluster_platform_version
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA bundle for the API server."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group EKS manages for the cluster."
  value       = module.eks.cluster_security_group_id
}

output "update_kubeconfig_command" {
  description = "Run this to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

###############################################################################
# Network
###############################################################################

output "region" {
  description = "Region the cluster is deployed in."
  value       = var.region
}

output "vpc_id" {
  description = "VPC id."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "VPC CIDR."
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "Private subnets hosting nodes, pods and internal load balancers."
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnets hosting NAT gateways and internet-facing load balancers."
  value       = module.vpc.public_subnet_ids
}

output "nat_gateway_public_ips" {
  description = "Egress IPs. Empty when enable_nat_gateway is false."
  value       = module.vpc.nat_gateway_public_ips
}

output "node_placement" {
  description = "Where worker nodes run and how they reach the internet."
  value = {
    subnets     = var.place_nodes_in_public_subnets ? "public" : "private"
    public_ip   = var.place_nodes_in_public_subnets
    nat_gateway = var.enable_nat_gateway
    egress_path = var.place_nodes_in_public_subnets ? "internet gateway" : (var.enable_nat_gateway ? "nat gateway" : "vpc endpoints only")
  }
}

output "availability_zones" {
  description = "Availability zones in use."
  value       = module.vpc.availability_zones
}

output "vpc_endpoint_ids" {
  description = "Interface VPC endpoint ids, or null when endpoints are disabled."
  value       = var.enable_vpc_endpoints ? module.vpc_endpoints[0].interface_endpoint_ids : null
}

###############################################################################
# Security groups
###############################################################################

output "node_security_group_id" {
  description = "Security group attached to worker nodes. Reference this from RDS, ElastiCache and other data stores."
  value       = module.security_groups.node_security_group_id
}

output "cluster_additional_security_group_id" {
  description = "Terraform-managed security group on the control plane ENIs."
  value       = module.security_groups.cluster_security_group_id
}

###############################################################################
# IAM and IRSA
###############################################################################

output "cluster_iam_role_arn" {
  description = "Role assumed by the control plane."
  value       = module.iam.cluster_role_arn
}

output "node_iam_role_arn" {
  description = "Worker node instance role."
  value       = module.iam.node_role_arn
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider for the cluster. Needed to create further IRSA roles."
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "OIDC issuer without the scheme, for IRSA trust conditions."
  value       = module.eks.oidc_provider_url
}

output "irsa_role_arns" {
  description = "IRSA role ARNs keyed by logical name."
  value       = module.irsa.role_arns
}

output "irsa_service_account_annotations" {
  description = "Service account annotation to apply for each IRSA role."
  value       = module.irsa.service_account_annotations
}

###############################################################################
# KMS
###############################################################################

output "kms_key_arns" {
  description = "Customer-managed keys created for the cluster. Values are null when use_customer_managed_keys is false."
  value = {
    logs        = local.kms_logs_key_arn
    eks_secrets = local.kms_eks_secrets_key_arn
    ebs         = local.kms_ebs_key_arn
  }
}

###############################################################################
# Data plane
###############################################################################

output "node_group_names" {
  description = "Managed node group names."
  value       = module.node_groups.node_group_names
}

output "node_group_autoscaling_groups" {
  description = "Autoscaling groups backing each node group."
  value       = module.node_groups.autoscaling_group_names
}

output "addon_versions" {
  description = "Installed addon versions. Copy these into addon_versions to pin them."
  value       = module.addons.addon_versions
}

###############################################################################
# Observability
###############################################################################

output "log_group_names" {
  description = "CloudWatch log groups created for the cluster."
  value = {
    control_plane = module.eks.cluster_log_group_name
    vpc_flow_logs = module.vpc.flow_log_group_name
  }
}
