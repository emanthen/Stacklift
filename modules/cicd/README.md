# stacklift/modules/cicd

Creates the AWS-side IAM infrastructure for GitHub Actions OIDC-based deployments — no long-lived AWS credentials stored in GitHub Secrets.

**What this module creates:**

- GitHub Actions OIDC provider in IAM (one per AWS account — set `create_oidc_provider = false` if it already exists)
- IAM role trusted by GitHub Actions for the specified org/repo/branch
- IAM policy: ECR push (scoped to the specific repository)
- IAM policy: ECS deploy — `RegisterTaskDefinition`, `UpdateService`, `DescribeServices`, `PassRole` (scoped to specific service + roles)
- IAM policy: Secrets Manager read (optional — only if `secret_arns` is set)
- IAM policy: S3 read/write (optional — only if `s3_bucket_arns` is set)

**No long-lived credentials.** GitHub Actions receives a short-lived OIDC token from GitHub, exchanges it for temporary AWS credentials via `sts:AssumeRoleWithWebIdentity`, and those credentials expire when the job ends.

---

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.5 |
| aws | ~> 5.0 |

---

## Usage

```hcl
module "cicd" {
  source = "../../modules/cicd"

  project_name = "mysaas"
  environment  = "prod"
  aws_region   = "us-east-1"

  # GitHub — must match your repo exactly
  github_org    = "acme-corp"
  github_repo   = "mysaas"
  github_branch = "main"

  # Set false if another module already created the OIDC provider in this account
  create_oidc_provider = true

  # From other modules
  ecr_repository_arn      = module.ecr.repository_arn
  ecs_cluster_arn         = module.ecs_cluster.cluster_arn
  ecs_service_arn         = module.ecs_service.service_id
  task_execution_role_arn = module.ecs_service.task_execution_role_arn
  task_role_arn           = module.ecs_service.task_role_arn
}
```

Reference the role ARN in your GitHub Actions workflow:

```yaml
# .github/workflows/deploy.yml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::123456789012:role/mysaas-prod-github-actions-role
    aws-region: us-east-1
```

---

## OIDC provider — one per account

⚠️ AWS allows exactly one OIDC provider per URL per account. If you already have `token.actions.githubusercontent.com` registered (check with `aws iam list-open-id-connect-providers --no-cli-pager`), set:

```hcl
create_oidc_provider = false
```

The module will look up the existing provider via `data` source. If you set `create_oidc_provider = true` and it already exists, `terraform apply` will fail with a conflict error.

---

## Trust policy

The IAM role trust condition uses `StringLike` on the OIDC `sub` claim:

```
repo:acme-corp/mysaas:ref:refs/heads/main
```

Only pushes to the `main` branch of `acme-corp/mysaas` can assume this role. PRs, other branches, forks, and other repos are denied.

**To allow any branch** (less secure — use for staging):
```hcl
github_sub_claim_override = "repo:acme-corp/mysaas:*"
```

**To allow GitHub Environments** (adds environment-scoped OIDC tokens):
```hcl
github_sub_claim_override = "repo:acme-corp/mysaas:environment:production"
```

---

## iam:PassRole

The ECS deploy policy includes `iam:PassRole` scoped to the task execution role and task role. This is required — without it, `ecs:RegisterTaskDefinition` fails with:

```
An error occurred (AccessDenied): User ... is not authorized to perform: iam:PassRole on resource: ...
```

If you see this error, verify both `task_execution_role_arn` and `task_role_arn` are passed correctly.

---

## GitHub Actions workflow

Minimal working workflow using this module's role:

```yaml
name: Deploy

on:
  push:
    branches: [main]

permissions:
  id-token: write   # required for OIDC token
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}

      - uses: aws-actions/amazon-ecr-login@v2
        id: login-ecr

      - name: Build and push
        env:
          REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          REPOSITORY: ${{ vars.ECR_REPOSITORY }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $REGISTRY/$REPOSITORY:$IMAGE_TAG -t $REGISTRY/$REPOSITORY:latest .
          docker push $REGISTRY/$REPOSITORY:$IMAGE_TAG
          docker push $REGISTRY/$REPOSITORY:latest

      - name: Fetch task definition
        run: |
          aws ecs describe-task-definition \
            --task-definition ${{ vars.ECS_TASK_FAMILY }} \
            --query taskDefinition \
            --no-cli-pager > task-def.json

      - uses: aws-actions/amazon-ecs-render-task-definition@v1
        id: render
        with:
          task-definition: task-def.json
          container-name: app
          image: ${{ steps.login-ecr.outputs.registry }}/${{ vars.ECR_REPOSITORY }}:${{ github.sha }}

      - uses: aws-actions/amazon-ecs-deploy-task-definition@v2
        with:
          task-definition: ${{ steps.render.outputs.task-definition }}
          service: ${{ vars.ECS_SERVICE }}
          cluster: ${{ vars.ECS_CLUSTER }}
          wait-for-service-stability: true
```

Set these GitHub Actions variables (`vars.*`) in your repo settings — not secrets, not hardcoded:

| Variable | Value |
|---|---|
| `AWS_ROLE_ARN` | `module.cicd.github_actions_role_arn` |
| `AWS_REGION` | `us-east-1` |
| `ECR_REPOSITORY` | `module.ecr.repository_name` |
| `ECS_TASK_FAMILY` | `module.ecs_service.task_definition_family` |
| `ECS_SERVICE` | `module.ecs_service.service_name` |
| `ECS_CLUSTER` | `module.ecs_cluster.cluster_name` |

---

## Inputs

| Name | Type | Default | Required | Description |
|---|---|---|---|---|
| `project_name` | `string` | — | yes | Prefix for all resource names. |
| `environment` | `string` | `"prod"` | no | `dev`, `staging`, or `prod`. |
| `aws_region` | `string` | `"us-east-1"` | no | AWS region. |
| `create_oidc_provider` | `bool` | `true` | no | Create the GitHub OIDC provider. Set `false` if already exists in this account. |
| `github_org` | `string` | — | yes | GitHub org or username. |
| `github_repo` | `string` | — | yes | GitHub repository name (without org). |
| `github_branch` | `string` | `"main"` | no | Branch allowed to assume the IAM role. |
| `github_sub_claim_override` | `string` | `null` | no | Override the full OIDC sub claim. Use for tag/environment/wildcard scenarios. |
| `ecr_repository_arn` | `string` | — | yes | ECR repository ARN from `ecr` module. |
| `ecs_cluster_arn` | `string` | — | yes | ECS cluster ARN from `ecs-cluster` module. |
| `ecs_service_arn` | `string` | — | yes | ECS service ARN from `ecs-service` module. |
| `task_execution_role_arn` | `string` | — | yes | Task execution role ARN for `iam:PassRole`. |
| `task_role_arn` | `string` | `null` | no | Task role ARN for `iam:PassRole`. |
| `secret_arns` | `list(string)` | `[]` | no | Secrets Manager ARNs for deploy-time reads (optional). |
| `s3_bucket_arns` | `list(string)` | `[]` | no | S3 bucket ARNs for static asset uploads (optional). |
| `tags` | `map(string)` | `{}` | no | Extra tags merged onto all resources. |

---

## Outputs

| Name | Description |
|---|---|
| `github_actions_role_arn` | IAM role ARN for `role-to-assume` in the workflow. |
| `github_actions_role_name` | IAM role name. |
| `oidc_provider_arn` | OIDC provider ARN. |
| `ecr_push_policy_arn` | ECR push IAM policy ARN. |
| `ecs_deploy_policy_arn` | ECS deploy IAM policy ARN. |

---

## Cost estimate

All IAM resources (roles, policies, OIDC provider) are **free**. GitHub Actions OIDC authentication has no AWS cost.
