variable "name" {
  description = "Name prefix for security groups."
  type        = string
}

variable "vpc_id" {
  description = "VPC the security groups belong to."
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR. Used for intra-VPC allowances such as webhook callbacks."
  type        = string
}

variable "cluster_api_allowed_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the private Kubernetes API endpoint on 443, for
    example a bastion subnet, VPN range or CI runner subnet.

    0.0.0.0/0 is rejected: the API server is an administrative control plane,
    not a public service.
  EOT

  type    = list(string)
  default = []

  validation {
    condition     = !contains(var.cluster_api_allowed_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 is not permitted as a source for the Kubernetes API endpoint."
  }
}

variable "node_extra_ingress_rules" {
  description = <<-EOT
    Additional inbound rules for the node security group, keyed by rule name.
    Supply exactly one source: cidr_ipv4 or source_security_group_id.

    Ports 22 and 3389 are rejected. Use SSM Session Manager for shell access -
    the node IAM role already carries AmazonSSMManagedInstanceCore.
  EOT

  type = map(object({
    description              = string
    ip_protocol              = optional(string, "tcp")
    from_port                = number
    to_port                  = number
    cidr_ipv4                = optional(string)
    source_security_group_id = optional(string)
  }))

  default = {}

  validation {
    condition = alltrue([
      for r in values(var.node_extra_ingress_rules) :
      !(r.from_port <= 22 && r.to_port >= 22) && !(r.from_port <= 3389 && r.to_port >= 3389)
    ])
    error_message = "Ingress on ports 22 (SSH) and 3389 (RDP) is prohibited. Use SSM Session Manager instead."
  }

  validation {
    condition = alltrue([
      for r in values(var.node_extra_ingress_rules) : r.cidr_ipv4 != "0.0.0.0/0"
    ])
    error_message = "0.0.0.0/0 is not permitted as an ingress source."
  }

  validation {
    condition = alltrue([
      for r in values(var.node_extra_ingress_rules) :
      (r.cidr_ipv4 == null) != (r.source_security_group_id == null)
    ])
    error_message = "Each rule must set exactly one of cidr_ipv4 or source_security_group_id."
  }
}

variable "node_egress_cidrs" {
  description = <<-EOT
    Destinations nodes may reach. Defaults to 0.0.0.0/0 because nodes need to
    pull images and reach AWS APIs through NAT.

    If every dependency is served by a VPC endpoint, narrow this to the VPC
    CIDR for a fully egress-restricted data plane.
  EOT

  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
