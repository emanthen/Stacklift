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
  description = "AWS region where all resources are created."
  type        = string
  default     = "us-east-1"
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights for per-task CPU, memory, and network metrics. Costs ~$0.50 per million metrics ingested."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs in the CloudWatch log group before automatic expiry."
  type        = number
  default     = 30

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "log_retention_days must be a value accepted by CloudWatch Logs: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, or higher standard values."
  }
}

variable "tags" {
  description = "Additional tags merged onto all resources. Project, Environment, and ManagedBy are always set automatically."
  type        = map(string)
  default     = {}
}
