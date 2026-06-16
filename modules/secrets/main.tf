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
  name_prefix = "${var.project_name}-${var.environment}"
  secret_name = coalesce(var.secret_name, "${var.project_name}-${var.environment}/app/secrets")
}

# ── SECRET ────────────────────────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "this" {
  name                    = local.secret_name
  description             = "Application secrets for ${local.name_prefix}"
  recovery_window_in_days = var.recovery_window_days

  tags = merge(var.tags, {
    Name        = local.secret_name
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

# ── SECRET VERSION ────────────────────────────────────────────────────────────
# Terraform writes the initial values from var.secret_values.
# After first apply, update real values in the AWS console or via CLI:
#   aws secretsmanager put-secret-value \
#     --secret-id <secret_name> \
#     --secret-string '{"SECRET_KEY":"real-value","RESEND_API_KEY":"real-value"}'
# ignore_changes prevents Terraform from reverting those updates on the next apply.

resource "aws_secretsmanager_secret_version" "this" {
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = jsonencode(var.secret_values)

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ── IAM READ POLICY ───────────────────────────────────────────────────────────
# Attach this policy to the ECS task execution role so ECS can inject secrets
# at task startup. Pass secret_arn to ecs-service.secret_arns instead if you
# prefer the inline policy approach.

data "aws_iam_policy_document" "read" {
  statement {
    sid    = "GetSecretValue"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.this.arn]
  }
}

resource "aws_iam_policy" "read" {
  name        = "${local.name_prefix}-secrets-read-policy"
  description = "Grants ECS task execution role read access to ${local.secret_name}"
  policy      = data.aws_iam_policy_document.read.json

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-secrets-read-policy"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}
