output "db_instance_id" {
  description = "RDS instance identifier."
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "ARN of the RDS instance."
  value       = aws_db_instance.this.arn
}

output "db_endpoint" {
  description = "Full connection endpoint (host:port). Use in DATABASE_URL."
  value       = aws_db_instance.this.endpoint
}

output "db_address" {
  description = "Hostname of the RDS instance (without port). Pass to ecs-service as an environment variable if needed."
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "Port the RDS instance listens on (5432)."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Name of the default database created on the instance."
  value       = aws_db_instance.this.db_name
}

output "db_username" {
  description = "Master username for the database."
  value       = aws_db_instance.this.username
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the DB credentials and DATABASE_URL. Pass to ecs-service as secret_arns."
  value       = aws_secretsmanager_secret.db.arn
}

output "db_secret_name" {
  description = "Name of the Secrets Manager secret."
  value       = aws_secretsmanager_secret.db.name
}

output "rds_security_group_id" {
  description = "ID of the RDS security group. Pass to allowed_security_group_ids after ECS service is known — Terraform resolves the ordering."
  value       = aws_security_group.rds.id
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group."
  value       = aws_db_subnet_group.this.name
}

output "db_parameter_group_name" {
  description = "Name of the DB parameter group."
  value       = aws_db_parameter_group.this.name
}
