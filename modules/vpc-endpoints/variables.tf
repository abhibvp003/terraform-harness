variable "name" {
  description = "Name prefix for endpoint resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC to attach the endpoints to."
  type        = string
}

variable "region" {
  description = "AWS region. Used to build service names."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet ids that host the interface endpoint ENIs."
  type        = list(string)
}

variable "route_table_ids" {
  description = "Route tables that receive prefix-list routes for gateway endpoints."
  type        = list(string)
}

variable "vpc_cidr_block" {
  description = "VPC CIDR allowed to reach the interface endpoints on 443."
  type        = string
}

variable "allowed_security_group_ids" {
  description = "Security groups additionally allowed to reach the interface endpoints on 443."
  type        = list(string)
  default     = []
}

variable "interface_services" {
  description = <<-EOT
    Short service names to create interface endpoints for. The module expands
    them to com.amazonaws.<region>.<service>.

    The defaults are what a private EKS cluster needs to pull images, write
    logs, resolve IRSA credentials and manage load balancers without egress to
    the internet.
  EOT

  type = list(string)

  default = [
    "ec2",
    "ecr.api",
    "ecr.dkr",
    "elasticloadbalancing",
    "logs",
    "sts",
    "autoscaling",
    "kms",
    "eks",
    "eks-auth",
  ]
}

variable "gateway_services" {
  description = "Gateway endpoint services. S3 is effectively mandatory - ECR stores image layers there."
  type        = list(string)
  default     = ["s3"]
}

variable "private_dns_enabled" {
  description = "Resolve the public AWS service hostnames to the endpoint ENIs. Leave true or clients will keep using the internet path."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
