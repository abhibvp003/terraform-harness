# EKS Platform — Terraform

Provisions a production-shaped Amazon EKS cluster and everything it depends on.
Each concern lives in its own module under `modules/`, and the root module wires
them together.

---

## Layout

```
.
├── main.tf                  # composition root — wires all modules together
├── variables.tf             # every knob, with validation
├── locals.tf                # naming, AZ selection, subnet CIDR math
├── outputs.tf               # cluster, network, IAM and addon outputs
├── providers.tf             # provider config + default_tags + account guard
├── versions.tf              # terraform and provider version constraints
├── backend.tf               # S3 remote state (commented, needs bucket first)
├── terraform.tfvars.example # copy and fill, or use envs/
│
├── envs/
│   ├── dev.tfvars           # small, single NAT, spot node group
│   └── prod.tfvars          # multi-AZ NAT, pinned addons, long retention
│
└── modules/
    ├── kms/                 # reusable customer-managed key + key policy
    ├── vpc/                 # VPC, subnets, NAT, routing, flow logs
    ├── vpc-endpoints/       # interface + gateway endpoints for AWS APIs
    ├── security-groups/     # control plane and worker node security groups
    ├── iam/                 # cluster role, node role, instance profile
    ├── eks/                 # control plane, OIDC provider, access entries
    ├── irsa/                # IAM roles assumable by service accounts
    ├── node-groups/         # managed node groups + launch templates
    └── addons/              # vpc-cni, coredns, kube-proxy, EBS CSI, pod identity
```

Every module follows the same four-file shape: `main.tf`, `variables.tf`,
`outputs.tf`, `versions.tf`.

---

## What gets created

| Module | Resources |
|---|---|
| `kms` | Three CMKs — control plane secrets, CloudWatch log groups, EBS volumes. Rotation on, scoped key policies. |
| `vpc` | VPC, one public + one private subnet per AZ, internet gateway, NAT gateways, per-AZ private route tables, VPC flow logs. Default security group stripped of all rules. |
| `vpc-endpoints` | Interface endpoints for ECR, EC2, STS, CloudWatch Logs, ELB, autoscaling, KMS, EKS, plus the S3 gateway endpoint. |
| `security-groups` | Control plane SG and node SG with only the ports EKS actually needs. |
| `iam` | Cluster role, node role (worker + ECR pull-only + SSM), node instance profile. |
| `eks` | Cluster with private endpoint, etcd secret encryption, all five log streams, IAM OIDC provider, access entries. |
| `irsa` | Roles for the VPC CNI and EBS CSI driver, trust pinned to one service account each. Extend via `additional_irsa_roles`. |
| `node-groups` | One managed node group and launch template per entry in `node_groups`. |
| `addons` | `vpc-cni`, `coredns`, `kube-proxy`, `aws-ebs-csi-driver`, `eks-pod-identity-agent`. |

---

## Module dependency order

```
kms_logs ─────────────► vpc ──► security-groups ──► vpc-endpoints
                                        │                   │
iam ──► kms_eks_secrets ────► eks ◄──────┘                  │
    └─► kms_ebs                │                            │
                               ▼                            │
                             irsa ──► node-groups ◄─────────┘
                                            │
                                            ▼
                                         addons
```

`node-groups` waits on `iam` so nodes never launch before their role carries
its policies, and on `vpc-endpoints` so the first image pull takes the private
path. `addons` waits on `node-groups` because CoreDNS and the CSI controller
are Deployments that need somewhere to schedule.

---

## Getting started

Requires Terraform >= 1.5 and credentials for the target account.

```bash
terraform init
terraform plan  -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
```

Then point `kubectl` at the cluster:

```bash
aws eks update-kubeconfig --region us-east-1 --name platform-dev-eks
```

The exact command is also an output:

```bash
terraform output -raw update_kubeconfig_command
```

### Before the first real apply

1. **Set `allowed_account_ids`** in your tfvars. Without it, nothing stops a
   plan from being applied to the wrong account.
2. **Set `cluster_admin_principal_arns`.** The cluster is created with
   `bootstrap_cluster_creator_admin_permissions = false`, so the identity
   running `apply` does *not* become a cluster admin. If you leave this empty,
   nobody can run `kubectl` against the cluster.
3. **Create the state bucket and uncomment `backend.tf`.** EKS state contains
   CA data and OIDC config; it does not belong on a laptop.
4. **Decide how you reach the API server.** `cluster_endpoint_public_access` is
   `false`, so the endpoint is VPC-only. Use a bastion, VPN, or an SSM
   port-forward, and list the source range in `cluster_api_allowed_cidrs`.

---

## Security defaults

These are deliberate. Changing them should be a conscious decision.

| Default | Why |
|---|---|
| API endpoint private only | The Kubernetes API is an administrative control plane, not a public service. Enabling public access requires explicit CIDRs — `0.0.0.0/0` is rejected by a variable validation. |
| etcd secrets encrypted with a CMK | Envelope encryption on top of the EKS-managed layer, with a key you control and can revoke. |
| Separate CMK per purpose | A key compromise is scoped to one concern. Keys rotate annually. |
| No port 22 or 3389 anywhere | The node role carries `AmazonSSMManagedInstanceCore`, so shell access goes through Session Manager. The `node_extra_ingress_rules` variable rejects both ports. |
| IMDSv2 required, hop limit 1 | A pod cannot read the node's IAM credentials. Host-network pods such as `aws-node` are unaffected. |
| Node root volumes encrypted | CMK-encrypted `gp3`, `delete_on_termination = true`. |
| CNI and CSI use IRSA, not the node role | `AmazonEKS_CNI_Policy` is bound to the `aws-node` service account instead of every pod on the node. IRSA trust policies pin both `:aud` and the exact `:sub`; wildcards are rejected. |
| Nodes in private subnets, no public IPs | Egress through NAT, or through VPC endpoints where available. |
| `audit` and `authenticator` logs cannot be disabled | They are the record of who did what. A variable validation enforces this. |
| All log groups CMK-encrypted with finite retention | An implicitly created EKS log group defaults to never-expire and no encryption. |
| Default VPC security group stripped | CIS 4.3. Nothing should ever attach to it. |
| Cluster creator is not an admin | Access is granted explicitly through access entries, reviewable in a merge request. |

---

## Common changes

### Add a node group

```hcl
node_groups = {
  general = {
    instance_types = ["m6i.large"]
    desired_size   = 3
    min_size       = 3
    max_size       = 9
  }

  memory = {
    instance_types = ["r6i.xlarge"]
    desired_size   = 2
    min_size       = 2
    max_size       = 6
    labels         = { workload = "memory-bound" }
    taints = [{
      key    = "workload"
      value  = "memory-bound"
      effect = "NO_SCHEDULE"
    }]
  }
}
```

### Add an IRSA role for your own workload

```hcl
additional_irsa_roles = {
  order-service = {
    namespace       = "orders"
    service_account = "order-service"
    policy_arns     = ["arn:aws:iam::111122223333:policy/order-service-dynamodb"]
  }
}
```

Then annotate the service account:

```bash
terraform output irsa_service_account_annotations
```

### Pin addon versions

Read the versions after the first apply and copy them into `addon_versions`:

```bash
terraform output addon_versions
```

```hcl
addon_versions = {
  "vpc-cni"            = "v1.19.0-eksbuild.1"
  "coredns"            = "v1.11.3-eksbuild.1"
  "aws-ebs-csi-driver" = "v1.37.0-eksbuild.1"
}
```

### Upgrade the Kubernetes version

Bump `kubernetes_version`, apply, and the control plane upgrades first. Node
groups follow in the same apply, replacing at most
`max_unavailable_percentage` nodes at a time. Upgrade one minor version at a
time, and check addon compatibility before you start.

---

## Things worth knowing

**Prefix delegation is on.** The `vpc-cni` addon runs with
`ENABLE_PREFIX_DELEGATION = "true"`, which assigns each ENI a `/28` instead of
individual IPs and raises pod density per node by roughly an order of
magnitude. The `/20` private subnets are sized for it. It requires Nitro
instances — the default `m6i` family qualifies. If you move to an older
instance family, turn this off in `main.tf`.

**Subnet sizing.** From a `/16`, each AZ gets a `/20` private subnet (4091
usable IPs for nodes and pods) and a `/24` public subnet for load balancers.
The public blocks start at offset 192 so growing `az_count` never collides with
the private range.

**Terraform owns `desired_size`.** If you add Cluster Autoscaler or Karpenter
later, uncomment the `ignore_changes` block in
`modules/node-groups/main.tf` so Terraform stops fighting the autoscaler over
the replica count.

**`single_nat_gateway` saves money, not availability.** It is fine in dev. In
prod it means one AZ's failure removes egress for the whole cluster.

**Node egress is open by default.** `node_egress_cidrs` defaults to
`0.0.0.0/0` because nodes pull images and reach AWS APIs through NAT. Once
every dependency is served by a VPC endpoint, narrow it to the VPC CIDR.

---

## Validation

```bash
terraform fmt -recursive -check
terraform validate
```

For security scanning of the generated plan, `checkov` and `tfsec` both read
Terraform directly:

```bash
checkov -d . --framework terraform
```

## Verified state of this configuration

- `terraform fmt -recursive` — clean
- `terraform init -backend=false` — succeeds (aws 5.100.0, tls 4.4.1)
- `terraform validate` — passes
- `terraform plan -var-file=envs/dev.tfvars` — reaches AWS credential
  validation, meaning all variable validations and type constraints pass.
  A full plan was **not** run against a live account, so no claim is made here
  about apply-time behaviour of the AWS API.
