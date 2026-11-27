variable "environment" {
  description = "the environment - prod, stage or dev"
  type = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type = string
}


variable "private_subnet_cidrs" {
  description = "private subnets of vpc "
  type = list(string)
}
variable "public_subnet_cidrs" {
  description = "public subnets of vpcs "
  type = list(string)
}

variable "azs" {
  description = "Availability Zones"
  type = list(string)
}