# Deploy a Django SaaS to AWS in 30 Minutes

*No Heroku. No Elastic Beanstalk. Production infrastructure you actually own.*

I've been running a Django SaaS ([KibaPay](https://kibapay.com)) on AWS for over a year. This is the exact stack — VPC, RDS, ECS Fargate, ALB, Secrets Manager, GitHub Actions — distilled into reusable Terraform modules you can drop into any project.

By the end of this post your Django app will be running on:
- **ECS Fargate** — containerized, auto-restarting, no EC2 to manage
- **RDS PostgreSQL 15** — encrypted, automated backups, private subnet
- **ALB + ACM** — HTTPS termination, free SSL certificate, HTTP→HTTPS redirect
- **Secrets Manager** — `DATABASE_URL` and all secrets injected at startup, zero plaintext
- **GitHub Actions** — push to main, CI/CD builds and deploys automatically

Everything Terraform. Everything auditable. Nothing locked to a platform.

---

## What this is not

This is not a "deploy to AWS in 5 clicks" tutorial. Those abstractions rot when you need to debug a hung container at 2am. This is the real stack, real Terraform, real IAM — the kind of infrastructure you'd be proud to hand off to a senior DevOps engineer.

---

## Pre-requisites

You need four things before starting:

```powershell
# 1. AWS CLI — configured with an IAM user or role
aws sts get-caller-identity --no-cli-pager
# Expected: JSON with your account ID

# 2. Terraform >= 1.5
terraform --version
# Expected: Terraform v1.x.x

# 3. Docker — running
docker info
# Expected: Server info block

# 4. A Route53 public hosted zone for your domain
aws route53 list-hosted-zones --no-cli-pager
# Expected: Your domain in the list
```

If you don't have a Route53 zone, transfer or delegate your domain to Route53. AWS charges $0.50/month per hosted zone.

---

## Step 0 — Clone Stacklift

```bash
git clone https://github.com/emanthen/stacklift
cd stacklift/examples/django-celery-postgres
```

This directory contains a complete working example that composes all 8 Stacklift modules. We'll fill in your values and apply it.

---

## Step 1 — S3 backend for Terraform state (5 minutes)

Terraform state must live somewhere safe. S3 + DynamoDB is the standard. Run this once per AWS account:

```powershell
# Replace mysaas with your project name
$PROJECT = "mysaas"
$REGION  = "us-east-1"

# Create the bucket
aws s3api create-bucket `
  --bucket "stacklift-tfstate-$PROJECT" `
  --region $REGION `
  --no-cli-pager

# Enable versioning — lets you recover from a bad apply
aws s3api put-bucket-versioning `
  --bucket "stacklift-tfstate-$PROJECT" `
  --versioning-configuration Status=Enabled `
  --no-cli-pager

# Encrypt at rest
aws s3api put-bucket-encryption `
  --bucket "stacklift-tfstate-$PROJECT" `
  --server-side-encryption-configuration '{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"AES256\"}}]}' `
  --no-cli-pager

# DynamoDB table for state locking — prevents concurrent applies
aws dynamodb create-table `
  --table-name stacklift-tfstate-lock `
  --attribute-definitions AttributeName=LockID,AttributeType=S `
  --key-schema AttributeName=LockID,KeyType=HASH `
  --billing-mode PAY_PER_REQUEST `
  --region $REGION `
  --no-cli-pager
```

Then create `backend.tfvars` (do not commit this file):

```hcl
bucket         = "stacklift-tfstate-mysaas"
key            = "prod/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "stacklift-tfstate-lock"
encrypt        = true
```

---

## Step 2 — Configure your variables (3 minutes)

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and set these at minimum:

```hcl
project_name = "mysaas"          # lowercase, hyphens ok, no spaces
environment  = "prod"
aws_region   = "us-east-1"

domain_name     = "api.mysaas.com"
route53_zone_id = "Z1234567890ABCDEFGHIJ"  # from aws route53 list-hosted-zones

github_org    = "your-github-username"
github_repo   = "mysaas"
github_branch = "main"
```

Get your Route53 zone ID:

```powershell
aws route53 list-hosted-zones `
  --query "HostedZones[*].{Name:Name,Id:Id}" `
  --output table `
  --no-cli-pager
```

---

## Step 3 — Initialise Terraform (1 minute)

```powershell
terraform init -backend-config=backend.tfvars
```

Expected output:

```
Initializing the backend...
Successfully configured the backend "s3"!

Initializing provider plugins...
- Installing hashicorp/aws v5.x.x...
- Installing hashicorp/random v3.x.x...

Terraform has been successfully initialized!
```

---

## Step 4 — Plan (2 minutes)

```powershell
terraform plan
```

You'll see approximately 60–70 resources planned. Scan for anything unexpected. The plan is read-only — nothing is created yet.

Key resources to verify in the plan:

```
+ aws_vpc.this                                (10.0.0.0/16)
+ aws_db_instance.this                        (db.t3.micro, postgres 15)
+ aws_lb.this                                 (internet-facing)
+ aws_acm_certificate.this                    (api.mysaas.com)
+ aws_ecs_cluster.this
+ aws_ecs_task_definition.this                (256 CPU, 512 MB)
+ aws_ecs_service.this                        (desired: 1)
+ aws_iam_role.github_actions                 (OIDC trust)
+ aws_secretsmanager_secret.this              (mysaas-prod/app/secrets)
+ aws_secretsmanager_secret.db                (mysaas-prod/rds/credentials)
```

---

## Step 5 — Apply (10 minutes)

```powershell
terraform apply
```

Type `yes` when prompted.

The apply runs in three waves:

**Wave 1 (~30 seconds):** VPC, subnets, IGW, NAT, ECR, ECS cluster, Secrets Manager secrets, RDS security group, ALB security group.

**Wave 2 (~7 minutes):** RDS instance (takes the longest — AWS is provisioning the database), ACM certificate DNS validation (~2 minutes), ALB, ECS service.

**Wave 3 (~1 minute):** GitHub Actions OIDC provider, IAM roles, security group rules wiring ECS to RDS.

While it runs, you'll see lines like:

```
aws_db_instance.this: Still creating... [5m10s elapsed]
aws_acm_certificate_validation.this: Still creating... [1m20s elapsed]
```

This is normal. RDS provisioning takes 5–8 minutes on first creation.

When it finishes:

```
Apply complete! Resources: 68 added, 0 changed, 0 destroyed.

Outputs:

alb_dns_name            = "mysaas-prod-alb-1234567.us-east-1.elb.amazonaws.com"
domain_name             = "api.mysaas.com"
ecr_repository_url      = "123456789012.dkr.ecr.us-east-1.amazonaws.com/mysaas-prod"
github_actions_role_arn = "arn:aws:iam::123456789012:role/mysaas-prod-github-actions-role"
log_group_name          = "/stacklift/mysaas/prod"
...
```

Save this output. You'll need the values for the next steps.

---

## Step 6 — Set your real secrets (2 minutes)

Terraform wrote placeholder values to Secrets Manager on first apply. Replace them now:

**Generate a Django SECRET_KEY:**

```powershell
python -c "import secrets; print(secrets.token_urlsafe(50))"
# Output: something like: 3Kp9mN2xL8qR7vT0wZ5sY1uJ6nB4cF...
```

**Write real values to Secrets Manager:**

```powershell
aws secretsmanager put-secret-value `
  --secret-id "mysaas-prod/app/secrets" `
  --secret-string ('{' +
    '"SECRET_KEY":"your-generated-key-here",' +
    '"RESEND_API_KEY":"re_your_resend_key",' +
    '"ALLOWED_HOSTS":"api.mysaas.com",' +
    '"CORS_ORIGINS":"https://app.mysaas.com"' +
  '}') `
  --no-cli-pager
```

The RDS credentials (including `DATABASE_URL`) were automatically written during the RDS module apply. Verify they're there:

```powershell
aws secretsmanager get-secret-value `
  --secret-id "mysaas-prod/rds/credentials" `
  --query SecretString `
  --output text `
  --no-cli-pager
```

Expected output — a JSON blob with `host`, `port`, `dbname`, `username`, `password`, and `DATABASE_URL`.

---

## Step 7 — Prepare your Django project (5 minutes)

Your project needs three things to work with this stack.

### Health check endpoint

```python
# your_project/urls.py
from django.http import HttpResponse
from django.urls import path

urlpatterns = [
    path("api/health/", lambda request: HttpResponse("ok"), name="health"),
    # ... your other routes
]
```

The ALB polls this endpoint every 30 seconds. If it stops returning 200, ECS stops sending traffic to that task.

### Production settings

```python
# config/settings/production.py
import os

DEBUG = False
SECRET_KEY = os.environ["SECRET_KEY"]
ALLOWED_HOSTS = os.environ.get("ALLOWED_HOSTS", "").split(",")

# Database — DATABASE_URL injected from Secrets Manager at startup
import dj_database_url
DATABASES = {"default": dj_database_url.parse(os.environ["DATABASE_URL"])}

# Static files — serve via WhiteNoise or S3
STATIC_ROOT = "/app/staticfiles"
```

### Dockerfile

```dockerfile
FROM python:3.12-slim

WORKDIR /app

# Install curl for ECS container health check
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN python manage.py collectstatic --noinput

EXPOSE 8000

CMD ["gunicorn", "config.wsgi:application", \
     "--bind", "0.0.0.0:8000", \
     "--workers", "2", \
     "--timeout", "30", \
     "--access-logfile", "-"]
```

---

## Step 8 — Configure GitHub Actions (3 minutes)

In your GitHub repo: **Settings → Secrets and variables → Actions → Variables**

Add these (use values from `terraform output`):

| Variable name | Value |
|---|---|
| `AWS_ROLE_ARN` | `arn:aws:iam::123456789012:role/mysaas-prod-github-actions-role` |
| `AWS_REGION` | `us-east-1` |
| `ECR_REPOSITORY` | `mysaas-prod` |
| `ECS_CLUSTER` | `mysaas-prod-cluster` |
| `ECS_WEB_SERVICE` | `mysaas-web-prod-service` |
| `ECS_CELERY_SERVICE` | `mysaas-celery-prod-service` |
| `ECS_TASK_FAMILY` | `mysaas-web-prod-task` |
| `ECS_CELERY_TASK_FAMILY` | `mysaas-celery-prod-task` |

Copy the `deploy.yml` from this example into your Django project:

```bash
mkdir -p .github/workflows
cp path/to/stacklift/examples/django-celery-postgres/.github/workflows/deploy.yml \
   .github/workflows/deploy.yml
```

---

## Step 9 — First deploy (3 minutes)

```bash
git add .
git commit -m "feat: add production AWS infrastructure"
git push origin main
```

Go to your repo → **Actions** tab. You'll see the `Deploy` workflow running.

What happens:

1. GitHub generates an OIDC token for your workflow
2. AWS exchanges it for temporary credentials (the IAM role you created)
3. Docker builds your image
4. Image is pushed to ECR with two tags: `:latest` and `:<git-sha>`
5. Current ECS task definition is downloaded
6. Task definition is updated with the new image URI
7. ECS rolls out the new task: starts new container, waits for health check, drains old container
8. Workflow exits 0 — deploy complete

Total time from push to running: ~3–4 minutes.

---

## Step 10 — Verify (1 minute)

```powershell
# ALB health check
curl -I https://api.mysaas.com/api/health/
# Expected: HTTP/2 200

# ECS service status
aws ecs describe-services `
  --cluster mysaas-prod-cluster `
  --services mysaas-web-prod-service `
  --query "services[0].{status:status,running:runningCount,desired:desiredCount,events:events[0].message}" `
  --no-cli-pager

# Tail CloudWatch logs
aws logs tail /stacklift/mysaas/prod --follow --no-cli-pager
```

Expected ECS output:

```json
{
    "status": "ACTIVE",
    "running": 1,
    "desired": 1,
    "events": "(service mysaas-web-prod-service) has reached a steady state."
}
```

---

## What you now have

A production AWS stack that:

- **Restarts crashed containers automatically** — ECS health check → unhealthy → replace
- **Rolls back failed deploys automatically** — ECS deployment circuit breaker
- **Never exposes secrets in plaintext** — Secrets Manager + ECS injection, zero `.env` files
- **Scales horizontally** — change `desired_count`, ECS places tasks, ALB routes traffic
- **Costs ~$80–100/month** at minimal scale (1 task, db.t3.micro, single NAT)
- **You own every line** — Terraform files in your repo, no SaaS dependency

---

## Common issues

**ACM certificate stuck validating**

Check that the Route53 CNAME records were created:

```powershell
aws route53 list-resource-record-sets `
  --hosted-zone-id Z1234567890ABCDEFGHIJ `
  --query "ResourceRecordSets[?Type=='CNAME']" `
  --no-cli-pager
```

If they're there, wait 2–5 more minutes. If they're missing, check that `route53_zone_id` matches your domain.

**ECS task keeps stopping**

```powershell
aws ecs describe-tasks `
  --cluster mysaas-prod-cluster `
  --tasks $(aws ecs list-tasks --cluster mysaas-prod-cluster --query "taskArns[0]" --output text --no-cli-pager) `
  --query "tasks[0].{status:lastStatus,stopCode:stopCode,reason:stoppedReason}" `
  --no-cli-pager
```

Most common cause: the health check endpoint doesn't exist or returns non-200. Add the `/api/health/` path.

**GitHub Actions: `AccessDenied` on `iam:PassRole`**

Verify `task_execution_role_arn` and `task_role_arn` are correctly set in the `cicd` module. These must match the roles the ECS service actually uses.

**RDS connection refused from ECS**

The ECS → RDS security group rule is created as a standalone resource after both security groups exist. If you destroyed and recreated modules individually, re-run `terraform apply` to restore the rule.

---

## What's next

**Add a staging environment** — duplicate `terraform.tfvars` with `environment = "staging"`, use a different `key` in `backend.tfvars`. Same modules, same workflow, isolated state.

**Scale the web service** — increase `web_desired_count` and `web_cpu`/`web_memory` in `terraform.tfvars`, run `terraform apply`. ECS places new tasks, ALB distributes traffic.

**Celery Beat scheduler** — add a third ECS service using the same image with `CELERY_BEAT=true` as an env var and `desired_count = 1`. Beat should always run as a single task.

**S3 for static files** — add `aws_s3_bucket` + CloudFront in the root module, pass the bucket ARN to `cicd` as `s3_bucket_arns`, add `collectstatic` + `aws s3 sync` to `deploy.yml`.

---

*Stacklift is open-source — [github.com/emanthen/stacklift](https://github.com/emanthen/stacklift). If this saved you a week of AWS wrestling, a star helps others find it.*
