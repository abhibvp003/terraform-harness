output "security_group_id" {
  description = "Security group guarding the interface endpoints."
  value       = aws_security_group.endpoints.id
}

output "interface_endpoint_ids" {
  description = "Interface endpoint ids keyed by service short name."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "gateway_endpoint_ids" {
  description = "Gateway endpoint ids keyed by service short name."
  value       = { for k, v in aws_vpc_endpoint.gateway : k => v.id }
}

output "interface_endpoint_dns_names" {
  description = "Private DNS entries for each interface endpoint."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.dns_entry }
}
