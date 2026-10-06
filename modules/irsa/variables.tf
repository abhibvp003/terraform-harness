variable "name_prefix" {
  description = "Prefix for the generated role names."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider."
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC issuer host and path with no scheme, e.g. oidc.eks.us-east-1.amazonaws.com/id/ABCDEF."
  type        = string

  validation {
    condition     = !startswith(var.oidc_provider_url, "https://")
    error_message = "oidc_provider_url must not include the https:// scheme."
  }
}

variable "roles" {
  description = <<-EOT
    IAM roles assumable by Kubernetes service accounts, keyed by logical name.

    The trust policy pins both the audience (sts.amazonaws.com) and the exact
    system:serviceaccount:<namespace>:<name> subject. Wildcard subjects are
    rejected - a role scoped to a whole namespace can be claimed by any pod
    that lands there.
  EOT

  type = map(object({
    namespace       = string
    service_account = string
    description     = optional(string, "")
    policy_arns     = optional(list(string), [])
    inline_policy   = optional(string, null)
  }))

  default = {}

  validation {
    condition = alltrue([
      for r in values(var.roles) :
      !strcontains(r.namespace, "*") && !strcontains(r.service_account, "*")
    ])
    error_message = "Wildcards are not allowed in namespace or service_account. Scope each role to one service account."
  }
}

variable "permissions_boundary_arn" {
  description = "Optional permissions boundary applied to every generated role."
  type        = string
  default     = null
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds for the generated roles."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds."
  }
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
