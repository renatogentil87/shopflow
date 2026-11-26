# Security Architecture Decisions

A grouped log of security-related decisions for ShopFlow. Each entry follows the ADR format
(Context / Decision / Consequences) established in `0001-record-architecture-decisions.md`; they're
kept in one security file by preference rather than as separate numbered ADRs. If a decision here is
later reversed, supersede it in place with a dated note rather than deleting it.

---

## SEC-1: Alert on Config compliance change only, not raw configuration changes
- **Status:** Accepted
- **Date:** 2026-11-25

### Context
During active building, resources change constantly. Subscribing a human to AWS Config's raw
configuration-item stream (every change → email) produces unusable noise and trains you to ignore it.
What actually matters is when a resource ends up in an *undesired* state.

### Decision
Do **not** notify humans on the raw Config configuration-change stream. Instead:
- Define desired state as **AWS Config Rules** (managed + custom) — e.g. public-bucket, open-security-
  group, unencrypted-volume checks.
- Alert **only on a compliance-state change to `NON_COMPLIANT`**, via an EventBridge rule matching:
  ```json
  {
    "source": ["aws.config"],
    "detail-type": ["Config Rules Compliance Change"],
    "detail": {
      "messageType": ["ComplianceChangeNotification"],
      "newEvaluationResult": { "complianceType": ["NON_COMPLIANT"] }
    }
  }
  ```
  routed to SNS / Slack (optionally narrowed by `configRuleName` / `resourceType`).

### Consequences
- Signal, not noise: you hear about rule violations, not routine edits.
- Requires defining and maintaining a set of Config Rules (ongoing cost/effort, accepted).
- Changes that violate no rule are intentionally **not** surfaced — that is the point.
- In dev, scope rules to security-critical checks only to tolerate expected churn; in prod, run the
  full set.

---

## SEC-2: Treat any change made outside the pipeline deploy role as unexpected
- **Status:** Accepted
- **Date:** 2026-11-25

### Context
All infrastructure changes are meant to flow through the Terraform + GitHub Actions pipeline. A change
made any other way (console, manual CLI, a different principal) is drift and a potential incident. We
want a precise definition of "unexpected" so an alert means something went genuinely wrong.

### Decision
Define an **unexpected change** as any resource mutation **not** made by the pipeline's deploy role.
Detect it two ways:
- **`terraform plan` drift detection** run on a schedule in CI — a non-empty plan means something
  changed out-of-band.
- **EventBridge on CloudTrail management events**, filtering **out** the pipeline deploy role's
  identity, so an alert fires only when a non-pipeline principal mutated a resource.
In **prod**, additionally restrict mutation to the pipeline role via an **SCP**, so non-pipeline
changes are blocked outright rather than merely detected. **dev** stays open for hands-on learning
with looser alerting.

### Consequences
- "Unexpected" has a precise meaning: `NON_COMPLIANT` against a rule (SEC-1), OR a non-empty
  `terraform plan`, OR a mutation by a principal other than the pipeline role.
- Prod SCP enforces the model instead of relying on detection alone.
- Emergency manual fixes in prod need a defined **break-glass** path (future decision).
- dev churn is expected and deliberately not alerted on.

---

## SEC-3: Human console access is read-only; admin is break-glass; all changes via the pipeline
- **Status:** Accepted
- **Date:** 2026-11-25

### Context
Control Tower set up IAM Identity Center as the SSO entry point across the ShopFlow accounts. Per
SEC-2, all infrastructure changes flow through the Terraform pipeline, so human console access exists
for *visibility*, not routine modification. Access is granted by assigning (group × permission set ×
account); best practice is to assign to **groups**, not individual users.

### Decision
- **One Identity Center identity per person** (a single user, not one per account). Access is granted
  through **groups**, never direct user-to-account assignments.
- **`shopflow-readonly`** group → **`AWSReadOnlyAccess`** permission set, assigned to **dev / stage /
  prod** → the everyday login for console overview (look, don't touch).
- **`shopflow-admin`** group → **`AWSAdministratorAccess`** permission set → **break-glass only**:
  dev may use it freely for learning; prod only in a genuine break-glass situation.
- **The Terraform pipeline uses its own GitHub OIDC deploy role**, entirely separate from Identity
  Center. It performs **all** resource modifications. Human SSO access never needs write for normal
  work.
- One permission set is defined once and **reused** across accounts; assignments are per account.

### Consequences
- Clean separation of duties: humans are read-only, the pipeline mutates — directly reinforces SEC-2.
- Any use of `shopflow-admin` (especially in prod) is by definition an out-of-pipeline action, so it
  should be logged and alerted (SEC-2 detection) and ideally time-bound. A formal **break-glass
  procedure** for prod is a future decision.
- Onboarding is trivial: add a person to a group — no per-account user setup.
- Routine console mistakes are structurally prevented (read-only), while Terraform remains the single
  path to change.
