# stacklift/modules/vpc

Creates a production-grade VPC for Django and FastAPI workloads on AWS.

**What this module creates:**

- VPC with DNS support and DNS hostnames enabled
- Public subnets (one per AZ) — ALB and NAT live here
- Private subnets (one per AZ) — ECS tasks and RDS live here; no direct internet exposure
- Internet Gateway attached to the VPC
- NAT Gateway (single by default, multi-AZ optional) with Elastic IPs for private subnet egress
- Public route table with `0.0.0.0/0 → IGW`
- Private route table(s) with `0.0.0.0/0 → NAT`
- Default security group locked down (no inbound, no outbound by default — each module creates its own SG)

Subnet CIDRs are derived automatically from `cidr_block` using `cidrsubnet`. With the default `10.0.0.0/16` and 2 AZs:

| Subnet | CIDR |
|---|---|
| public-1 | 10.0.0.0/20 |
| public-2 | 10.0.16.0/20 |
| private-1 | 10.0.32.0/20 |
| private-2 | 10.0.48.0/20 |

---

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.5 |
| aws | ~> 5.0 |

---

## Usage

```hcl
module "vpc" {
  source = "../../modules/vpc"

  project_name       = "mysaas"
  environment        = "prod"
  aws_region         = "us-east-1"
  cidr_block         = "10.0.0.0/16"
  az_count           = 2
  enable_nat_gateway = true
  single_nat_gateway = true   # false for HA prod (adds ~$32/mo per extra NAT)
}
```

Pass outputs to downstream modules:

```hcl
module "rds" {
  source = "../../modules/rds"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  # ...
}

module "alb" {
  source = "../../modules/alb"

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  # ...
}
```

---

## Inputs

| Name | Type | Default | Required | Description |
|---|---|---|---|---|
| `project_name` | `string` | — | yes | Prefix for all resource names. Lowercase letters, numbers, hyphens. 3–30 chars. |
| `environment` | `string` | `"prod"` | no | `dev`, `staging`, or `prod`. |
| `aws_region` | `string` | `"us-east-1"` | no | AWS region where resources are created. |
| `cidr_block` | `string` | `"10.0.0.0/16"` | no | VPC CIDR block. |
| `az_count` | `number` | `2` | no | Number of AZs to span. Capped at available AZs in the region. |
| `enable_nat_gateway` | `bool` | `true` | no | Create NAT Gateway(s). Required for ECS tasks to pull images from ECR. |
| `single_nat_gateway` | `bool` | `true` | no | Share one NAT across all AZs. Set `false` for multi-AZ NAT in HA prod. |
| `tags` | `map(string)` | `{}` | no | Extra tags merged onto all resources. |

---

## Outputs

| Name | Description |
|---|---|
| `vpc_id` | ID of the created VPC. Pass to all other modules. |
| `vpc_cidr_block` | CIDR block of the VPC. |
| `public_subnet_ids` | List of public subnet IDs. Pass to the `alb` module. |
| `private_subnet_ids` | List of private subnet IDs. Pass to `rds` and `ecs-service` modules. |
| `default_security_group_id` | ID of the locked-down default security group. |
| `internet_gateway_id` | ID of the Internet Gateway. |
| `nat_gateway_ids` | List of NAT Gateway IDs. Empty when `enable_nat_gateway = false`. |
| `public_route_table_id` | ID of the public route table. |
| `availability_zones` | AZ names used by subnets. |

---

## Cost estimate

| Resource | Cost |
|---|---|
| VPC, subnets, route tables, IGW | Free |
| NAT Gateway (single) | ~$32/mo + $0.045/GB data processed |
| NAT Gateway (per AZ, 2 AZs) | ~$64/mo + data |
| Elastic IP (attached to NAT) | Free while attached |

Set `enable_nat_gateway = false` for development environments where ECS tasks can tolerate no outbound internet (e.g. all images pre-pulled, no external calls). For any real deployment, NAT is required for ECR image pulls.
