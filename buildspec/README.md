# ShopFlow — CodePipeline / CodeBuild (Terraform) wiring

This directory holds the CodeBuild buildspecs that run the Terraform pipeline. It replaces
the GitHub Actions workflows under `.github/workflows/` (which relied on a GitHub OIDC provider
that Cloud Security auto-deletes on internal Isengard/Conduit accounts — CodeBuild uses its own
service role instead, with no external identity provider, so it sidesteps that control).

## Pipeline shape

```
Source   GitHub (CodeStar Connections)  — triggers on merge to main
  │
Test     CodeBuild  ← buildspec/test.yml     fmt • validate • checkov • trivy • terraform test • plan
  │        (output artifact: tf-plan-dev)
Approve  CodePipeline manual approval        (prod only; optional for dev)
  │
Apply    CodeBuild  ← buildspec/apply.yml     terraform apply of the saved plan
           (input artifact: tf-plan-dev)
```

For dev → stage → prod promotion, repeat the Test/Approve/Apply actions per environment (one
CodeBuild project per action, each with a different `TF_ENV`), or use one pipeline per env.

## Why not CodeDeploy?

CodeDeploy deploys **application artifacts** to EC2 / ECS / Lambda. It cannot run `terraform
apply`. The "deploy" of infrastructure here is the Apply CodeBuild action above. Keep CodeDeploy
in reserve for the M2 ECS app tier (blue/green of the container service), not for Terraform.

## CodeBuild project settings

Create (or point your existing project at) these buildspec paths:

| Action | Buildspec              | Key env vars |
|--------|------------------------|--------------|
| Test   | `buildspec/test.yml`   | `TF_ENV`, `TF_STATE_BUCKET`, `TF_STATE_REGION`, `AWS_DEFAULT_REGION` |
| Apply  | `buildspec/apply.yml`  | same |

- Image: `aws/codebuild/standard:7.0` (Ubuntu) or newer.
- `TF_VERSION` in both files must match the Terraform version that wrote your state
  (your local `.terraform` recorded `1.17.2`). Keep Test and Apply identical.
- Variables: `.gitignore` excludes `*.tfvars`, so `terraform.tfvars` is **not** in the source.
  Supply inputs one of these ways:
  - `TF_VAR_vpc_cidr`, `TF_VAR_public_subnet_cidrs`, … as CodeBuild env vars, or
  - `parameter-store:` entries (see the commented block in `test.yml`), or
  - commit `infra/envs/dev/dev.tfvars.example`, copy to `dev.tfvars` in the build, and it is
    auto-picked by the `-var-file` guard in `test.yml`.

## CodeBuild service role — minimum IAM

The CodeBuild role needs: state backend access, permission to create the dev resources (directly,
or by assuming a dev deploy role), and CloudWatch Logs. Replace placeholders.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TfStateBucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketVersioning"],
      "Resource": "arn:aws:s3:::shopflow-global-resources-tfstate"
    },
    {
      "Sid": "TfStateObjectsAndNativeLock",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::shopflow-global-resources-tfstate/env/*"
    },
    {
      "Sid": "Logs",
      "Effect": "Allow",
      "Action": ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
      "Resource": "*"
    },
    {
      "Sid": "AssumeDevDeployRole",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::<DEV_ACCOUNT_ID>:role/shopflow-governance-deployer"
    }
  ]
}
```

- `use_lockfile=true` (S3-native locking, Terraform ≥ 1.10) means **no DynamoDB lock table** is
  needed — just the S3 object permissions above.
- If CodeBuild runs in the **central** account and deploys into dev by assuming
  `shopflow-governance-deployer`, keep the `AssumeDevDeployRole` statement and have the dev env's
  provider assume that role. If CodeBuild runs **in the dev account directly**, drop that statement
  and instead grant the VPC-creation permissions (ec2:*Vpc*, subnets, route tables, IGW, NAT, EIP,
  flow logs, the logs role) — scope them down from `ec2:*`.

## Prerequisites still open (pipeline will go green but deploy NOTHING until these exist)

The Test/Apply buildspecs are correct, but the dev stack is empty, so a run today plans "No
changes." To actually create the dev VPC you still need:

1. **`infra/modules/network`** — currently 0-byte stubs. Needs the VPC/subnets/route-tables/IGW/
   NAT/flow-logs module. Two ADR-level choices your ROADMAP (M1) flags: NAT **per-AZ vs single**,
   and **attach to the shared TGW/Cloud WAN vs standalone VPC**.
2. **`infra/envs/dev/main.tf`** — currently empty. Needs to call the network module with the dev
   `vpc_cidr` / subnet CIDRs.
3. **`infra/envs/dev/backend.tf`** — currently empty. Needs the S3 partial backend block
   (`terraform { backend "s3" {} }`) so `terraform init -backend-config=...` works in CI. Your dev
   `.terraform` already remembers bucket `shopflow-global-resources-tfstate`, key
   `env/dev/terraform.tfstate`, region `ca-central-1`.
4. **`infra/envs/dev/providers.tf` / `terraform.tf`** — provider + `required_providers` (aws ~> 5.92)
   for the dev stack, matching `infra/global`.

Items 1–4 are Terraform changes, which you asked me not to make unless necessary. They ARE
necessary for "VPC in dev," so I've left them for your go-ahead rather than inventing the module
design and the two ADR decisions for you.
