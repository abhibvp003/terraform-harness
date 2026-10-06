###############################################################################
# Identity / placement
###############################################################################

variable "project" {
  description = "Short project name. Used as the prefix for every resource name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,22}[a-z0-9]$", var.project))
    error_message = "project must be 3-24 chars, lowercase alphanumeric or hyphen, and may not start/end with a hyphen."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "si", "stage", "prod"], var.environment)
    error_message = "environment must be one of: dev, si, stage, prod."
  }
}

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "allowed_account_ids" {
  description = "AWS account ids this configuration is allowed to apply to. Empty list disables the check (not recommended)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Extra tags applied to every resource via provider default_tags."
  type        = map(string)
  default     = {}
}

variable "use_customer_managed_keys" {
  description = <<-EOT
    Create customer-managed KMS keys for etcd secrets, log groups and EBS
    volumes.

    Each CMK is 1 USD/month, so three keys cost 3 USD/month. Setting this
    false falls back to AWS-managed keys: everything stays encrypted at rest,
    but you lose key control, rotation policy and the ability to revoke.

    Note that etcd envelope encryption cannot be toggled after the cluster is
    created - flipping this later replaces the cluster.
  EOT

  type    = bool
  default = true
}

###############################################################################
# Networking
###############################################################################

variable "vpc_cidr" {
  description = "Primary IPv4 CIDR for the VPC. A /16 is recommended for EKS because every pod consumes a VPC IP."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be a valid IPv4 CIDR of /20 or larger."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 6
    error_message = "az_count must be between 2 and 6. EKS requires at least 2 AZs."
  }
}

variable "enable_nat_gateway" {
  description = <<-EOT
    Create NAT gateways for the private subnets.

    Roughly 33 USD/month per gateway plus 0.045 USD/GB processed, and the
    second largest cost after the EKS control plane.

    Setting this false requires place_nodes_in_public_subnets = true (or VPC
    endpoints), otherwise nodes cannot reach ECR and will never register.
  EOT

  type    = bool
  default = true
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per AZ. Cheaper, but a single AZ failure breaks egress. Keep false for prod."
  type        = bool
  default     = false
}

variable "place_nodes_in_public_subnets" {
  description = <<-EOT
    Put worker nodes in the public subnets with public IPv4 addresses instead
    of private subnets behind NAT.

    This is a cost decision: about 3.60 USD/month per public IP against roughly
    33 USD/month for a NAT gateway. It also weakens the network posture -
    nodes become internet-addressable, with only their security group in
    front. No inbound rules are opened from outside the cluster and there is
    no SSH port, but a private subnet is still strictly safer.

    Reasonable for a learning cluster. Not for anything handling real data.
  EOT

  type    = bool
  default = false
}

variable "enable_flow_logs" {
  description = <<-EOT
    Send VPC flow logs to CloudWatch.

    Nothing in the cluster depends on these - they are purely for forensics
    and debugging connectivity. CloudWatch ingestion is 0.50 USD/GB with only
    5 GB/month free, and flow logs are chatty, so this is the first thing to
    turn off on a learning cluster.
  EOT

  type    = bool
  default = true
}

variable "flow_log_retention_days" {
  description = "Retention for VPC flow logs."
  type        = number
  default     = 90
}

variable "enable_vpc_endpoints" {
  description = "Create interface/gateway VPC endpoints so nodes can reach AWS APIs without traversing the internet."
  type        = bool
  default     = true
}

###############################################################################
# Cluster
###############################################################################

variable "kubernetes_version" {
  description = "EKS control plane minor version."
  type        = string
  default     = "1.31"

  validation {
    condition     = can(regex("^1\\.(2[6-9]|3[0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.30, 1.31, ..."
  }
}

variable "cluster_endpoint_public_access" {
  description = "Expose the Kubernetes API endpoint to the internet. Keep false and reach the API over the private endpoint."
  type        = bool
  default     = false
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Required when cluster_endpoint_public_access is true. 0.0.0.0/0 is rejected."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.cluster_endpoint_public_access_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 is not an acceptable source for the Kubernetes API endpoint. List explicit corporate CIDRs."
  }
}

variable "cluster_api_allowed_cidrs" {
  description = "CIDRs inside the network allowed to reach the private API endpoint on 443 (e.g. bastion / VPN / CI subnets). 0.0.0.0/0 is rejected."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.cluster_api_allowed_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 is not an acceptable source for the Kubernetes API endpoint."
  }
}

variable "cluster_log_types" {
  description = "Control plane log types shipped to CloudWatch."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_log_retention_days" {
  description = "Retention for control plane logs."
  type        = number
  default     = 90
}

variable "service_ipv4_cidr" {
  description = "CIDR the cluster allocates Service IPs from. Must not overlap the VPC. null lets EKS pick."
  type        = string
  default     = null
}

variable "cluster_admin_principal_arns" {
  description = "IAM role/user ARNs granted cluster-admin through EKS access entries. Prefer roles, never long-lived users."
  type        = list(string)
  default     = []
}

###############################################################################
# Node groups
###############################################################################

variable "node_groups" {
  description = <<-EOT
    Managed node groups, keyed by name. All fields except desired/min/max have
    sane defaults. Nodes always land in private subnets with IMDSv2 required
    and encrypted EBS.
  EOT

  type = map(object({
    instance_types = optional(list(string), ["t3.medium"])
    capacity_type  = optional(string, "ON_DEMAND")
    ami_type       = optional(string, "AL2023_x86_64_STANDARD")

    desired_size = number
    min_size     = number
    max_size     = number

    disk_size_gb = optional(number, 50)
    disk_type    = optional(string, "gp3")
    disk_iops    = optional(number, 3000)

    labels = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])

    max_unavailable_percentage = optional(number, 25)
    force_update_version       = optional(bool, false)
  }))

  # Single t3.medium (2 vCPU, 4 GiB) - the cheapest shape that still runs the
  # kube-system pods with room to spare.
  #
  # max_size is 2 rather than 1 on purpose: a managed node group upgrade drains
  # the old node before the replacement joins, so with a ceiling of 1 every
  # version bump is a full outage. A ceiling of 2 lets the roll overlap. Only
  # one node runs in steady state, so the bill is unchanged.
  default = {
    general = {
      instance_types = ["t3.medium"]
      desired_size   = 1
      min_size       = 1
      max_size       = 2
    }
  }
}

###############################################################################
# Addons
###############################################################################

variable "coredns_replica_count" {
  description = <<-EOT
    Number of CoreDNS replicas.

    Set this to 1 on a single-node cluster. With 2 replicas the addon also gets
    a PodDisruptionBudget of maxUnavailable=1, and on one node that budget
    blocks the drain during an upgrade: the second replica cannot be evicted
    because there is nowhere else to schedule it.

    Use 2 or more as soon as you have more than one node, so losing a node
    does not take cluster DNS with it.
  EOT

  type    = number
  default = 1

  validation {
    condition     = var.coredns_replica_count >= 1
    error_message = "coredns_replica_count must be at least 1."
  }
}

variable "addon_versions" {
  description = "Pin addon versions. Key = addon name, value = version string. null/omitted means 'EKS default for this cluster version'."
  type        = map(string)
  default     = {}
}

variable "additional_irsa_roles" {
  description = "Extra IRSA roles to create, keyed by logical name."
  type = map(object({
    namespace       = string
    service_account = string
    description     = optional(string, "")
    policy_arns     = optional(list(string), [])
    inline_policy   = optional(string, null)
  }))
  default = {}
}
