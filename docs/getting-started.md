# Getting Started

Everything you need to go from zero to a running Django or FastAPI app on AWS.

---

## Prerequisites

| Tool | Required version | Check |
|---|---|---|
| AWS CLI | >= 2.x | `aws --version` |
| AWS credentials | configured | `aws sts get-caller-identity --no-cli-pager` |
| Terraform | >= 1.5 | `terraform --version` |
| Docker | running | `docker info` |

You also need:
- A Route53 public hosted zone for your domain
- A GitHub repository for your application

---

## Option A — CLI (recommended)

The CLI runs pre-flight checks, asks 11 questions, and writes all Terraform files for you.

**Install:**
```bash
pip install stacklift
```

**Run:**
```bash
cd your-project
stacklift init
```

The CLI creates:
```
infra/
  main.tf
  variables.tf
  terraform.tfvars
  backend.tf
.github/
  workflows/
    deploy.yml
```

Then follow the printed next steps.

---

## Option B — Copy an example

Clone the repo and copy the example closest to your stack:

```bash
git clone https://github.com/emanthen/Stacklift
```

**Django + Celery + PostgreSQL:**
```bash
cp -r Stacklift/examples/django-celery-postgres/* your-project/infra/
```

**FastAPI + PostgreSQL:**
```bash
cp -r Stacklift/examples/fastapi-postgres/* your-project/infra/
```

Edit `terraform.tfvars` with your values.

---

## Step 1 — Create the S3 backend

Terraform state is stored in S3. Create the bucket and DynamoDB lock table once per AWS account:

```bash
PROJECT="myproject"
REGION="us-east-1"

aws s3api create-bucket \
  --bucket "stacklift-tfstate-$PROJECT" \
  --region $REGION --no-cli-pager

aws s3api put-bucket-versioning \
  --bucket "stacklift-tfstate-$PROJECT" \
  --versioning-configuration Status=Enabled --no-cli-pager

aws s3api put-bucket-encryption \
  --bucket "stacklift-tfstate-$PROJECT" \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
  --no-cli-pager

aws dynamodb create-table \
  --table-name stacklift-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $REGION --no-cli-pager
```

Create `backend.tfvars` (do not commit):
```hcl
bucket         = "stacklift-tfstate-myproject"
key            = "prod/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "stacklift-tfstate-lock"
encrypt        = true
```

---

## Step 2 — Fill in your variables

Edit `infra/terraform.tfvars`. Required values:

```hcl
project_name    = "myproject"
aws_region      = "us-east-1"
domain_name     = "api.myproject.com"
route53_zone_id = "Z1234567890ABCDEF"   # from aws route53 list-hosted-zones
github_org      = "your-github-username"
github_repo     = "myproject"
```

Find your Route53 zone ID:
```bash
aws route53 list-hosted-zones \
  --query "HostedZones[*].{Name:Name,Id:Id}" \
  --output table --no-cli-pager
```

---

## Step 3 — Initialise

```bash
cd infra
terraform init -backend-config=backend.tfvars
```

---

## Step 4 — Plan and apply

```bash
terraform plan
terraform apply
```

First apply takes ~10 minutes. ACM certificate validation and RDS creation are the long poles.

---

## Step 5 — Update secrets

After apply, replace placeholder values with real secrets:

```bash
aws secretsmanager put-secret-value \
  --secret-id "myproject-prod/app/secrets" \
  --secret-string '{"SECRET_KEY":"real-key","RESEND_API_KEY":"re_xxx"}' \
  --no-cli-pager
```

---

## Step 6 — Configure GitHub Actions

Run `terraform output` and add the values as GitHub Actions variables in your repo settings. See the [CI/CD section](module-reference.md#cicd) for the full list.

---

## Step 7 — Push and deploy

```bash
git push origin main
```

GitHub Actions builds the Docker image, pushes to ECR, and deploys to ECS automatically.

---

## Full walkthrough

The [Deploy a Django SaaS in 30 Minutes](tutorials/deploy-django-saas-in-30-minutes.md) tutorial covers every step with real commands and expected output.
