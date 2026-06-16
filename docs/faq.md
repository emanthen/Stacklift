# FAQ

Answers to the most common questions from GitHub Issues and the community.

---

## How do I run Django migrations?

Stacklift has a built-in migration runner. Set `enable_migration_task = true` on your `ecs-service` module call:

```hcl
module "ecs_web" {
  source = "../../modules/ecs-service"
  # ...
  enable_migration_task = true
}
```

This creates a second ECS task definition (`{project}-{env}-migrate-task`) with `command = ["python", "manage.py", "migrate", "--no-input"]`. The task uses the same image, IAM roles, secrets, and log group as your web service — no separate configuration needed.

The `deploy.yml` workflow runs migrations automatically before every deploy:

1. `aws ecs run-task` launches the migrate task
2. `aws ecs wait tasks-stopped` blocks until it finishes (up to 10 min)
3. If the exit code is non-zero, the pipeline fails — the web service is never updated with broken migrations

Set these GitHub Actions variables after `terraform apply`:

| Variable | Value |
|---|---|
| `ECS_MIGRATE_TASK_FAMILY` | `terraform output -raw migrate_task_definition_family` (from `module.ecs_web`) |
| `ECS_PRIVATE_SUBNETS` | Comma-separated private subnet IDs from `module.vpc.private_subnet_ids` |
| `ECS_TASK_SECURITY_GROUP` | `terraform output -raw task_security_group_id` (from `module.ecs_web`) |

---

## Why isn't my health check passing?

The most common causes:

**1. Your app isn't listening on the expected port.**  
Default is `8000`. Check that gunicorn/uvicorn binds to `0.0.0.0:8000`, not `127.0.0.1:8000`.

**2. The health check path doesn't return 200.**  
Default path is `/api/health/`. Add a minimal view that returns HTTP 200 with no database queries. For Django:
```python
# urls.py
from django.http import HttpResponse
urlpatterns = [
    path("api/health/", lambda r: HttpResponse("ok")),
    ...
]
```
For FastAPI:
```python
@app.get("/api/health/")
def health():
    return {"status": "ok"}
```

**3. The app needs more time to start.**  
Increase `health_check_grace_period_seconds` (default: 60). Django apps that run migrations on startup or load large models may need 90–120 seconds.

**4. Missing environment variables cause a crash on startup.**  
Check CloudWatch Logs: `aws logs tail /ecs/{project}-{env} --follow --no-cli-pager`. If the container exits before the health check interval, you'll see the error there.

---

## How do I update secrets after the first `terraform apply`?

Terraform writes placeholder values on first apply and then ignores changes. Update real values with the AWS CLI:

```bash
aws secretsmanager put-secret-value \
  --secret-id "myproject-prod/app/secrets" \
  --secret-string '{
    "SECRET_KEY": "your-real-django-secret-key",
    "RESEND_API_KEY": "re_your_real_key"
  }' \
  --no-cli-pager
```

The new values are picked up the next time ECS starts a task. To force an immediate reload, redeploy the service:

```bash
aws ecs update-service \
  --cluster myproject-prod-cluster \
  --service myproject-prod-web-service \
  --force-new-deployment \
  --no-cli-pager
```

ECS will drain old tasks and start new ones with the updated secrets.

---

## Can I use Stacklift without a custom domain?

Yes. Set `create_dns_record = false` in the `alb` module call:

```hcl
module "alb" {
  source = "../../modules/alb"
  # ...
  domain_name       = "placeholder.example.com"  # used for ACM cert only
  route53_zone_id   = ""                          # not needed when DNS creation is disabled
  create_dns_record = false
}
```

Your app will be accessible at the ALB DNS name (`terraform output alb_dns_name`). You can add a Route53 record later without re-creating the ALB.

Note: ACM certificate validation requires DNS ownership. If you disable DNS record creation, you must validate the certificate manually via the AWS Console.

---

## `terraform apply` fails on first run with a "dependency cycle" error

This happens when you wire `allowed_security_group_ids` on the `rds` module directly to an `ecs-service` output. Both modules need a value from the other before either exists.

**Fix**: Pass an empty list to `rds`, then add the ingress rule as a standalone resource after both modules are created:

```hcl
module "rds" {
  # ...
  allowed_security_group_ids = []  # intentionally empty — rule added below
}

module "ecs_web" {
  # ...
}

# Wire RDS → ECS after both SGs exist
resource "aws_security_group_rule" "ecs_to_rds" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.rds.rds_security_group_id
  source_security_group_id = module.ecs_web.task_security_group_id
  description              = "ECS tasks to RDS PostgreSQL"
}
```

This is already done for you in the `examples/django-celery-postgres` example.

---

## How do I scale up the ECS service?

After the first `terraform apply`, CI/CD owns the task definition and Terraform ignores `desired_count` drift. Scale via the AWS CLI:

```bash
aws ecs update-service \
  --cluster myproject-prod-cluster \
  --service myproject-prod-web-service \
  --desired-count 3 \
  --no-cli-pager
```

Or in the AWS Console: ECS → Clusters → your cluster → Services → Update → Desired tasks.

The count you set persists until you change it again. Running `terraform apply` will not reset it back to the value in `terraform.tfvars`.

To make Terraform manage scaling again (e.g. after an incident where you scaled down to 0), remove `desired_count` from the `ignore_changes` list in the `ecs-service` module — but be aware that every subsequent `terraform apply` will then enforce the tfvars value.

For autoscaling (scale in/out automatically based on CPU/memory), see the [Pro tier](pro-tier.md).
