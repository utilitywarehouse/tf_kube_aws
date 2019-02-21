// IAM instance role
resource "aws_iam_role" "worker" {
  name                 = "${var.cluster_name}_worker"
  path                 = "${var.iam_path}"
  permissions_boundary = "${var.permissions_boundary}"

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
  name = "${var.cluster_name}-worker"
  role = "${aws_iam_role.worker.name}"
  path = "${var.iam_path}"
}

resource "aws_iam_role_policy" "worker" {
  name = "${var.cluster_name}-worker"
  role = "${aws_iam_role.worker.id}"

  policy = <<EOS
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    }
  ]
}
EOS
}

// EC2 AutoScaling groups
resource "aws_launch_configuration" "worker" {
  iam_instance_profile = "${aws_iam_instance_profile.worker.name}"
  image_id             = "${var.containerlinux_ami_id}"
  instance_type        = "${var.worker_instance_type}"
  key_name             = "${var.key_name}"
  security_groups      = ["${aws_security_group.worker.id}"]
  user_data            = "${var.worker_user_data}"

  lifecycle {
    create_before_destroy = true
  }

  root_block_device {
    volume_size = 50
    volume_type = "gp2"
  }
}

resource "aws_launch_configuration" "worker-spot" {
  iam_instance_profile = "${aws_iam_instance_profile.worker.name}"
  image_id             = "${var.containerlinux_ami_id}"
  instance_type        = "${var.worker_instance_type}"
  spot_price           = "${var.worker_spot_instance_bid}"
  key_name             = "${var.key_name}"
  security_groups      = ["${aws_security_group.worker.id}"]
  user_data            = "${var.worker_user_data}"

  lifecycle {
    create_before_destroy = true
  }

  root_block_device {
    volume_size = 50
    volume_type = "gp2"
  }
}

resource "aws_autoscaling_group" "worker" {
  name                      = "worker ${var.cluster_name}"
  desired_capacity          = "${var.worker_ondemand_instance_count}"
  max_size                  = "${var.worker_ondemand_instance_count}"
  min_size                  = "${var.worker_ondemand_instance_count}"
  health_check_grace_period = 60
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = "${aws_launch_configuration.worker.name}"
  vpc_zone_identifier       = ["${var.private_subnet_ids}"]
  load_balancers            = ["${var.worker_elb_names}"]
  target_group_arns         = ["${var.worker_target_group_arns}"]
  default_cooldown          = 60

  tags = [
    {
      key                 = "Name"
      value               = "worker ${var.cluster_name}"
      propagate_at_launch = true
    },
    {
      key                 = "terraform.io/component"
      value               = "${var.cluster_name}/master"
      propagate_at_launch = true
    },
    {
      // kube uses this tag to learn its cluster name and tag managed resources
      key                 = "kubernetes.io/cluster/${var.cluster_name}"
      value               = "owned"
      propagate_at_launch = true
    },
  ]
}

resource "aws_autoscaling_group" "worker-spot" {
  name                      = "worker-spot ${var.cluster_name}"
  desired_capacity          = "${var.worker_spot_instance_count}"
  max_size                  = "${var.worker_spot_instance_count}"
  min_size                  = "${var.worker_spot_instance_count}"
  health_check_grace_period = 60
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = "${aws_launch_configuration.worker-spot.name}"
  vpc_zone_identifier       = ["${var.private_subnet_ids}"]
  load_balancers            = ["${var.worker_elb_names}"]
  target_group_arns         = ["${var.worker_target_group_arns}"]
  default_cooldown          = 60

  tags = [
    {
      key                 = "Name"
      value               = "worker-spot ${var.cluster_name}"
      propagate_at_launch = true
    },
    {
      key                 = "terraform.io/component"
      value               = "${var.cluster_name}/master"
      propagate_at_launch = true
    },
    {
      // kube uses this tag to learn its cluster name and tag managed resources
      key                 = "kubernetes.io/cluster/${var.cluster_name}"
      value               = "owned"
      propagate_at_launch = true
    },
  ]
}

// VPC security groups
resource "aws_security_group" "worker" {
  name        = "${var.cluster_name}-worker"
  description = "k8s worker security group"
  vpc_id      = "${var.vpc_id}"

  // kube uses the kubernetes.io tag to learn its cluster name and tag managed resources
  tags = "${map(
    "Name", "worker ${var.cluster_name}",
    "terraform.io/component", "${var.cluster_name}/worker",
    "kubernetes.io/cluster/${var.cluster_name}", "owned",
  )}"
}

resource "aws_security_group_rule" "egress-from-worker" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.worker.id}"
}

resource "aws_security_group_rule" "ingress-worker-to-self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = "${aws_security_group.worker.id}"
  self              = true
}

resource "aws_security_group_rule" "ingress-master-to-worker" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = "${aws_security_group.master.id}"
  security_group_id        = "${aws_security_group.worker.id}"
}

resource "aws_security_group_rule" "worker-ssh" {
  count                    = "${length(var.ssh_security_group_ids)}"
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = "${element(var.ssh_security_group_ids, count.index)}"
  security_group_id        = "${aws_security_group.worker.id}"
}
