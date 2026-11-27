terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }
}

# Default provider = central account (CodeBuild runs here, or you locally).
# Used to read SSM. No assume_role.
provider "aws" {
  region = var.region
}

# Account IDs are sensitive -> read from SSM Parameter Store (central account),
# NOT from committed tfvars. Resolved at plan time, so it's valid in provider config.
data "aws_ssm_parameter" "prod_account_id" {
  name = "/shopflow/accounts/prod"
}

# Spoke provider: assume the dev deployer role in the dev account.
provider "aws" {
  alias  = "prod"
  region = var.region
  assume_role {
    role_arn = "arn:aws:iam::${data.aws_ssm_parameter.prod_account_id.value}:role/shopflow-governance-deployer"
  }
}

