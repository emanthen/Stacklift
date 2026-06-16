# Changelog

All notable changes to Stacklift are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).  
Stacklift follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added
- Django migration runner: `enable_migration_task` variable in `ecs-service` module creates a one-shot ECS task definition for running `python manage.py migrate --no-input` before each deploy.
- `deploy.yml` migration step: runs and waits for the migration task before updating the web service; fails the pipeline on non-zero exit.
- `versions.tf` in all 8 modules (Terraform Registry compliance).
- `SECURITY.md` with vulnerability reporting policy and security design documentation.
- `docs/faq.md` with answers to 6 common deployment questions.
- Security comparison, cost estimate, and competitor comparison tables in `README.md`.

---

## [0.1.0] — 2024-01-01

### Added
- `modules/vpc` — VPC with public/private subnets, NAT Gateway, IGW, route tables, locked-down default SG.
- `modules/rds` — RDS PostgreSQL with encrypted gp3 storage, automated backups, random password, Secrets Manager credentials. `prevent_destroy = true`.
- `modules/ecr` — ECR repository with lifecycle policy (untagged: 1 day, tagged: keep 10).
- `modules/ecs-cluster` — ECS cluster with FARGATE + FARGATE_SPOT capacity providers, Container Insights, CloudWatch log group.
- `modules/ecs-service` — ECS Fargate service with IAM execution + task roles, security group, ALB registration, circuit breaker rollback. `ignore_changes = [task_definition, desired_count]`.
- `modules/alb` — Internet-facing ALB with ACM certificate (DNS validation), HTTP→HTTPS redirect, TLS 1.3, Route53 A alias.
- `modules/secrets` — Secrets Manager secret for application env vars with IAM read policy.
- `modules/cicd` — GitHub Actions OIDC provider + IAM role with scoped ECR push and ECS deploy policies. No long-lived credentials.
- `examples/django-celery-postgres` — Full Django + Celery + PostgreSQL stack with GitHub Actions CI/CD.
- `examples/fastapi-postgres` — FastAPI + PostgreSQL stack.
- `cli/` — `stacklift init` CLI: pre-flight checks, 11-question scaffold, Jinja2 templates for `main.tf`, `variables.tf`, `terraform.tfvars`, `backend.tf`, `deploy.yml`.
- Full documentation: `docs/getting-started.md`, `docs/module-reference.md`, `docs/cli-reference.md`, `docs/pro-tier.md`.

[Unreleased]: https://github.com/emanthen/Stacklift/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/emanthen/Stacklift/releases/tag/v0.1.0
