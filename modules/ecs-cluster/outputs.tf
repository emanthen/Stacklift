output "cluster_id" {
  description = "ID of the ECS cluster. Pass to ecs-service as cluster_id."
  value       = aws_ecs_cluster.this.id
}

output "cluster_arn" {
  description = "ARN of the ECS cluster. Pass to the cicd module as ecs_cluster_arn to scope GitHub Actions deploy permissions."
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.this.name
}

output "log_group_name" {
  description = "CloudWatch log group name for all ECS tasks in this cluster. Pass to ecs-service as log_group_name."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group."
  value       = aws_cloudwatch_log_group.this.arn
}
