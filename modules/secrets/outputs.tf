output "secret_arn" {
  description = "ARN of the Secrets Manager secret. Pass to ecs-service as an element of secret_arns for IAM permission, and reference individual keys in the secrets map with the ':KEY::' suffix."
  value       = aws_secretsmanager_secret.this.arn
}

output "secret_name" {
  description = "Name of the Secrets Manager secret. Use to fetch or update values via CLI."
  value       = aws_secretsmanager_secret.this.name
}

output "secret_id" {
  description = "ID of the Secrets Manager secret (same as ARN)."
  value       = aws_secretsmanager_secret.this.id
}

output "read_policy_arn" {
  description = "ARN of the IAM policy that grants GetSecretValue on this secret. Attach to the ECS task execution role via task_role_policy_arns in ecs-service, or attach directly to any role that needs to read this secret."
  value       = aws_iam_policy.read.arn
}

output "read_policy_name" {
  description = "Name of the IAM read policy."
  value       = aws_iam_policy.read.name
}
