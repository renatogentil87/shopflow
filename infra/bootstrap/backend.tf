# backend.tf — bootstrap stack state
#
# LOCAL state on purpose. This stack creates the foundation (GitHub OIDC provider,
# pipeline role, spoke deployer roles) that the pipeline needs to exist BEFORE it can
# run. You apply this once, manually, with admin credentials. Nothing depends on it
# having remote state, so keep it simple and local.
terraform {
  backend "local" {}
}
