# modules/spoke-config-alerting/variables.tf

variable "central_bus_arn" {
  description = "ARN of the central EventBridge bus that NON_COMPLIANT events are forwarded to."
  type        = string
}
