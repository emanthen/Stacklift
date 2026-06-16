locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # OIDC sub claim — scoped to a specific repo + branch by default.
  # StringLike allows wildcard; swap to StringEquals for exact match.
  github_sub = coalesce(
    var.github_sub_claim_override,
    "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${var.github_branch}"
  )
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── GITHUB ACTIONS OIDC PROVIDER ──────────────────────────────────────────────
# ⚠️  One OIDC provider per URL per AWS account. If you already have
#     token.actions.githubusercontent.com registered, set create_oidc_provider = false
#     and this module will look it up instead.

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # Both thumbprints cover old and new GitHub OIDC leaf certificates.
  # AWS validates GitHub tokens via the well-known endpoint (not thumbprint)
  # as of Oct 2023 — these are still required by the API but not used for validation.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = merge(var.tags, {
    Name      = "github-actions-oidc-provider"
    ManagedBy = "stacklift"
  })
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_oidc_provider \
    ? aws_iam_openid_connect_provider.github[0].arn \
    : data.aws_iam_openid_connect_provider.github[0].arn
}

# ── GITHUB ACTIONS IAM ROLE ───────────────────────────────────────────────────
# ⚠️  The condition below restricts which repo + branch can assume this role.
#     Verify github_org, github_repo, and github_branch match your repo exactly.

data "aws_iam_policy_document" "github_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.github_sub]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${local.name_prefix}-github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json
  description        = "Assumed by GitHub Actions for ${var.github_org}/${var.github_repo} on ${var.github_branch}"

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-github-actions-role"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
    GitHubRepo  = "${var.github_org}/${var.github_repo}"
    GitHubBranch = var.github_branch
  })
}

# ── POLICY: ECR PUSH ─────────────────────────────────────────────────────────

data "aws_iam_policy_document" "ecr_push" {
  # GetAuthorizationToken is account-level — cannot be scoped to a repo ARN
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
    ]
    resources = [var.ecr_repository_arn]
  }
}

resource "aws_iam_policy" "ecr_push" {
  name        = "${local.name_prefix}-gha-ecr-push"
  description = "Allows GitHub Actions to push images to ECR for ${local.name_prefix}"
  policy      = data.aws_iam_policy_document.ecr_push.json

  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

resource "aws_iam_role_policy_attachment" "ecr_push" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ecr_push.arn
}

# ── POLICY: ECS DEPLOY ────────────────────────────────────────────────────────

data "aws_iam_policy_document" "ecs_deploy" {
  # Register new task definition revisions
  statement {
    sid    = "ECSRegisterTaskDef"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:DeregisterTaskDefinition",
    ]
    resources = ["*"]
    # Note: RegisterTaskDefinition/DescribeTaskDefinition do not support
    # resource-level permissions in the IAM policy — must use "*" here.
    # The task definition family is constrained by the ecs:UpdateService scope below.
  }

  # Update the specific service
  statement {
    sid    = "ECSUpdateService"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = [var.ecs_service_arn]
  }

  # Describe cluster for wait-for-stability checks
  statement {
    sid       = "ECSDescribeCluster"
    effect    = "Allow"
    actions   = ["ecs:DescribeClusters"]
    resources = [var.ecs_cluster_arn]
  }

  # RunTask — required by the migration step in deploy.yml (aws ecs run-task).
  # Resources: cluster ARN + wildcard under it + migration task def ARN when provided.
  # compact() drops the task def entry when migration_task_definition_arn = "".
  # The ecs:cluster condition pins the action to this specific cluster.
  statement {
    sid     = "ECSRunTask"
    effect  = "Allow"
    actions = ["ecs:RunTask"]
    resources = compact([
      var.ecs_cluster_arn,
      "${var.ecs_cluster_arn}/*",
      var.migration_task_definition_arn,
    ])
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [var.ecs_cluster_arn]
    }
  }

  # DescribeTasks/ListTasks/StopTask — used by aws ecs wait tasks-stopped
  # and the exit-code check after migrations complete.
  # Task ARNs are not known at policy creation time; resources = "*" is
  # restricted to this cluster via the ecs:cluster condition.
  statement {
    sid    = "ECSManageTasks"
    effect = "Allow"
    actions = [
      "ecs:DescribeTasks",
      "ecs:ListTasks",
      "ecs:StopTask",
    ]
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [var.ecs_cluster_arn]
    }
  }

  # ⚠️  PassRole — required for both RegisterTaskDefinition and RunTask.
  #     Scoped to the task execution role + task role only.
  statement {
    sid     = "PassRolesToECS"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = compact([
      var.task_execution_role_arn,
      var.task_role_arn,
    ])
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "ecs_deploy" {
  name        = "${local.name_prefix}-gha-ecs-deploy"
  description = "Allows GitHub Actions to update ECS task definitions and services for ${local.name_prefix}"
  policy      = data.aws_iam_policy_document.ecs_deploy.json

  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

resource "aws_iam_role_policy_attachment" "ecs_deploy" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ecs_deploy.arn
}

# ── POLICY: SECRETS READ (OPTIONAL) ──────────────────────────────────────────
# Attach when CI/CD needs to read secrets at deploy time (e.g. for smoke tests).
# ECS task startup already reads secrets via the task execution role — this is
# only needed if the GitHub Actions workflow itself reads a secret value.

data "aws_iam_policy_document" "secrets_read" {
  count = length(var.secret_arns) > 0 ? 1 : 0

  statement {
    sid    = "SecretsRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = var.secret_arns
  }
}

resource "aws_iam_policy" "secrets_read" {
  count = length(var.secret_arns) > 0 ? 1 : 0

  name        = "${local.name_prefix}-gha-secrets-read"
  description = "Allows GitHub Actions to read Secrets Manager values at deploy time for ${local.name_prefix}"
  policy      = data.aws_iam_policy_document.secrets_read[0].json

  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

resource "aws_iam_role_policy_attachment" "secrets_read" {
  count = length(var.secret_arns) > 0 ? 1 : 0

  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.secrets_read[0].arn
}

# ── POLICY: S3 ACCESS (OPTIONAL) ─────────────────────────────────────────────
# Attach when CI/CD uploads static assets (e.g. collected Django staticfiles)
# to S3 as part of the deploy workflow.

data "aws_iam_policy_document" "s3_deploy" {
  count = length(var.s3_bucket_arns) > 0 ? 1 : 0

  statement {
    sid    = "S3ListBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = var.s3_bucket_arns
  }

  statement {
    sid    = "S3ReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [for arn in var.s3_bucket_arns : "${arn}/*"]
  }
}

resource "aws_iam_policy" "s3_deploy" {
  count = length(var.s3_bucket_arns) > 0 ? 1 : 0

  name        = "${local.name_prefix}-gha-s3-deploy"
  description = "Allows GitHub Actions to upload static assets to S3 for ${local.name_prefix}"
  policy      = data.aws_iam_policy_document.s3_deploy[0].json

  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

resource "aws_iam_role_policy_attachment" "s3_deploy" {
  count = length(var.s3_bucket_arns) > 0 ? 1 : 0

  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.s3_deploy[0].arn
}
