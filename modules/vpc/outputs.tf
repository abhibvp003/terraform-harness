output "vpc_id" {
  description = "VPC id."
  value       = aws_vpc.this.id
}

output "vpc_arn" {
  description = "VPC ARN."
  value       = aws_vpc.this.arn
}

output "vpc_cidr_block" {
  description = "VPC primary CIDR."
  value       = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet ids. EKS nodes and pods go here."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet ids. Internet-facing load balancers go here."
  value       = aws_subnet.public[*].id
}

output "private_subnet_cidrs" {
  description = "Private subnet CIDRs."
  value       = aws_subnet.private[*].cidr_block
}

output "public_subnet_cidrs" {
  description = "Public subnet CIDRs."
  value       = aws_subnet.public[*].cidr_block
}

output "private_route_table_ids" {
  description = "Private route table ids, one per AZ."
  value       = aws_route_table.private[*].id
}

output "public_route_table_id" {
  description = "Shared public route table id."
  value       = aws_route_table.public.id
}

output "nat_gateway_public_ips" {
  description = "Elastic IPs used for egress. Share these with partners that allow-list source addresses."
  value       = aws_eip.nat[*].public_ip
}

output "availability_zones" {
  description = "Availability zones in use."
  value       = var.azs
}

output "flow_log_group_name" {
  description = "CloudWatch log group receiving flow logs, or null when disabled."
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].name : null
}
