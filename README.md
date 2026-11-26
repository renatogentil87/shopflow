# ShopFlow

A 3-tier e-commerce platform on AWS — built to demonstrate end-to-end **solutions architecture** and
**DevOps / CI-CD** practice: infrastructure as code, containerized services, a managed relational
database, and a GitHub Actions pipeline promoting across **dev → stage → prod**.

> **Status:** scaffolding. This repository currently contains the folder structure only; application
> code, Terraform, and pipelines are built out incrementally. See `docs/architecture.md`.

## Architecture (MVP, classic 3-tier)

```
Users → Route 53 + ACM → Public ALB (WAF)
           → Web tier:  FastAPI + Jinja2 (server-rendered)   [ECS Fargate]
              → Internal ALB
                 → App tier:  FastAPI REST API                [ECS Fargate, private]
                    → DB tier:  Aurora PostgreSQL Serverless v2  [isolated subnets, Multi-AZ]
```

All-Python stack (FastAPI for both tiers). Supporting services added over time: Cognito (auth),
ElastiCache Redis (cart/session + cache), S3 + CloudFront (assets/edge), SQS + Lambda / EventBridge
(async order processing), OpenSearch (product search), and full observability (CloudWatch, X-Ray).

## Tech stack
- **Language / framework:** Python, FastAPI, Jinja2
- **Containers:** Docker, Amazon ECS on Fargate, Amazon ECR
- **Data:** Aurora PostgreSQL Serverless v2 (+ ElastiCache Redis)
- **Infrastructure as code:** Terraform (remote state on S3 + DynamoDB lock)
- **CI/CD:** GitHub Actions with OIDC federation to AWS (no long-lived keys)
- **Edge / security:** CloudFront, WAF, Secrets Manager, least-privilege IAM

## Repository layout
```
.github/workflows/   GitHub Actions — app CI, app CD, infra pipeline
app/api/             FastAPI REST API (app tier)
app/web/             FastAPI + Jinja2 web tier
infra/modules/       Reusable Terraform modules (network, alb, ecs, database, cache, observability)
infra/envs/          Per-environment stacks (dev / stage / prod)
infra/global/        Shared bootstrap (state backend, OIDC provider, ECR)
docs/                Architecture notes and ADRs
scripts/             Helper scripts
```

## Environments
Promoted **dev → stage → prod** through GitHub Actions, with a manual approval gate before prod.
The shared network backbone (Transit Gateway / Cloud WAN) is managed separately and is not part of
this repository — each environment's app VPC attaches to it.

## What this project demonstrates
- **Solutions architecture:** multi-tier design, data-store selection, decoupling, HA/DR, edge, and
  cost/security trade-offs across environments.
- **DevOps:** IaC with policy gates, OIDC-based pipeline auth, blue/green deployment, observability,
  and operate-in-production practices.

---
*Built by Renato Gentil as a hands-on AWS solutions-architecture / DevOps portfolio project.*
