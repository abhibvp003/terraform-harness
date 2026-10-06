variable "name" {
  description = "Name prefix for VPC resources."
  type        = string
}

variable "cidr_block" {
  description = "Primary IPv4 CIDR for the VPC."
  type        = string
}

variable "azs" {
  description = "Availability zone names. One private and one public subnet is created per AZ."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "EKS requires subnets in at least two availability zones."
  }
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs, index-aligned with azs. Nodes and pods live here."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, index-aligned with azs. Internet-facing load balancers and NAT gateways live here."
  type        = list(string)
}

variable "cluster_name" {
  description = "EKS cluster name, used for subnet discovery tags."
  type        = string
}

variable "enable_nat_gateway" {
  description = <<-EOT
    Create NAT gateways so private subnets can reach the internet.

    A NAT gateway is about 33 USD/month plus data processing, and it is the
    second largest line item after the EKS control plane. Set this to false
    only if nothing runs in the private subnets, or if the nodes sit in public
    subnets instead.

    With this false the private route tables get no default route, so private
    subnets become genuinely isolated.
  EOT

  type    = bool
  default = true
}

variable "single_nat_gateway" {
  description = "Place one NAT gateway in the first AZ instead of one per AZ. Ignored when enable_nat_gateway is false."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Publish VPC flow logs to CloudWatch Logs."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "CloudWatch retention for flow logs."
  type        = number
  default     = 90
}

variable "flow_log_traffic_type" {
  description = "Which traffic to capture: ACCEPT, REJECT or ALL."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be ACCEPT, REJECT or ALL."
  }
}

variable "kms_key_arn" {
  description = <<-EOT
    CMK used to encrypt the flow log group.

    null means CloudWatch Logs encrypts the group with an AWS-managed key
    instead. The data is still encrypted at rest; you just do not control or
    audit the key. Saves 1 USD/month per CMK.
  EOT

  type    = string
  default = null
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}

variable "public_subnet_tags" {
  description = "Extra tags for public subnets."
  type        = map(string)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Extra tags for private subnets."
  type        = map(string)
  default     = {}
}
