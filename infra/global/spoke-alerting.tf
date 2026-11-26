# spoke-alerting.tf
#
# Deploy the spoke-side forwarder into EACH workload account via provider aliases.
# ONE `terraform apply` creates these resources in dev, stage, and prod — no
# per-account export/apply. The `providers = { aws = aws.<env> }` line is what
# targets each account; everything inside the module then runs in that account.

module "spoke_alerting_dev" {
  source          = "../modules/spoke-config-alerting"
  providers       = { aws = aws.dev }
  central_bus_arn = aws_cloudwatch_event_bus.config_alerts.arn
}

module "spoke_alerting_stage" {
  source          = "../modules/spoke-config-alerting"
  providers       = { aws = aws.stage }
  central_bus_arn = aws_cloudwatch_event_bus.config_alerts.arn
}

module "spoke_alerting_prod" {
  source          = "../modules/spoke-config-alerting"
  providers       = { aws = aws.prod }
  central_bus_arn = aws_cloudwatch_event_bus.config_alerts.arn
}
