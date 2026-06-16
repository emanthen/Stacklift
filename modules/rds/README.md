# stacklift/modules/rds

Creates a production-grade PostgreSQL RDS instance on AWS for Django and FastAPI workloads.

**What this module creates:**

- RDS PostgreSQL instance (gp3 storage, encrypted at rest)
- DB subnet group across private subnets (no public access)
- Security group — port 5432 open only to explicitly listed security group IDs
- DB parameter group with slow-query logging (>1s) enabled
- IAM role for RDS Enhanced Monitoring
- Secrets Manager secret with full credentials + a ready-to-use `DATABASE_URL`
- Random 32-character master password (excluded from Terraform state after initial write)

**Security defaults:**

- `publicly_accessible = false` — RDS is never reachable from the internet
- `storage_encrypted = true` — encryption at rest always on
- `deletion_protection = true` — prevents accidental destruction via console or API
- `lifecycle { prevent_destroy = true }` — prevents `terraform destroy` from removing the instance
- Password excluded from Terraform state via `ignore_changes` after initial creation

---

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.5 |
| aws | ~> 5.0 |
| random | ~> 3.5 |

---

## Usage

```hcl
module "rds" {
  source = "../../modules/rds"

  project_name       = "mysaas"
  environment        = "prod"
  aws_region         = "us-east-1"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # Populated after ecs-service is created — Terraform resolves the ordering
  allowed_security_group_ids = [module.ecs_service.task_security_group_id]

  instance_class        = "db.t3.micro"
  engine_version        = "15"
  allocated_storage     = 20
  multi_az              = false
  deletion_protection   = true
  backup_retention_days = 7
}
```

Pass outputs to the `ecs-service` module:

```hcl
module "ecs_service" {
  source = "../../modules/ecs-service"

  secret_arns = [module.rds.db_secret_arn]
  # The secret contains DATABASE_URL, host, port, dbname, username, password
  # ECS task reads it at startup — no plaintext env vars
  ...
}
```

> **Note on ordering:** `rds` needs `module.ecs_service.task_security_group_id` and `ecs-service` needs `module.rds.db_secret_arn`. This is not a circular dependency — Terraform creates both security groups in parallel, then resolves the SG rule and secret reference in a second pass. Run `terraform apply` once and Terraform handles it.

---

## Inputs

| Name | Type | Default | Required | Description |
|---|---|---|---|---|
| `project_name` | `string` | — | yes | Prefix for all resource names. Also used as DB name and master username (hyphens → underscores). |
| `environment` | `string` | `"prod"` | no | `dev`, `staging`, or `prod`. |
| `aws_region` | `string` | `"us-east-1"` | no | AWS region. |
| `vpc_id` | `string` | — | yes | VPC ID. Use `module.vpc.vpc_id`. |
| `private_subnet_ids` | `list(string)` | — | yes | Private subnet IDs for the subnet group. Use `module.vpc.private_subnet_ids`. |
| `allowed_security_group_ids` | `list(string)` | `[]` | no | SG IDs allowed to reach port 5432. Pass `[module.ecs_service.task_security_group_id]`. |
| `instance_class` | `string` | `"db.t3.micro"` | no | RDS instance class. |
| `engine_version` | `string` | `"15"` | no | PostgreSQL engine version (e.g. `"15"`, `"16.1"`). |
| `allocated_storage` | `number` | `20` | no | Storage in GB (gp3). Min 20. |
| `multi_az` | `bool` | `false` | no | Enable Multi-AZ standby. Doubles cost; recommended for prod. |
| `deletion_protection` | `bool` | `true` | no | Prevent deletion via console/API. Must be disabled before destroy. |
| `skip_final_snapshot` | `bool` | `false` | no | Skip final snapshot on delete. `true` for throwaway dev envs only. |
| `backup_retention_days` | `number` | `7` | no | Automated backup retention in days (0–35). |
| `recovery_window_days` | `number` | `30` | no | Secrets Manager recovery window in days. `0` for immediate delete (dev only). |
| `tags` | `map(string)` | `{}` | no | Extra tags merged onto all resources. |

---

## Outputs

| Name | Description |
|---|---|
| `db_instance_id` | RDS instance identifier. |
| `db_instance_arn` | ARN of the RDS instance. |
| `db_endpoint` | Full `host:port` connection string. |
| `db_address` | Hostname only (without port). |
| `db_port` | Port number (5432). |
| `db_name` | Default database name. |
| `db_username` | Master username. |
| `db_secret_arn` | ARN of the Secrets Manager secret. Pass to `ecs-service` as `secret_arns`. |
| `db_secret_name` | Name of the Secrets Manager secret. |
| `rds_security_group_id` | ID of the RDS security group. |
| `db_subnet_group_name` | Name of the DB subnet group. |
| `db_parameter_group_name` | Name of the parameter group. |

---

## Secret structure

The Secrets Manager secret at `{project}-{env}/rds/credentials` contains:

```json
{
  "engine":       "postgres",
  "host":         "mysaas-prod-rds.xxxxxx.us-east-1.rds.amazonaws.com",
  "port":         "5432",
  "dbname":       "mysaas",
  "username":     "mysaas",
  "password":     "...",
  "DATABASE_URL": "postgres://mysaas:...@mysaas-prod-rds.xxxxxx.us-east-1.rds.amazonaws.com:5432/mysaas"
}
```

In Django `settings.py`:

```python
import boto3, json
secret = json.loads(boto3.client("secretsmanager").get_secret_value(
    SecretId=os.environ["DB_SECRET_ARN"]
)["SecretString"])
DATABASES = {"default": {"ENGINE": "django.db.backends.postgresql", **{
    "NAME": secret["dbname"], "USER": secret["username"],
    "PASSWORD": secret["password"], "HOST": secret["host"], "PORT": secret["port"],
}}}
```

Or with `dj-database-url`:

```python
DATABASES = {"default": dj_database_url.parse(secret["DATABASE_URL"])}
```

---

## Destroying this module

⚠️ Two safeguards block destruction by default:

1. `deletion_protection = true` — disable via `terraform apply` first:
   ```hcl
   deletion_protection = false
   ```
2. `lifecycle { prevent_destroy = true }` — comment out the block in `main.tf`, then `terraform apply`, then `terraform destroy`.

This is intentional. Data loss from an accidental destroy is not recoverable.

---

## Cost estimate

| Resource | Cost |
|---|---|
| db.t3.micro, single-AZ, 20GB gp3 | ~$15–18/mo |
| db.t3.micro, Multi-AZ, 20GB gp3 | ~$30–36/mo |
| Automated backups (same region) | Free up to DB storage size |
| Enhanced Monitoring | Free |
| Performance Insights (7-day) | Free |
| Secrets Manager secret | $0.40/mo + $0.05/10k API calls |

Verify current pricing at [https://aws.amazon.com/rds/postgresql/pricing/](https://aws.amazon.com/rds/postgresql/pricing/).
