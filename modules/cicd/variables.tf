variable "project_name" {
  description = "Name of the project. Used as a prefix on all resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3–22 lowercase letters, numbers, or hyphens, starting with a letter. No trailing hyphens."
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
  description = "AWS region where all resources are created."
  type        = string
  default     = "us-east-1"
}

# ── GitHub OIDC ───────────────────────────────────────────────────────────────

variable "create_oidc_provider" {
  description = "Create the GitHub Actions OIDC provider in this AWS account. Set false if the provider already exists (only one is allowed per account per URL). Check: aws iam list-open-id-connect-providers --no-cli-pager"
  type        = bool
  default     = true
}

variable "github_org" {
  description = "GitHub organisation or username that owns the repository (e.g. 'acme-corp' or 'prabhat')."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name without the org prefix (e.g. 'mysaas')."
  type        = string
}

variable "github_branch" {
  description = "Branch that is allowed to assume the IAM role. Pushes from other branches will be denied. Use 'main' or 'master' for production deploys."
  type        = string
  default     = "main"
}

variable "github_sub_claim_override" {
  description = "Override the full OIDC sub claim condition. Useful for allowing PR workflows, tags, or environments. Default: 'repo:{org}/{repo}:ref:refs/heads/{branch}'. Example for any branch: 'repo:acme/mysaas:*'"
  type        = string
  default     = null
}

# ── ECR ───────────────────────────────────────────────────────────────────────

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository GitHub Actions will push images to. Use module.ecr.repository_arn."
  type        = string
}

# ── ECS ───────────────────────────────────────────────────────────────────────

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster. Use module.ecs_cluster.cluster_arn."
  type        = string
}

variable "ecs_service_arn" {
  description = "Full ARN of the ECS service GitHub Actions will update. Use module.ecs_service.service_id."
  type        = string
}

variable "migration_task_definition_arn" {
  description = "ARN of the migration ECS task definition. When set, ecs:RunTask is scoped to this ARN (instead of *). Use module.ecs_web.migrate_task_definition_arn. Leave empty if enable_migration_task = false."
  type        = string
  default     = ""
}

# ── IAM PassRole ─────────────────────────────────────────────────────────────

variable "task_execution_role_arn" {
  description = "ARN of the ECS task execution role. Required for iam:PassRole when registering new task definition revisions. Use module.ecs_service.task_execution_role_arn."
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS task role (app runtime). Required for iam:PassRole. Use module.ecs_service.task_role_arn."
  type        = string
  default     = null
}

# ── Optional: Secrets Manager ─────────────────────────────────────────────────

variable "secret_arns" {
  description = "Secrets Manager ARNs the GitHub Actions workflow can read at deploy time (e.g. for smoke tests). Not needed if secrets are only read by ECS tasks at startup."
  type        = list(string)
  default     = []
}

# ── Optional: S3 ─────────────────────────────────────────────────────────────

variable "s3_bucket_arns" {
  description = "S3 bucket ARNs GitHub Actions can read/write during deploy (e.g. for uploading Django collectstatic output). Each ARN gets ListBucket + GetObject + PutObject + DeleteObject."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags merged onto all resources. Project, Environment, and ManagedBy are always set automatically."
  type        = map(string)
  default     = {}
}
