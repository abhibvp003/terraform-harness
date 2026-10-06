###############################################################################
# Remote state.
#
# This is a PARTIAL backend configuration: the block is declared here, but the
# bucket, key and region are supplied at init time. That lets one checkout
# serve several environments without editing tracked files.
#
#   CI (.harness pipeline):
#     terraform init \
#       -backend-config="bucket=${STATE_BUCKET}" \
#       -backend-config="key=eks/${TF_ENV}/terraform.tfstate" \
#       -backend-config="region=${STATE_REGION}"
#
#   Locally, run.sh does the same thing for you:
#     STATE_BUCKET=my-tfstate-bucket ./run.sh init dev
#
# Create the bucket once before the first init:
#     STATE_BUCKET=my-tfstate-bucket ./run.sh bootstrap-state
#
# The bucket must have versioning on, default encryption, public access
# blocked, and a policy denying non-TLS requests. bootstrap-state sets all of
# those up.
#
# ---------------------------------------------------------------------------
# Want local state instead (no bucket, laptop only)?
#
# Comment out the whole terraform block below and run `terraform init
# -migrate-state`. Be aware that terraform.tfstate then holds the cluster CA
# data and OIDC config in cleartext on disk, and .gitignore already excludes
# it so it will never be committed.
###############################################################################

terraform {
  backend "s3" {
    # Deliberately empty. See the header above.
    encrypt = true
  }
}
