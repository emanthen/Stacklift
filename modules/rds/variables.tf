variable "project_name" {
  description = "Name of the project. Used as a prefix on all resource names and as the database name / username."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3–22 lowercase letters, numbers, or hyphens, starting with a letter. No trailing hyphens. RDS identifiers must begin with a letter."
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

# ── Network (from vpc module outputs) ────────────────────────────────────────

variable "vpc_id" {
  description = "VPC ID where the RDS instance will be placed. Use module.vpc.vpc_id."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the DB subnet group. Use module.vpc.private_subnet_ids."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to reach PostgreSQL on port 5432. Pass [module.ecs_service.task_security_group_id]."
  type        = list(string)
  default     = []
}

# ── Instance ─────────────────────────────────────────────────────────────────

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "engine_version" {
  description = "PostgreSQL engine version. Must be a version supported by RDS (e.g. '15', '15.4', '16.1')."
  type        = string
  default     = "15"
}

variable "allocated_storage" {
  description = "Allocated storage in GB. gp3 volumes have no minimum IOPS charge below 3000."
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20 && var.allocated_storage <= 65536
    error_message = "allocated_storage must be between 20 and 65536 GB."
  }
}

# ── Availability ──────────────────────────────────────────────────────────────

variable "multi_az" {
  description = "Enable Multi-AZ for automatic failover. Doubles the instance cost. Recommended for prod."
  type        = bool
  default     = false
}

# ── Protection ───────────────────────────────────────────────────────────────

variable "deletion_protection" {
  description = "Prevent the instance from being deleted via the AWS console or API. Must be disabled before terraform destroy."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot when the instance is deleted. Set true only for throwaway dev environments."
  type        = bool
  default     = false
}

# ── Backups ───────────────────────────────────────────────────────────────────

variable "backup_retention_days" {
  description = "Number of days to retain automated backups. 0 disables backups (not recommended)."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 0 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 0 and 35."
  }
}

# ── Secrets Manager ───────────────────────────────────────────────────────────

variable "recovery_window_days" {
  description = "Days Secrets Manager waits before permanently deleting a secret after destroy. Set 0 to delete immediately (dev only)."
  type        = number
  default     = 30

  validation {
    condition     = var.recovery_window_days == 0 || (var.recovery_window_days >= 7 && var.recovery_window_days <= 30)
    error_message = "recovery_window_days must be 0 (immediate delete) or between 7 and 30."
  }
}

variable "tags" {
  description = "Additional tags merged onto all resources. Project, Environment, and ManagedBy are always set automatically."
  type        = map(string)
  default     = {}
}
