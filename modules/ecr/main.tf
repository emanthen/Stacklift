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
  name_prefix     = "${var.project_name}-${var.environment}"
  repository_name = coalesce(var.repository_name, "${var.project_name}-${var.environment}")

  # Collect all principal ARNs that need push/pull access
  push_principal_arns = compact(concat(
    var.github_actions_role_arns,
    [],
  ))

  pull_principal_arns = compact(concat(
    var.task_execution_role_arns,
    var.github_actions_role_arns,
  ))

  has_push_principals = length(local.push_principal_arns) > 0
  has_pull_principals = length(local.pull_principal_arns) > 0
  has_any_principals  = local.has_push_principals || local.has_pull_principals
}

# ── ECR REPOSITORY ────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "this" {
  name                 = local.repository_name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name        = local.repository_name
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

# ── LIFECYCLE POLICY ──────────────────────────────────────────────────────────
# Rule 1: expire untagged images after 1 day (keeps the repo clean of build noise)
# Rule 2: keep the last N tagged images (per var.keep_image_count)

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last ${var.keep_image_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha-", "latest"]
          countType     = "imageCountMoreThan"
          countNumber   = var.keep_image_count
        }
        action = { type = "expire" }
      },
    ]
  })
}

# ── REPOSITORY POLICY ─────────────────────────────────────────────────────────
# Resource-based policy granting push access to GitHub Actions role and
# pull access to ECS task execution roles.
# Note: ecr:GetAuthorizationToken is account-level and lives in the IAM
# role policies (cicd module), not here.

data "aws_iam_policy_document" "ecr_policy" {
  count = local.has_any_principals ? 1 : 0

  dynamic "statement" {
    for_each = local.has_push_principals ? [1] : []
    content {
      sid    = "AllowPush"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = local.push_principal_arns
      }
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
      ]
    }
  }

  dynamic "statement" {
    for_each = local.has_pull_principals ? [1] : []
    content {
      sid    = "AllowPull"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = local.pull_principal_arns
      }
      actions = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:DescribeImages",
      ]
    }
  }
}

resource "aws_ecr_repository_policy" "this" {
  count = local.has_any_principals ? 1 : 0

  repository = aws_ecr_repository.this.name
  policy     = data.aws_iam_policy_document.ecr_policy[0].json
}
