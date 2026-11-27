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

## Variables — where each one comes from

Split by sensitivity:

- **Non-secret config, committed for PR review** — `vpc_cidr`, `public_subnet_cidrs`,
  `private_subnet_cidrs`, `region`, `az_count` live in `infra/envs/dev/dev.auto.tfvars`.
  Terraform auto-loads `*.auto.tfvars`, so it works locally and in CI with no `-var-file`. A
  `.gitignore` exception (`!*.auto.tfvars`) keeps this file tracked even though `*.tfvars` is
  ignored. **Never put account IDs or secrets in an `*.auto.tfvars` file.**
- **`account_ids` — kept out of GitHub, in SSM.** Stored at `/shopflow/account_ids` as one map
  for all envs. The buildspecs read it via their `parameter-store` block and expose it as
  `TF_VAR_account_ids`, which Terraform picks up automatically. (Your `providers.tf` uses it to
  assume `shopflow-governance-deployer` in each spoke.)

### Create the SSM parameter BEFORE the first run

CodeBuild resolves `parameter-store` entries at build start — if the parameter is missing, the
build fails immediately. Create it once (out-of-band; it is not managed by the env stack that
consumes it). Account IDs are not credentials, so a plain `String` is fine:

```bash
aws ssm put-parameter \
  --name /shopflow/account_ids \
  --type String \
  --value '{"dev":"<DEV_ID>","stage":"<STAGE_ID>","prod":"<PROD_ID>"}' \
  --region ca-central-1
# fill the IDs from your local infra/envs/dev/terraform.tfvars (which stays gitignored)
```

Local runs are unaffected: your gitignored `terraform.tfvars` still supplies `account_ids`
locally. (You can trim it to just `account_ids` now that CIDRs live in `dev.auto.tfvars`.)

## CodeBuild service role — minimum IAM

The CodeBuild role needs: state backend access, the SSM parameter, permission to create the dev
resources (directly, or by assuming a dev deploy role), and CloudWatch Logs. Replace placeholders.

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
      "Sid": "ReadAccountIdsParam",
      "Effect": "Allow",
      "Action": ["ssm:GetParameters"],
      "Resource": "arn:aws:ssm:ca-central-1:<CENTRAL_ACCOUNT_ID>:parameter/shopflow/account_ids"
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

- `String` SSM param → no `kms:Decrypt` needed. If you switch it to `SecureString`, add
  `kms:Decrypt` on the key.
- `use_lockfile=true` (S3-native locking, Terraform ≥ 1.10) means **no DynamoDB lock table** is
  needed — just the S3 object permissions above.
- `AssumeDevDeployRole` matches your `dev/providers.tf`, which assumes
  `arn:aws:iam::<DEV_ACCOUNT_ID>:role/shopflow-governance-deployer`. That deployer role must exist
  in the dev account (from `infra/bootstrap`) with the VPC-creation permissions.

## Still open before a green end-to-end run

The dev VPC module is written — it lives on the **`dev-vpc` branch** (commit `cf2ffa7`,
"feat(network): dev VPC via module"), not yet on `main`. To get a run that creates the VPC:

1. **Merge the module to `main`.** Open a PR `dev-vpc` → `main`. Include `buildspec/` and
   `infra/envs/dev/dev.auto.tfvars` in it (commit them onto `dev-vpc` first so one PR carries
   module + pipeline + config). Expect a modify/delete conflict on the old
   `.github/workflows/infra-*.yml` — resolve by keeping them deleted (moving to CodePipeline).
2. **Create the SSM parameter** `/shopflow/account_ids` (command above).
3. **Grant the CodeBuild role** the IAM above (state bucket, SSM param, assume deployer role).
4. **Confirm the pipeline has an Apply stage** wired to `buildspec/apply.yml` with the Test
   action's output artifact as its input — otherwise it plans but never applies.

Items 2–4 are in your AWS account (CodePipeline / IAM / SSM), which this repo does not manage;
set them once by hand or add them to `infra/bootstrap`.
