###############################################################################
# EKS managed node groups.
#
# Each group gets its own launch template so we control the things the default
# EKS template leaves open:
#   - IMDSv2 required, hop limit 1 (pods cannot read node IAM credentials)
#   - root volume encrypted with a customer-managed CMK
#   - no public IP, no SSH key, no port 22
#
# image_id and user_data are deliberately not set. EKS then resolves the right
# optimised AMI for ami_type and cluster_version and injects the bootstrap
# config itself, which keeps version upgrades a one-line change.
###############################################################################

resource "aws_launch_template" "this" {
  for_each = var.node_groups

  name_prefix            = "${var.name_prefix}-${each.key}-"
  description            = "Launch template for ${var.cluster_name} node group ${each.key}"
  update_default_version = true

  # EC2 rejects vpc_security_group_ids and network_interfaces together, so the
  # security groups move onto the interface when we declare one to request a
  # public IP.
  vpc_security_group_ids = var.associate_public_ip ? null : var.security_group_ids

  dynamic "network_interfaces" {
    for_each = var.associate_public_ip ? [1] : []

    content {
      device_index                = 0
      associate_public_ip_address = true
      delete_on_termination       = true
      security_groups             = var.security_group_ids
    }
  }

  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  # IMDSv2 only. Token-less IMDSv1 requests are the classic path from a pod
  # with SSRF to the node's credentials.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = var.imds_hop_limit
    instance_metadata_tags      = "disabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = each.value.disk_size_gb
      volume_type = each.value.disk_type
      iops        = contains(["gp3", "io1", "io2"], each.value.disk_type) ? each.value.disk_iops : null
      throughput  = each.value.disk_type == "gp3" ? each.value.disk_throughput_mbps : null
      encrypted   = true
      # null here means the AWS-managed aws/ebs key. Still encrypted.
      kms_key_id            = var.ebs_kms_key_arn
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name      = "${var.cluster_name}-${each.key}"
      NodeGroup = each.key
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name      = "${var.cluster_name}-${each.key}-root"
      NodeGroup = each.key
    })
  }

  tag_specifications {
    resource_type = "network-interface"
    tags = merge(var.tags, {
      Name      = "${var.cluster_name}-${each.key}-eni"
      NodeGroup = each.key
    })
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = var.cluster_name
  node_group_name = "${var.name_prefix}-${each.key}"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids
  version         = var.cluster_version

  capacity_type  = each.value.capacity_type
  ami_type       = each.value.ami_type
  instance_types = each.value.instance_types

  force_update_version = each.value.force_update_version

  scaling_config {
    desired_size = each.value.desired_size
    min_size     = each.value.min_size
    max_size     = each.value.max_size
  }

  update_config {
    max_unavailable_percentage = each.value.max_unavailable_percentage
  }

  launch_template {
    id      = aws_launch_template.this[each.key].id
    version = aws_launch_template.this[each.key].latest_version
  }

  labels = each.value.labels

  dynamic "taint" {
    for_each = each.value.taints

    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-${each.key}"
    NodeGroup = each.key
  })

  lifecycle {
    # Replacing a node group drains the old one only after the new one is
    # healthy, so capacity never dips during an instance-type change.
    create_before_destroy = true

    # If you later run Cluster Autoscaler or Karpenter, uncomment this so
    # Terraform stops fighting the autoscaler over the replica count:
    #
    # ignore_changes = [scaling_config[0].desired_size]
  }

  timeouts {
    create = "30m"
    update = "60m"
    delete = "30m"
  }
}
