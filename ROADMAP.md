# ShopFlow — Build Roadmap

Build-driven learning: each milestone is a **working end-to-end slice**, shipped as a PR and
promoted **dev → stage → prod**. The goal is not to "finish exercises" — it's to build a real system
and record *why* each decision was made (that's what turns building into demonstrable solutions-
architecture skill, and it's what makes the repo worth showing).

## How to use this roadmap
- Build **one milestone at a time**. Don't start the next until the current one is deployed to all
  three environments and its **Prove it** checks pass.
- **Definition of done (per milestone):** merged via the pipeline, applied to dev → stage → prod
  (prod behind the approval gate), Prove-it checks pass, README updated, and the milestone's ADR(s)
  written under `docs/adr/`.
- **Capture decisions as you go.** Each milestone lists the architecture decisions to record as ADRs.
  Write them *when you make the call*, not after — see `docs/adr/`.
- M0 and M1 can use the already-written study references `TFWB00_Foundations_State.md` and
  `TFWB01_CICD_Pipeline_Environments.md` (in `aws-net-study/terraform-workbooks/`) as checklists.

## Status
| Milestone | Status | PR | ADRs |
|-----------|--------|----|------|
| M0 — Delivery spine | ☐ not started | — | — |
| M1 — Network foundation | ☐ not started | — | — |
| M2 — 3-tier skeleton | ☐ not started | — | — |
| M3 — Data tier | ☐ not started | — | — |
| M4 — Auth | ☐ not started | — | — |
| M5 — Perf + decoupling | ☐ not started | — | — |
| M6 — Observability + security | ☐ not started | — | — |
| M7 — Resilience / DR (stretch) | ☐ not started | — | — |

(Mark ☐ → ◐ in progress → ☑ done, and fill in the PR link + ADR numbers.)

---

## M0 — Delivery spine (walking skeleton)
**Goal:** the GitHub Actions pipeline deploys a trivial resource to **dev** via OIDC, with remote
Terraform state — before any app exists.
**Build:** S3 + DynamoDB state backend; GitHub OIDC identity provider + a scoped deploy role (no
long-lived keys); GitHub Actions workflow: `plan` on PR, `apply` on merge; dev environment.
**Prove it:** a PR posts a plan; merging applies to dev; the workflow's `aws sts get-caller-identity`
shows the OIDC role session; GitHub stores no AWS access keys.
**ADRs:** remote-state backend choice; OIDC vs access keys; environment model (separate accounts vs
Terraform workspaces); repository layout (app + infra in one repo).

## M1 — Network foundation (per-env VPC)
**Goal:** each environment has its own app VPC with public / private / isolated subnets across 2 AZs.
**Build:** a reusable Terraform `network` module (VPC, subnets, route tables, IGW + NAT, VPC flow
logs); the `shopflow-<env>-*` naming convention and the tag schema (`Application`, `Environment`,
`Owner`, `ManagedBy`).
**Prove it:** subnets land in the right AZs/tiers; private-subnet egress works via NAT; flow logs are
recording.
**ADRs:** attach to the shared network backbone (TGW/Cloud WAN) vs a standalone VPC for the project;
NAT strategy (single vs per-AZ — availability vs cost).

## M2 — 3-tier skeleton (web + API on ECS behind ALBs)
**Goal:** a minimal FastAPI **web** tier and FastAPI **API** tier run on ECS Fargate — public ALB →
web, internal ALB → API — promoted dev → stage → prod.
**Build:** ECR repos; minimal web (Jinja "storefront" page that calls the API) and API (`/health` +
one real endpoint); Dockerfiles; ECS cluster, task definitions, services; target groups (type `ip`);
SG referencing between tiers; ACM certificate + Route 53 record.
**Prove it:** `curl` the public ALB → the web page renders and successfully calls the API; target
groups healthy; the prod apply waits for manual approval.
**ADRs:** Fargate vs EC2 launch type; deployment strategy (rolling vs blue/green); public ALB vs
CloudFront in front of the web tier.

## M3 — Data tier (Aurora PostgreSQL + secrets)
**Goal:** the API persists to Aurora; database credentials live in Secrets Manager.
**Build:** Aurora PostgreSQL Serverless v2 in isolated subnets, Multi-AZ; Secrets Manager for creds;
wire the API to the DB; schema + migrations (Alembic); product/order/user models.
**Prove it:** API CRUD operations hit Aurora; Multi-AZ confirmed; no credentials in code or plain
env vars; migrations run as a pipeline step.
**ADRs:** Aurora vs DynamoDB (relational + transactional rationale); Serverless v2 vs provisioned;
migration tooling; secret rotation.

## M4 — Auth (Cognito)
**Goal:** users can sign up / log in; the API authorizes requests via JWT.
**Build:** a Cognito user pool; the web login flow; API validation of the JWT.
**Prove it:** an unauthenticated request is rejected; login issues a token; a protected endpoint works
with the token.
**ADRs:** Cognito vs self-managed auth; token validation at the API vs at the ALB.

## M5 — Performance + decoupling (ElastiCache + async)
**Goal:** cart/session and product data are cached in Redis; order processing is asynchronous.
**Build:** ElastiCache (Redis) with a cache-aside pattern in the API; checkout publishes to SQS; a
Lambda worker processes orders; a dead-letter queue for failures.
**Prove it:** cache hit/miss behaviour is observable; checkout returns quickly while the order is
processed asynchronously; the queue drains; a forced failure lands in the DLQ.
**ADRs:** cache-aside vs write-through; SQS vs EventBridge; idempotency of the worker.

## M6 — Observability + security hardening
**Goal:** you can see the system end to end and it is hardened.
**Build:** CloudWatch dashboards + alarms; X-Ray / ADOT tracing; structured application logs; WAF on
the public edge; least-privilege ECS task roles; GuardDuty; Secrets Manager rotation.
**Prove it:** a single trace spans web → API → DB; an induced error fires an alarm; WAF blocks a test
request; task roles are demonstrably least-privilege.
**ADRs:** tracing approach (X-Ray vs ADSOT/OpenTelemetry); alarm/SLO thresholds; WAF managed rule set.

## M7 — Resilience / DR (stretch, SA-Pro flex)
**Goal:** a defensible HA posture and a tested DR story.
**Build:** Multi-AZ across all tiers; autoscaling (ECS service + Aurora); a backup-restore (or
pilot-light) runbook; a load test.
**Prove it:** losing an AZ doesn't drop service; the system autoscales under load; RTO/RPO are
documented and a restore has actually been tested.
**ADRs:** DR pattern (backup-restore vs pilot-light vs warm standby) and the cost trade-off.

---

## Cross-cutting conventions
- **Every milestone is a PR** that flows dev → stage → prod through the pipeline (prod gated).
- **Naming:** `shopflow-<env>-<purpose>` (e.g. `shopflow-dev-vpc`, `shopflow-dev-api`).
- **Tags on everything:** `Application=shopflow`, `Environment=<env>`, `Owner=rrdog`,
  `ManagedBy=terraform`.
- **ADR per decision:** record the choice when you make it; link it from the status table.

> Optional later milestone: **OpenSearch** product search as its own slice (read model separate from
> the transactional DB) — insert after M3 if/when you want it.
