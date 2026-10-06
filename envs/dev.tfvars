###############################################################################
# Learning environment - absolute minimum cost
#
#   ./run.sh apply dev
#
# Rough monthly cost if left running 24/7 in us-east-1:
#
#   EKS control plane            73.00   unavoidable, no free tier
#   1 x t3.medium on-demand      30.37   free tier only covers t3.micro
#   1 x public IPv4 (node)        3.65   replaces a ~33/month NAT gateway
#   30 GB gp3 root                2.40   covered by free tier for 12 months
#   -------------------------------------
#   TOTAL                      ~109/month
#
#   Hourly:                      ~0.15   a 3 hour session is about 45 cents
#
# The control plane is two thirds of that and cannot be reduced. Destroying
# the cluster between sessions is the only real lever:
#
#   ./run.sh destroy dev
#
# What is switched off here and why it is safe:
#
#   NAT gateway     ~33/month. Nodes sit in public subnets with a public IP
#                   instead and reach ECR through the internet gateway. No
#                   inbound rules are opened.
#   Flow logs       0.50/GB into CloudWatch, 5 GB/month free and easily
#                   exceeded. Nothing in the cluster depends on them.
#   VPC endpoints   Billed per endpoint per AZ. Ten endpoints across two AZs
#                   costs several times the NAT gateway they replace.
#   KMS CMKs        1/month each. AWS-managed keys still encrypt everything
#                   at rest; you just do not control the key.
###############################################################################

project     = "learn"
environment = "dev"
region      = "us-east-1"

# Fill this in. It is the cheapest insurance against applying to the wrong
# account by accident.
# allowed_account_ids = ["111122223333"]

###############################################################################
# Network - no NAT gateway
###############################################################################

vpc_cidr = "10.20.0.0/16"

# Two is the minimum EKS accepts.
az_count = 2

# The big saving. Nodes go in public subnets instead, see below.
enable_nat_gateway = false

# Nodes get a public IPv4 (~3.65/month) rather than routing through NAT
# (~33/month). They are internet-addressable, guarded only by their security
# group, which opens nothing inbound from outside the cluster and has no SSH
# port. Fine for learning. Do not do this with real data.
place_nodes_in_public_subnets = true

# Pure forensics. Off.
enable_flow_logs = false

# Per endpoint, per AZ, per hour. Far more expensive than the NAT gateway.
enable_vpc_endpoints = false

###############################################################################
# Cluster
###############################################################################

kubernetes_version = "1.31"

# AWS-managed keys instead of three customer-managed CMKs. Saves 3/month.
#
# Careful: etcd envelope encryption cannot be toggled after creation. Flipping
# this to true later replaces the whole cluster.
use_customer_managed_keys = false

# Nodes are in public subnets but the API endpoint does not have to be. Keep
# it private and reach it with "./run.sh kubeconfig dev" from inside the VPC,
# or flip this to true and lock it to your own IP.
cluster_endpoint_public_access = false

# If you turn public access on, put your own address here. /0 is rejected.
# cluster_endpoint_public_access_cidrs = ["203.0.113.4/32"]

# Only the logs needed to see what is happening, to stay inside the 5 GB free
# CloudWatch tier. "api" and "controllerManager" are the chatty ones.
# "audit" and "authenticator" are mandatory and cannot be removed.
cluster_log_types          = ["audit", "authenticator"]
cluster_log_retention_days = 7

# One node, so one replica. Two would bring a PodDisruptionBudget that blocks
# draining the only node during an upgrade.
coredns_replica_count = 1

# Without this nobody can run kubectl - the cluster is created with
# bootstrap_cluster_creator_admin_permissions = false on purpose.
# Find your ARN with: aws sts get-caller-identity --query Arn --output text
# cluster_admin_principal_arns = [
#   "arn:aws:iam::111122223333:role/your-role",
# ]

###############################################################################
# Node group - one t3.medium
#
# t3.medium is the practical floor: 2 vCPU, 4 GiB. kube-system alone
# (CoreDNS, kube-proxy, aws-node, EBS CSI, pod identity agent) wants about
# 0.5 vCPU and 400 MiB.
#
# t3.small (2 GiB) technically boots but leaves almost nothing for workloads.
# t3.micro, the only free tier size, caps at 4 pods and cannot fit kube-system.
#
# t3 is burstable. Sustained CPU drains the credit balance and the node drops
# to 20% baseline, which looks like random slowness. Fine for learning.
#
# max_size 2 lets a version upgrade roll instead of going fully offline.
# Steady state is one node, so it does not change the bill.
###############################################################################

node_groups = {
  general = {
    instance_types = ["t3.medium"]
    capacity_type  = "ON_DEMAND"

    desired_size = 1
    min_size     = 1
    max_size     = 2

    disk_size_gb = 30

    labels = {
      workload = "general"
    }
  }
}
