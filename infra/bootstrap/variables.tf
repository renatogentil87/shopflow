# variables.tf — bootstrap stack
# Provide these in a terraform.tfvars (do not commit secrets; these aren't secret).

variable "region" {
  type    = string
  default = "ca-central-1"
}

# 12-digit spoke account IDs. Example tfvars:
#   account_ids = { dev = "111111111111", stage = "222222222222", prod = "333333333333" }
variable "account_ids" {
  description = "Map: dev/stage/prod spoke account IDs."
  type        = map(string)
}

# Your GitHub repo as <owner>/<repo>, e.g. "rrdog/shopflow".
# Used to scope the pipeline role's trust so only THIS repo can assume it.
variable "github_repo" {
  description = "GitHub <owner>/<repo> allowed to assume the pipeline role."
  type        = string
}
