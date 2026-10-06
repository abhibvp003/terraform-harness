#!/usr/bin/env bash
#
# Wrapper around the Terraform workflow for this project.
#
#   ./run.sh <command> [env]
#
# env defaults to "dev" and must match a file in envs/<env>.tfvars.
#
# On Windows run this from Git Bash or WSL. There is a run.ps1 alongside it
# for PowerShell.
#
# If terraform is not on your PATH, point at it explicitly:
#   TERRAFORM_BIN=/c/tools/terraform.exe ./run.sh plan dev

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ENVS_DIR="${SCRIPT_DIR}/envs"
readonly DEFAULT_ENV="dev"

TERRAFORM_BIN="${TERRAFORM_BIN:-terraform}"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

if [[ -t 1 ]]; then
  readonly C_RESET=$'\033[0m'
  readonly C_BOLD=$'\033[1m'
  readonly C_RED=$'\033[31m'
  readonly C_GREEN=$'\033[32m'
  readonly C_YELLOW=$'\033[33m'
  readonly C_BLUE=$'\033[34m'
else
  readonly C_RESET='' C_BOLD='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE=''
fi

info()  { printf '%s==>%s %s\n' "${C_BLUE}" "${C_RESET}" "$*"; }
ok()    { printf '%s[ok]%s %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
warn()  { printf '%s[warn]%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
fail()  { printf '%s[error]%s %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: ./run.sh <command> [env]

Commands:
  check             Preflight: tools, credentials, account
  bootstrap-state   Create the S3 state bucket (versioned, encrypted, TLS-only)
  init              Initialise Terraform against the S3 backend
  fmt               Rewrite all .tf files to canonical format
  validate          Check formatting and configuration validity
  plan              Show what would change, saved to tfplan.<env>
  apply             Apply the saved plan (runs plan first, then asks)
  destroy           Tear everything down (asks first)
  kubeconfig        Point kubectl at the cluster
  status            Show nodes and all pods
  output            Print Terraform outputs
  cost              Print the cost breakdown for this setup

Environments:
  Any envs/<name>.tfvars. Defaults to "dev".

Environment variables:
  STATE_BUCKET      required for init, S3 bucket holding state
  STATE_KEY_PREFIX  optional, defaults to "eks"
  STATE_REGION      optional, defaults to AWS_REGION or us-east-1
  STATE_LOCK_TABLE  optional, DynamoDB table for state locking
  TERRAFORM_BIN     optional, path to terraform if not on PATH
  FORCE=1           skip confirmation prompts

First run:
  ./run.sh check
  export STATE_BUCKET=my-tfstate-bucket
  ./run.sh bootstrap-state
  ./run.sh init dev
  ./run.sh apply dev

Daily loop:
  ./run.sh apply dev        start of session
  ./run.sh destroy dev      end of session
EOF
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

require_terraform() {
  if ! command -v "${TERRAFORM_BIN}" >/dev/null 2>&1; then
    fail "terraform not found.

Install it, or set TERRAFORM_BIN to the binary:
  TERRAFORM_BIN=/path/to/terraform.exe ./run.sh $*

Downloads: https://developer.hashicorp.com/terraform/install"
  fi
}

require_aws() {
  command -v aws >/dev/null 2>&1 \
    || fail "aws CLI not found. See https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
}

require_kubectl() {
  command -v kubectl >/dev/null 2>&1 \
    || fail "kubectl not found. See https://kubernetes.io/docs/tasks/tools/"
}

resolve_env() {
  local env="${1:-${DEFAULT_ENV}}"

  # Reject anything that is not a plain name, so the value can never be
  # smuggled into a path or a command.
  if [[ ! "${env}" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    fail "Invalid environment name: '${env}'. Use lowercase letters, digits and hyphens."
  fi

  local file="${ENVS_DIR}/${env}.tfvars"
  if [[ ! -f "${file}" ]]; then
    printf 'No such environment: %s\n\nAvailable:\n' "${env}" >&2
    for f in "${ENVS_DIR}"/*.tfvars; do
      [[ -e "${f}" ]] || continue
      printf '  %s\n' "$(basename "${f}" .tfvars)" >&2
    done
    exit 1
  fi

  printf '%s' "${env}"
}

confirm() {
  local prompt="$1" expected="$2" answer=""

  if [[ "${FORCE:-}" == "1" ]]; then
    warn "FORCE=1 set, skipping confirmation"
    return 0
  fi

  printf '\n%s%s%s\n' "${C_BOLD}" "${prompt}" "${C_RESET}"
  printf 'Type %s%s%s to continue: ' "${C_BOLD}" "${expected}" "${C_RESET}"
  read -r answer

  [[ "${answer}" == "${expected}" ]] || { info "Aborted."; exit 1; }
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_check() {
  local failed=0

  info "Checking tools"
  for tool in "${TERRAFORM_BIN}" aws kubectl; do
    if command -v "${tool}" >/dev/null 2>&1; then
      ok "${tool}"
    else
      warn "${tool} not found"
      [[ "${tool}" == "kubectl" ]] || failed=1
    fi
  done

  info "Checking AWS credentials"
  if ! command -v aws >/dev/null 2>&1; then
    warn "skipped, aws CLI missing"
  elif account="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"; then
    ok "account ${account}"
    local arn
    arn="$(aws sts get-caller-identity --query Arn --output text)"
    ok "identity ${arn}"
    printf '\n  Add this to envs/<env>.tfvars so you can use kubectl:\n'
    printf '    cluster_admin_principal_arns = ["%s"]\n\n' "${arn}"
  else
    warn "no valid AWS credentials. Run: aws configure"
    failed=1
  fi

  [[ "${failed}" -eq 0 ]] || fail "Preflight failed."
  ok "Ready."
}

#   STATE_BUCKET      required, S3 bucket holding state
#   STATE_KEY_PREFIX  optional, defaults to eks
#   STATE_REGION      optional, defaults to AWS_REGION or us-east-1
#   STATE_LOCK_TABLE  optional, DynamoDB table for locking
state_region() {
  printf '%s' "${STATE_REGION:-${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}}"
}

cmd_init() {
  local env="$1"
  require_terraform

  if [[ -z "${STATE_BUCKET:-}" ]]; then
    fail "STATE_BUCKET is not set.

backend.tf declares a partial S3 backend, so init needs to be told where
state lives.

  Create the bucket once:
    STATE_BUCKET=my-tfstate-bucket ./run.sh bootstrap-state

  Then:
    STATE_BUCKET=my-tfstate-bucket ./run.sh init ${env}

To keep state on this machine instead, comment out the terraform block in
backend.tf and re-run. Note that local state holds the cluster CA data in
cleartext."
  fi

  local prefix region key
  prefix="${STATE_KEY_PREFIX:-eks}"
  region="$(state_region)"
  key="${prefix}/${env}/terraform.tfstate"

  info "Initialising '${env}'"
  printf '  bucket: %s\n  key:    %s\n  region: %s\n' "${STATE_BUCKET}" "${key}" "${region}"

  local -a args=(
    -input=false
    -backend-config="bucket=${STATE_BUCKET}"
    -backend-config="key=${key}"
    -backend-config="region=${region}"
    -backend-config="encrypt=true"
  )

  if [[ -n "${STATE_LOCK_TABLE:-}" ]]; then
    printf '  lock:   %s\n' "${STATE_LOCK_TABLE}"
    args+=(-backend-config="dynamodb_table=${STATE_LOCK_TABLE}")
  else
    warn "no STATE_LOCK_TABLE set - concurrent runs could corrupt state"
  fi

  "${TERRAFORM_BIN}" -chdir="${SCRIPT_DIR}" init "${args[@]}"
  ok "Initialised."
}

cmd_bootstrap_state() {
  require_aws

  [[ -n "${STATE_BUCKET:-}" ]] || fail "STATE_BUCKET is not set.

  STATE_BUCKET=my-tfstate-bucket ./run.sh bootstrap-state"

  local region
  region="$(state_region)"

  info "Creating state bucket '${STATE_BUCKET}' in ${region}"

  if aws s3api head-bucket --bucket "${STATE_BUCKET}" 2>/dev/null; then
    ok "Bucket already exists."
  else
    # us-east-1 is the one region that rejects a LocationConstraint.
    if [[ "${region}" == "us-east-1" ]]; then
      aws s3api create-bucket --bucket "${STATE_BUCKET}" --region "${region}"
    else
      aws s3api create-bucket --bucket "${STATE_BUCKET}" --region "${region}" \
        --create-bucket-configuration "LocationConstraint=${region}"
    fi
    ok "Bucket created."
  fi

  info "Enabling versioning"
  # Without versioning, a corrupt apply can leave no way back to a good state.
  aws s3api put-bucket-versioning \
    --bucket "${STATE_BUCKET}" \
    --versioning-configuration Status=Enabled
  ok "Versioning on."

  info "Enabling default encryption"
  aws s3api put-bucket-encryption \
    --bucket "${STATE_BUCKET}" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
  ok "Encryption on."

  info "Blocking public access"
  aws s3api put-public-access-block \
    --bucket "${STATE_BUCKET}" \
    --public-access-block-configuration \
    'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
  ok "Public access blocked."

  info "Denying non-TLS requests"
  aws s3api put-bucket-policy \
    --bucket "${STATE_BUCKET}" \
    --policy "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${STATE_BUCKET}",
        "arn:aws:s3:::${STATE_BUCKET}/*"
      ],
      "Condition": {
        "Bool": { "aws:SecureTransport": "false" }
      }
    }
  ]
}
EOF
)"
  ok "TLS-only policy applied."

  if [[ -n "${STATE_LOCK_TABLE:-}" ]]; then
    info "Creating lock table '${STATE_LOCK_TABLE}'"
    if aws dynamodb describe-table --table-name "${STATE_LOCK_TABLE}" --region "${region}" >/dev/null 2>&1; then
      ok "Table already exists."
    else
      aws dynamodb create-table \
        --table-name "${STATE_LOCK_TABLE}" \
        --region "${region}" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --sse-specification Enabled=true >/dev/null
      ok "Table created (on-demand billing, pennies per month)."
    fi
  else
    warn "STATE_LOCK_TABLE not set, skipping the lock table.

  Recommended if more than one person or pipeline runs terraform:
    STATE_BUCKET=${STATE_BUCKET} STATE_LOCK_TABLE=tfstate-locks ./run.sh bootstrap-state"
  fi

  cat <<EOF

${C_BOLD}Done.${C_RESET} Put these in your shell profile so you do not retype them:

  export STATE_BUCKET="${STATE_BUCKET}"
  export STATE_KEY_PREFIX="${STATE_KEY_PREFIX:-eks}"
  export STATE_REGION="${region}"
${STATE_LOCK_TABLE:+  export STATE_LOCK_TABLE=\"${STATE_LOCK_TABLE}\"}

Then: ./run.sh init dev

EOF
}

cmd_fmt() {
  require_terraform
  info "Formatting"
  "${TERRAFORM_BIN}" -chdir="${SCRIPT_DIR}" fmt -recursive
  ok "Formatted."
}

cmd_validate() {
  require_terraform
  info "Checking formatting"
  "${TERRAFORM_BIN}" -chdir="${SCRIPT_DIR}" fmt -recursive -check \
    || fail "Formatting issues. Run: ./run.sh fmt"
  ok "Formatting clean."

  info "Validating configuration"
  "${TERRAFORM_BIN}" -chdir="${SCRIPT_DIR}" validate
  ok "Configuration valid."
}

cmd_plan() {
  local env="$1"
  require_terraform

  info "Planning '${env}'"
  "${TERRAFORM_BIN}" -chdir="${SCRIPT_DIR}" plan \
    -input=false \
    -var-file="envs/${env}.tfvars" \
    -out="tfplan.${env}"

  ok "Plan saved to tfplan.${env}"
}

cmd_apply() {
  local env="$1"
  require_terraform

  cmd_plan "${env}"

  cat <<EOF

${C_BOLD}This creates billable AWS resources.${C_RESET}

  EKS control plane   ~0.10/hour  (~73/month) - no free tier
  Worker node(s)      ~0.04/hour  per t3.medium

  Roughly 0.15/hour, about 109/month if left running.

  Tear it down when you are done: ./run.sh destroy ${env}
EOF

  confirm "Apply the plan above to environment '${env}'?" "yes"

  info "Applying '${env}' (10-15 minutes)"
  "${TERRAFORM_BIN}" -chdir="${SCRIPT_DIR}" apply -input=false "tfplan.${env}"

  rm -f "${SCRIPT_DIR}/tfplan.${env}"
  ok "Applied."

  printf '\nNext:\n'
  printf '  ./run.sh kubeconfig %s\n' "${env}"
  printf '  ./run.sh status %s\n\n' "${env}"
}

cmd_destroy() {
  local env="$1"
  require_terraform

  info "Planning destroy for '${env}'"
  "${TERRAFORM_BIN}" -chdir="${SCRIPT_DIR}" plan -destroy \
    -input=false \
    -var-file="envs/${env}.tfvars"

  confirm "Destroy EVERYTHING in '${env}'? This cannot be undone." "destroy ${env}"

  info "Destroying '${env}'"
  "${TERRAFORM_BIN}" -chdir="${SCRIPT_DIR}" destroy \
    -input=false \
    -auto-approve \
    -var-file="envs/${env}.tfvars"

  ok "Destroyed. Billing has stopped."
}

cmd_kubeconfig() {
  local env="$1"
  require_terraform
  require_aws

  local cluster region
  cluster="$("${TERRAFORM_BIN}" -chdir="${SCRIPT_DIR}" output -raw cluster_name 2>/dev/null)" \
    || fail "No cluster in state. Run: ./run.sh apply ${env}"
  region="$("${TERRAFORM_BIN}" -chdir="${SCRIPT_DIR}" output -raw region 2>/dev/null || printf 'us-east-1')"

  info "Writing kubeconfig for ${cluster}"
  aws eks update-kubeconfig --region "${region}" --name "${cluster}"
  ok "kubectl now targets ${cluster}"

  cat <<'EOF'

If kubectl times out, the API endpoint is private (the default). Either:
  - run kubectl from inside the VPC, or
  - set cluster_endpoint_public_access = true plus
    cluster_endpoint_public_access_cidrs = ["YOUR.IP/32"] and re-apply
EOF
}

cmd_status() {
  require_kubectl
  info "Nodes"
  kubectl get nodes -o wide
  printf '\n'
  info "Pods"
  kubectl get pods --all-namespaces
}

cmd_output() {
  require_terraform
  "${TERRAFORM_BIN}" -chdir="${SCRIPT_DIR}" output
}

cmd_cost() {
  cat <<'EOF'
Monthly cost, us-east-1, running 24/7 with envs/dev.tfvars
----------------------------------------------------------

  EKS control plane            73.00    no free tier, unavoidable
  1 x t3.medium on-demand      30.37    free tier covers t3.micro only
  1 x public IPv4               3.65    replaces a ~33/month NAT gateway
  30 GB gp3 root volume         2.40    free tier covers 30 GB for 12 months
  CloudWatch logs (audit)       ~0.50   within the 5 GB free tier
                             --------
  TOTAL                       ~109/month
  HOURLY                        ~0.15

Already switched off in envs/dev.tfvars
---------------------------------------

  NAT gateway        -33.00/month   nodes use public subnets instead
  VPC endpoints     -146.00/month   10 endpoints x 2 AZs x 0.01/hour
  VPC flow logs        -0.50/GB     nothing depends on them
  3 KMS CMKs          -3.00/month   AWS-managed keys still encrypt at rest

What is NOT in the AWS free tier
--------------------------------

  The EKS control plane has no free tier at any usage level. Two thirds of
  the bill above is the control plane, and no configuration change reduces it.

  The free tier EC2 allowance is 750 hours/month of t3.micro. A t3.micro
  caps at 4 pods and cannot fit kube-system, so it will not run a cluster.

The only real lever
-------------------

  Destroy between sessions. At ~0.15/hour:

    3 hour session      ~0.45
    8 hour day          ~1.20
    left running 1 week ~25.00

    ./run.sh apply dev      before you start
    ./run.sh destroy dev    when you finish

  Set a billing alarm as well:
    https://console.aws.amazon.com/billing/home#/budgets
EOF
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

main() {
  local command="${1:-}"
  [[ -n "${command}" ]] || { usage; exit 1; }
  shift || true

  case "${command}" in
    check)           cmd_check ;;
    fmt)             cmd_fmt ;;
    validate)        cmd_validate ;;
    cost)            cmd_cost ;;
    output)          cmd_output ;;
    status)          cmd_status ;;
    bootstrap-state) cmd_bootstrap_state ;;
    init)       cmd_init "$(resolve_env "${1:-}")" ;;
    plan)       cmd_plan "$(resolve_env "${1:-}")" ;;
    apply)      cmd_apply "$(resolve_env "${1:-}")" ;;
    destroy)    cmd_destroy "$(resolve_env "${1:-}")" ;;
    kubeconfig) cmd_kubeconfig "$(resolve_env "${1:-}")" ;;
    -h|--help|help) usage ;;
    *)          printf 'Unknown command: %s\n\n' "${command}" >&2; usage; exit 1 ;;
  esac
}

main "$@"
