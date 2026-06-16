# Module Reference

Quick reference for all 8 Stacklift modules. Each module has a full README with complete input/output tables.

---

## vpc

**Source:** `github.com/emanthen/Stacklift//modules/vpc?ref=v0.1.0`

Creates a VPC with public and private subnets, NAT Gateway, Internet Gateway, and route tables.

**Key inputs:**

| Input | Default | Description |
|---|---|---|
| `cidr_block` | `10.0.0.0/16` | VPC CIDR |
| `az_count` | `2` | Number of AZs |
| `single_nat_gateway` | `true` | One NAT for all AZs (saves ~$32/mo) |

**Key outputs:** `vpc_id`, `public_subnet_ids`, `private_subnet_ids`

[Full README →](../modules/vpc/README.md)

---

## rds

**Source:** `github.com/emanthen/Stacklift//modules/rds?ref=v0.1.0`

Creates a PostgreSQL RDS instance in private subnets with encrypted storage, automated backups, and Secrets Manager credentials.

**Key inputs:**

| Input | Default | Description |
|---|---|---|
| `instance_class` | `db.t3.micro` | RDS instance size |
| `engine_version` | `"15"` | PostgreSQL version |
| `deletion_protection` | `true` | Prevent accidental deletion |
| `allowed_security_group_ids` | `[]` | SG IDs with port 5432 access |

**Key outputs:** `db_endpoint`, `db_secret_arn`, `rds_security_group_id`

> **Note:** `db_secret_arn` contains a JSON blob with `host`, `port`, `dbname`, `username`, `password`, and `DATABASE_URL`.

[Full README →](../modules/rds/README.md)

---

## ecr

**Source:** `github.com/emanthen/Stacklift//modules/ecr?ref=v0.1.0`

Creates an ECR repository with a lifecycle policy (expire untagged after 1 day, keep last 10 tagged) and optional push/pull access policies.

**Key inputs:**

| Input | Default | Description |
|---|---|---|
| `scan_on_push` | `true` | AWS Basic Scanning on push |
| `keep_image_count` | `10` | Tagged images to retain |

**Key outputs:** `repository_url`, `repository_arn`, `registry_url`

[Full README →](../modules/ecr/README.md)

---

## ecs-cluster

**Source:** `github.com/emanthen/Stacklift//modules/ecs-cluster?ref=v0.1.0`

Creates an ECS cluster with FARGATE and FARGATE_SPOT capacity providers, Container Insights, and a shared CloudWatch log group.

**Key inputs:**

| Input | Default | Description |
|---|---|---|
| `enable_container_insights` | `true` | Per-task CloudWatch metrics |
| `log_retention_days` | `30` | Log expiry |

**Key outputs:** `cluster_id`, `cluster_arn`, `cluster_name`, `log_group_name`

[Full README →](../modules/ecs-cluster/README.md)

---

## ecs-service

**Source:** `github.com/emanthen/Stacklift//modules/ecs-service?ref=v0.1.0`

Creates an ECS Fargate service with task definition, IAM roles (execution + task), security group, and ALB registration.

**Key inputs:**

| Input | Default | Description |
|---|---|---|
| `image_url` | — | Full ECR image URL with tag |
| `cpu` | `256` | Fargate CPU units |
| `memory` | `512` | Fargate memory in MB |
| `health_check_path` | `/api/health/` | HTTP path for health checks |
| `secrets` | `{}` | `{ENV_VAR: "sm_arn:KEY::"}` map |
| `secret_arns` | `[]` | Base ARNs for IAM permission |
| `enable_migration_task` | `false` | Create a one-shot migration task definition |

**Key outputs:** `service_name`, `service_id`, `task_definition_family`, `task_execution_role_arn`, `task_security_group_id`, `migrate_task_definition_family`

> **Important:** After the first `terraform apply`, the CI/CD pipeline owns `task_definition` updates. Terraform ignores them via `ignore_changes`.

[Full README →](../modules/ecs-service/README.md)

---

## alb

**Source:** `github.com/emanthen/Stacklift//modules/alb?ref=v0.1.0`

Creates an internet-facing ALB with HTTPS termination, ACM certificate via DNS validation, HTTP→HTTPS redirect, and Route53 A record.

**Key inputs:**

| Input | Default | Description |
|---|---|---|
| `domain_name` | — | Domain for ACM cert + DNS record |
| `route53_zone_id` | — | Hosted zone for validation + alias |
| `health_check_path` | `/api/health/` | ALB target health check |
| `deregistration_delay` | `30` | Seconds before draining old targets |

**Key outputs:** `alb_dns_name`, `target_group_arn`, `alb_security_group_id`, `https_listener_arn`, `certificate_arn`

[Full README →](../modules/alb/README.md)

---

## secrets

**Source:** `github.com/emanthen/Stacklift//modules/secrets?ref=v0.1.0`

Creates a Secrets Manager secret for application env vars (Django `SECRET_KEY`, API keys, etc.) and an IAM read policy.

**Key inputs:**

| Input | Default | Description |
|---|---|---|
| `secret_values` | `{}` | Initial key-value pairs (placeholders) |
| `recovery_window_days` | `30` | Days before permanent deletion |

**Key outputs:** `secret_arn`, `secret_name`, `read_policy_arn`

> **Note:** Terraform writes initial values and then ignores changes. Update real values via `aws secretsmanager put-secret-value`.

[Full README →](../modules/secrets/README.md)

---

## cicd

**Source:** `github.com/emanthen/Stacklift//modules/cicd?ref=v0.1.0`

Creates a GitHub Actions OIDC provider and IAM role with scoped policies for ECR push, ECS deploy, and optional Secrets Manager + S3 access.

**Key inputs:**

| Input | Default | Description |
|---|---|---|
| `github_org` | — | GitHub org or username |
| `github_repo` | — | Repository name |
| `github_branch` | `main` | Branch allowed to assume the role |
| `create_oidc_provider` | `true` | One per AWS account — set `false` if exists |
| `task_execution_role_arn` | — | Required for `iam:PassRole` |

**Key outputs:** `github_actions_role_arn`, `oidc_provider_arn`

**GitHub Actions variables to set after apply:**

| Variable | Terraform output |
|---|---|
| `AWS_ROLE_ARN` | `github_actions_role_arn` |
| `AWS_REGION` | your region |
| `ECR_REPOSITORY` | `module.ecr.repository_name` |
| `ECS_CLUSTER` | `module.ecs_cluster.cluster_name` |
| `ECS_SERVICE` | `module.ecs_service.service_name` |
| `ECS_TASK_FAMILY` | `module.ecs_service.task_definition_family` |

[Full README →](../modules/cicd/README.md)

---

## Module dependency order

```
vpc → rds, alb, ecs-cluster, ecr, secrets
rds → (standalone SG rule after ecs-service)
ecs-service → vpc, rds, alb, ecs-cluster, ecr, secrets
cicd → ecr, ecs-cluster, ecs-service
```

All modules in a single `terraform apply` — Terraform resolves the ordering automatically.
