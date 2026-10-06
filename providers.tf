provider "aws" {
  region = var.region

  # Guard-rail: refuse to run against an unexpected account.
  allowed_account_ids = var.allowed_account_ids

  default_tags {
    tags = local.tags
  }
}
