# central-alerting.tf
#
# CENTRAL (governance) side of the compliance-alert pipeline.
# Flow:  spoke default bus --(forward)--> THIS custom bus --> rule --> SNS --> email
#
# The SNS topic + subscription already live in main.tf (aws_sns_topic.config_alerts).

# 1. Custom event bus that RECEIVES forwarded NON_COMPLIANT events from the spokes.
resource "aws_cloudwatch_event_bus" "config_alerts" {
  name = "shopflow-config-alerts"
}

resource "aws_cloudwatch_event_bus_policy" "allow_org_putevents" {
  event_bus_name = aws_cloudwatch_event_bus.config_alerts.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowOrgAccountsPutEvents"
      Effect    = "Allow"
      Principal = "*"
      Action    = "events:PutEvents"
      Resource  = aws_cloudwatch_event_bus.config_alerts.arn
      Condition = {
        StringEquals = { "aws:PrincipalOrgID" = var.organization_id }
      }
    }]
  })
}

# 3. Rule ON the custom bus — match the forwarded NON_COMPLIANT events.
resource "aws_cloudwatch_event_rule" "noncompliant_central" {
  name           = "config-noncompliant-central"
  event_bus_name = aws_cloudwatch_event_bus.config_alerts.name
  event_pattern = jsonencode({
    source        = ["aws.config"]
    "detail-type" = ["Config Rules Compliance Change"]
    detail = {
      messageType         = ["ComplianceChangeNotification"]
      newEvaluationResult = { complianceType = ["NON_COMPLIANT"] }
    }
  })
}

# 4. Target — send matched events to the SNS topic (defined in main.tf).
resource "aws_cloudwatch_event_target" "to_sns" {
  rule           = aws_cloudwatch_event_rule.noncompliant_central.name
  event_bus_name = aws_cloudwatch_event_bus.config_alerts.name
  arn            = aws_sns_topic.config_alerts.arn
}


resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.config_alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgePublish"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.config_alerts.arn
    }]
  })
}
