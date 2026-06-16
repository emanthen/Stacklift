# Stacklift

**Production AWS for Django & FastAPI. In under an hour.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.5-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS Provider](https://img.shields.io/badge/AWS%20Provider-~%3E5.0-FF9900?logo=amazonaws)](https://registry.terraform.io/providers/hashicorp/aws/latest)

Stacklift is an open-source Terraform module set that gives your Django or FastAPI project a production-grade AWS stack — VPC, RDS, ECS Fargate, ALB, Secrets Manager, and GitHub Actions CI/CD — composed from modular, auditable Terraform files you own completely.

No black boxes. No Heroku-style abstraction. Just AWS, done right from the start.

---

## What you get

```
Your repo/
└── infra/
    ├── main.tf          ← 8 modules wired together (~150 lines)
    ├── variables.tf
    ├── terraform.tfvars
    └── backend.tf
.github/
└── workflows/
    └── deploy.yml       ← push to main → build → ECR → ECS
```

**Infrastructure created:**

| Resource | Details |
|---|---|
| VPC | 2 public + 2 private subnets, NAT Gateway, IGW |
| RDS PostgreSQL | Encrypted gp3, automated backups, Secrets Manager credentials |
| ECR | Image repository with lifecycle policy |
| ECS Fargate | Private subnet, CloudWatch logs, awslogs driver |
| ALB | HTTPS termination, ACM certificate, Route53 DNS |
| Secrets Manager | DATABASE_URL + app secrets, ECS injection at startup |
| GitHub Actions | OIDC auth, ECR push, ECS rolling deploy, no stored credentials |

---

## Quickstart

```bash
# 1. Clone the repo
git clone https://github.com/your-org/stacklift
cd stacklift/examples/django-celery-postgres

# 2. Copy and fill in your values
cp terraform.tfvars.example terraform.tfvars

# 3. Create S3 backend (once per AWS account)
aws s3api create-bucket --bucket stacklift-tfstate-myproject --region us-east-1 --no-cli-pager
aws dynamodb create-table \
  --table-name stacklift-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1 --no-cli-pager

# 4. Init and apply (~10 minutes)
terraform init -backend-config=backend.tfvars
terraform plan
terraform apply

# 5. Set GitHub Actions variables, push to main — CI/CD runs automatically
```

Full walkthrough: [Deploy a Django SaaS in 30 Minutes](docs/tutorials/deploy-django-saas-in-30-minutes.md)

---

## Modules

Each module is self-contained with its own `main.tf`, `variables.tf`, `outputs.tf`, and `README.md`.

| Module | What it creates | README |
|---|---|---|
| [`vpc`](modules/vpc/) | VPC, public/private subnets, NAT Gateway, IGW, route tables | [→](modules/vpc/README.md) |
| [`rds`](modules/rds/) | RDS PostgreSQL, subnet group, security group, Secrets Manager credentials | [→](modules/rds/README.md) |
| [`ecr`](modules/ecr/) | ECR repository, lifecycle policy, repository policy | [→](modules/ecr/README.md) |
| [`ecs-cluster`](modules/ecs-cluster/) | ECS cluster, Fargate capacity providers, CloudWatch log group | [→](modules/ecs-cluster/README.md) |
| [`ecs-service`](modules/ecs-service/) | ECS task definition, Fargate service, IAM roles, security group | [→](modules/ecs-service/README.md) |
| [`alb`](modules/alb/) | ALB, HTTPS listener, ACM certificate, Route53 DNS | [→](modules/alb/README.md) |
| [`secrets`](modules/secrets/) | Secrets Manager secret for app env vars, IAM read policy | [→](modules/secrets/README.md) |
| [`cicd`](modules/cicd/) | GitHub Actions OIDC provider, IAM role, ECR push + ECS deploy policies | [→](modules/cicd/README.md) |

---

## Use from Terraform Registry

Each module is published to the Terraform Registry. Reference directly without cloning:

```hcl
module "ecs_service" {
  source  = "emanthen/stacklift/aws//modules/ecs-service"
  version = "~> 0.1"

  project_name   = "mysaas"
  environment    = "prod"
  aws_region     = "us-east-1"
  cluster_id     = module.ecs_cluster.cluster_id
  log_group_name = module.ecs_cluster.log_group_name
  vpc_id         = module.vpc.vpc_id
  # ...
}
```

Or let the CLI wire everything together:

```bash
pip install stacklift
stacklift init
```

---

## Examples

### [Django + Celery + PostgreSQL](examples/django-celery-postgres/)

Full Django SaaS stack with a Celery worker, RDS, Secrets Manager, and GitHub Actions CI/CD. Includes a complete `deploy.yml` that deploys both the web service and worker on every push to main.

### [FastAPI + PostgreSQL](examples/fastapi-postgres/)

Minimal FastAPI API stack — single ECS service, RDS, Secrets Manager, ALB with HTTPS. No worker. Identical deployment workflow.

---

## How modules connect

```
                      ┌─────────┐
                      │   vpc   │
                      └────┬────┘
          ┌─────────────────┼──────────────────┐
          ▼                 ▼                  ▼
       ┌─────┐         ┌────────┐          ┌─────┐
       │ rds │         │  alb   │          │ ecr │
       └──┬──┘         └───┬────┘          └──┬──┘
          │                │                  │
          └────────┬───────┘                  │
                   ▼                          │
            ┌─────────────┐                  │
            │ ecs-cluster │                  │
            └──────┬──────┘                  │
                   ▼                          │
            ┌─────────────┐◄─────────────────┘
            │ ecs-service │◄── secrets
            └──────┬──────┘
                   ▼
              ┌─────────┐
              │  cicd   │
              └─────────┘
```

Outputs flow downstream explicitly — no data source lookups across module boundaries.

---

## Design decisions

**No `.env` files in production.** All secrets live in Secrets Manager. ECS injects them as environment variables at task startup. Your application reads `os.environ["DATABASE_URL"]` — no SDK calls, no secret fetching code.

**No long-lived AWS credentials in GitHub.** The `cicd` module creates an OIDC provider and IAM role. GitHub Actions exchanges a short-lived OIDC token for temporary AWS credentials. Nothing is stored in GitHub Secrets.

**`ignore_changes` on task definitions.** Terraform creates the initial task definition. After that, CI/CD owns it. Running `terraform apply` will not roll back a deploy that CI/CD pushed.

**`prevent_destroy` on RDS.** Both `deletion_protection = true` and `lifecycle { prevent_destroy = true }` are set. Two steps required to destroy — this is intentional. Data loss from an accidental `terraform destroy` is not recoverable.

**Single NAT Gateway by default.** Saves ~$32/month compared to one NAT per AZ. For HA production, set `single_nat_gateway = false`. The module handles both cases.

---

## Security comparison

Controls that distinguish Stacklift from typical blog-post Terraform tutorials:

| Control | Stacklift | Most tutorials |
|---|---|---|
| AWS credentials in CI/CD | OIDC token, nothing stored | Long-lived key in GitHub Secrets |
| Application secrets | Secrets Manager + ECS injection | `.env` file or hardcoded tfvars |
| Database password | `random_password`, stored in Secrets Manager | Hardcoded in variables |
| ECS task networking | Private subnet, `assign_public_ip = false` | Often public subnet |
| RDS protection | `deletion_protection` + `prevent_destroy` | No protection |
| TLS policy | TLS 1.3 minimum (ELBSecurityPolicy-TLS13-1-2-2021-06) | Default (accepts TLS 1.0) |
| `iam:PassRole` scope | Specific execution + task role ARNs | Wildcard `*` |
| Django migration runner | One-shot ECS task, blocks deploy on failure | Not covered |

---

## Estimated monthly cost

Minimal configuration: 1 web task, 1 RDS instance, single NAT, us-east-1.

| Resource | Configuration | ~$/month |
|---|---|---|
| NAT Gateway | 1 NAT × 730h + ~10 GB data | $35 |
| ALB | 730h + ~1 LCU | $17 |
| RDS PostgreSQL | db.t3.micro, 20 GB gp3, single-AZ | $15 |
| ECS Fargate | 1 task × 0.25 vCPU × 0.5 GB × 730h | $11 |
| ECR | < 1 GB stored | < $1 |
| Secrets Manager | 2 secrets × $0.40 | < $1 |
| CloudWatch Logs | Minimal volume | < $1 |
| **Total** | | **~$79/month** |

Common add-ons:

| Addition | Extra cost |
|---|---|
| Celery worker task | +$11/month |
| Multi-AZ RDS | +$15/month (doubles RDS line) |
| Second NAT (HA) | +$32/month |

---

## Requirements

| Tool | Version | Check |
|---|---|---|
| Terraform | >= 1.5 | `terraform --version` |
| AWS CLI | >= 2.x | `aws --version` |
| AWS credentials | configured | `aws sts get-caller-identity` |
| Docker | running | `docker info` |

---

## Pro tier

The open-source modules cover the core stack. The Pro tier adds:

- Multi-environment from one config (dev / staging / prod)
- Blue-green deployment with AWS CodeDeploy
- Autoscaling presets (CPU and memory target tracking)
- AWS Cost alerting (Budgets + SNS + email)
- Secrets rotation automation
- Private Discord + email support

[Learn more →](docs/pro-tier.md)

---

## vs. alternatives

The two most-starred open-source Django+ECS Terraform projects on GitHub:

| | **Stacklift** | testdrivenio/django-ecs-terraform | briancaffey/terraform-aws-django |
|---|---|---|---|
| FastAPI support | ✅ | ❌ Django only | ❌ Django only |
| GitHub Actions OIDC | ✅ No stored credentials | ❌ Long-lived key | ❌ Long-lived key |
| Secrets Manager | ✅ ECS injection | ❌ | ❌ |
| Django migration runner | ✅ One-shot ECS task | ❌ | ❌ |
| Python CLI (`stacklift init`) | ✅ | ❌ | ❌ |
| Windows compatible | ✅ Documented | ❌ | ❌ |
| `prevent_destroy` on RDS | ✅ | ❌ | ❌ |
| Active maintenance | ✅ | Last commit ~2022 | Last commit ~2023 |
| Pro tier | ✅ Multi-env, blue-green, autoscaling | ❌ | ❌ |

---

## Contributing

PRs welcome for bug fixes and documentation improvements. For new features, open an issue first.

All PRs must pass the lint workflow (`terraform fmt -check` + `terraform validate` on every module).

```bash
# Format before pushing
terraform fmt -recursive modules/
terraform fmt -recursive examples/
```

---

## License

MIT — see [LICENSE](LICENSE).

---

*Built by [Prabhat](https://github.com/your-github) from real production decisions made building [KibaPay](https://kibapay.com).*
