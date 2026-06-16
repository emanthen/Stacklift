variable "project_name" {
  description = "Name of the project. Used as a prefix on all resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3–30 lowercase letters, numbers, or hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region. Used in the awslogs log driver configuration."
  type        = string
  default     = "us-east-1"
}

# ── Cluster (from ecs-cluster outputs) ───────────────────────────────────────

variable "cluster_id" {
  description = "ECS cluster ID. Use module.ecs_cluster.cluster_id."
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group name for awslogs driver. Use module.ecs_cluster.log_group_name."
  type        = string
}

# ── Network (from vpc outputs) ────────────────────────────────────────────────

variable "vpc_id" {
  description = "VPC ID where ECS tasks run. Use module.vpc.vpc_id."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs where ECS tasks are placed. Use module.vpc.private_subnet_ids."
  type        = list(string)
}

# ── ALB (from alb outputs) ────────────────────────────────────────────────────

variable "alb_target_group_arn" {
  description = "ALB target group ARN to register tasks against. Use module.alb.target_group_arn. Set null for services without an ALB (e.g. Celery workers)."
  type        = string
  default     = null
}

variable "alb_security_group_id" {
  description = "ALB security group ID. Ingress on container_port is scoped to this SG. Use module.alb.alb_security_group_id."
  type        = string
  default     = null
}

# ── Container ─────────────────────────────────────────────────────────────────

variable "image_url" {
  description = "Full ECR image URL including tag (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/mysaas-prod:latest). Use module.ecr.repository_url."
  type        = string
}

variable "cpu" {
  description = "Fargate task CPU units. Valid values: 256, 512, 1024, 2048, 4096."
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.cpu)
    error_message = "cpu must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "memory" {
  description = "Fargate task memory in MB. Must be compatible with the chosen cpu value. See https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html"
  type        = number
  default     = 512

  validation {
    condition     = var.memory >= 512 && var.memory <= 30720
    error_message = "memory must be between 512 and 30720 MB."
  }
}

variable "desired_count" {
  description = "Number of task instances to run. CI/CD pipeline manages this after initial deploy — Terraform ignores drift on this value."
  type        = number
  default     = 1

  validation {
    condition     = var.desired_count >= 0
    error_message = "desired_count must be 0 or greater."
  }
}

variable "container_port" {
  description = "Port the container listens on. Must match what your Django/FastAPI app binds to (e.g. gunicorn --bind 0.0.0.0:8000)."
  type        = number
  default     = 8000
}

variable "health_check_path" {
  description = "HTTP path the container health check polls. Must return 200. Django: add a view at this path that returns 200. FastAPI: /api/health/ or /health."
  type        = string
  default     = "/api/health/"
}

variable "health_check_grace_period_seconds" {
  description = "Seconds ECS waits after a task starts before checking ALB target health. Increase if your app needs more time to run migrations on startup."
  type        = number
  default     = 60
}

# ── Environment and Secrets ───────────────────────────────────────────────────

variable "environment_variables" {
  description = "Plaintext environment variables injected into the container. Do not put secrets here — use var.secrets instead."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = <<-EOT
    Secrets Manager values injected as environment variables at task startup.
    Key   = environment variable name in the container (e.g. "DATABASE_URL")
    Value = Secrets Manager ARN with optional JSON key suffix:
              Full secret as string:  "arn:aws:secretsmanager:...:secret-name"
              Specific JSON key:      "arn:aws:secretsmanager:...:secret-name:KEY_NAME::"
    Example:
      secrets = {
        "DATABASE_URL"   = "${module.rds.db_secret_arn}:DATABASE_URL::"
        "SECRET_KEY"     = "${module.app_secrets.secret_arn}:SECRET_KEY::"
        "RESEND_API_KEY" = "${module.app_secrets.secret_arn}:RESEND_API_KEY::"
      }
  EOT
  type        = map(string)
  default     = {}
}

variable "secret_arns" {
  description = "Base Secrets Manager ARNs the task execution role needs GetSecretValue on. Must include every ARN referenced in var.secrets (without the :KEY:: suffix)."
  type        = list(string)
  default     = []
}

# ── IAM — Task Role ───────────────────────────────────────────────────────────

variable "task_role_policy_arns" {
  description = "Additional IAM policy ARNs to attach to the ECS task role (used by the app at runtime). Use for S3 read, SES send, SQS consume, etc."
  type        = list(string)
  default     = []
}

variable "enable_migration_task" {
  description = "When true, creates an additional ECS task definition for running Django migrations. The task uses the same image, IAM roles, secrets, and log group as the web service but runs 'python manage.py migrate --no-input' as its command. Run via aws ecs run-task in CI/CD — not a long-running service."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags merged onto all resources. Project, Environment, and ManagedBy are always set automatically."
  type        = map(string)
  default     = {}
}
