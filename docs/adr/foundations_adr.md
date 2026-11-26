# Foundations Architecture Decisions

A grouped log of the foundational platform decisions for ShopFlow — landing zone, environment model,
and Terraform state backend. Same ADR format (Context / Decision / Consequences) as
`0001-record-architecture-decisions.md`; supersede in place with a dated note if reversed.

---

## FND-1: Landing zone via AWS Control Tower, workloads in a Workloads OU
- **Status:** Accepted
- **Date:** 2026-11-25

### Context
ShopFlow is built as a realistic multi-account project. It needs governance, guardrails, and
centralized audit logging from day one, rather than a single hand-managed account.

### Decision
Use **AWS Control Tower** to set up the landing zone. Place the workload accounts
(`shopflow-dev` / `stage` / `prod`) under a **Workloads OU**, enrolled in Control Tower so they are
automatically governed. Keep the shared accounts — **management, Log Archive, Audit** — clean (no
application workloads). Rely on the Control Tower **organization-level CloudTrail** and **Config
aggregator** for cross-account logging and compliance; do **not** create per-account CloudTrail
trails.

### Consequences
- Guardrails, org trail, and Config come configured out of the box.
- Separation of duties: workloads never run in management/Log Archive/Audit.
- No per-account trails (avoids duplicate CloudTrail charges; the org trail already covers every
  enrolled account automatically).
- Control Tower landing-zone version upgrades become an ongoing operational task.
- Resources are created in the workload accounts; logging flows to the shared accounts with no action
  needed in those accounts.

---

## FND-2: Three separate accounts for dev / stage / prod
- **Status:** Accepted
- **Date:** 2026-11-25

### Context
The application needs isolated environments to promote changes safely and to mirror a real SDLC. The
shared network backbone, by contrast, is a single shared service and should not be triplicated.

### Decision
Use **three separate AWS accounts** — `shopflow-dev`, `shopflow-stage`, `shopflow-prod` — under the
Workloads OU, each enrolled in Control Tower. The **application layer** is promoted **dev → stage →
prod** through the pipeline, with a manual approval gate before prod. Each account holds its own app
VPC that attaches to the **single shared network backbone** (the backbone is not replicated per
environment, per the AWS SRA Network-account pattern).

### Consequences
- Strong blast-radius isolation and least-privilege per environment (a dev credential cannot touch
  prod).
- Natural home for per-account resources, including each account's own Terraform state (see FND-3).
- More accounts to manage, but Control Tower automates enrollment and guardrails.
- The prod approval gate enforces promotion discipline.

---

## FND-3: Per-account Terraform state backend (S3 + native locking)
- **Status:** Accepted
- **Date:** 2026-11-25

### Context
Terraform needs remote state before the pipeline can run, and the multi-account model (FND-2) means
state should live with the account it manages. State also contains secrets in plaintext, so it must
be protected.

### Decision
Each account has its **own S3 state bucket in that account** (dev state in the dev account, etc.),
with **versioning on**, **encryption on**, and **Block Public Access on**. Use **S3 native state
locking via `use_lockfile = true`** — **not** a DynamoDB lock table (DynamoDB-based locking is
deprecated in the Terraform S3 backend). Because backend blocks cannot be parameterized with
variables, use **per-environment directories** (`infra/envs/dev|stage|prod/`), each with its own
`backend.tf` pointing at that account's bucket. Bootstrap each account's backend by creating the
bucket with local state, then `terraform init -migrate-state`.

### Consequences
- State isolation per account: dev credentials cannot read or write prod state.
- No DynamoDB table to create or manage (native lockfile handles locking).
- The backend is bootstrapped three times (once per account) — accepted repetition.
- Backend values are hardcoded per env directory (not variable-driven), which is a Terraform
  constraint, not a choice.
- Versioning provides recovery from a corrupted or accidental state write.
