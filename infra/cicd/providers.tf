# providers.tf — the CI/CD stack lives entirely in the CENTRAL account
# (228923847373): CodePipeline, CodeBuild, their roles, and the artifact bucket.
# CodeBuild then ASSUMES the per-spoke deployer roles at run time (via Terraform
# in the env stacks) — this stack itself does not touch the spoke accounts.
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
