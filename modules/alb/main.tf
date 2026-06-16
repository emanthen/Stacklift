locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ── SECURITY GROUP ────────────────────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB: HTTP and HTTPS inbound from internet, all outbound to ECS"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-alb-sg"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "alb_ingress_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet"
}

resource "aws_security_group_rule" "alb_ingress_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
}

resource "aws_security_group_rule" "alb_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "All outbound to ECS tasks"
}

# ── ACM CERTIFICATE ───────────────────────────────────────────────────────────

resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-cert"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ── DNS VALIDATION RECORDS ────────────────────────────────────────────────────

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]

  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]

  # Default provider timeout is 75 min. 30 min fails fast if DNS is misconfigured
  # rather than silently hanging terraform apply for over an hour.
  timeouts {
    create = "30m"
  }
}

# ── APPLICATION LOAD BALANCER ─────────────────────────────────────────────────

resource "aws_lb" "this" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  # Prevents HTTP request smuggling attacks
  drop_invalid_header_fields = true

  idle_timeout               = var.idle_timeout
  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-alb"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

# ── TARGET GROUP ──────────────────────────────────────────────────────────────

resource "aws_lb_target_group" "this" {
  name        = "${local.name_prefix}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"  # required for Fargate awsvpc networking

  # Shorter than AWS default (300s) — faster drain during rolling deploys
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    matcher             = "200-299"
  }

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-tg"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ── HTTP LISTENER — redirect to HTTPS ─────────────────────────────────────────

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-listener-http"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

# ── HTTPS LISTENER — forward to target group ──────────────────────────────────

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = aws_acm_certificate_validation.this.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  # Explicit dependency — the implicit one via certificate_arn is sufficient for
  # planning but AWS rejects the listener if the cert is still PENDING_VALIDATION
  # at the moment of creation. This guarantees the cert is ISSUED first.
  depends_on = [aws_acm_certificate_validation.this]

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-listener-https"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

# ── ROUTE53 ALIAS RECORD ──────────────────────────────────────────────────────
# Points domain_name → ALB DNS name.
# Set create_dns_record = false if you manage DNS outside Terraform.

resource "aws_route53_record" "alb" {
  count = var.create_dns_record ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
