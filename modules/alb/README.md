# stacklift/modules/alb

Creates an internet-facing Application Load Balancer with HTTPS termination, ACM certificate via DNS validation, and Route53 wiring.

**What this module creates:**

- ALB security group — inbound 80 + 443 from `0.0.0.0/0` and `::/0`, all outbound
- Application Load Balancer (internet-facing, `drop_invalid_header_fields = true`)
- ACM certificate for `domain_name` (+ optional SANs) via DNS validation
- Route53 CNAME records for ACM DNS validation
- `aws_acm_certificate_validation` — Terraform waits here until the cert is issued (~1–3 min)
- Target group — protocol HTTP, target type `ip` (required for Fargate), configurable health check
- HTTP listener (port 80) → 301 redirect to HTTPS
- HTTPS listener (port 443) → forward to target group, TLS 1.3 policy
- Route53 A alias record → ALB (optional, `create_dns_record = true`)

**Pre-requisite:** A Route53 public hosted zone must already exist for your domain. This module does not create the hosted zone.

---

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.5 |
| aws | ~> 5.0 |

---

## Usage

```hcl
module "alb" {
  source = "../../modules/alb"

  project_name = "mysaas"
  environment  = "prod"
  aws_region   = "us-east-1"

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids

  domain_name      = "api.mysaas.com"
  route53_zone_id  = "Z1234567890ABC"
  create_dns_record = true

  container_port       = 8000
  health_check_path    = "/api/health/"
  deregistration_delay = 30
}
```

Pass outputs to `ecs-service`:

```hcl
module "ecs_service" {
  source = "../../modules/ecs-service"

  alb_target_group_arn  = module.alb.target_group_arn
  alb_security_group_id = module.alb.alb_security_group_id
  ...
}
```

---

## Certificate issuance timing

`terraform apply` will pause at `aws_acm_certificate_validation.this` for 1–3 minutes while ACM validates ownership via the DNS CNAME records created in the same apply. This is normal — ACM polls the CNAME, confirms the record exists, and issues the certificate. No action needed.

If validation stalls beyond 5 minutes:
1. Check the Route53 hosted zone in the console — the CNAME records should be present
2. Confirm `route53_zone_id` matches the zone for `domain_name`
3. If the domain was recently transferred, DNS propagation may need more time

---

## SSL policy

Default: `ELBSecurityPolicy-TLS13-1-2-2021-06`

This policy:
- Enables TLS 1.3 (preferred) and TLS 1.2 (fallback)
- Disables TLS 1.0 and 1.1
- Is the current AWS recommended policy for new load balancers

For stricter TLS 1.3-only (drops ~1% of older clients):
```hcl
ssl_policy = "ELBSecurityPolicy-TLS13-1-3-2021-06"
```

---

## Health check tuning

| Scenario | Recommended settings |
|---|---|
| Standard Django/FastAPI | `interval=30`, `timeout=5`, `healthy=2`, `unhealthy=3` |
| Cold-start heavy (migrations on startup) | Increase `health_check_grace_period_seconds` in `ecs-service` to 120 |
| Fast failover | `interval=10`, `unhealthy=2` (increases AWS cost slightly) |

The health check hits `health_check_path` on each registered target's IP directly (not via domain). A 200–299 response marks the target healthy.

---

## Deregistration delay

Default: `30` seconds (AWS default is 300).

Lower values speed up rolling deployments — ECS can terminate old tasks faster once the ALB stops sending them traffic. 30 seconds is safe for most Django/FastAPI APIs where in-flight requests complete in under 30 seconds. Increase if you have long-running synchronous requests (file processing, reports).

---

## Adding path-based routing

To route `/api/*` to one service and `/admin/*` to another, add listener rules pointing to the `https_listener_arn` output:

```hcl
resource "aws_lb_listener_rule" "admin" {
  listener_arn = module.alb.https_listener_arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = module.admin_service_tg.arn
  }

  condition {
    path_pattern { values = ["/admin/*"] }
  }
}
```

---

## Inputs

| Name | Type | Default | Required | Description |
|---|---|---|---|---|
| `project_name` | `string` | — | yes | Prefix for all resource names. |
| `environment` | `string` | `"prod"` | no | `dev`, `staging`, or `prod`. |
| `aws_region` | `string` | `"us-east-1"` | no | AWS region. |
| `vpc_id` | `string` | — | yes | VPC ID from `vpc` module. |
| `public_subnet_ids` | `list(string)` | — | yes | At least 2 public subnets from `vpc` module. |
| `domain_name` | `string` | — | yes | Primary domain for ACM cert and DNS record (e.g. `api.mysaas.com`). |
| `subject_alternative_names` | `list(string)` | `[]` | no | Additional SANs for the ACM certificate. |
| `route53_zone_id` | `string` | — | yes | Route53 hosted zone ID for DNS validation and A record. |
| `create_dns_record` | `bool` | `true` | no | Create Route53 A alias record for `domain_name` → ALB. |
| `ssl_policy` | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no | ALB TLS security policy. |
| `container_port` | `number` | `8000` | no | Port ECS tasks listen on. Must match `ecs-service` container_port. |
| `deregistration_delay` | `number` | `30` | no | Seconds before ALB stops sending traffic to deregistering targets. |
| `health_check_path` | `string` | `"/api/health/"` | no | Path ALB polls for target health. |
| `health_check_interval` | `number` | `30` | no | Seconds between health checks. |
| `health_check_timeout` | `number` | `5` | no | Seconds to wait for a health check response. |
| `health_check_healthy_threshold` | `number` | `2` | no | Consecutive successes to mark healthy. |
| `health_check_unhealthy_threshold` | `number` | `3` | no | Consecutive failures to mark unhealthy. |
| `idle_timeout` | `number` | `60` | no | ALB idle connection timeout in seconds. |
| `enable_deletion_protection` | `bool` | `false` | no | Prevent ALB deletion via console or API. |
| `tags` | `map(string)` | `{}` | no | Extra tags merged onto all resources. |

---

## Outputs

| Name | Description |
|---|---|
| `alb_arn` | ARN of the ALB. |
| `alb_dns_name` | ALB DNS name. Use to verify the ALB before DNS propagates. |
| `alb_zone_id` | ALB hosted zone ID. For external Route53 alias records. |
| `alb_security_group_id` | ALB SG ID. Pass to `ecs-service` as `alb_security_group_id`. |
| `target_group_arn` | Target group ARN. Pass to `ecs-service` as `alb_target_group_arn`. |
| `target_group_name` | Target group name. |
| `http_listener_arn` | HTTP listener ARN (redirects to HTTPS). |
| `https_listener_arn` | HTTPS listener ARN. Use for `aws_lb_listener_rule` path routing. |
| `certificate_arn` | Validated ACM certificate ARN. |
| `domain_name` | Primary domain this ALB serves. |

---

## Verification

After `terraform apply`, confirm the ALB is healthy:

```powershell
# D:\Stacklift
# Replace with your ALB DNS name from Terraform output
curl -I http://mysaas-prod-alb-123456.us-east-1.elb.amazonaws.com/api/health/
# Expected: HTTP/1.1 301 Moved Permanently (redirect to HTTPS)

curl -I https://api.mysaas.com/api/health/
# Expected: HTTP/1.1 200 OK
```

---

## Cost estimate

| Resource | Cost |
|---|---|
| ALB (hourly) | ~$16/mo (0.008/LCU-hour + $0.022/hr base) |
| LCU usage (light traffic) | ~$2–5/mo |
| ACM certificate | Free |
| Route53 DNS queries | ~$0.40/million queries |
| Data transfer out | $0.008/GB (first 10TB) |

Total ALB cost for a low-traffic SaaS: **~$18–22/month**.
