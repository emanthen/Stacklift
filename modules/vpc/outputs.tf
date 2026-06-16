output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs. Pass to the ALB module."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs. Pass to RDS and ECS service modules."
  value       = aws_subnet.private[*].id
}

output "default_security_group_id" {
  description = "ID of the locked-down default security group."
  value       = aws_default_security_group.this.id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway attached to the VPC."
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs. Empty when enable_nat_gateway = false."
  value       = aws_nat_gateway.this[*].id
}

output "public_route_table_id" {
  description = "ID of the public route table."
  value       = aws_route_table.public.id
}

output "availability_zones" {
  description = "List of AZ names used by subnets in this VPC."
  value       = data.aws_availability_zones.available.names
}
