###############################################################################
# VPC endpoints.
#
# Keeps node -> AWS API traffic (ECR pulls, CloudWatch Logs, STS for IRSA) on
# the AWS private network instead of routing it out through NAT. Reduces both
# the exposure surface and the NAT data processing bill.
###############################################################################

resource "aws_security_group" "endpoints" {
  name        = "${var.name}-vpce"
  description = "Allows HTTPS from inside the VPC to interface VPC endpoints"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-vpce" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_vpc" {
  security_group_id = aws_security_group.endpoints.id
  description       = "HTTPS from within the VPC"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = var.vpc_cidr_block
}

resource "aws_vpc_security_group_ingress_rule" "from_security_groups" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id = aws_security_group.endpoints.id
  description       = "HTTPS from ${each.value}"

  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = each.value
}

# Endpoint ENIs only ever respond to requests they receive; they do not
# originate traffic. Egress is restricted to the VPC instead of 0.0.0.0/0.
resource "aws_vpc_security_group_egress_rule" "to_vpc" {
  security_group_id = aws_security_group.endpoints.id
  description       = "Return traffic to the VPC"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = var.vpc_cidr_block
}

###############################################################################
# Interface endpoints
###############################################################################

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_services)

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = var.private_dns_enabled

  tags = merge(var.tags, {
    Name = "${var.name}-vpce-${replace(each.value, ".", "-")}"
  })
}

###############################################################################
# Gateway endpoints
###############################################################################

resource "aws_vpc_endpoint" "gateway" {
  for_each = toset(var.gateway_services)

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  tags = merge(var.tags, {
    Name = "${var.name}-vpce-${each.value}"
  })
}
