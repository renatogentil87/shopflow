terraform {
  backend "s3" {
    bucket       = "shopflow-global-resources-tfstate"
    key          = "env/dev/terraform.tfstate"
    region       = "ca-central-1"
    encrypt      = true
    use_lockfile = true # native S3 locking (Terraform ≥ 1.10)
  }
}