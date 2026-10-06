variable "name" {
  description = "Alias suffix for the key. Becomes alias/<name>."
  type        = string
}

variable "description" {
  description = "Human readable description of what the key protects."
  type        = string
}

variable "deletion_window_in_days" {
  description = "Waiting period before a scheduled key deletion completes."
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "enable_key_rotation" {
  description = "Rotate the key material automatically every year."
  type        = bool
  default     = true
}

variable "multi_region" {
  description = "Create a multi-region key. Only needed when replicating data across regions."
  type        = bool
  default     = false
}

variable "key_administrator_arns" {
  description = "Principals allowed to administer (but not use) the key. The account root always retains access."
  type        = list(string)
  default     = []
}

variable "key_user_arns" {
  description = "Principals allowed to encrypt/decrypt with the key and create AWS-resource grants."
  type        = list(string)
  default     = []
}

variable "service_principals" {
  description = <<-EOT
    AWS service principals granted use of the key. Always scope with a
    condition so the service can only use the key on your behalf.

    Example:
      [{
        sid       = "AllowCloudWatchLogs"
        principal = "logs.us-east-1.amazonaws.com"
        conditions = [{
          test     = "ArnLike"
          variable = "kms:EncryptionContext:aws:logs:arn"
          values   = ["arn:aws:logs:us-east-1:111122223333:log-group:*"]
        }]
      }]
  EOT

  type = list(object({
    sid       = string
    principal = string
    actions = optional(list(string), [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ])
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))

  default = []
}

variable "tags" {
  description = "Additional tags for the key."
  type        = map(string)
  default     = {}
}
