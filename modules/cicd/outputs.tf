output "github_actions_role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions via OIDC. Set this as the role-to-assume value in aws-actions/configure-aws-credentials in your workflow."
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_role_name" {
  description = "Name of the IAM role assumed by GitHub Actions."
  value       = aws_iam_role.github_actions.name
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider. Shared across all cicd module instances in the same AWS account."
  value       = local.oidc_provider_arn
}

output "ecr_push_policy_arn" {
  description = "ARN of the ECR push IAM policy."
  value       = aws_iam_policy.ecr_push.arn
}

output "ecs_deploy_policy_arn" {
  description = "ARN of the ECS deploy IAM policy."
  value       = aws_iam_policy.ecs_deploy.arn
}
