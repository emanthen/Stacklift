# Example: Django + Celery + PostgreSQL on AWS

A complete, production-grade deployment of a Django application with a Celery worker and PostgreSQL on AWS using Stacklift modules.

**What gets created:**

| Resource | Module | Notes |
|---|---|---|
| VPC, 2 public + 2 private subnets, NAT | `vpc` | Single NAT (~$32/mo) |
| ECR repository | `ecr` | Lifecycle policy: keep 10 images |
| ECS cluster | `ecs-cluster` | Fargate + Fargate Spot, Container Insights |
| App secrets (SECRET_KEY, API keys) | `secrets` | Placeholders on first apply |
| RDS PostgreSQL 15 | `rds` | db.t3.micro, gp3, encrypted, deletion protected |
| ALB with HTTPS + ACM cert | `alb` | DNS validation, HTTP→HTTPS redirect |
| ECS web service (Django/gunicorn) | `ecs-service` | 256 CPU / 512MB, private subnet |
| ECS Celery worker | `ecs-service` | 256 CPU / 512MB, no ALB |
| GitHub Actions OIDC + IAM role | `cicd` | No long-lived credentials |

**Estimated cost:** ~$80–100/month for a minimal single-task production setup.

---

## Pre-requisites

- AWS CLI configured: `aws sts get-caller-identity --no-cli-pager`
- Terraform >= 1.5: `terraform --version`
- Docker running: `docker info`
- A Route53 public hosted zone for your domain
- A GitHub repository for your Django project

---

## Step 1 — Create the S3 backend

Run once per AWS account. Skip if already done.

```powershell
# D:\your-project\infra

aws s3api create-bucket `
  --bucket stacklift-tfstate-mysaas `
  --region us-east-1 `
  --no-cli-pager

aws s3api put-bucket-versioning `
  --bucket stacklift-tfstate-mysaas `
  --versioning-configuration Status=Enabled `
  --no-cli-pager

aws s3api put-bucket-encryption `
  --bucket stacklift-tfstate-mysaas `
  --server-side-encryption-configuration '{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"AES256\"}}]}' `
  --no-cli-pager

aws dynamodb create-table `
  --table-name stacklift-tfstate-lock `
  --attribute-definitions AttributeName=LockID,AttributeType=S `
  --key-schema AttributeName=LockID,KeyType=HASH `
  --billing-mode PAY_PER_REQUEST `
  --region us-east-1 `
  --no-cli-pager
```

## Step 2 — Configure variables

```powershell
# Copy and edit the example vars file
Copy-Item terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` — at minimum set:
- `project_name`
- `domain_name` and `route53_zone_id`
- `github_org` and `github_repo`

Find your Route53 zone ID:
```powershell
aws route53 list-hosted-zones --no-cli-pager
```

## Step 3 — Create the backend config

Create `backend.tfvars` (do not commit):
```
bucket         = "stacklift-tfstate-mysaas"
key            = "prod/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "stacklift-tfstate-lock"
encrypt        = true
```

## Step 4 — Initialise and deploy

```powershell
terraform init -backend-config=backend.tfvars
terraform plan
terraform apply
```

`terraform apply` takes approximately **8–12 minutes** on first run:
- ACM certificate DNS validation: ~2–3 minutes
- RDS instance creation: ~5–7 minutes
- ECS service stabilisation: ~1–2 minutes

## Step 5 — Update secrets

After `terraform apply`, replace the placeholder values with real secrets:

```powershell
aws secretsmanager put-secret-value `
  --secret-id "mysaas-prod/app/secrets" `
  --secret-string '{\"SECRET_KEY\":\"your-real-django-secret-key\",\"RESEND_API_KEY\":\"re_your_key\",\"ALLOWED_HOSTS\":\"api.mysaas.com\",\"CORS_ORIGINS\":\"https://api.mysaas.com\"}' `
  --no-cli-pager
```

Generate a Django SECRET_KEY:
```powershell
python -c "import secrets; print(secrets.token_urlsafe(50))"
```

## Step 6 — Set GitHub Actions variables

In your GitHub repo → **Settings → Secrets and variables → Actions → Variables**, add:

| Variable | Value (from terraform output) |
|---|---|
| `AWS_ROLE_ARN` | `terraform output -raw github_actions_role_arn` |
| `AWS_REGION` | `us-east-1` |
| `ECR_REPOSITORY` | `terraform output -raw ecr_repository_name` |
| `ECS_CLUSTER` | `terraform output -raw ecs_cluster_name` |
| `ECS_WEB_SERVICE` | `terraform output -raw ecs_web_service_name` |
| `ECS_CELERY_SERVICE` | `terraform output -raw ecs_celery_service_name` |
| `ECS_TASK_FAMILY` | `terraform output -raw ecs_web_task_family` |
| `ECS_CELERY_TASK_FAMILY` | `terraform output -raw ecs_celery_task_family` |

```powershell
# Get all output values at once
terraform output --no-cli-pager
```

## Step 7 — Push your first image

Make sure your Django project has a `Dockerfile` and a health check endpoint:

```python
# urls.py
from django.http import HttpResponse
path("api/health/", lambda request: HttpResponse("ok")),
```

Then push to main:
```bash
git push origin main
```

The workflow in `.github/workflows/deploy.yml` will:
1. Build the Docker image
2. Push to ECR
3. Update the ECS task definition
4. Roll out to both the web service and Celery worker
5. Wait for service stability (rolls back automatically on failure)

## Step 8 — Verify

```powershell
# Confirm ALB returns 200 on the health endpoint
curl -I https://api.mysaas.com/api/health/

# Check ECS service is stable
aws ecs describe-services `
  --cluster mysaas-prod-cluster `
  --services mysaas-web-prod-service `
  --query "services[0].{status:status,running:runningCount,desired:desiredCount}" `
  --no-cli-pager

# Tail CloudWatch logs
aws logs tail /stacklift/mysaas/prod --follow --no-cli-pager
```

---

## Outputs reference

After `terraform apply`, run `terraform output` to see:

```
alb_dns_name              = "mysaas-prod-alb-123456.us-east-1.elb.amazonaws.com"
domain_name               = "api.mysaas.com"
ecr_repository_url        = "123456789.dkr.ecr.us-east-1.amazonaws.com/mysaas-prod"
ecr_repository_name       = "mysaas-prod"
ecs_cluster_name          = "mysaas-prod-cluster"
ecs_web_service_name      = "mysaas-web-prod-service"
ecs_celery_service_name   = "mysaas-celery-prod-service"
ecs_web_task_family       = "mysaas-web-prod-task"
ecs_celery_task_family    = "mysaas-celery-prod-task"
github_actions_role_arn   = "arn:aws:iam::123456789:role/mysaas-prod-github-actions-role"
rds_endpoint              = "mysaas-prod-rds.xxxxxx.us-east-1.rds.amazonaws.com:5432"
db_secret_arn             = "arn:aws:secretsmanager:..."
app_secret_arn            = "arn:aws:secretsmanager:..."
log_group_name            = "/stacklift/mysaas/prod"
```

---

## Destroying this example

⚠️ RDS has two destruction safeguards. Remove them in order:

**1.** Disable `deletion_protection` in `main.tf`:
```hcl
deletion_protection = false
```
Run `terraform apply`.

**2.** Comment out `lifecycle { prevent_destroy = true }` in `modules/rds/main.tf`. Run `terraform apply`.

**3.** Now run:
```powershell
terraform destroy
```

All other resources (ALB, ECS, ECR, VPC, Secrets) destroy cleanly in one pass.
