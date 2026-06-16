# Pro Tier

The Stacklift Pro tier extends the open-source modules with production features that most SaaS products need within the first year.

**Price:** $129 one-time (no subscription)

---

## What's included

### Multi-environment module

Manage dev, staging, and prod from a single Terraform configuration. One set of module calls, one `terraform.tfvars` per environment, isolated state.

```hcl
module "stack" {
  source = "..."

  environments = {
    dev = {
      instance_class = "db.t3.micro"
      desired_count  = 1
      domain         = "dev.api.mysaas.com"
    }
    staging = {
      instance_class = "db.t3.micro"
      desired_count  = 1
      domain         = "staging.api.mysaas.com"
    }
    prod = {
      instance_class = "db.t3.small"
      desired_count  = 2
      domain         = "api.mysaas.com"
    }
  }
}
```

### Blue-green deployment module

Zero-downtime deployments with AWS CodeDeploy and ECS. Traffic shifts gradually (10% → 100% over configurable minutes) with automatic rollback on health check failure.

Replaces the rolling deployment in the open-source `ecs-service` module with a CodeDeploy deployment group.

### Autoscaling presets

CPU and memory target tracking autoscaling with sensible defaults. Scale out when CPU > 70%, scale in when CPU < 30%. Configurable min/max task counts.

```hcl
module "autoscaling" {
  source = "..."

  ecs_service_name  = module.ecs_service.service_name
  ecs_cluster_name  = module.ecs_cluster.cluster_name
  min_capacity      = 1
  max_capacity      = 10
  cpu_target        = 70
  memory_target     = 80
}
```

### Cost alerting module

AWS Budgets + SNS + email notification when your monthly AWS spend exceeds a threshold. Configurable per-service and total-account budgets.

```hcl
module "cost_alerts" {
  source = "..."

  monthly_budget_usd    = 150
  alert_threshold_pct   = 80     # alert at $120
  notification_email    = "you@yourcompany.com"
}
```

### Secrets rotation module

Automated rotation of RDS master password via AWS Lambda. Rotates every 30 days, updates Secrets Manager, zero application downtime.

---

## How to purchase

1. Buy on Gumroad: [gumroad.com/l/stacklift-pro](https://gumroad.com/l/stacklift-pro)
2. You receive a GitHub repo invite to `emanthen/stacklift-pro` within 24 hours
3. Clone the pro repo alongside the open-source repo and reference modules from both

---

## Support

Pro buyers get:
- Private Discord channel (`#stacklift-pro`)
- Email support: emanthen@gmail.com
- Priority issue responses

---

## Upgrade path

The pro modules are designed as drop-in additions — they do not require changes to your existing open-source module configuration. Add the pro module calls alongside your existing `main.tf`, run `terraform apply`.
