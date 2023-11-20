resource "aws_s3_object" "master" {
  bucket  = aws_s3_bucket.userdata.id
  key     = "master-config.json"
  content = var.master_user_data
}

resource "aws_iam_role" "master" {
  name                 = "${local.iam_prefix}${var.cluster_name}-master"
  path                 = var.iam_path
  permissions_boundary = var.permissions_boundary

  assume_role_policy = <<EOS
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOS
}

resource "aws_iam_instance_profile" "master" {
  name = "${local.iam_prefix}${var.cluster_name}-master"
  role = aws_iam_role.master.name
  path = var.iam_path
}

data "aws_iam_policy_document" "master" {
  statement {
    actions = [
      "ec2:*"
    ]
    resources = ["*"]
  }

  statement {
    actions = [
      "elasticloadbalancing:*",
    ]
    resources = ["*"]
  }

  # https://github.com/kubernetes/kops/blob/master/pkg/model/iam/tests/iam_builder_master_strict.json#L158
  statement {
    actions = [
      "kms:CreateGrant",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*"
    ]
    resources = var.master_kms_ebs_key_arns
  }

  statement {
    actions = [
      "s3:GetObject"
    ]
    resources = ["arn:aws:s3:::${aws_s3_bucket.userdata.id}/master-*"]
  }
}

resource "aws_iam_role_policy" "master" {
  name   = "${local.iam_prefix}${var.cluster_name}-master"
  role   = aws_iam_role.master.id
  policy = data.aws_iam_policy_document.master.json
}

resource "aws_launch_template" "master" {
  name_prefix = "${var.cluster_name}-master-"
  iam_instance_profile { name = aws_iam_instance_profile.master.name }
  image_id               = var.containerlinux_ami_id
  instance_type          = var.master_instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.master.id]

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

  # Allow containers to talk to IMDSv2 endpoint if needed by allowing 2 hops
  metadata_options {
    http_tokens                 = "optional"
    http_put_response_hop_limit = 2
  }

  user_data = base64encode(
    templatefile("${path.module}/userdata.tftpl",
      {
        region = var.region,
        source = "s3://${aws_s3_bucket.userdata.id}/master-config.json"
      }
    )
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "master" {
  name                      = "master ${var.cluster_name}"
  desired_capacity          = var.master_instance_count
  health_check_grace_period = 60
  health_check_type         = "EC2"
  force_delete              = true
  max_size                  = var.master_instance_count
  min_size                  = var.master_instance_count
  vpc_zone_identifier       = var.control_plane_private_subnet_ids
  target_group_arns         = [aws_lb_target_group.control_plane_443.arn]
  default_cooldown          = 60

  launch_template {
    id      = aws_launch_template.master.id
    version = aws_launch_template.master.latest_version
  }

  tag {
    key                 = "Name"
    value               = "master ${var.cluster_name}"
    propagate_at_launch = true
  }

  tag {
    key                 = "terraform.io/component"
    value               = "${var.cluster_name}/master"
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

resource "aws_lb" "control_plane" {
  name               = "${var.cluster_name}-control-plane-lb"
  load_balancer_type = "network"
  internal           = true
  subnets            = var.control_plane_private_subnet_ids

  idle_timeout = 3600

  tags = {
    "Name"                                      = "${var.cluster_name}-control-plane-lb"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_lb_listener" "control_plane_443" {
  load_balancer_arn = aws_lb.control_plane.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    target_group_arn = aws_lb_target_group.control_plane_443.arn
    type             = "forward"
  }
}

resource "aws_lb_target_group" "control_plane_443" {
  name     = "${var.cluster_name}-control-plane-443"
  vpc_id   = var.vpc_id
  port     = 443
  protocol = "TCP"

  health_check {
    protocol = "TCP"
    port     = 443
  }

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_security_group" "master" {
  name        = "${var.cluster_name}-master"
  description = "k8s master security group"
  vpc_id      = var.vpc_id

  // kube uses the kubernetes.io tag to learn its cluster name and tag managed resources
  tags = {
    "Name"                                      = "master ${var.cluster_name}"
    "terraform.io/component"                    = "${var.cluster_name}/master"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "owner"                                     = "system"
  }
}

resource "aws_security_group_rule" "egress-from-master" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.master.id
}

resource "aws_security_group_rule" "ingress-master-to-self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.master.id
  self              = true
}

resource "aws_security_group_rule" "ingress-worker-to-master" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.worker.id
  security_group_id        = aws_security_group.master.id
}

resource "aws_security_group_rule" "ingress-world-to-master" {
  security_group_id = aws_security_group.master.id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "master-ssh" {
  count                    = length(var.ssh_security_group_ids)
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = element(var.ssh_security_group_ids, count.index)
  security_group_id        = aws_security_group.master.id
}

resource "aws_route53_record" "master-lb" {
  zone_id = var.route53_zone_id
  name    = "elb.master.${var.cluster_subdomain}.${data.aws_route53_zone.main.name}"
  type    = "CNAME"
  ttl     = "30"
  records = [aws_lb.control_plane.dns_name]
}
