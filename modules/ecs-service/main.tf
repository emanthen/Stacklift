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
  name_prefix    = "${var.project_name}-${var.environment}"
  container_name = "app"
}

# ── IAM — TASK EXECUTION ROLE ─────────────────────────────────────────────────
# Used by the ECS agent to pull images from ECR, read secrets, and write logs.

data "aws_iam_policy_document" "execution_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${local.name_prefix}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.execution_assume.json

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-ecs-execution-role"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "secrets_read" {
  count = length(var.secret_arns) > 0 ? 1 : 0

  statement {
    sid    = "ReadSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = var.secret_arns
  }
}

resource "aws_iam_role_policy" "secrets_read" {
  count = length(var.secret_arns) > 0 ? 1 : 0

  name   = "${local.name_prefix}-ecs-secrets-read"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.secrets_read[0].json
}

# ── IAM — TASK ROLE ───────────────────────────────────────────────────────────
# Assumed by the application container at runtime. Empty by default.
# Extend via task_role_policy_arns for S3, SQS, SES, etc.

data "aws_iam_policy_document" "task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task" {
  name               = "${local.name_prefix}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-ecs-task-role"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

resource "aws_iam_role_policy_attachment" "task_extra" {
  count = length(var.task_role_policy_arns)

  role       = aws_iam_role.task.name
  policy_arn = var.task_role_policy_arns[count.index]
}

# ── SECURITY GROUP ────────────────────────────────────────────────────────────

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks-sg"
  description = "ECS tasks: inbound from ALB only, all outbound"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-ecs-tasks-sg"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "ecs_ingress_alb" {
  count = var.alb_security_group_id != null ? 1 : 0

  type                     = "ingress"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_tasks.id
  source_security_group_id = var.alb_security_group_id
  description              = "Container port from ALB"
}

resource "aws_security_group_rule" "ecs_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs_tasks.id
  description       = "Allow all outbound (ECR pull, Secrets Manager, external APIs)"
}

# ── TASK DEFINITION ───────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "this" {
  family                   = "${local.name_prefix}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = var.image_url
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        for k, v in var.environment_variables : { name = k, value = v }
      ]

      secrets = [
        for k, v in var.secrets : { name = k, valueFrom = v }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = local.container_name
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -sf http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-task"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

# ── ECS SERVICE ───────────────────────────────────────────────────────────────

resource "aws_ecs_service" "this" {
  name            = "${local.name_prefix}-service"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  launch_type = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = var.alb_target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.alb_target_group_arn
      container_name   = local.container_name
      container_port   = var.container_port
    }
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-service"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })

  lifecycle {
    # CI/CD pipeline owns task_definition updates — prevent Terraform drift
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [
    aws_iam_role_policy_attachment.execution_managed,
    aws_iam_role_policy.secrets_read,
  ]
}
