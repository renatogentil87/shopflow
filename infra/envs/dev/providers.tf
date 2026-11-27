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
  assume_role { role_arn = "arn:aws:iam::${var.account_ids["dev"]}:role/shopflow-governance-deployer" }
}

provider "aws" {
  alias  = "stage"
  region = var.region
  assume_role { role_arn = "arn:aws:iam::${var.account_ids["stage"]}:role/shopflow-governance-deployer" }
}

provider "aws" {
  alias  = "prod"
  region = var.region
  assume_role { role_arn = "arn:aws:iam::${var.account_ids["prod"]}:role/shopflow-governance-deployer" }
}

