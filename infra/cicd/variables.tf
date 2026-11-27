variable "region" {
  description = "Region for the CI/CD resources (central account)."
  type        = string
  default     = "ca-central-1"
}

variable "connection_arn" {
  description = "Existing CodeConnections (GitHub) connection ARN."
  type        = string
}

variable "repo" {
  description = "owner/repo, e.g. renatogentil87/shopflow."
  type        = string
}

variable "branch" {
  description = "Branch that triggers the pipeline on merge."
  type        = string
  default     = "main"
}

variable "artifact_bucket_name" {
  description = "Globally-unique S3 bucket name for pipeline artifacts."
  type        = string
}

variable "state_bucket_name" {
  description = "The Terraform state bucket CodeBuild must read/write."
  type        = string
  default     = "shopflow-global-resources-tfstate"
}

# Names kept as vars so bootstrap can predict the CodeBuild role ARN for the
# deployer-role trust without a cross-stack dependency.
variable "codebuild_role_name" {
  description = "Name of the CodeBuild service role."
  type        = string
  default     = "shopflow-codebuild"
}

variable "deployer_role_name" {
  description = "Name of the per-spoke deployer role CodeBuild assumes."
  type        = string
  default     = "shopflow-governance-deployer"
}
