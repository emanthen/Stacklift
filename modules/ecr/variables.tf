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

variable "repository_name" {
  description = "ECR repository name. Defaults to '{project_name}-{environment}' when null."
  type        = string
  default     = null
}

variable "image_tag_mutability" {
  description = "Whether image tags can be overwritten. MUTABLE allows re-pushing :latest. IMMUTABLE enforces unique tags per push (more secure, requires unique tag per CI run)."
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Enable automatic vulnerability scanning on every image push (AWS Basic Scanning — free)."
  type        = bool
  default     = true
}

variable "keep_image_count" {
  description = "Number of tagged images to retain per lifecycle policy rule. Older images beyond this count are expired."
  type        = number
  default     = 10

  validation {
    condition     = var.keep_image_count >= 1 && var.keep_image_count <= 1000
    error_message = "keep_image_count must be between 1 and 1000."
  }
}

variable "github_actions_role_arns" {
  description = "IAM role ARNs for GitHub Actions OIDC. These roles receive push + pull permissions via the repository policy. Use module.cicd.github_actions_role_arn."
  type        = list(string)
  default     = []
}

variable "task_execution_role_arns" {
  description = "IAM role ARNs for ECS task execution. These roles receive pull-only permissions via the repository policy. Use module.ecs_service.task_execution_role_arn."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags merged onto all resources. Project, Environment, and ManagedBy are always set automatically."
  type        = map(string)
  default     = {}
}
