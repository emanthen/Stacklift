output "service_name" {
  description = "Name of the ECS service. Pass to the cicd module as ecs_service_name."
  value       = aws_ecs_service.this.name
}

output "service_id" {
  description = "Full ARN of the ECS service."
  value       = aws_ecs_service.this.id
}

output "task_definition_arn" {
  description = "ARN of the latest Terraform-managed task definition. The CI/CD pipeline registers new revisions — this output reflects the initial revision only."
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_family" {
  description = "Task definition family name. Used in GitHub Actions to fetch the current task definition before updating the image."
  value       = aws_ecs_task_definition.this.family
}

output "task_execution_role_arn" {
  description = "ARN of the ECS task execution role. Pass to the ecr module as task_execution_role_arns."
  value       = aws_iam_role.task_execution.arn
}

output "task_execution_role_name" {
  description = "Name of the ECS task execution role."
  value       = aws_iam_role.task_execution.name
}

output "task_role_arn" {
  description = "ARN of the ECS task role (assumed by the app container at runtime)."
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "Name of the ECS task role."
  value       = aws_iam_role.task.name
}

output "task_security_group_id" {
  description = "ID of the ECS tasks security group. Pass to module.rds as allowed_security_group_ids so RDS accepts connections from ECS."
  value       = aws_security_group.ecs_tasks.id
}
