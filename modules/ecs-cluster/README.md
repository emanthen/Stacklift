# stacklift/modules/ecs-cluster

Creates a Fargate ECS cluster with CloudWatch Container Insights and a shared log group.

**What this module creates:**

- ECS cluster with Container Insights enabled
- FARGATE and FARGATE_SPOT capacity providers registered on the cluster
- Default capacity provider strategy: FARGATE (weight 1, base 1)
- CloudWatch log group at `/stacklift/{project}/{environment}` with configurable retention

**What it does NOT create:**

- Task definitions, services, or security groups — those live in `ecs-service`
- IAM roles — those live in `ecs-service`

One cluster per environment is the standard pattern. All services for a project share the cluster and the log group. Individual services get their own log stream prefix.

---

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.5 |
| aws | ~> 5.0 |

---

## Usage

```hcl
module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  project_name              = "mysaas"
  environment               = "prod"
  aws_region                = "us-east-1"
  enable_container_insights = true
  log_retention_days        = 30
}
```

Pass outputs to `ecs-service` and `cicd`:

```hcl
module "ecs_service" {
  source = "../../modules/ecs-service"

  cluster_id     = module.ecs_cluster.cluster_id
  log_group_name = module.ecs_cluster.log_group_name
  ...
}

module "cicd" {
  source = "../../modules/cicd"

  ecs_cluster_arn = module.ecs_cluster.cluster_arn
  ...
}
```

---

## Capacity providers

Both `FARGATE` and `FARGATE_SPOT` are registered. The default strategy runs tasks on `FARGATE`.

To run a specific service on FARGATE_SPOT (e.g. a Celery worker tolerant of interruption), override the capacity provider strategy in the `ecs-service` module:

```hcl
capacity_provider_strategy = [
  { capacity_provider = "FARGATE_SPOT", weight = 1, base = 0 }
]
```

FARGATE_SPOT is up to 70% cheaper but tasks can be interrupted with a 2-minute warning. Never run your primary web service on SPOT.

---

## Inputs

| Name | Type | Default | Required | Description |
|---|---|---|---|---|
| `project_name` | `string` | — | yes | Prefix for all resource names. |
| `environment` | `string` | `"prod"` | no | `dev`, `staging`, or `prod`. |
| `aws_region` | `string` | `"us-east-1"` | no | AWS region. |
| `enable_container_insights` | `bool` | `true` | no | Enable per-task CloudWatch metrics. ~$0.50/million metrics. |
| `log_retention_days` | `number` | `30` | no | Days before CloudWatch automatically expires log streams. |
| `tags` | `map(string)` | `{}` | no | Extra tags merged onto all resources. |

---

## Outputs

| Name | Description |
|---|---|
| `cluster_id` | ECS cluster ID. Pass to `ecs-service`. |
| `cluster_arn` | ECS cluster ARN. Pass to `cicd` module. |
| `cluster_name` | ECS cluster name. |
| `log_group_name` | CloudWatch log group name. Pass to `ecs-service`. |
| `log_group_arn` | CloudWatch log group ARN. |

---

## Cost estimate

| Resource | Cost |
|---|---|
| ECS cluster (control plane) | Free |
| FARGATE compute | Per task — see `ecs-service` module |
| Container Insights metrics | ~$0.50/million metrics ingested |
| CloudWatch logs (ingestion) | $0.50/GB |
| CloudWatch logs (storage) | $0.03/GB/month |

A single Django/FastAPI task emitting moderate logs (~500MB/month) costs roughly $0.25–$0.50/month in log ingestion. Set `log_retention_days = 7` for dev to keep storage costs near zero.
