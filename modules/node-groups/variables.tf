variable "cluster_name" {
  description = "Name of the EKS cluster the node groups join."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the nodes. Keep it aligned with the control plane."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for node group and launch template names."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets nodes launch into. Use private subnets only."
  type        = list(string)
}

variable "node_role_arn" {
  description = "ARN of the node instance role."
  type        = string
}

variable "security_group_ids" {
  description = "Security groups attached to node ENIs, in addition to the EKS-managed cluster security group."
  type        = list(string)
  default     = []
}

variable "ebs_kms_key_arn" {
  description = <<-EOT
    CMK encrypting node root volumes.

    null uses the AWS-managed aws/ebs key. Volumes stay encrypted either way;
    a CMK just gives you control and an audit trail over the key.
  EOT

  type    = string
  default = null

  validation {
    condition = (
      var.ebs_kms_key_arn == null
      || can(regex("^arn:aws[a-z-]*:kms:", var.ebs_kms_key_arn))
    )
    error_message = "ebs_kms_key_arn must be a KMS key ARN or null."
  }
}

variable "associate_public_ip" {
  description = <<-EOT
    Give each node a public IPv4 address.

    This exists to avoid paying for a NAT gateway: a node in a public subnet
    reaches ECR and the AWS APIs straight through the internet gateway. A
    public IPv4 address costs about 3.60 USD/month versus roughly 33 USD/month
    for a NAT gateway.

    The tradeoff is real. The node is addressable from the internet and only
    its security group stands in the way. That group allows no inbound rules
    from outside the cluster, and there is no SSH port open, but this is still
    a weaker posture than a private subnet. Use it for learning, not for
    anything carrying data you care about.

    Requires subnet_ids to be public subnets.
  EOT

  type    = bool
  default = false
}

variable "node_groups" {
  description = "Managed node groups, keyed by name."

  type = map(object({
    instance_types = optional(list(string), ["t3.medium"])
    capacity_type  = optional(string, "ON_DEMAND")
    ami_type       = optional(string, "AL2023_x86_64_STANDARD")

    desired_size = number
    min_size     = number
    max_size     = number

    disk_size_gb         = optional(number, 50)
    disk_type            = optional(string, "gp3")
    disk_iops            = optional(number, 3000)
    disk_throughput_mbps = optional(number, 125)

    labels = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])

    max_unavailable_percentage = optional(number, 25)
    force_update_version       = optional(bool, false)
  }))

  validation {
    condition = alltrue([
      for g in values(var.node_groups) : g.min_size <= g.desired_size && g.desired_size <= g.max_size
    ])
    error_message = "Each node group needs min_size <= desired_size <= max_size."
  }

  validation {
    condition = alltrue([
      for g in values(var.node_groups) : contains(["ON_DEMAND", "SPOT"], g.capacity_type)
    ])
    error_message = "capacity_type must be ON_DEMAND or SPOT."
  }

  validation {
    condition = alltrue([
      for g in values(var.node_groups) : alltrue([
        for t in g.taints : contains(["NO_SCHEDULE", "NO_EXECUTE", "PREFER_NO_SCHEDULE"], t.effect)
      ])
    ])
    error_message = "Taint effect must be NO_SCHEDULE, NO_EXECUTE or PREFER_NO_SCHEDULE."
  }
}

variable "imds_hop_limit" {
  description = <<-EOT
    IMDSv2 PUT response hop limit.

    1 means only the host itself can reach instance metadata, so an ordinary
    pod cannot read the node's IAM credentials. Pods that need AWS access use
    IRSA. Host-network pods such as aws-node are unaffected.

    Raise to 2 only if you knowingly run a workload that must read IMDS from
    inside a container network namespace.
  EOT

  type    = number
  default = 1

  validation {
    condition     = var.imds_hop_limit >= 1 && var.imds_hop_limit <= 64
    error_message = "imds_hop_limit must be between 1 and 64."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable EC2 detailed (1-minute) monitoring. Costs extra per instance but shortens the time to notice a bad node."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
