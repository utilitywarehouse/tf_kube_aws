resource "aws_s3_object" "worker" {
  for_each = local.effective_worker_groups

  bucket  = aws_s3_bucket.userdata.id
  key     = "worker-${each.key}-config.json"
  content = each.value.user_data
}

resource "aws_iam_role" "worker" {
  name                 = "${local.iam_prefix}${var.cluster_name}-worker"
  path                 = var.iam_path
  permissions_boundary = var.permissions_boundary

  assume_role_policy = <<EOS
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOS
}

resource "aws_iam_instance_profile" "worker" {
  name = "${local.iam_prefix}${var.cluster_name}-worker"
  role = aws_iam_role.worker.name
  path = var.iam_path
}

data "aws_iam_policy_document" "worker" {
  statement {
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }

  statement {
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${aws_s3_bucket.userdata.id}/worker-*"]
  }

  # Grant worker nodes permissions to access EFS cluster. Source:
  # https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/docs/iam-policy-example.json
  statement {
    actions = [
      "ec2:DescribeAvailabilityZones",
      "elasticfilesystem:DescribeAccessPoints",
      "elasticfilesystem:DescribeFileSystems",
      "elasticfilesystem:DescribeMountTargets",
    ]
    resources = ["*"]
  }

  statement {
    actions   = ["elasticfilesystem:CreateAccessPoint"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/efs.csi.aws.com/cluster"
      values   = ["true"]
    }
  }

  statement {
    actions = [
      "elasticfilesystem:TagResource",
      "elasticfilesystem:DeleteAccessPoint",
    ]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/efs.csi.aws.com/cluster"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role_policy" "worker" {
  name   = "${local.iam_prefix}${var.cluster_name}-worker"
  role   = aws_iam_role.worker.id
  policy = data.aws_iam_policy_document.worker.json
}

resource "aws_launch_template" "worker" {
  for_each = local.effective_worker_groups

  name_prefix            = "${var.cluster_name}-worker-${each.key}-"
  image_id               = var.containerlinux_ami_parameter != "" ? var.containerlinux_ami_parameter : var.containerlinux_ami_id
  instance_type          = each.value.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.worker.id]

  iam_instance_profile { name = aws_iam_instance_profile.worker.name }

  # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/device_naming.html#available-ec2-device-names
  #
  # Flatcar Linux mentions using "/dev/xvda" as root:
  #   https://flatcar-linux.org/docs/latest/reference/developer-guides/sdk-disk-partitions/#read-only-usr
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 100
      delete_on_termination = true
    }
  }

  # Enable IMDSv2 (require session tokens to talk to metadata services) adn set
  # hop limit to 1, so that pods communication is rejected following best practices:
  # https://docs.aws.amazon.com/whitepapers/latest/security-practices-multi-tenant-saas-applications-eks/restrict-the-use-of-host-networking-and-block-access-to-instance-metadata-service.html
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(
    templatefile("${path.module}/userdata.tftpl",
      {
        region = var.region,
        source = "s3://${aws_s3_bucket.userdata.id}/worker-${each.key}-config.json"
      }
    )
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_template" "worker_spot" {
  for_each = local.effective_worker_groups

  name_prefix            = "${var.cluster_name}-worker-${each.key}-spot-"
  image_id               = var.containerlinux_ami_parameter != "" ? var.containerlinux_ami_parameter : var.containerlinux_ami_id
  instance_type          = each.value.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.worker.id]

  iam_instance_profile { name = aws_iam_instance_profile.worker.name }

  instance_market_options {
    market_type = "spot"
  }

  # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/device_naming.html#available-ec2-device-names
  #
  # Flatcar Linux mentions using "/dev/xvda" as root:
  #   https://flatcar-linux.org/docs/latest/reference/developer-guides/sdk-disk-partitions/#read-only-usr
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 100
      delete_on_termination = true
    }
  }

  # Enable IMDSv2 (require session tokens to talk to metadata services) adn set
  # hop limit to 1, so that pods communication is rejected following best practices:
  # https://docs.aws.amazon.com/whitepapers/latest/security-practices-multi-tenant-saas-applications-eks/restrict-the-use-of-host-networking-and-block-access-to-instance-metadata-service.html
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(
    templatefile("${path.module}/userdata.tftpl",
      {
        region = var.region,
        source = "s3://${aws_s3_bucket.userdata.id}/worker-${each.key}-config.json"
      }
    )
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "worker" {
  for_each = local.effective_worker_groups

  name                      = "worker-${each.key} ${var.cluster_name}"
  desired_capacity          = each.value.ondemand_instance_count
  max_size                  = each.value.ondemand_instance_count
  min_size                  = each.value.ondemand_instance_count
  health_check_grace_period = 60
  health_check_type         = "EC2"
  force_delete              = true
  vpc_zone_identifier       = var.worker_node_private_subnet_ids
  load_balancers            = each.value.elb_names
  target_group_arns         = each.value.target_group_arns
  default_cooldown          = 60

  lifecycle {
    prevent_destroy = true
  }

  launch_template {
    id      = aws_launch_template.worker[each.key].id
    version = aws_launch_template.worker[each.key].latest_version
  }

  tag {
    key                 = "Name"
    value               = "worker-${each.key} ${var.cluster_name}"
    propagate_at_launch = true
  }

  tag {
    key                 = "terraform.io/component"
    value               = "${var.cluster_name}/worker-${each.key}"
    propagate_at_launch = true
  }

  tag {
    // kube uses this tag to learn its cluster name and tag managed resources
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "owner"
    value               = "system"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group" "worker-spot" {
  for_each = local.effective_worker_groups

  name                      = "worker-${each.key}-spot ${var.cluster_name}"
  desired_capacity          = each.value.spot_instance_count
  max_size                  = each.value.spot_instance_count
  min_size                  = each.value.spot_instance_count
  health_check_grace_period = 60
  health_check_type         = "EC2"
  force_delete              = true
  vpc_zone_identifier       = var.worker_node_private_subnet_ids
  load_balancers            = each.value.elb_names
  target_group_arns         = each.value.target_group_arns
  default_cooldown          = 60

  lifecycle {
    prevent_destroy = true
  }

  launch_template {
    id      = aws_launch_template.worker_spot[each.key].id
    version = aws_launch_template.worker_spot[each.key].latest_version
  }

  tag {
    key                 = "Name"
    value               = "worker-${each.key}-spot ${var.cluster_name}"
    propagate_at_launch = true
  }

  tag {
    key                 = "terraform.io/component"
    value               = "${var.cluster_name}/worker-${each.key}-spot"
    propagate_at_launch = true
  }

  tag {
    // kube uses this tag to learn its cluster name and tag managed resources
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "owner"
    value               = "system"
    propagate_at_launch = true
  }
}

resource "aws_security_group" "worker" {
  name        = "${var.cluster_name}-worker"
  description = "k8s worker security group"
  vpc_id      = var.vpc_id

  // kube uses the kubernetes.io tag to learn its cluster name and tag managed resources
  tags = {
    "Name"                                      = "worker ${var.cluster_name}"
    "terraform.io/component"                    = "${var.cluster_name}/worker"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "owner"                                     = "system"
  }
}

resource "aws_security_group_rule" "egress-from-worker" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.worker.id
}

resource "aws_security_group_rule" "ingress-worker-to-self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.worker.id
  self              = true
}

resource "aws_security_group_rule" "ingress-master-to-worker" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.master.id
  security_group_id        = aws_security_group.worker.id
}

resource "aws_security_group_rule" "worker-ssh" {
  count                    = length(var.ssh_security_group_ids)
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = element(var.ssh_security_group_ids, count.index)
  security_group_id        = aws_security_group.worker.id
}
