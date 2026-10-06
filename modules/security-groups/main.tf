###############################################################################
# Security groups for the EKS control plane ENIs and the worker nodes.
#
# EKS also creates its own "cluster security group" and attaches it to both the
# control plane and managed nodes. The groups here are additional, explicitly
# owned by Terraform, and are where you add your own rules - never edit the
# AWS-managed one.
#
# Deliberately absent: any inbound rule on 22 or 3389. Shell access goes
# through SSM Session Manager.
###############################################################################

###############################################################################
# Control plane
###############################################################################

resource "aws_security_group" "cluster" {
  name        = "${var.name}-cluster"
  description = "EKS control plane - additional rules managed by Terraform"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-cluster" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "cluster_api_from_nodes" {
  security_group_id = aws_security_group.cluster.id
  description       = "Kubernetes API from worker nodes"

  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.node.id
}

resource "aws_vpc_security_group_ingress_rule" "cluster_api_from_cidrs" {
  for_each = toset(var.cluster_api_allowed_cidrs)

  security_group_id = aws_security_group.cluster.id
  description       = "Kubernetes API from ${each.value}"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = each.value
}

# The control plane initiates connections to kubelets (logs, exec, metrics) and
# to admission/conversion webhooks running as pods.
resource "aws_vpc_security_group_egress_rule" "cluster_to_node_kubelet" {
  security_group_id = aws_security_group.cluster.id
  description       = "Kubelet API on worker nodes"

  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250
  referenced_security_group_id = aws_security_group.node.id
}

resource "aws_vpc_security_group_egress_rule" "cluster_to_node_webhooks" {
  security_group_id = aws_security_group.cluster.id
  description       = "Admission and conversion webhooks on worker nodes"

  ip_protocol                  = "tcp"
  from_port                    = 1025
  to_port                      = 65535
  referenced_security_group_id = aws_security_group.node.id
}

###############################################################################
# Worker nodes
###############################################################################

resource "aws_security_group" "node" {
  name        = "${var.name}-node"
  description = "EKS worker nodes"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-node"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Pod-to-pod traffic across nodes, CoreDNS, kube-proxy and the CNI all need
# unrestricted node-to-node communication.
resource "aws_vpc_security_group_ingress_rule" "node_from_node" {
  security_group_id = aws_security_group.node.id
  description       = "All traffic between nodes in this cluster"

  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.node.id
}

resource "aws_vpc_security_group_ingress_rule" "node_kubelet_from_cluster" {
  security_group_id = aws_security_group.node.id
  description       = "Kubelet API from the control plane"

  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250
  referenced_security_group_id = aws_security_group.cluster.id
}

resource "aws_vpc_security_group_ingress_rule" "node_webhooks_from_cluster" {
  security_group_id = aws_security_group.node.id
  description       = "Webhook and extension API server ports from the control plane"

  ip_protocol                  = "tcp"
  from_port                    = 1025
  to_port                      = 65535
  referenced_security_group_id = aws_security_group.cluster.id
}

resource "aws_vpc_security_group_ingress_rule" "node_extra" {
  for_each = var.node_extra_ingress_rules

  security_group_id = aws_security_group.node.id
  description       = each.value.description

  ip_protocol = each.value.ip_protocol
  from_port   = each.value.from_port
  to_port     = each.value.to_port

  cidr_ipv4                    = each.value.cidr_ipv4
  referenced_security_group_id = each.value.source_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "node_egress" {
  for_each = toset(var.node_egress_cidrs)

  security_group_id = aws_security_group.node.id
  description       = "Node egress to ${each.value}"

  ip_protocol = "-1"
  cidr_ipv4   = each.value
}
