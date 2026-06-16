terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  az_count = min(var.az_count, length(data.aws_availability_zones.available.names))

  public_subnet_cidrs  = [for i in range(local.az_count) : cidrsubnet(var.cidr_block, 4, i)]
  private_subnet_cidrs = [for i in range(local.az_count) : cidrsubnet(var.cidr_block, 4, i + local.az_count)]
}

data "aws_availability_zones" "available" {
  state = "available"
}

# ── VPC ─────────────────────────────────────────────────────────────────────

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-vpc"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

# ── INTERNET GATEWAY ─────────────────────────────────────────────────────────

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-igw"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

# ── PUBLIC SUBNETS ───────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-public-${count.index + 1}"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
    Tier        = "public"
  })
}

# ── PRIVATE SUBNETS ──────────────────────────────────────────────────────────

resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-private-${count.index + 1}"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
    Tier        = "private"
  })
}

# ── ELASTIC IPs FOR NAT ──────────────────────────────────────────────────────

resource "aws_eip" "nat" {
  # single_nat_gateway=true → 1 EIP; false → one per AZ
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : local.az_count) : 0

  domain = "vpc"

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-nat-eip-${count.index + 1}"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })

  depends_on = [aws_internet_gateway.this]
}

# ── NAT GATEWAYS ─────────────────────────────────────────────────────────────

resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : local.az_count) : 0

  # single NAT always placed in first public subnet
  subnet_id     = aws_subnet.public[var.single_nat_gateway ? 0 : count.index].id
  allocation_id = aws_eip.nat[count.index].id

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-nat-${count.index + 1}"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })

  depends_on = [aws_internet_gateway.this]
}

# ── PUBLIC ROUTE TABLE ───────────────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-rt-public"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── PRIVATE ROUTE TABLES ─────────────────────────────────────────────────────
# One per AZ when multi-NAT; one shared when single-NAT or no NAT.

resource "aws_route_table" "private" {
  # one per AZ (multi-NAT) or one shared (single-NAT / no NAT)
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : local.az_count) : 1

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-rt-private-${count.index + 1}"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}

resource "aws_route" "private_nat" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : local.az_count) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id = aws_subnet.private[count.index].id

  # single-NAT or no-NAT → all private subnets share route table index 0
  route_table_id = var.enable_nat_gateway && !var.single_nat_gateway \
    ? aws_route_table.private[count.index].id \
    : aws_route_table.private[0].id
}

# ── DEFAULT SECURITY GROUP (locked down) ─────────────────────────────────────
# Overrides the AWS default which allows all intra-VPC traffic.

resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-default-sg"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "stacklift"
  })
}
