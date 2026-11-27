# main.tf — the CI/CD stack.
# Flow: Source(GitHub, merge to main) -> Test(validate) -> Deploy-Dev -> Deploy-Stage
#       -> Manual approval -> Deploy-Prod. One CodeBuild project, reused; each stage
#       passes ENV (which env dir) and MODE (validate|apply) as action env vars.

data "aws_caller_identity" "current" {}

# Account IDs come from SSM (same scheme as the env stacks), used only to build
# the deployer-role ARNs CodeBuild is allowed to assume.
data "aws_ssm_parameter" "dev" { name = "/shopflow/accounts/dev" }
data "aws_ssm_parameter" "stage" { name = "/shopflow/accounts/stage" }
data "aws_ssm_parameter" "prod" { name = "/shopflow/accounts/prod" }

locals {
  deployer_role_arns = [
    "arn:aws:iam::${data.aws_ssm_parameter.dev.value}:role/${var.deployer_role_name}",
    "arn:aws:iam::${data.aws_ssm_parameter.stage.value}:role/${var.deployer_role_name}",
    "arn:aws:iam::${data.aws_ssm_parameter.prod.value}:role/${var.deployer_role_name}",
  ]
}

# ----------------------------------------------------------------------------
# Artifact bucket (CodePipeline hands artifacts between stages through here)
# ----------------------------------------------------------------------------
resource "aws_s3_bucket" "artifacts" {
  bucket = var.artifact_bucket_name
}
resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ----------------------------------------------------------------------------
# CodeBuild service role — what Terraform-in-CodeBuild runs as.
# NOTE: the spoke deployer roles must TRUST this role (bootstrap edit) or the
# cross-account assume fails.
# ----------------------------------------------------------------------------
data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "codebuild" {
  name               = var.codebuild_role_name
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
}
data "aws_iam_policy_document" "codebuild_perms" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
  statement {
    sid       = "Artifacts"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
  }
  statement {
    sid       = "TerraformState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${var.state_bucket_name}", "arn:aws:s3:::${var.state_bucket_name}/*"]
  }
  statement {
    sid       = "AccountIdParams"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/shopflow/accounts/*"]
  }
  statement {
    sid       = "AssumeSpokeDeployers"
    actions   = ["sts:AssumeRole"]
    resources = local.deployer_role_arns
  }
}
resource "aws_iam_role_policy" "codebuild" {
  name   = "codebuild-perms"
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild_perms.json
}

# ----------------------------------------------------------------------------
# CodePipeline service role
# ----------------------------------------------------------------------------
data "aws_iam_policy_document" "codepipeline_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "codepipeline" {
  name               = "shopflow-codepipeline"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume.json
}
data "aws_iam_policy_document" "codepipeline_perms" {
  statement {
    sid       = "Artifacts"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
  }
  statement {
    sid       = "RunBuilds"
    actions   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
    resources = [aws_codebuild_project.tf.arn]
  }
  statement {
    sid       = "UseGitHubConnection"
    actions   = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
    resources = [var.connection_arn]
  }
}
resource "aws_iam_role_policy" "codepipeline" {
  name   = "codepipeline-perms"
  role   = aws_iam_role.codepipeline.id
  policy = data.aws_iam_policy_document.codepipeline_perms.json
}

# ----------------------------------------------------------------------------
# One CodeBuild project, reused by every stage. ENV + MODE come from each
# pipeline action, so the same project validates or applies any env.
# ----------------------------------------------------------------------------
resource "aws_codebuild_project" "tf" {
  name         = "shopflow-terraform"
  service_role = aws_iam_role.codebuild.arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
    type         = "LINUX_CONTAINER"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml" # from the repo root
  }
}

# ----------------------------------------------------------------------------
# The pipeline
# ----------------------------------------------------------------------------
resource "aws_codepipeline" "this" {
  name          = "shopflow"
  role_arn      = aws_iam_role.codepipeline.arn
  pipeline_type = "V2"

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.artifacts.bucket
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source"]
      configuration = {
        ConnectionArn    = var.connection_arn
        FullRepositoryId = var.repo
        BranchName       = var.branch
        DetectChanges    = "true" # merge to main auto-starts the pipeline
      }
    }
  }

  stage {
    name = "Test"
    action {
      name            = "Validate"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source"]
      configuration = {
        ProjectName          = aws_codebuild_project.tf.name
        EnvironmentVariables = jsonencode([{ name = "ENV", value = "dev", type = "PLAINTEXT" }, { name = "MODE", value = "validate", type = "PLAINTEXT" }])
      }
    }
  }

  stage {
    name = "Deploy-Dev"
    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source"]
      configuration = {
        ProjectName          = aws_codebuild_project.tf.name
        EnvironmentVariables = jsonencode([{ name = "ENV", value = "dev", type = "PLAINTEXT" }, { name = "MODE", value = "apply", type = "PLAINTEXT" }])
      }
    }
  }

  stage {
    name = "Deploy-Stage"
    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source"]
      configuration = {
        ProjectName          = aws_codebuild_project.tf.name
        EnvironmentVariables = jsonencode([{ name = "ENV", value = "stage", type = "PLAINTEXT" }, { name = "MODE", value = "apply", type = "PLAINTEXT" }])
      }
    }
  }

  stage {
    name = "Approve-Prod"
    action {
      name     = "ManualApproval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"
    }
  }

  stage {
    name = "Deploy-Prod"
    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source"]
      configuration = {
        ProjectName          = aws_codebuild_project.tf.name
        EnvironmentVariables = jsonencode([{ name = "ENV", value = "prod", type = "PLAINTEXT" }, { name = "MODE", value = "apply", type = "PLAINTEXT" }])
      }
    }
  }
}

output "codebuild_role_arn" {
  description = "Add THIS to the spoke deployer_trust in bootstrap, then re-apply bootstrap."
  value       = aws_iam_role.codebuild.arn
}
