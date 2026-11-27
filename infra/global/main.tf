data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "shopflow-global-resources-tfstate" {
  bucket = "shopflow-global-resources-tfstate"
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Terraform = "True"
    Env = "prod"
    Governance = "True"
  }
}

resource "aws_config_organization_managed_rule" "s3_block_public_access"{
  name            = "s3-bucket-level-public-access-prohibited"
  rule_identifier = "S3_BUCKET_LEVEL_PUBLIC_ACCESS_PROHIBITED"
  description     = "NON_COMPLIANT if an S3 bucket's bucket-level settings allow public access."
  excluded_accounts = [data.aws_caller_identity.current.account_id]
}

resource "aws_config_organization_managed_rule" "alb_waf_enabled" {
  name  = "alb-waf-enabled"
  rule_identifier = "ALB_WAF_ENABLED"
  description = "NON_COMPLIANT if ALB doesn't have WAF together"
  excluded_accounts = [data.aws_caller_identity.current.account_id]
}

resource "aws_config_organization_managed_rule" "cloudtrail_encryption" {
  name            = "cloudtrail-encryption-enabled"
  rule_identifier = "CLOUD_TRAIL_ENCRYPTION_ENABLED"
  description = "NON_COMPLIANT if CloudTrail isn't encrypted"
  maximum_execution_frequency = "TwentyFour_Hours"
  excluded_accounts = [data.aws_caller_identity.current.account_id]
}

resource "aws_config_organization_managed_rule" "ssh_restricted_access" {
  name            = "restricted-ssh"
  rule_identifier = "INCOMING_SSH_DISABLED"
  description = "NON_COMPLIANT if ssh port is opened to the world"
  excluded_accounts = [data.aws_caller_identity.current.account_id]
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.config_alerts.arn
  protocol  = "email"
  endpoint  = "rrdog+config@amazon.com"
}

resource "aws_sns_topic" "config_alerts" {
  name = "config-rule-alerts"
}


