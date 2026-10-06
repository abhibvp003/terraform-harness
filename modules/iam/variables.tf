variable "name" {
  description = "Name prefix for IAM roles."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Optional permissions boundary applied to both roles. Set this in regulated accounts to make privilege escalation impossible."
  type        = string
  default     = null
}

variable "attach_cni_policy_to_node_role" {
  description = <<-EOT
    Attach AmazonEKS_CNI_Policy to the node instance role.

    Leave false. The vpc-cni addon is configured with its own IRSA role, which
    scopes ENI management to the aws-node service account instead of handing it
    to every pod that can reach the instance metadata endpoint.

    Set true only if you deliberately run the CNI without IRSA.
  EOT

  type    = bool
  default = false
}

variable "enable_ssm_access" {
  description = "Attach AmazonSSMManagedInstanceCore so operators get shell access through Session Manager rather than SSH on port 22."
  type        = bool
  default     = true
}

variable "additional_cluster_policy_arns" {
  description = "Extra managed policy ARNs for the cluster role."
  type        = list(string)
  default     = []
}

variable "additional_node_policy_arns" {
  description = "Extra managed policy ARNs for the node role."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
