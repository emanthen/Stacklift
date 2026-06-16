variable "project_name" {
  description = "Name of the project. Prefix for all AWS resource names."
  type        = string
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
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

# ── DNS ───────────────────────────────────────────────────────────────────────

variable "domain_name" {
  description = "Domain name for the ALB (e.g. api.mysaas.com). Must exist in the Route53 hosted zone."
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for the domain."
  type        = string
}

# ── Database ──────────────────────────────────────────────────────────────────

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

# ── ECS ───────────────────────────────────────────────────────────────────────

variable "container_port" {
  description = "Port uvicorn listens on inside the container."
  type        = number
  default     = 8000
}

variable "app_cpu" {
  description = "Fargate CPU units."
  type        = number
  default     = 256
}

variable "app_memory" {
  description = "Fargate memory in MB."
  type        = number
  default     = 512
}

variable "app_desired_count" {
  description = "Number of task instances."
  type        = number
  default     = 1
}

# ── Logging ───────────────────────────────────────────────────────────────────

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 30
}

# ── GitHub OIDC ───────────────────────────────────────────────────────────────

variable "github_org" {
  description = "GitHub organisation or username."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without the org prefix)."
  type        = string
}

variable "github_branch" {
  description = "Branch that triggers deployments."
  type        = string
  default     = "main"
}

variable "create_oidc_provider" {
  description = "Create the GitHub Actions OIDC provider. Set false if already exists in this account."
  type        = bool
  default     = true
}
