# Example: FastAPI + PostgreSQL on AWS

A production-grade deployment of a FastAPI application with PostgreSQL on AWS using Stacklift modules.

**What gets created:**

| Resource | Module | Notes |
|---|---|---|
| VPC, 2 public + 2 private subnets, NAT | `vpc` | Single NAT (~$32/mo) |
| ECR repository | `ecr` | Lifecycle policy: keep 10 images |
| ECS cluster | `ecs-cluster` | Fargate + Fargate Spot, Container Insights |
| App secrets (APP_SECRET_KEY, API keys) | `secrets` | Placeholders on first apply |
| RDS PostgreSQL 15 | `rds` | db.t3.micro, gp3, encrypted, deletion protected |
| ALB with HTTPS + ACM cert | `alb` | DNS validation, HTTP→HTTPS redirect |
| ECS service (FastAPI/uvicorn) | `ecs-service` | 256 CPU / 512MB, private subnet |
| GitHub Actions OIDC + IAM role | `cicd` | No long-lived credentials |

**Estimated cost:** ~$80–100/month for a minimal single-task production setup.

---

## FastAPI application requirements

### Health check endpoint

The ALB and ECS both poll `/health`. Add this route:

```python
# main.py
from fastapi import FastAPI

app = FastAPI()

@app.get("/health")
def health():
    return {"status": "ok"}
```

### Reading secrets

ECS injects all secrets as plain environment variables at task startup. Use `pydantic-settings`:

```python
# config.py
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str
    app_secret_key: str
    resend_api_key: str
    allowed_origins: str = ""
    environment: str = "prod"
    port: int = 8000

    class Config:
        env_file = ".env"  # local dev only — ignored in ECS

settings = Settings()
```

### Database connection (SQLAlchemy + asyncpg)

```python
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

# DATABASE_URL from Secrets Manager is postgres:// — convert for asyncpg
DATABASE_URL = settings.database_url.replace("postgres://", "postgresql+asyncpg://", 1)

engine = create_async_engine(DATABASE_URL, pool_pre_ping=True)
AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
```

### Dockerfile

```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
```

---

## Deployment steps

### Step 1 — Create the S3 backend

```powershell
aws s3api create-bucket `
  --bucket stacklift-tfstate-myapi `
  --region us-east-1 `
  --no-cli-pager

aws s3api put-bucket-versioning `
  --bucket stacklift-tfstate-myapi `
  --versioning-configuration Status=Enabled `
  --no-cli-pager

aws dynamodb create-table `
  --table-name stacklift-tfstate-lock `
  --attribute-definitions AttributeName=LockID,AttributeType=S `
  --key-schema AttributeName=LockID,KeyType=HASH `
  --billing-mode PAY_PER_REQUEST `
  --region us-east-1 `
  --no-cli-pager
```

### Step 2 — Configure variables

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

Find your Route53 zone ID:
```powershell
aws route53 list-hosted-zones --no-cli-pager
```

### Step 3 — Create backend config

Create `backend.tfvars` (do not commit):
```
bucket         = "stacklift-tfstate-myapi"
key            = "prod/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "stacklift-tfstate-lock"
encrypt        = true
```

### Step 4 — Apply

```powershell
terraform init -backend-config=backend.tfvars
terraform plan
terraform apply
```

Takes ~8–12 minutes on first run (ACM validation + RDS creation).

### Step 5 — Update secrets

```powershell
aws secretsmanager put-secret-value `
  --secret-id "myapi-prod/app/secrets" `
  --secret-string '{\"APP_SECRET_KEY\":\"your-secret\",\"RESEND_API_KEY\":\"re_your_key\",\"ALLOWED_ORIGINS\":\"https://app.myapi.com\"}' `
  --no-cli-pager
```

### Step 6 — Set GitHub Actions variables

```powershell
terraform output --no-cli-pager
```

In GitHub repo → **Settings → Secrets and variables → Actions → Variables**:

| Variable | Value |
|---|---|
| `AWS_ROLE_ARN` | `terraform output -raw github_actions_role_arn` |
| `AWS_REGION` | `us-east-1` |
| `ECR_REPOSITORY` | `terraform output -raw ecr_repository_name` |
| `ECS_CLUSTER` | `terraform output -raw ecs_cluster_name` |
| `ECS_SERVICE` | `terraform output -raw ecs_service_name` |
| `ECS_TASK_FAMILY` | `terraform output -raw ecs_task_family` |

### Step 7 — CI/CD workflow

Use the same workflow as the django-celery-postgres example, simplified for a single service:

```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [main]

permissions:
  id-token: write
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
          docker build \
            --tag $REGISTRY/$REPOSITORY:$IMAGE_TAG \
            --tag $REGISTRY/$REPOSITORY:latest \
            --cache-from $REGISTRY/$REPOSITORY:latest \
            --build-arg BUILDKIT_INLINE_CACHE=1 .
          docker push $REGISTRY/$REPOSITORY:$IMAGE_TAG
          docker push $REGISTRY/$REPOSITORY:latest

      - name: Fetch task definition
        run: |
          aws ecs describe-task-definition \
            --task-definition ${{ vars.ECS_TASK_FAMILY }} \
            --query taskDefinition --output json > task-def.json

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

### Step 8 — Verify

```powershell
curl -I https://api.myapi.com/health

aws ecs describe-services `
  --cluster myapi-prod-cluster `
  --services myapi-prod-service `
  --query "services[0].{status:status,running:runningCount,desired:desiredCount}" `
  --no-cli-pager

aws logs tail /stacklift/myapi/prod --follow --no-cli-pager
```

---

## Differences from django-celery-postgres

| | fastapi-postgres | django-celery-postgres |
|---|---|---|
| Health check path | `/health` | `/api/health/` |
| Worker | None | Celery on Fargate Spot |
| Settings module | `pydantic-settings` | `DJANGO_SETTINGS_MODULE` |
| Secret key name | `APP_SECRET_KEY` | `SECRET_KEY` |
| Deploy workflow | Single service | Web + Celery services |

---

## Destroying this example

⚠️ Two safeguards on RDS must be removed before `terraform destroy`:

```hcl
# 1. In terraform.tfvars (or main.tf), set:
deletion_protection = false
# Run: terraform apply

# 2. In modules/rds/main.tf, comment out:
# lifecycle { prevent_destroy = true }
# Run: terraform apply

# 3. Now destroy:
# terraform destroy
```
