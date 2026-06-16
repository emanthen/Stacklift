terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  name_prefix   = "${var.project_name}-${var.environment}"
  log_group_name = "/stacklift/${var.project_name}/${var.environment}"
}

# ── ECS CLUSTER ───────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-cluster"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

# ── CAPACITY PROVIDERS ────────────────────────────────────────────────────────
# Both FARGATE and FARGATE_SPOT are registered.
# Default strategy uses FARGATE. Override in ecs-service for SPOT workloads.

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# ── CLOUDWATCH LOG GROUP ──────────────────────────────────────────────────────
# All ECS tasks in this cluster write here via the awslogs driver.
# Log group name is passed to ecs-service so the task definition can reference it.

resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name        = local.log_group_name
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}
