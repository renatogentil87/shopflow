# dev.auto.tfvars — NON-SECRET dev config, committed for PR review.
#
# Terraform auto-loads *.auto.tfvars, so no -var-file flag is needed locally or in CI.
#
# DO NOT put account IDs, secrets, or anything sensitive in this file — it IS committed.
#     `account_ids` is supplied separately from SSM (/shopflow/account_ids) via the
#     TF_VAR_account_ids env var that the buildspecs inject. See buildspec/README.md.

region   = "ca-central-1"
az_count = 2

vpc_cidr             = "172.20.0.0/16"
public_subnet_cidrs  = ["172.20.1.0/24", "172.20.2.0/24"]
private_subnet_cidrs = ["172.20.10.0/24", "172.20.20.0/24"]
