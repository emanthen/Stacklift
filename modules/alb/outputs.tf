output "alb_arn" {
  description = "ARN of the Application Load Balancer."
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "DNS name of the ALB (e.g. mysaas-prod-alb-123456.us-east-1.elb.amazonaws.com). Use this to verify the ALB is up before DNS propagates."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB. Required when creating Route53 alias records pointing to this ALB outside of this module."
  value       = aws_lb.this.zone_id
}

output "alb_security_group_id" {
  description = "ID of the ALB security group. Pass to ecs-service as alb_security_group_id so ECS tasks only accept traffic from the ALB."
  value       = aws_security_group.alb.id
}

output "target_group_arn" {
  description = "ARN of the ALB target group. Pass to ecs-service as alb_target_group_arn."
  value       = aws_lb_target_group.this.arn
}

output "target_group_name" {
  description = "Name of the ALB target group."
  value       = aws_lb_target_group.this.name
}

output "http_listener_arn" {
  description = "ARN of the HTTP (port 80) listener. Redirects all traffic to HTTPS."
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS (port 443) listener. Add aws_lb_listener_rule resources to this ARN for path-based routing."
  value       = aws_lb_listener.https.arn
}

output "certificate_arn" {
  description = "ARN of the validated ACM certificate. Pass to cicd module if needed for reference."
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "domain_name" {
  description = "The primary domain name this ALB serves (from var.domain_name)."
  value       = var.domain_name
}
