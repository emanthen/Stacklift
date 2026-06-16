# stacklift/modules/ecr

Creates a production-grade ECR repository for Docker images with lifecycle management, vulnerability scanning, and access policies.

**What this module creates:**

- ECR repository with AES-256 encryption at rest
- Lifecycle policy — untagged images expire after 1 day, last N tagged images retained (default: 10)
- Repository policy — scoped push access for GitHub Actions role, pull access for ECS task execution role
- Image scanning on push via AWS Basic Scanning (free)

**What it does NOT create:**

- The GitHub Actions IAM role — that lives in the `cicd` module
- The ECS task execution role — that lives in the `ecs-service` module

Wire those outputs into this module after they exist and Terraform resolves the ordering.

---

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.5 |
| aws | ~> 5.0 |

---

## Usage

```hcl
module "ecr" {
  source = "../../modules/ecr"

  project_name = "mysaas"
  environment  = "prod"
  aws_region   = "us-east-1"

  scan_on_push     = true
  keep_image_count = 10

  # Populated after cicd and ecs-service modules exist
  github_actions_role_arns = [module.cicd.github_actions_role_arn]
  task_execution_role_arns = [module.ecs_service.task_execution_role_arn]
}
```

Pass the repository URL to the `ecs-service` module and into CI/CD:

```hcl
module "ecs_service" {
  source = "../../modules/ecs-service"

  image_url = "${module.ecr.repository_url}:latest"
  ...
}
```

In GitHub Actions:

```yaml
- name: Build and push
  env:
    ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
    IMAGE_TAG: ${{ github.sha }}
  run: |
    docker build -t $ECR_REGISTRY/${{ vars.ECR_REPOSITORY }}:$IMAGE_TAG .
    docker push $ECR_REGISTRY/${{ vars.ECR_REPOSITORY }}:$IMAGE_TAG
```

---

## Lifecycle policy

| Rule | Behaviour |
|---|---|
| Untagged images | Expired after **1 day** |
| Tagged images (`v*`, `sha-*`, `latest`) | Keep last **10** (configurable via `keep_image_count`) |

Untagged images accumulate from `docker build` runs that never get tagged and pushed cleanly. The 1-day rule prevents storage cost creep at $0.10/GB/month.

---

## Image tag strategy

`MUTABLE` (default) — `:latest` and `:sha-<hash>` tags can be re-pushed. Standard for most Django/FastAPI CI pipelines where the deploy workflow always uses the commit SHA and also updates `:latest`.

`IMMUTABLE` — every tag is write-once. More secure (no silent overwrites), but CI must always push a unique tag and can never re-tag an existing image. Requires your deploy workflow to never reuse a tag.

---

## Inputs

| Name | Type | Default | Required | Description |
|---|---|---|---|---|
| `project_name` | `string` | — | yes | Prefix for all resource names. |
| `environment` | `string` | `"prod"` | no | `dev`, `staging`, or `prod`. |
| `aws_region` | `string` | `"us-east-1"` | no | AWS region. Used in the registry URL output. |
| `repository_name` | `string` | `null` | no | Override repository name. Defaults to `{project}-{env}`. |
| `image_tag_mutability` | `string` | `"MUTABLE"` | no | `MUTABLE` or `IMMUTABLE`. |
| `scan_on_push` | `bool` | `true` | no | Enable AWS Basic Scanning on every push. |
| `keep_image_count` | `number` | `10` | no | Number of tagged images to retain. |
| `github_actions_role_arns` | `list(string)` | `[]` | no | IAM role ARNs for GitHub Actions. Receives push + pull via repository policy. |
| `task_execution_role_arns` | `list(string)` | `[]` | no | IAM role ARNs for ECS task execution. Receives pull-only via repository policy. |
| `tags` | `map(string)` | `{}` | no | Extra tags merged onto all resources. |

---

## Outputs

| Name | Description |
|---|---|
| `repository_url` | Full ECR URL including repository name. Use in `ecs-service` and CI/CD. |
| `repository_arn` | ARN of the repository. Pass to `cicd` module as `ecr_repository_arn`. |
| `repository_name` | Repository name only. |
| `registry_id` | AWS account ID owning the registry. |
| `registry_url` | Base registry URL without repository name. Use for `docker login`. |

---

## Cost estimate

| Resource | Cost |
|---|---|
| ECR storage | $0.10/GB/month |
| Data transfer in (push) | Free |
| Data transfer out to ECS (same region) | Free |
| Image scanning (Basic) | Free |

10 images of a typical Django/FastAPI container (~300MB compressed) = ~3GB = ~$0.30/month. The lifecycle policy keeps this bounded.
