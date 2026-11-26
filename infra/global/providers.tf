# providers.tf
#
# The DEFAULT provider (no alias) targets the CENTRAL / governance (delegated-admin)
# account — i.e. whatever credentials you run `terraform apply` with. The org Config
# rules, the central event bus, and the SNS topic are all created here.
#
# Each ALIASED provider assumes a role INTO a spoke account, so one `terraform apply`
# can deploy the spoke forwarder into dev / stage / prod. The identity running
# Terraform must be allowed to sts:AssumeRole each of these role ARNs.

provider "aws" {
  region = var.region
}

provider "aws" {
  alias  = "dev"
  region = var.region
  assume_role {
    role_arn = var.spoke_deploy_role_arns["dev"]
  }
}

provider "aws" {
  alias  = "stage"
  region = var.region
  assume_role {
    role_arn = var.spoke_deploy_role_arns["stage"]
  }
}

provider "aws" {
  alias  = "prod"
  region = var.region
  assume_role {
    role_arn = var.spoke_deploy_role_arns["prod"]
  }
}
