# modules/spoke-config-alerting/main.tf
#
# SPOKE side — runs IN a workload account (dev/stage/prod), selected by the
# `providers = { aws = aws.<env> }` passed from the caller.
#
# Config compliance events land on the account's DEFAULT event bus. This module
# catches NON_COMPLIANT ones and FORWARDS them to the central bus.

terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

# 1. Rule on the DEFAULT bus (no event_bus_name = default) matching NON_COMPLIANT.
resource "aws_cloudwatch_event_rule" "noncompliant" {
  name = "config-noncompliant-forward"
  event_pattern = jsonencode({
    source        = ["aws.config"]
    "detail-type" = ["Config Rules Compliance Change"]
    detail = {
      messageType         = ["ComplianceChangeNotification"]
      newEvaluationResult = { complianceType = ["NON_COMPLIANT"] }
    }
  })
}

# 2. IAM role EventBridge ASSUMES to deliver cross-account to the central bus.
#    (Cross-account delivery requires a role; same-account targets usually don't.)
resource "aws_iam_role" "forwarder" {
  name = "config-alert-forwarder"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "forwarder_putevents" {
  name = "put-events-to-central-bus"
  role = aws_iam_role.forwarder.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "events:PutEvents"
      Resource = var.central_bus_arn
    }]
  })
}

# 3. Target — forward matched events to the central bus, using the role above.
resource "aws_cloudwatch_event_target" "to_central_bus" {
  rule     = aws_cloudwatch_event_rule.noncompliant.name
  arn      = var.central_bus_arn
  role_arn = aws_iam_role.forwarder.arn
}
