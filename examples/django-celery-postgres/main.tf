terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }

  # Configure the S3 backend in backend.tf — values cannot use variables here.
  # Run: terraform init -backend-config=backend.tfvars
  # See backend.tf for the full setup instructions.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "stacklift"
    }
  }
}

# ── VPC ───────────────────────────────────────────────────────────────────────

module "vpc" {
  source = "../../modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  aws_region         = var.aws_region
  cidr_block         = var.vpc_cidr
  az_count           = 2
  enable_nat_gateway = true
  single_nat_gateway = true
}

# ── ECR ───────────────────────────────────────────────────────────────────────
# Repository policy is omitted here — the task execution role gets pull access
# via AmazonECSTaskExecutionRolePolicy (grants ECR on *), and the GitHub Actions
# role gets push access via the CICD module's IAM policy.

module "ecr" {
  source = "../../modules/ecr"

  project_name     = var.project_name
  environment      = var.environment
  aws_region       = var.aws_region
  scan_on_push     = true
  keep_image_count = 10
}

# ── ECS CLUSTER ───────────────────────────────────────────────────────────────

module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  project_name              = var.project_name
  environment               = var.environment
  aws_region                = var.aws_region
  enable_container_insights = true
  log_retention_days        = var.log_retention_days
}

# ── APP SECRETS ───────────────────────────────────────────────────────────────
# Stores Django SECRET_KEY, Resend API key, Stripe key, etc.
# Terraform writes placeholders on first apply.
# Update real values after apply:
#   aws secretsmanager put-secret-value --secret-id <name> --secret-string '{...}'

module "app_secrets" {
  source = "../../modules/secrets"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  secret_values = {
    SECRET_KEY     = "replace-me-after-apply"
    RESEND_API_KEY = "replace-me-after-apply"
    ALLOWED_HOSTS  = var.domain_name
    CORS_ORIGINS   = "https://${var.domain_name}"
  }

  recovery_window_days = 30
}

# ── RDS ───────────────────────────────────────────────────────────────────────
# allowed_security_group_ids is intentionally empty here.
# The ECS → RDS ingress rule is added below via a standalone resource to avoid
# a dependency cycle (rds needs ecs SG id; ecs needs rds secret ARN).

module "rds" {
  source = "../../modules/rds"

  project_name       = var.project_name
  environment        = var.environment
  aws_region         = var.aws_region
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # Rule added below — see aws_security_group_rule.ecs_to_rds
  allowed_security_group_ids = []

  instance_class        = var.db_instance_class
  engine_version        = "15"
  allocated_storage     = 20
  multi_az              = var.environment == "prod" ? false : false
  deletion_protection   = true
  skip_final_snapshot   = false
  backup_retention_days = 7
  recovery_window_days  = 30
}

# ── ALB ───────────────────────────────────────────────────────────────────────

module "alb" {
  source = "../../modules/alb"

  project_name      = var.project_name
  environment       = var.environment
  aws_region        = var.aws_region
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids

  domain_name       = var.domain_name
  route53_zone_id   = var.route53_zone_id
  create_dns_record = true

  container_port       = var.container_port
  health_check_path    = "/api/health/"
  deregistration_delay = 30
}

# ── SHARED CONFIG: env vars + secrets used by both web and celery ─────────────

locals {
  common_env_vars = {
    DJANGO_SETTINGS_MODULE = "config.settings.production"
    AWS_REGION             = var.aws_region
    PORT                   = tostring(var.container_port)
    LOG_LEVEL              = "INFO"
  }

  common_secrets = {
    "DATABASE_URL"   = "${module.rds.db_secret_arn}:DATABASE_URL::"
    "SECRET_KEY"     = "${module.app_secrets.secret_arn}:SECRET_KEY::"
    "RESEND_API_KEY" = "${module.app_secrets.secret_arn}:RESEND_API_KEY::"
    "ALLOWED_HOSTS"  = "${module.app_secrets.secret_arn}:ALLOWED_HOSTS::"
    "CORS_ORIGINS"   = "${module.app_secrets.secret_arn}:CORS_ORIGINS::"
  }

  secret_arns = [
    module.rds.db_secret_arn,
    module.app_secrets.secret_arn,
  ]
}

# ── ECS SERVICE — WEB ─────────────────────────────────────────────────────────

module "ecs_web" {
  source = "../../modules/ecs-service"

  project_name = "${var.project_name}-web"
  environment  = var.environment
  aws_region   = var.aws_region

  cluster_id     = module.ecs_cluster.cluster_id
  log_group_name = module.ecs_cluster.log_group_name

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  alb_target_group_arn  = module.alb.target_group_arn
  alb_security_group_id = module.alb.alb_security_group_id

  image_url      = "${module.ecr.repository_url}:latest"
  cpu            = var.web_cpu
  memory         = var.web_memory
  desired_count  = var.web_desired_count
  container_port = var.container_port

  health_check_path                 = "/api/health/"
  health_check_grace_period_seconds = 90

  enable_migration_task = true

  environment_variables = local.common_env_vars
  secrets               = local.common_secrets
  secret_arns           = local.secret_arns
}

# ── ECS SERVICE — CELERY WORKER ───────────────────────────────────────────────

module "ecs_celery" {
  source = "../../modules/ecs-service"

  project_name = "${var.project_name}-celery"
  environment  = var.environment
  aws_region   = var.aws_region

  cluster_id     = module.ecs_cluster.cluster_id
  log_group_name = module.ecs_cluster.log_group_name

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # No ALB for the worker
  alb_target_group_arn  = null
  alb_security_group_id = null

  image_url     = "${module.ecr.repository_url}:latest"
  cpu           = var.celery_cpu
  memory        = var.celery_memory
  desired_count = var.celery_desired_count
  container_port = var.container_port  # not exposed — worker makes no inbound connections

  health_check_path = "/api/health/"

  environment_variables = merge(local.common_env_vars, {
    IS_CELERY_WORKER = "true"
    CELERY_CONCURRENCY = "2"
  })
  secrets     = local.common_secrets
  secret_arns = local.secret_arns
}

# ── BREAK THE DEPENDENCY CYCLE: ECS → RDS ────────────────────────────────────
# RDS module was created with allowed_security_group_ids = [] to avoid a cycle.
# This standalone rule wires the connection after both SGs exist.

resource "aws_security_group_rule" "ecs_web_to_rds" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.rds.rds_security_group_id
  source_security_group_id = module.ecs_web.task_security_group_id
  description              = "Web ECS tasks to RDS PostgreSQL"
}

resource "aws_security_group_rule" "ecs_celery_to_rds" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.rds.rds_security_group_id
  source_security_group_id = module.ecs_celery.task_security_group_id
  description              = "Celery ECS tasks to RDS PostgreSQL"
}

# ── MIGRATION RUNNER (Terraform-driven, on-demand) ───────────────────────────
# Primary path: deploy.yml CI/CD runs migrations automatically before every deploy.
# This null_resource runs migrations via terraform apply whenever the migration
# task definition family changes (new task def registered).
#
# Requires: AWS CLI + bash (Git Bash on Windows, native on macOS/Linux).
# To skip on apply: terraform apply -target=module.ecs_web (excludes null_resource)

resource "null_resource" "run_migrations" {
  count = var.run_migrations_on_apply ? 1 : 0

  triggers = {
    task_definition = module.ecs_web.migrate_task_definition_family
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      TASK_ARN=$(aws ecs run-task \
        --cluster "${module.ecs_cluster.cluster_id}" \
        --task-definition "${module.ecs_web.migrate_task_definition_family}" \
        --launch-type FARGATE \
        --network-configuration \
          "awsvpcConfiguration={subnets=[${join(",", module.vpc.private_subnet_ids)}],securityGroups=[${module.ecs_web.task_security_group_id}],assignPublicIp=DISABLED}" \
        --query 'tasks[0].taskArn' \
        --output text \
        --no-cli-pager)

      echo "Migration task: $$TASK_ARN"

      aws ecs wait tasks-stopped \
        --cluster "${module.ecs_cluster.cluster_id}" \
        --tasks "$$TASK_ARN" \
        --no-cli-pager

      EXIT_CODE=$(aws ecs describe-tasks \
        --cluster "${module.ecs_cluster.cluster_id}" \
        --tasks "$$TASK_ARN" \
        --query 'tasks[0].containers[0].exitCode' \
        --output text \
        --no-cli-pager)

      echo "Migration exit code: $$EXIT_CODE"
      if [ "$$EXIT_CODE" != "0" ]; then
        echo "ERROR: Migration failed (exit $$EXIT_CODE)" >&2
        exit 1
      fi
      echo "Migrations complete."
    EOT
  }

  depends_on = [module.ecs_web]
}

# ── CICD ──────────────────────────────────────────────────────────────────────
# ⚠️  Creates IAM roles. Review the trust policy variables before applying.

module "cicd" {
  source = "../../modules/cicd"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  create_oidc_provider = var.create_oidc_provider
  github_org           = var.github_org
  github_repo          = var.github_repo
  github_branch        = var.github_branch

  ecr_repository_arn            = module.ecr.repository_arn
  ecs_cluster_arn               = module.ecs_cluster.cluster_arn
  ecs_service_arn               = module.ecs_web.service_id
  task_execution_role_arn       = module.ecs_web.task_execution_role_arn
  task_role_arn                 = module.ecs_web.task_role_arn
  migration_task_definition_arn = module.ecs_web.migrate_task_definition_arn
}
