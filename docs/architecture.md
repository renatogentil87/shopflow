# ShopFlow — Architecture

ShopFlow is a 3-tier e-commerce platform used to demonstrate solutions-architecture and DevOps
practice on AWS. This document is the standalone architecture reference for the repository.

## Tiers (MVP)
1. **Web tier** — FastAPI + Jinja2 server-rendered HTML, containerized on ECS Fargate, behind a
   public Application Load Balancer. Serves the storefront and calls the API.
2. **App tier** — FastAPI REST API on ECS Fargate in private subnets, behind an internal ALB.
   Business logic: catalog, cart, checkout, orders, users.
3. **Data tier** — Aurora PostgreSQL Serverless v2 in isolated subnets, Multi-AZ. Transactional
   store for products, inventory, orders, and users.

Tier-to-tier access is controlled by security-group referencing (web SG → internal ALB SG →
app SG → database SG), not CIDR rules. ECS tasks run in private subnets; load-balancer target
groups use the `ip` target type (required for Fargate / `awsvpc`).

## Supporting services (added incrementally)
- **Amazon Cognito** — user authentication and JWT issuance.
- **ElastiCache (Redis)** — cart/session state and product caching.
- **S3 + CloudFront + WAF** — product images / static assets and edge protection.
- **SQS + Lambda / EventBridge** — asynchronous order processing (decouples checkout from fulfilment).
- **Amazon OpenSearch** — product search / catalog read model.
- **Secrets Manager** — database credentials (with rotation).
- **CloudWatch + X-Ray/ADOT** — metrics, logs, dashboards, alarms, tracing, synthetics.

## Environments
- **dev / stage / prod**, promoted through GitHub Actions with a manual approval gate before prod.
- Each environment is isolated (separate account preferred; Terraform workspaces otherwise) and has
  its own app VPC that **attaches to a shared network backbone** (Transit Gateway / Cloud WAN).
- The shared backbone is managed outside this repository, following the AWS multi-account pattern of a
  dedicated Network account.

## Delivery
- **Infrastructure:** Terraform, remote state on S3 with a DynamoDB lock table, reusable modules under
  `infra/modules/`, per-environment stacks under `infra/envs/`.
- **Application:** container images built and scanned in CI, pushed to Amazon ECR, deployed to ECS
  with a blue/green strategy.
- **Authentication:** GitHub Actions authenticates to AWS via OIDC federation (no long-lived access
  keys stored in the repository).

## Architecture decisions
Significant decisions are recorded as ADRs under `docs/adr/`.

> This document describes the intended target architecture. Components are implemented incrementally;
> the repository may not yet contain every element described here.
