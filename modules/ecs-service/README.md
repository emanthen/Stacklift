# stacklift/modules/ecs-service

Creates a Fargate ECS service — task definition, IAM roles, security group, and ALB registration — for Django and FastAPI applications.

**What this module creates:**

- ECS task definition (Fargate, awsvpc, awslogs driver)
- ECS service with rolling deployment, circuit breaker, and automatic rollback
- IAM task execution role — ECR pull, CloudWatch Logs write, Secrets Manager read
- IAM task role — app runtime role, empty by default, extend via `task_role_policy_arns`
- Security group — inbound on `container_port` from ALB SG only, all outbound

**Key behaviours:**

- `assign_public_ip = false` — tasks run in private subnets, egress via NAT
- `ignore_changes = [task_definition, desired_count]` — CI/CD pipeline owns both after initial deploy; Terraform won't revert them
- Deployment circuit breaker enabled with automatic rollback — a failed deploy rolls back to the previous task definition revision automatically
- Secrets injected at task startup via ECS + Secrets Manager integration — never in plaintext env vars or `.env` files

---

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.5 |
| aws | ~> 5.0 |

---

## Usage

```hcl
module "ecs_service" {
  source = "../../modules/ecs-service"

  project_name = "mysaas"
  environment  = "prod"
  aws_region   = "us-east-1"

  # From ecs-cluster
  cluster_id     = module.ecs_cluster.cluster_id
  log_group_name = module.ecs_cluster.log_group_name

  # From vpc
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # From alb
  alb_target_group_arn  = module.alb.target_group_arn
  alb_security_group_id = module.alb.alb_security_group_id

  # From ecr
  image_url = "${module.ecr.repository_url}:latest"

  cpu           = 256
  memory        = 512
  desired_count = 1
  container_port = 8000
  health_check_path = "/api/health/"

  # Plaintext env vars (non-secret config)
  environment_variables = {
    DJANGO_SETTINGS_MODULE = "config.settings.production"
    AWS_REGION             = "us-east-1"
    PORT                   = "8000"
  }

  # Secrets — each key becomes an env var in the container
  secrets = {
    "DATABASE_URL"   = "${module.rds.db_secret_arn}:DATABASE_URL::"
    "SECRET_KEY"     = "${module.app_secrets.secret_arn}:SECRET_KEY::"
    "RESEND_API_KEY" = "${module.app_secrets.secret_arn}:RESEND_API_KEY::"
  }

  # Base ARNs for IAM GetSecretValue permission
  secret_arns = [
    module.rds.db_secret_arn,
    module.app_secrets.secret_arn,
  ]
}
```

Pass outputs to other modules:

```hcl
module "rds" {
  ...
  allowed_security_group_ids = [module.ecs_service.task_security_group_id]
}

module "ecr" {
  ...
  task_execution_role_arns = [module.ecs_service.task_execution_role_arn]
}

module "cicd" {
  ...
  ecs_service_arn = module.ecs_service.service_id
}
```

---

## Secrets injection

ECS injects secrets directly from Secrets Manager at task startup. The container sees them as plain environment variables — no SDK calls, no boto3.

**Full JSON secret as one env var:**
```hcl
secrets = {
  "DB_CREDENTIALS" = module.rds.db_secret_arn
}
# Container gets: DB_CREDENTIALS='{"host":"...","password":"...","DATABASE_URL":"..."}'
```

**Individual keys from a JSON secret (recommended):**
```hcl
secrets = {
  "DATABASE_URL" = "${module.rds.db_secret_arn}:DATABASE_URL::"
  "PASSWORD"     = "${module.rds.db_secret_arn}:password::"
}
# Container gets: DATABASE_URL="postgres://..." and PASSWORD="secret123"
```

The `:KEY::` suffix syntax tells ECS to extract a single key from the JSON blob. The trailing `::` means latest version, no stage.

---

## Health check

The container health check polls `http://localhost:{container_port}{health_check_path}` every 30 seconds with a 60-second start period. The ALB also independently health-checks registered targets.

**Django** — add a minimal view:
```python
# urls.py
path("api/health/", lambda request: HttpResponse("ok"), name="health"),
```

**FastAPI** — add a route:
```python
@app.get("/api/health/")
def health(): return {"status": "ok"}
```

The health check uses `curl`. If your base image doesn't include curl, either install it in your Dockerfile or change `health_check_path` to `null` and rely solely on the ALB health check.

---

## Deployment behaviour

After `terraform apply` creates the service, all subsequent task definition updates happen through CI/CD:

```yaml
# GitHub Actions (from the cicd module's deploy.yml)
- uses: aws-actions/amazon-ecs-render-task-definition@v1
  with:
    task-definition: task-def.json
    container-name: app
    image: ${{ env.ECR_REGISTRY }}/${{ env.ECR_REPOSITORY }}:${{ github.sha }}

- uses: aws-actions/amazon-ecs-deploy-task-definition@v2
  with:
    task-definition: ${{ steps.render.outputs.task-definition }}
    service: mysaas-prod-service
    cluster: mysaas-prod-cluster
    wait-for-service-stability: true
```

Terraform will not revert these updates on the next `terraform apply` because `task_definition` is in `ignore_changes`.

---

## Celery worker (no ALB)

For a Celery worker service, omit ALB variables and set `alb_target_group_arn = null`:

```hcl
module "celery_worker" {
  source = "../../modules/ecs-service"

  alb_target_group_arn  = null
  alb_security_group_id = null
  container_port        = 0   # unused — set any value, no port mapping needed

  environment_variables = {
    CELERY_WORKER = "true"
  }
  ...
}
```

---

## Inputs

| Name | Type | Default | Required | Description |
|---|---|---|---|---|
| `project_name` | `string` | — | yes | Prefix for all resource names. |
| `environment` | `string` | `"prod"` | no | `dev`, `staging`, or `prod`. |
| `aws_region` | `string` | `"us-east-1"` | no | AWS region for awslogs driver. |
| `cluster_id` | `string` | — | yes | ECS cluster ID from `ecs-cluster` module. |
| `log_group_name` | `string` | — | yes | CloudWatch log group from `ecs-cluster` module. |
| `vpc_id` | `string` | — | yes | VPC ID from `vpc` module. |
| `private_subnet_ids` | `list(string)` | — | yes | Private subnets from `vpc` module. |
| `alb_target_group_arn` | `string` | `null` | no | ALB target group ARN from `alb` module. |
| `alb_security_group_id` | `string` | `null` | no | ALB SG ID from `alb` module. |
| `image_url` | `string` | — | yes | Full ECR image URL with tag. |
| `cpu` | `number` | `256` | no | Fargate CPU units (256/512/1024/2048/4096). |
| `memory` | `number` | `512` | no | Fargate memory in MB. |
| `desired_count` | `number` | `1` | no | Initial task count. CI/CD manages this after first deploy. |
| `container_port` | `number` | `8000` | no | Port the container listens on. |
| `health_check_path` | `string` | `"/api/health/"` | no | HTTP path for container health check. |
| `health_check_grace_period_seconds` | `number` | `60` | no | Grace period before ALB health checks start. |
| `environment_variables` | `map(string)` | `{}` | no | Plaintext env vars. Never put secrets here. |
| `secrets` | `map(string)` | `{}` | no | Secret env vars. Key = var name, value = SM ARN with optional `:KEY::` suffix. |
| `secret_arns` | `list(string)` | `[]` | no | Base SM ARNs for IAM GetSecretValue permission. |
| `task_role_policy_arns` | `list(string)` | `[]` | no | IAM policies for the app runtime role (S3, SQS, SES, etc.). |
| `tags` | `map(string)` | `{}` | no | Extra tags merged onto all resources. |

---

## Outputs

| Name | Description |
|---|---|
| `service_name` | ECS service name. Pass to `cicd` module. |
| `service_id` | ECS service ARN. Pass to `cicd` module as `ecs_service_arn`. |
| `task_definition_arn` | Initial task definition ARN (Terraform-managed revision). |
| `task_definition_family` | Task definition family. Used in CI/CD to fetch current def before rendering. |
| `task_execution_role_arn` | Execution role ARN. Pass to `ecr` as `task_execution_role_arns`. |
| `task_execution_role_name` | Execution role name. |
| `task_role_arn` | Task role ARN (app runtime). |
| `task_role_name` | Task role name. |
| `task_security_group_id` | ECS tasks SG ID. Pass to `rds` as `allowed_security_group_ids`. |

---

## Cost estimate

| Resource | Cost |
|---|---|
| Fargate 256 CPU / 512MB, 1 task, 24/7 | ~$11–13/mo |
| Fargate 256 CPU / 512MB, 2 tasks, 24/7 | ~$22–26/mo |
| IAM roles | Free |
| Security group | Free |

Fargate pricing: $0.04048/vCPU/hr + $0.004445/GB/hr (us-east-1). Verify at [https://aws.amazon.com/fargate/pricing/](https://aws.amazon.com/fargate/pricing/).
