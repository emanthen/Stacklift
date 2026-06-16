variable "project_name" {
  description = "Name of the project. Used as a prefix on all resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3–22 lowercase letters, numbers, or hyphens, starting with a letter. No trailing hyphens."
  }
}

variable "environment" {
  description = "Deployment environment. Controls naming and tagging."
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

variable "cidr_block" {
  description = "CIDR block for the VPC. Must be a valid /16 to /24 range."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid CIDR notation (e.g. 10.0.0.0/16)."
  }
}

variable "az_count" {
  description = "Number of Availability Zones to use. Actual count is capped at available AZs in the region."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 4
    error_message = "az_count must be between 1 and 4."
  }
}

variable "enable_nat_gateway" {
  description = "Whether to create NAT Gateway(s) for private subnet internet access. Required for ECS tasks pulling from ECR."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway shared across all AZs. Reduces cost (~$32/mo per NAT). Set false for production HA."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags merged onto all resources. Project, Environment, and ManagedBy are always set automatically."
  type        = map(string)
  default     = {}
}
