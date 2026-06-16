locals {
  name_prefix  = "${var.project_name}-${var.environment}"
  db_name      = replace(var.project_name, "-", "_")
  db_username  = replace(var.project_name, "-", "_")
  pg_family    = "postgres${split(".", var.engine_version)[0]}"
  pg_name_slug = replace(var.engine_version, ".", "")
}

# ── MASTER PASSWORD ───────────────────────────────────────────────────────────
# Excluded chars break psql connection strings and shell quoting.

resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#%&*()-_=+[]{}<>:"
}

# ── SECURITY GROUP ────────────────────────────────────────────────────────────

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "PostgreSQL inbound from allowed security groups only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-rds-sg"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "rds_ingress_from_sg" {
  count = length(var.allowed_security_group_ids)

  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = var.allowed_security_group_ids[count.index]
  description              = "PostgreSQL from SG ${count.index + 1}"
}

resource "aws_security_group_rule" "rds_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rds.id
  description       = "Allow all outbound"
}

# ── SUBNET GROUP ──────────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "this" {
  name        = "${local.name_prefix}-rds-subnet-group"
  subnet_ids  = var.private_subnet_ids
  description = "Private subnet group for ${local.name_prefix} RDS"

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-rds-subnet-group"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

# ── PARAMETER GROUP ───────────────────────────────────────────────────────────

resource "aws_db_parameter_group" "this" {
  name        = "${local.name_prefix}-pg${local.pg_name_slug}"
  family      = local.pg_family
  description = "Parameter group for ${local.name_prefix} PostgreSQL ${var.engine_version}"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_duration"
    value = "0"
  }

  # Log queries slower than 1 second — safe default for production
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-rds-pg"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ── ENHANCED MONITORING ROLE ──────────────────────────────────────────────────

data "aws_iam_policy_document" "rds_monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name               = "${local.name_prefix}-rds-monitoring-role"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume.json

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-rds-monitoring-role"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ── RDS INSTANCE ──────────────────────────────────────────────────────────────
# ⚠️  prevent_destroy = true is set on this resource.
#     To run terraform destroy you must first remove or comment out the
#     lifecycle block below, then run terraform apply, then destroy.

resource "aws_db_instance" "this" {
  identifier = "${local.name_prefix}-rds"

  engine               = "postgres"
  engine_version       = var.engine_version
  parameter_group_name = aws_db_parameter_group.this.name

  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = local.db_name
  username = local.db_username
  password = random_password.master.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  port                   = 5432

  multi_az = var.multi_az

  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name_prefix}-final-snapshot"
  copy_tags_to_snapshot     = true

  deletion_protection = var.deletion_protection

  # Free tier: Performance Insights with 7-day retention
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  # Enhanced monitoring at 60-second granularity (included in RDS cost)
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  auto_minor_version_upgrade = true

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-rds"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })

  lifecycle {
    prevent_destroy = true
    # Password is rotated externally via Secrets Manager — ignore drift here
    ignore_changes = [password]
  }

  depends_on = [
    aws_db_subnet_group.this,
    aws_iam_role_policy_attachment.rds_monitoring,
  ]
}

# ── SECRETS MANAGER ───────────────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "db" {
  name                    = "${local.name_prefix}/rds/credentials"
  description             = "RDS master credentials for ${local.name_prefix}"
  recovery_window_in_days = var.recovery_window_days

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-rds-secret"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    engine   = "postgres"
    host     = aws_db_instance.this.address
    port     = tostring(aws_db_instance.this.port)
    dbname   = aws_db_instance.this.db_name
    username = aws_db_instance.this.username
    password = random_password.master.result

    # DATABASE_URL ready for Django/FastAPI settings.py — password is URL-encoded
    DATABASE_URL = "postgres://${aws_db_instance.this.username}:${urlencode(random_password.master.result)}@${aws_db_instance.this.address}:${aws_db_instance.this.port}/${aws_db_instance.this.db_name}"
  })

  lifecycle {
    # Allow external rotation without Terraform flagging drift on every plan
    ignore_changes = [secret_string]
  }
}
