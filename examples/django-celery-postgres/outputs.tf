output "alb_dns_name" {
  description = "ALB DNS name. Use this to verify the load balancer before DNS propagates."
  value       = module.alb.alb_dns_name
}

output "domain_name" {
  description = "Domain name serving the application."
  value       = module.alb.domain_name
}

output "ecr_repository_url" {
  description = "Full ECR repository URL for docker build/push commands."
  value       = module.ecr.repository_url
}

output "ecr_repository_name" {
  description = "ECR repository name. Set as ECR_REPOSITORY in GitHub Actions variables."
  value       = module.ecr.repository_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name. Set as ECS_CLUSTER in GitHub Actions variables."
  value       = module.ecs_cluster.cluster_name
}

output "ecs_web_service_name" {
  description = "ECS web service name. Set as ECS_WEB_SERVICE in GitHub Actions variables."
  value       = module.ecs_web.service_name
}

output "ecs_celery_service_name" {
  description = "ECS Celery worker service name. Set as ECS_CELERY_SERVICE in GitHub Actions variables."
  value       = module.ecs_celery.service_name
}

output "ecs_web_task_family" {
  description = "Web task definition family. Set as ECS_TASK_FAMILY in GitHub Actions variables."
  value       = module.ecs_web.task_definition_family
}

output "ecs_celery_task_family" {
  description = "Celery task definition family. Set as ECS_CELERY_TASK_FAMILY in GitHub Actions variables."
  value       = module.ecs_celery.task_definition_family
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC. Set as AWS_ROLE_ARN in GitHub Actions variables."
  value       = module.cicd.github_actions_role_arn
}

output "rds_endpoint" {
  description = "RDS instance endpoint (host:port)."
  value       = module.rds.db_endpoint
}

output "db_secret_arn" {
  description = "Secrets Manager ARN for RDS credentials (includes DATABASE_URL)."
  value       = module.rds.db_secret_arn
}

output "app_secret_arn" {
  description = "Secrets Manager ARN for application secrets (SECRET_KEY, API keys, etc.)."
  value       = module.app_secrets.secret_arn
}

output "app_secret_name" {
  description = "Secrets Manager secret name. Use in put-secret-value CLI commands."
  value       = module.app_secrets.secret_name
}

output "log_group_name" {
  description = "CloudWatch log group. Use with: aws logs tail <name> --follow --no-cli-pager"
  value       = module.ecs_cluster.log_group_name
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}
