data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name         = "${var.project}-${var.environment}"
  cluster_name = "${local.name}-eks"

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      Cluster     = "${var.project}-${var.environment}-eks"
      ManagedBy   = "terraform"
    },
    var.tags,
  )

  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /20 per AZ for nodes+pods (4091 usable IPs), /24 per AZ for load balancers.
  # Offset the public blocks far enough that growing az_count never overlaps.
  private_subnet_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnet_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 192 + i)]

  # The autoscaling service-linked role must be able to use the EBS key,
  # otherwise node groups fail to launch instances with encrypted volumes.
  autoscaling_slr_arn = "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
}
