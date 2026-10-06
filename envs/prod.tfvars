###############################################################################
# Production environment
#
#   terraform plan  -var-file=envs/prod.tfvars
#   terraform apply -var-file=envs/prod.tfvars
#
# Use a separate state key (or workspace) per environment so a prod apply can
# never be driven by a dev plan.
#
# -----------------------------------------------------------------------------
# READ THIS FIRST
#
# This file is set to one t3.medium node to match the cost-optimised profile.
# That is NOT a production-grade data plane:
#
#   - One node means no availability. Losing it takes the whole workload down,
#     and there is nowhere for pods to reschedule.
#   - One CoreDNS replica means cluster DNS dies with that node.
#   - t3 instances are burstable. Once CPU credits are exhausted the node is
#     throttled to its baseline (20% of 2 vCPU for t3.medium), which shows up
#     as latency nobody can explain.
#
# For anything carrying real traffic, raise these three together:
#
#   node_groups.general.desired_size = 3   (min 3, max 6+)
#   coredns_replica_count            = 2
#   instance_types                   = ["m6i.large"]   # non-burstable
#   single_nat_gateway               = false           # already set below
# -----------------------------------------------------------------------------
###############################################################################

project     = "platform"
environment = "prod"
region      = "us-east-1"

# Strongly recommended in prod.
# allowed_account_ids = ["444455556666"]

###############################################################################
# Network
###############################################################################

vpc_cidr = "10.30.0.0/16"
az_count = 3

# One NAT gateway per AZ. A zonal failure must not break egress for the
# surviving zones. Worth the cost even on a small cluster.
single_nat_gateway = false

enable_flow_logs        = true
flow_log_retention_days = 365

# Interface endpoints are billed per endpoint per AZ. Keep them on in prod:
# they keep ECR, STS and CloudWatch traffic off the internet path, which is
# usually a compliance requirement rather than a cost decision.
enable_vpc_endpoints = true

###############################################################################
# Cluster
###############################################################################

kubernetes_version = "1.31"

cluster_endpoint_public_access = false

# cluster_api_allowed_cidrs = ["10.0.0.0/8"]

cluster_log_retention_days = 365

# 1 because the node group below is a single node. Raise to 2 the moment you
# add a second node.
coredns_replica_count = 1

# cluster_admin_principal_arns = [
#   "arn:aws:iam::444455556666:role/platform-sre",
# ]

# Pin addon versions in prod so an upgrade is a reviewable diff.
# Read the current values from the addon_versions output after the first apply.
# addon_versions = {
#   "vpc-cni"                = "v1.19.0-eksbuild.1"
#   "coredns"                = "v1.11.3-eksbuild.1"
#   "kube-proxy"             = "v1.31.2-eksbuild.3"
#   "aws-ebs-csi-driver"     = "v1.37.0-eksbuild.1"
#   "eks-pod-identity-agent" = "v1.3.4-eksbuild.1"
# }

###############################################################################
# Node group
###############################################################################

node_groups = {
  general = {
    instance_types = ["t3.medium"]
    capacity_type  = "ON_DEMAND"

    desired_size = 1
    min_size     = 1
    max_size     = 2

    disk_size_gb = 50

    # With one node this has no effect - EKS always takes at least one node
    # out to replace it. It starts mattering at three or more.
    max_unavailable_percentage = 25

    labels = {
      workload = "general"
    }
  }
}
