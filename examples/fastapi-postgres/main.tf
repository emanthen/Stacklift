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
  }

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
# Terraform writes placeholders on first apply.
# Update real values after apply:
#   aws secretsmanager put-secret-value --secret-id <name> --secret-string '{...}'

module "app_secrets" {
  source = "../../modules/secrets"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  secret_values = {
    APP_SECRET_KEY = "replace-me-after-apply"
    RESEND_API_KEY = "replace-me-after-apply"
    ALLOWED_ORIGINS = "https://${var.domain_name}"
  }

  recovery_window_days = 30
}

# ── RDS ───────────────────────────────────────────────────────────────────────
# allowed_security_group_ids left empty — ECS→RDS rule added below to avoid
# the dependency cycle (rds needs ecs SG; ecs needs rds secret ARN).

module "rds" {
  source = "../../modules/rds"

  project_name       = var.project_name
  environment        = var.environment
  aws_region         = var.aws_region
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  allowed_security_group_ids = []

  instance_class        = var.db_instance_class
  engine_version        = "15"
  allocated_storage     = 20
  multi_az              = false
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
  health_check_path    = "/health"
  deregistration_delay = 30
}

# ── ECS SERVICE ───────────────────────────────────────────────────────────────

module "ecs_service" {
  source = "../../modules/ecs-service"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  cluster_id     = module.ecs_cluster.cluster_id
  log_group_name = module.ecs_cluster.log_group_name

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  alb_target_group_arn  = module.alb.target_group_arn
  alb_security_group_id = module.alb.alb_security_group_id

  image_url      = "${module.ecr.repository_url}:latest"
  cpu            = var.app_cpu
  memory         = var.app_memory
  desired_count  = var.app_desired_count
  container_port = var.container_port

  health_check_path                 = "/health"
  health_check_grace_period_seconds = 60

  environment_variables = {
    ENVIRONMENT = var.environment
    AWS_REGION  = var.aws_region
    PORT        = tostring(var.container_port)
    LOG_LEVEL   = "info"
  }

  secrets = {
    "DATABASE_URL"    = "${module.rds.db_secret_arn}:DATABASE_URL::"
    "APP_SECRET_KEY"  = "${module.app_secrets.secret_arn}:APP_SECRET_KEY::"
    "RESEND_API_KEY"  = "${module.app_secrets.secret_arn}:RESEND_API_KEY::"
    "ALLOWED_ORIGINS" = "${module.app_secrets.secret_arn}:ALLOWED_ORIGINS::"
  }

  secret_arns = [
    module.rds.db_secret_arn,
    module.app_secrets.secret_arn,
  ]
}

# ── BREAK THE DEPENDENCY CYCLE: ECS → RDS ────────────────────────────────────

resource "aws_security_group_rule" "ecs_to_rds" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.rds.rds_security_group_id
  source_security_group_id = module.ecs_service.task_security_group_id
  description              = "ECS tasks to RDS PostgreSQL"
}

# ── CICD ──────────────────────────────────────────────────────────────────────
# ⚠️  Creates IAM roles. Review github_org, github_repo, github_branch before applying.

module "cicd" {
  source = "../../modules/cicd"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  create_oidc_provider = var.create_oidc_provider
  github_org           = var.github_org
  github_repo          = var.github_repo
  github_branch        = var.github_branch

  ecr_repository_arn      = module.ecr.repository_arn
  ecs_cluster_arn         = module.ecs_cluster.cluster_arn
  ecs_service_arn         = module.ecs_service.service_id
  task_execution_role_arn = module.ecs_service.task_execution_role_arn
  task_role_arn           = module.ecs_service.task_role_arn
}
