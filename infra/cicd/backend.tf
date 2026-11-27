# backend.tf — remote state in the central state bucket, under its own key.
terraform {
  backend "s3" {
    bucket       = "shopflow-global-resources-tfstate"
    key          = "cicd/terraform.tfstate"
    region       = "ca-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
