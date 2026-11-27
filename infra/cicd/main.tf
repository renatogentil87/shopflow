# main.tf — the CI/CD stack.
# Flow: Source(merge->main) -> Test(validate) -> Dev(plan->apply)
#       -> Stage(plan->apply) -> Prod(plan->approval->apply).
# One CodeBuild project, reused; each action passes ENV + MODE. The plan action
# exports a saved tfplan artifact that the apply action consumes, so apply does
# exactly what was planned/reviewed.

data "aws_caller_identity" "current" {}

# Account IDs from SSM (same scheme as the env stacks) -> deployer-role ARNs
# CodeBuild is allowed to assume.
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
# Artifact bucket
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
# CodeBuild service role (runs Terraform; assumes the spoke deployer roles)
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
# One CodeBuild project, reused by every action (ENV + MODE set per action)
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
    buildspec = "buildspec.yml"
  }
}

# ----------------------------------------------------------------------------
# The pipeline. Each deploy env = a plan action (saves tfplan artifact) then an
# apply action (consumes it). Prod inserts a manual approval between them.
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
        DetectChanges    = "true"
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
      name             = "Plan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      run_order        = 1
      input_artifacts  = ["source"]
      output_artifacts = ["dev_plan"]
      configuration = {
        ProjectName          = aws_codebuild_project.tf.name
        EnvironmentVariables = jsonencode([{ name = "ENV", value = "dev", type = "PLAINTEXT" }, { name = "MODE", value = "plan", type = "PLAINTEXT" }])
      }
    }
    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      run_order       = 2
      input_artifacts = ["dev_plan"]
      configuration = {
        ProjectName          = aws_codebuild_project.tf.name
        EnvironmentVariables = jsonencode([{ name = "ENV", value = "dev", type = "PLAINTEXT" }, { name = "MODE", value = "apply", type = "PLAINTEXT" }])
      }
    }
  }

  stage {
    name = "Deploy-Stage"
    action {
      name             = "Plan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      run_order        = 1
      input_artifacts  = ["source"]
      output_artifacts = ["stage_plan"]
      configuration = {
        ProjectName          = aws_codebuild_project.tf.name
        EnvironmentVariables = jsonencode([{ name = "ENV", value = "stage", type = "PLAINTEXT" }, { name = "MODE", value = "plan", type = "PLAINTEXT" }])
      }
    }
    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      run_order       = 2
      input_artifacts = ["stage_plan"]
      configuration = {
        ProjectName          = aws_codebuild_project.tf.name
        EnvironmentVariables = jsonencode([{ name = "ENV", value = "stage", type = "PLAINTEXT" }, { name = "MODE", value = "apply", type = "PLAINTEXT" }])
      }
    }
  }

  stage {
    name = "Deploy-Prod"
    action {
      name             = "Plan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      run_order        = 1
      input_artifacts  = ["source"]
      output_artifacts = ["prod_plan"]
      configuration = {
        ProjectName          = aws_codebuild_project.tf.name
        EnvironmentVariables = jsonencode([{ name = "ENV", value = "prod", type = "PLAINTEXT" }, { name = "MODE", value = "plan", type = "PLAINTEXT" }])
      }
    }
    action {
      name      = "Approve"
      category  = "Approval"
      owner     = "AWS"
      provider  = "Manual"
      version   = "1"
      run_order = 2
    }
    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      run_order       = 3
      input_artifacts = ["prod_plan"]
      configuration = {
        ProjectName          = aws_codebuild_project.tf.name
        EnvironmentVariables = jsonencode([{ name = "ENV", value = "prod", type = "PLAINTEXT" }, { name = "MODE", value = "apply", type = "PLAINTEXT" }])
      }
    }
  }
}

output "codebuild_role_arn" {
  description = "Trusted by the spoke deployer roles (see bootstrap/deployer-roles.tf)."
  value       = aws_iam_role.codebuild.arn
}
