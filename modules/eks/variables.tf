variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Control plane minor version, for example 1.31."
  type        = string
}

variable "cluster_role_arn" {
  description = "ARN of the IAM role the control plane assumes."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the control plane ENIs. Use the private subnets."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS requires subnets in at least two availability zones."
  }
}

variable "security_group_ids" {
  description = "Additional security groups attached to the control plane ENIs."
  type        = list(string)
  default     = []
}

variable "endpoint_private_access" {
  description = "Enable the private API endpoint inside the VPC. Keep true."
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Expose the API endpoint to the internet."
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public endpoint. Ignored when endpoint_public_access is false."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.public_access_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 is not permitted. List explicit administrative CIDRs."
  }
}

variable "secrets_kms_key_arn" {
  description = <<-EOT
    CMK for envelope encryption of Kubernetes secrets in etcd.

    null disables the envelope encryption layer. EKS still encrypts etcd at
    rest with an AWS-managed key, so secrets are not sitting in plaintext -
    you simply lose the second layer and the ability to revoke the key.

    Set a key for anything handling real data.
  EOT

  type    = string
  default = null

  validation {
    condition = (
      var.secrets_kms_key_arn == null
      || can(regex("^arn:aws[a-z-]*:kms:", var.secrets_kms_key_arn))
    )
    error_message = "secrets_kms_key_arn must be a KMS key ARN or null."
  }
}

variable "log_types" {
  description = "Control plane log types to publish to CloudWatch."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  validation {
    condition = alltrue([
      for t in var.log_types :
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)
    ])
    error_message = "Valid log types: api, audit, authenticator, controllerManager, scheduler."
  }

  validation {
    condition     = contains(var.log_types, "audit") && contains(var.log_types, "authenticator")
    error_message = "The audit and authenticator logs are the record of who did what in the cluster. Both must stay enabled."
  }
}

variable "log_retention_days" {
  description = "Retention for the control plane log group."
  type        = number
  default     = 90
}

variable "log_kms_key_arn" {
  description = "CMK encrypting the control plane log group. null falls back to the AWS-managed CloudWatch Logs key."
  type        = string
  default     = null
}

variable "service_ipv4_cidr" {
  description = "CIDR for Kubernetes Service IPs. Must not overlap the VPC. null lets EKS choose."
  type        = string
  default     = null
}

variable "ip_family" {
  description = "Address family for the cluster: ipv4 or ipv6."
  type        = string
  default     = "ipv4"

  validation {
    condition     = contains(["ipv4", "ipv6"], var.ip_family)
    error_message = "ip_family must be ipv4 or ipv6."
  }
}

variable "authentication_mode" {
  description = <<-EOT
    How cluster authorisation is managed.

    API                 - access entries only. Cleanest, fully in Terraform.
    API_AND_CONFIG_MAP  - access entries plus the legacy aws-auth ConfigMap.
                          Use while migrating existing tooling.
  EOT

  type    = string
  default = "API"

  validation {
    condition     = contains(["API", "API_AND_CONFIG_MAP"], var.authentication_mode)
    error_message = "authentication_mode must be API or API_AND_CONFIG_MAP. CONFIG_MAP alone is deprecated."
  }
}

variable "admin_principal_arns" {
  description = "IAM principals granted AmazonEKSClusterAdminPolicy via access entries. Use roles, not users."
  type        = list(string)
  default     = []
}

variable "support_type" {
  description = "STANDARD ends support at end of standard support. EXTENDED keeps the version patched (and billed) for longer."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.support_type)
    error_message = "support_type must be STANDARD or EXTENDED."
  }
}

variable "enable_irsa" {
  description = "Create the IAM OIDC provider so service accounts can assume IAM roles."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
