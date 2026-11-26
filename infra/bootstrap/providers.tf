# providers.tf — bootstrap stack
#
# Run this stack LOCALLY with ADMIN credentials for your CENTRAL/management account.
#  - Default provider  = that central account. The OIDC provider + pipeline role live here.
#  - Aliased providers = each spoke. They assume AWSControlTowerExecution — the PRE-EXISTING
#    Control Tower role — because the dedicated deployer roles don't exist yet (this stack
#    creates them). That is the bootstrap chicken-and-egg resolution.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "aws" {
  alias  = "dev"
  region = var.region
  assume_role { role_arn = "arn:aws:iam::${var.account_ids["dev"]}:role/AWSControlTowerExecution" }
}

provider "aws" {
  alias  = "stage"
  region = var.region
  assume_role { role_arn = "arn:aws:iam::${var.account_ids["stage"]}:role/AWSControlTowerExecution" }
}

provider "aws" {
  alias  = "prod"
  region = var.region
  assume_role { role_arn = "arn:aws:iam::${var.account_ids["prod"]}:role/AWSControlTowerExecution" }
}
