data "aws_availability_zones" "available" {
  provider = aws.prod
  state    = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

module "network" {
  source               = "../../modules/network"
  providers            = { aws = aws.prod }
  environment          = "prod"
  vpc_cidr             = var.vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}