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

# ── Network (from vpc outputs) ────────────────────────────────────────────────

variable "vpc_id" {
  description = "VPC ID where the ALB will be placed. Use module.vpc.vpc_id."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs across at least 2 AZs for the ALB. Use module.vpc.public_subnet_ids."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "ALB requires at least 2 public subnets in different AZs."
  }
}

# ── DNS and TLS ───────────────────────────────────────────────────────────────

variable "domain_name" {
  description = "Primary domain name for the ACM certificate and Route53 A record (e.g. api.mysaas.com)."
  type        = string
}

variable "subject_alternative_names" {
  description = "Additional domain names to include in the ACM certificate (SANs). Useful for www.mysaas.com alongside api.mysaas.com."
  type        = list(string)
  default     = []
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for the domain. Used for DNS validation records and the A alias record."
  type        = string
}

variable "create_dns_record" {
  description = "Whether to create a Route53 A alias record pointing domain_name to the ALB. Set false if you manage DNS externally."
  type        = bool
  default     = true
}

variable "ssl_policy" {
  description = "ALB HTTPS listener SSL/TLS security policy. ELBSecurityPolicy-TLS13-1-2-2021-06 enables TLS 1.3 and is the current AWS recommended policy."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

# ── Target Group ──────────────────────────────────────────────────────────────

variable "container_port" {
  description = "Port the ECS containers listen on. Must match ecs-service container_port."
  type        = number
  default     = 8000
}

variable "deregistration_delay" {
  description = "Seconds the ALB waits before removing a deregistering target. Lower values speed up rolling deploys. AWS default is 300."
  type        = number
  default     = 30

  validation {
    condition     = var.deregistration_delay >= 0 && var.deregistration_delay <= 3600
    error_message = "deregistration_delay must be between 0 and 3600 seconds."
  }
}

# ── Health Check ──────────────────────────────────────────────────────────────

variable "health_check_path" {
  description = "HTTP path the ALB polls to determine target health. Must return 200–299."
  type        = string
  default     = "/api/health/"
}

variable "health_check_interval" {
  description = "Seconds between ALB health check requests."
  type        = number
  default     = 30

  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "health_check_interval must be between 5 and 300 seconds."
  }
}

variable "health_check_timeout" {
  description = "Seconds the ALB waits for a health check response before marking the check as failed."
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_timeout >= 2 && var.health_check_timeout <= 120
    error_message = "health_check_timeout must be between 2 and 120 seconds."
  }
}

variable "health_check_healthy_threshold" {
  description = "Number of consecutive successful health checks before a target is considered healthy."
  type        = number
  default     = 2

  validation {
    condition     = var.health_check_healthy_threshold >= 2 && var.health_check_healthy_threshold <= 10
    error_message = "health_check_healthy_threshold must be between 2 and 10."
  }
}

variable "health_check_unhealthy_threshold" {
  description = "Number of consecutive failed health checks before a target is considered unhealthy."
  type        = number
  default     = 3

  validation {
    condition     = var.health_check_unhealthy_threshold >= 2 && var.health_check_unhealthy_threshold <= 10
    error_message = "health_check_unhealthy_threshold must be between 2 and 10."
  }
}

# ── ALB Settings ──────────────────────────────────────────────────────────────

variable "idle_timeout" {
  description = "ALB idle connection timeout in seconds. Increase if your API has long-running requests (e.g. file uploads, streaming)."
  type        = number
  default     = 60

  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "idle_timeout must be between 1 and 4000 seconds."
  }
}

variable "enable_deletion_protection" {
  description = "Prevent the ALB from being deleted via the AWS console or API."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags merged onto all resources. Project, Environment, and ManagedBy are always set automatically."
  type        = map(string)
  default     = {}
}
