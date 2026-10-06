###############################################################################
# Root module.
#
# Composition order:
#
#   kms (logs)  ->  vpc  ->  security-groups  ->  vpc-endpoints
#   iam         ->  kms (secrets, ebs)        ->  eks
#   eks         ->  irsa  ->  node-groups  ->  addons
#
# Every module lives in ./modules and takes only the inputs it needs, so each
# one can be read, reviewed and reused on its own.
###############################################################################

###############################################################################
# Encryption keys
#
# One key per purpose. A compromised log-reader cannot touch etcd secrets, and
# key rotation or deletion is scoped to a single concern.
###############################################################################

module "kms_logs" {
  source = "./modules/kms"
  count  = var.use_customer_managed_keys ? 1 : 0

  name        = "${local.name}-logs"
  description = "Encrypts CloudWatch log groups for ${local.name} (control plane and VPC flow logs)"

  service_principals = [{
    sid       = "AllowCloudWatchLogs"
    principal = "logs.${var.region}.amazonaws.com"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    # Restricts the service to log groups in this account and region.
    conditions = [{
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:*"]
    }]
  }]

  tags = { Purpose = "cloudwatch-logs" }
}

module "kms_eks_secrets" {
  source = "./modules/kms"
  count  = var.use_customer_managed_keys ? 1 : 0

  name        = "${local.name}-eks-secrets"
  description = "Envelope encryption key for Kubernetes secrets in etcd for ${local.cluster_name}"

  # The control plane role creates grants against this key when it encrypts
  # and decrypts secrets.
  key_user_arns = [module.iam.cluster_role_arn]

  tags = { Purpose = "eks-secrets-envelope-encryption" }
}

module "kms_ebs" {
  source = "./modules/kms"
  count  = var.use_customer_managed_keys ? 1 : 0

  name        = "${local.name}-ebs"
  description = "Encrypts worker node root volumes and EBS-backed persistent volumes for ${local.cluster_name}"

  key_user_arns = [
    module.iam.node_role_arn,
    # Autoscaling launches the instances, so its service-linked role must be
    # able to use the key. Without this, node groups fail with a cryptic
    # "client error on launch" and no instances appear.
    local.autoscaling_slr_arn,
  ]

  tags = { Purpose = "ebs-volume-encryption" }
}

###############################################################################
# Network
###############################################################################

module "vpc" {
  source = "./modules/vpc"

  name       = local.name
  cidr_block = var.vpc_cidr

  azs                  = local.azs
  private_subnet_cidrs = local.private_subnet_cidrs
  public_subnet_cidrs  = local.public_subnet_cidrs

  cluster_name       = local.cluster_name
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  enable_flow_logs        = var.enable_flow_logs
  flow_log_retention_days = var.flow_log_retention_days
  kms_key_arn             = local.kms_logs_key_arn
}

module "security_groups" {
  source = "./modules/security-groups"

  name           = local.name
  vpc_id         = module.vpc.vpc_id
  vpc_cidr_block = module.vpc.vpc_cidr_block

  cluster_api_allowed_cidrs = var.cluster_api_allowed_cidrs
}

module "vpc_endpoints" {
  source = "./modules/vpc-endpoints"
  count  = var.enable_vpc_endpoints ? 1 : 0

  name   = local.name
  vpc_id = module.vpc.vpc_id
  region = var.region

  subnet_ids      = module.vpc.private_subnet_ids
  route_table_ids = module.vpc.private_route_table_ids
  vpc_cidr_block  = module.vpc.vpc_cidr_block

  allowed_security_group_ids = [module.security_groups.node_security_group_id]
}

###############################################################################
# IAM
###############################################################################

module "iam" {
  source = "./modules/iam"

  name = local.name
}

###############################################################################
# Control plane
###############################################################################

module "eks" {
  source = "./modules/eks"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version
  cluster_role_arn   = module.iam.cluster_role_arn

  # Control plane ENIs sit in the private subnets.
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.security_groups.cluster_security_group_id]

  endpoint_private_access = true
  endpoint_public_access  = var.cluster_endpoint_public_access
  public_access_cidrs     = var.cluster_endpoint_public_access_cidrs

  secrets_kms_key_arn = local.kms_eks_secrets_key_arn

  log_types          = var.cluster_log_types
  log_retention_days = var.cluster_log_retention_days
  log_kms_key_arn    = local.kms_logs_key_arn

  service_ipv4_cidr = var.service_ipv4_cidr

  admin_principal_arns = var.cluster_admin_principal_arns
}

###############################################################################
# IRSA roles
#
# The CNI and the EBS CSI driver get their own roles instead of inheriting the
# node instance role. That keeps ENI management and volume encryption out of
# reach of every other pod on the node.
###############################################################################

locals {
  # one() turns a 0-or-1 element list into the element or null, which is the
  # safe way to read an output from a module that may have count = 0.
  kms_logs_key_arn        = one(module.kms_logs[*].key_arn)
  kms_eks_secrets_key_arn = one(module.kms_eks_secrets[*].key_arn)
  kms_ebs_key_arn         = one(module.kms_ebs[*].key_arn)

  # Nodes go wherever they can reach ECR from.
  node_subnet_ids = (
    var.place_nodes_in_public_subnets
    ? module.vpc.public_subnet_ids
    : module.vpc.private_subnet_ids
  )
}

# Hard stop on a combination that produces a cluster whose nodes can never
# register. Cheaper to catch at plan time than after a 15 minute apply.
resource "terraform_data" "preflight" {
  input = local.cluster_name

  lifecycle {
    precondition {
      condition = (
        var.enable_nat_gateway
        || var.place_nodes_in_public_subnets
        || var.enable_vpc_endpoints
      )
      error_message = <<-EOT
        Nodes would have no route to ECR and would never join the cluster.

        Pick one:
          enable_nat_gateway            = true   (~33 USD/month)
          place_nodes_in_public_subnets = true   (~3.60 USD/month per node)
          enable_vpc_endpoints          = true   (billed per endpoint per AZ)
      EOT
    }

    precondition {
      condition = (
        !var.place_nodes_in_public_subnets
        || var.az_count >= 2
      )
      error_message = "EKS needs subnets in at least two availability zones."
    }
  }
}

locals {
  # Both branches are strings, so the conditional has a single consistent type.
  #
  # With one replica there is no point in a PodDisruptionBudget or a spread
  # constraint, and a PDB would actively block node drains on a single-node
  # cluster.
  coredns_configuration_values = var.coredns_replica_count > 1 ? jsonencode({
    replicaCount = var.coredns_replica_count

    podDisruptionBudget = {
      enabled        = true
      maxUnavailable = 1
    }

    # Spread replicas across AZs so losing one zone does not take cluster DNS
    # with it.
    topologySpreadConstraints = [{
      maxSkew           = 1
      topologyKey       = "topology.kubernetes.io/zone"
      whenUnsatisfiable = "ScheduleAnyway"
      labelSelector = {
        matchLabels = {
          "k8s-app" = "kube-dns"
        }
      }
    }]
    }) : jsonencode({
    replicaCount = var.coredns_replica_count
  })
}

# Only needed when there is a CMK to grant against. With the AWS-managed
# aws/ebs key, AmazonEBSCSIDriverPolicy already covers it.
data "aws_iam_policy_document" "ebs_csi_kms" {
  count = var.use_customer_managed_keys ? 1 : 0

  statement {
    sid    = "AllowGrantsForEbsEncryption"
    effect = "Allow"

    actions = [
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
    ]

    resources = [local.kms_ebs_key_arn]

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  statement {
    sid    = "AllowEbsVolumeEncryption"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = [local.kms_ebs_key_arn]
  }
}

module "irsa" {
  source = "./modules/irsa"

  name_prefix       = local.name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  roles = merge(
    {
      vpc-cni = {
        namespace       = "kube-system"
        service_account = "aws-node"
        description     = "Amazon VPC CNI - manages ENIs and pod IP addresses"
        policy_arns     = ["arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"]
        inline_policy   = null
      }

      ebs-csi = {
        namespace       = "kube-system"
        service_account = "ebs-csi-controller-sa"
        description     = "EBS CSI driver - provisions and attaches encrypted persistent volumes"
        policy_arns     = ["arn:${local.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
        inline_policy   = one(data.aws_iam_policy_document.ebs_csi_kms[*].json)
      }
    },
    var.additional_irsa_roles,
  )
}

###############################################################################
# Data plane
###############################################################################

module "node_groups" {
  source = "./modules/node-groups"

  cluster_name    = module.eks.cluster_name
  cluster_version = module.eks.cluster_version
  name_prefix     = local.name

  subnet_ids    = local.node_subnet_ids
  node_role_arn = module.iam.node_role_arn

  security_group_ids  = [module.security_groups.node_security_group_id]
  ebs_kms_key_arn     = local.kms_ebs_key_arn
  associate_public_ip = var.place_nodes_in_public_subnets

  node_groups = var.node_groups

  depends_on = [
    # Nodes must not launch before their role actually carries the policies,
    # or the kubelet fails to register.
    module.iam,
    # Bring the private AWS service paths up first so the first boot pulls
    # images over the endpoints rather than NAT.
    module.vpc_endpoints,
    # Fail the plan on an unroutable configuration before anything is built.
    terraform_data.preflight,
  ]
}

###############################################################################
# Addons
###############################################################################

module "addons" {
  source = "./modules/addons"

  cluster_name = module.eks.cluster_name

  addons = {
    "vpc-cni" = {
      version                  = lookup(var.addon_versions, "vpc-cni", null)
      service_account_role_arn = module.irsa.role_arns["vpc-cni"]

      # Prefix delegation hands each ENI a /28 instead of individual IPs,
      # which raises pod density per node by roughly an order of magnitude.
      # The /20 private subnets are sized for this. Requires Nitro instances.
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })

      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      preserve                    = true
    }

    "kube-proxy" = {
      version                     = lookup(var.addon_versions, "kube-proxy", null)
      service_account_role_arn    = null
      configuration_values        = null
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      preserve                    = true
    }

    "coredns" = {
      version                  = lookup(var.addon_versions, "coredns", null)
      service_account_role_arn = null
      configuration_values     = local.coredns_configuration_values

      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      preserve                    = true
    }

    "aws-ebs-csi-driver" = {
      version                     = lookup(var.addon_versions, "aws-ebs-csi-driver", null)
      service_account_role_arn    = module.irsa.role_arns["ebs-csi"]
      configuration_values        = null
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      preserve                    = true
    }

    # Lets workloads use EKS Pod Identity, the newer alternative to IRSA.
    "eks-pod-identity-agent" = {
      version                     = lookup(var.addon_versions, "eks-pod-identity-agent", null)
      service_account_role_arn    = null
      configuration_values        = null
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      preserve                    = true
    }
  }

  # CoreDNS and the CSI controller are Deployments. They stay Pending until
  # there is somewhere to schedule them.
  depends_on = [module.node_groups]
}
