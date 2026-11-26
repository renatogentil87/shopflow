# modules/spoke-config-alerting/outputs.tf

output "forwarder_role_arn" {
  description = "IAM role EventBridge uses to forward events to the central bus."
  value       = aws_iam_role.forwarder.arn
}

output "rule_arn" {
  description = "ARN of the spoke NON_COMPLIANT forwarding rule."
  value       = aws_cloudwatch_event_rule.noncompliant.arn
}
