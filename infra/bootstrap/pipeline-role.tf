# pipeline-role.tf — the role GitHub Actions assumes (CENTRAL account)
#
# This role is the pipeline's identity. It REPLACES your local admin when CI runs:
# it operates on the central governance resources AND assumes the spoke deployer roles.

# --- TRUST: who may assume this role ---
# Federated principal = the GitHub OIDC provider. The sub condition scopes it to YOUR
# repo. IAM REJECTS a GitHub OIDC trust that does not restrict sub.
data "aws_iam_policy_document" "pipeline_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Start broad-ish (any ref in your repo). Tighten later to a branch
      # (repo:<owner>/<repo>:ref:refs/heads/main) or environment
      # (repo:<owner>/<repo>:environment:prod).
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "pipeline" {
  name               = "shopflow-pipeline"
  assume_role_policy = data.aws_iam_policy_document.pipeline_trust.json
}

# --- PERMISSIONS: what the pipeline can do ---
# (1) assume the spoke deployer roles; (2) manage the central governance resources.
data "aws_iam_policy_document" "pipeline_perms" {
  statement {
    sid       = "AssumeSpokeDeployers"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [
      "arn:aws:iam::${var.account_ids["dev"]}:role/shopflow-governance-deployer",
      "arn:aws:iam::${var.account_ids["stage"]}:role/shopflow-governance-deployer",
      "arn:aws:iam::${var.account_ids["prod"]}:role/shopflow-governance-deployer",
    ]
  }
  statement {
    sid       = "CentralGovernanceAndState"
    effect    = "Allow"
    actions   = ["config:*", "events:*", "sns:*", "s3:*", "iam:PassRole"]
    resources = ["*"] # TODO: scope down (e.g. state bucket ARN, specific rule/topic ARNs)
  }
}

resource "aws_iam_role_policy" "pipeline_perms" {
  name   = "shopflow-pipeline-perms"
  role   = aws_iam_role.pipeline.id
  policy = data.aws_iam_policy_document.pipeline_perms.json
}

output "pipeline_role_arn" {
  description = "Put this in the workflows' role-to-assume."
  value       = aws_iam_role.pipeline.arn
}
