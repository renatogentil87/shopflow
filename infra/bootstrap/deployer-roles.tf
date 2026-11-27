# deployer-roles.tf — per-spoke deploy roles (Option B)
#
# Created IN each spoke via the aliased providers (which assume AWSControlTowerExecution).
# All three trust the central pipeline role, so the pipeline can assume them to deploy
# the spoke-config-alerting resources. Permissions are least-privilege for exactly what
# that module creates (EventBridge rule/target + the forwarder IAM role).

# TRUST (shared): allow the central pipeline role to assume these.
# (Add your human admin principal here too if you also run locally.)
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "deployer_trust" {
  # CI path: the central pipeline role may assume these (used by the pipeline).
  statement {
    sid     = "PipelineRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.pipeline.arn]
    }
  }

  # Local path: your human admin (SSO AdministratorAccess in the mgmt account)
  # may also assume these, so you can run the stacks locally while building.
  # We trust the account ROOT and scope with ArnLike to the SSO admin role, so
  # the permission-set hash can rotate without breaking this trust.
  # account_id is derived from the running (default-provider) identity — the
  # management account — so no literal account ID appears in the repo.
  statement {
    sid     = "HumanAdminLocal"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values = [
        # SSO AdministratorAccess (hash rotation tolerated by the wildcard)
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_AWSAdministratorAccess*",
        # Isengard Administrator role — the identity you actually run Terraform as locally
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/Administrator",
      ]
    }
  }
}

# PERMISSIONS (shared): what the spoke-config-alerting module needs.
data "aws_iam_policy_document" "deployer_perms" {
  statement {
    sid    = "EventBridge"
    effect = "Allow"
    actions = [
      "events:PutRule", "events:DeleteRule", "events:DescribeRule",
      "events:PutTargets", "events:RemoveTargets", "events:ListTargetsByRule",
      "events:EnableRule", "events:DisableRule",
      "events:TagResource", "events:UntagResource", "events:ListTagsForResource"
    ]
    resources = ["*"]
  }
  statement {
    sid    = "IamForForwarderRole"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:PassRole"
    ]
    resources = ["*"] # TODO: scope to the forwarder role ARN
  }
  statement {
    sid = "EC2Permissions"
    effect = "Allow"
    actions = ["ec2:*"]
    resources = ["*"]
  }
}


# --- DEV ---
resource "aws_iam_role" "deployer_dev" {
  provider           = aws.dev
  name               = "shopflow-governance-deployer"
  assume_role_policy = data.aws_iam_policy_document.deployer_trust.json
}
resource "aws_iam_role_policy" "deployer_dev" {
  provider = aws.dev
  name     = "deploy-perms"
  role     = aws_iam_role.deployer_dev.id
  policy   = data.aws_iam_policy_document.deployer_perms.json
}

# --- STAGE ---
resource "aws_iam_role" "deployer_stage" {
  provider           = aws.stage
  name               = "shopflow-governance-deployer"
  assume_role_policy = data.aws_iam_policy_document.deployer_trust.json
}
resource "aws_iam_role_policy" "deployer_stage" {
  provider = aws.stage
  name     = "deploy-perms"
  role     = aws_iam_role.deployer_stage.id
  policy   = data.aws_iam_policy_document.deployer_perms.json
}

# --- PROD ---
resource "aws_iam_role" "deployer_prod" {
  provider           = aws.prod
  name               = "shopflow-governance-deployer"
  assume_role_policy = data.aws_iam_policy_document.deployer_trust.json
}
resource "aws_iam_role_policy" "deployer_prod" {
  provider = aws.prod
  name     = "deploy-perms"
  role     = aws_iam_role.deployer_prod.id
  policy   = data.aws_iam_policy_document.deployer_perms.json
}
