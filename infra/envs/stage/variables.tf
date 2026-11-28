
variable "az_count" {
  type    = number
  default = 2
}

variable "vpc_cidr" {
  description = "vpc cidr"
  type        = string
}
variable "private_subnet_cidrs" {
  description = "Private subnet"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet cidr"
  type        = list(string)
}

variable "region" {
  description = "AWS region for the dev stack"
  type        = string
}

