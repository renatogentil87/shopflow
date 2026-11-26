variable "tags" {
  description = "Tags to set on the bucket."
  type        = map(string)
  default     = {}
}

variable "region" {
  description = "AWS region for all resources in this stack."
  type        = string
  default     = "ca-central-1"
}

# Role ARN in EACH spoke account that this stack assumes to deploy the spoke
# forwarder. YOU MUST FILL THESE IN (e.g. in a terraform.tfvars, not committed).
#
# Which role?
#   - Quick start: Control Tower creates "AWSControlTowerExecution" in every
#     enrolled member account. It is assumable by the MANAGEMENT account (so you'd
#     run this stack from management if you use it) and is broad / not least-priv.
#   - Proper: create a dedicated least-privilege deploy role in each spoke that your
#     running identity can assume, and put its ARN here.
#
# Example: { dev = "arn:aws:iam::<DEV_ID>:role/AWSControlTowerExecution", ... }
variable "spoke_deploy_role_arns" {
  description = "Map of env (dev/stage/prod) -> IAM role ARN to assume in each spoke account."
  type        = map(string)
  # no default on purpose — provide dev/stage/prod ARNs yourself
}

# Your AWS Organizations ID (format o-xxxxxxxxxx). Used to scope the central event
# bus policy so only accounts in YOUR org can forward events to it.
variable "organization_id" {
  description = "AWS Organizations ID (o-xxxxxxxxxx) for the event-bus policy condition."
  type        = string
}

