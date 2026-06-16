# stacklift/modules/secrets

Creates an AWS Secrets Manager secret for Django/FastAPI application secrets and an IAM policy granting read access.

**What this module creates:**

- Secrets Manager secret at `{project}-{env}/app/secrets`
- Initial secret version populated from `var.secret_values` (Terraform ignores subsequent changes — you own updates after first apply)
- IAM managed policy granting `GetSecretValue` + `DescribeSecret` on this secret

**What this module does NOT manage:**

- RDS credentials — those live in the `rds` module under `{project}-{env}/rds/credentials`
- Ongoing secret rotation — use the Pro tier secrets rotation module for that

**Separation of concerns:**

| Secret | Module | Path |
|---|---|---|
| RDS master credentials + DATABASE_URL | `rds` | `{project}-{env}/rds/credentials` |
| App secrets (SECRET_KEY, API keys, etc.) | `secrets` | `{project}-{env}/app/secrets` |

---

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.5 |
| aws | ~> 5.0 |

---

## Usage

```hcl
module "app_secrets" {
  source = "../../modules/secrets"

  project_name = "mysaas"
  environment  = "prod"

  secret_values = {
    SECRET_KEY     = "replace-me"
    RESEND_API_KEY = "replace-me"
    STRIPE_SECRET  = "replace-me"
    ALLOWED_HOSTS  = "api.mysaas.com"
  }

  recovery_window_days = 30
}
```

Wire into `ecs-service`:

```hcl
module "ecs_service" {
  source = "../../modules/ecs-service"

  # Grant the task execution role GetSecretValue on both secrets
  secret_arns = [
    module.rds.db_secret_arn,
    module.app_secrets.secret_arn,
  ]

  # Inject individual keys as container env vars
  secrets = {
    "DATABASE_URL"   = "${module.rds.db_secret_arn}:DATABASE_URL::"
    "SECRET_KEY"     = "${module.app_secrets.secret_arn}:SECRET_KEY::"
    "RESEND_API_KEY" = "${module.app_secrets.secret_arn}:RESEND_API_KEY::"
    "STRIPE_SECRET"  = "${module.app_secrets.secret_arn}:STRIPE_SECRET::"
    "ALLOWED_HOSTS"  = "${module.app_secrets.secret_arn}:ALLOWED_HOSTS::"
  }
  ...
}
```

---

## Updating secret values after first apply

Terraform creates the secret on the first `apply` with your placeholder values, then ignores changes forever (`ignore_changes = [secret_string]`). Update real values via CLI:

```powershell
# D:\your-project
aws secretsmanager put-secret-value `
  --secret-id "mysaas-prod/app/secrets" `
  --secret-string '{\"SECRET_KEY\":\"real-django-secret\",\"RESEND_API_KEY\":\"re_abc123\",\"STRIPE_SECRET\":\"sk_live_abc123\"}' `
  --no-cli-pager
```

Or via the AWS console: **Secrets Manager → mysaas-prod/app/secrets → Retrieve secret value → Edit**.

New ECS tasks started after the update will pick up the new values automatically. Running tasks keep the old values until the next deployment.

---

## Generating a Django SECRET_KEY

```python
# Run locally — never commit the output
python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"
```

```powershell
# Or with Python directly
python -c "import secrets; print(secrets.token_urlsafe(50))"
```

---

## Reading secrets in Django / FastAPI

ECS injects secrets as plain environment variables at task startup. No SDK calls needed in application code.

**Django `settings/production.py`:**
```python
import os

SECRET_KEY = os.environ["SECRET_KEY"]
RESEND_API_KEY = os.environ["RESEND_API_KEY"]

DATABASES = {
    "default": dj_database_url.parse(os.environ["DATABASE_URL"])
}
```

**FastAPI:**
```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    secret_key: str
    resend_api_key: str
    database_url: str

settings = Settings()
```

---

## Inputs

| Name | Type | Default | Required | Description |
|---|---|---|---|---|
| `project_name` | `string` | — | yes | Prefix for all resource names. |
| `environment` | `string` | `"prod"` | no | `dev`, `staging`, or `prod`. |
| `aws_region` | `string` | `"us-east-1"` | no | AWS region. |
| `secret_name` | `string` | `null` | no | Override the secret name. Defaults to `{project}-{env}/app/secrets`. |
| `secret_values` | `map(string)` | `{}` | no | Initial key-value pairs. **Sensitive.** Terraform ignores changes after first apply. |
| `recovery_window_days` | `number` | `30` | no | Days before permanent deletion after `terraform destroy`. `0` = immediate. |
| `tags` | `map(string)` | `{}` | no | Extra tags merged onto all resources. |

---

## Outputs

| Name | Description |
|---|---|
| `secret_arn` | ARN of the secret. Pass to `ecs-service` as an element of `secret_arns`. |
| `secret_name` | Name of the secret. Use in CLI `put-secret-value` commands. |
| `secret_id` | Secret ID (same as ARN). |
| `read_policy_arn` | IAM policy ARN granting `GetSecretValue`. Attach to any role that needs to read this secret. |
| `read_policy_name` | IAM policy name. |

---

## Cost estimate

| Resource | Cost |
|---|---|
| Secret (per secret per month) | $0.40/mo |
| API calls (per 10,000) | $0.05 |

One ECS task reading 6 secrets at startup = 6 API calls per task launch. At $0.05/10k calls, cost is effectively zero. Total: **~$0.40–0.80/month** for two secrets (app + RDS).
