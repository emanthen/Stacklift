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

variable "secret_name" {
  description = "Secrets Manager secret name. Defaults to '{project}-{env}/app/secrets'. Override to organise multiple secrets under a common path prefix."
  type        = string
  default     = null
}

variable "secret_values" {
  description = <<-EOT
    Initial key-value pairs written to the secret on first apply.
    Terraform ignores subsequent changes — update real values via AWS console or CLI after first apply.
    Mark sensitive keys here with placeholder values; replace them outside Terraform.

    Example:
      secret_values = {
        SECRET_KEY     = "replace-me"
        RESEND_API_KEY = "replace-me"
        STRIPE_SECRET  = "replace-me"
      }
  EOT
  type      = map(string)
  sensitive = true
  default   = {}
}

variable "recovery_window_days" {
  description = "Days Secrets Manager waits before permanently deleting the secret after destruction. Use 0 for immediate deletion in dev environments."
  type        = number
  default     = 30

  validation {
    condition     = var.recovery_window_days == 0 || (var.recovery_window_days >= 7 && var.recovery_window_days <= 30)
    error_message = "recovery_window_days must be 0 (immediate) or between 7 and 30."
  }
}

variable "tags" {
  description = "Additional tags merged onto all resources. Project, Environment, and ManagedBy are always set automatically."
  type        = map(string)
  default     = {}
}
