variable "cluster_name" {
  description = "Cluster the addons are installed into."
  type        = string
}

variable "addons" {
  description = <<-EOT
    EKS managed addons, keyed by the official addon name
    (vpc-cni, coredns, kube-proxy, aws-ebs-csi-driver, eks-pod-identity-agent, ...).

    version = null asks EKS for the default version matching the cluster
    version. Pin a version in prod so an upgrade is a reviewable diff rather
    than a surprise.
  EOT

  type = map(object({
    version                  = optional(string)
    service_account_role_arn = optional(string)
    configuration_values     = optional(string)

    resolve_conflicts_on_create = optional(string, "OVERWRITE")
    resolve_conflicts_on_update = optional(string, "OVERWRITE")

    # Keep the addon's Kubernetes resources when the addon is removed from
    # Terraform, so deleting the addon does not take CoreDNS down with it.
    preserve = optional(bool, true)
  }))

  default = {}

  validation {
    condition = alltrue([
      for a in values(var.addons) :
      contains(["OVERWRITE", "NONE"], a.resolve_conflicts_on_create)
    ])
    error_message = "resolve_conflicts_on_create must be OVERWRITE or NONE."
  }

  validation {
    condition = alltrue([
      for a in values(var.addons) :
      contains(["OVERWRITE", "NONE", "PRESERVE"], a.resolve_conflicts_on_update)
    ])
    error_message = "resolve_conflicts_on_update must be OVERWRITE, NONE or PRESERVE."
  }

  validation {
    condition = alltrue([
      for a in values(var.addons) :
      a.configuration_values == null || can(jsondecode(a.configuration_values))
    ])
    error_message = "configuration_values must be a JSON string."
  }
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
