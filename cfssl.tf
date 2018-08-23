// IAM instance role
resource "aws_iam_role" "cfssl" {
  name = "${var.cluster_name}_cfssl"

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

resource "aws_iam_instance_profile" "cfssl" {
  name = "${var.cluster_name}-cfssl"
  role = "${aws_iam_role.cfssl.name}"
}

// EC2 Instance
resource "aws_instance" "cfssl" {
  ami                    = "${var.containerlinux_ami_id}"
  instance_type          = "t3.nano"
  iam_instance_profile   = "${aws_iam_instance_profile.cfssl.name}"
  user_data              = "${var.cfssl_user_data}"
  key_name               = "${var.key_name}"
  vpc_security_group_ids = ["${aws_security_group.cfssl.id}"]
  subnet_id              = "${var.private_subnet_ids[0]}"
  private_ip             = "${var.cfssl_server_address}"

  lifecycle {
    ignore_changes = ["ami"]
  }

  root_block_device = {
    volume_type = "gp2"
    volume_size = 5
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  // kube uses the kubernetes.io tag to learn its cluster name and tag managed resources
  tags = "${map(
    "Name", "cfssl ${var.cluster_name}",
    "terraform.io/component", "${var.cluster_name}/cfssl",
    "kubernetes.io/cluster/${var.cluster_name}", "owned",
  )}"
}

resource "aws_ebs_volume" "cfssl-data" {
  availability_zone = "${data.aws_subnet.private.*.availability_zone[0]}"
  size              = 5
  type              = "gp2"

  // kube uses the kubernetes.io tag to learn its cluster name and tag managed resources
  tags = "${map(
    "Name", "cfssl ${var.cluster_name} data vol ${count.index}",
    "terraform.io/component", "${var.cluster_name}/cfssl",
    "kubernetes.io/cluster/${var.cluster_name}", "owned",
  )}"
}

resource "aws_volume_attachment" "cfssl-data" {
  // This is a terraform workaround. The device_name is ignored by the
  // instance, but terraform insists that it needs to be set. Actual device
  // name will be something like: /dev/nvme1n1
  device_name = "/dev/${var.cfssl_data_device_name}"

  volume_id   = "${aws_ebs_volume.cfssl-data.*.id[count.index]}"
  instance_id = "${aws_instance.cfssl.*.id[count.index]}"

  // Skip destroying the attachment. In case of instance recreation the os will handle that for us.
  skip_destroy = true
}

// VPC Security Group
resource "aws_security_group" "cfssl" {
  name        = "${var.cluster_name}-cfssl"
  description = "k8s cfssl security group"
  vpc_id      = "${var.vpc_id}"

  // kube uses the kubernetes.io tag to learn its cluster name and tag managed resources
  tags = "${map(
    "Name", "cfssl ${var.cluster_name}",
    "terraform.io/component", "${var.cluster_name}/cfssl",
    "kubernetes.io/cluster/${var.cluster_name}", "owned",
  )}"
}

resource "aws_security_group_rule" "egress-from-cfssl" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.cfssl.id}"
}

resource "aws_security_group_rule" "ingress-cfssl-to-self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = "${aws_security_group.cfssl.id}"
  self              = true
}

resource "aws_security_group_rule" "cfssl-ssh" {
  count                    = "${length(var.ssh_security_group_ids)}"
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = "${element(var.ssh_security_group_ids, count.index)}"
  security_group_id        = "${aws_security_group.cfssl.id}"
}

resource "aws_security_group_rule" "ingress-etcd-to-cfssl" {
  type                     = "ingress"
  from_port                = 8888
  to_port                  = 8888
  protocol                 = "tcp"
  source_security_group_id = "${aws_security_group.etcd.id}"
  security_group_id        = "${aws_security_group.cfssl.id}"
}

resource "aws_security_group_rule" "ingress-master-to-cfssl" {
  type                     = "ingress"
  from_port                = 8888
  to_port                  = 8889
  protocol                 = "tcp"
  source_security_group_id = "${aws_security_group.master.id}"
  security_group_id        = "${aws_security_group.cfssl.id}"
}

resource "aws_security_group_rule" "ingress-worker-to-cfssl" {
  type                     = "ingress"
  from_port                = 8888
  to_port                  = 8888
  protocol                 = "tcp"
  source_security_group_id = "${aws_security_group.worker.id}"
  security_group_id        = "${aws_security_group.cfssl.id}"
}

resource "aws_security_group_rule" "ingress-worker-to-cfssl-node-exporter" {
  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  source_security_group_id = "${aws_security_group.worker.id}"
  security_group_id        = "${aws_security_group.cfssl.id}"
}

// Route53 records
resource "aws_route53_record" "cfssl-instance" {
  zone_id = "${var.route53_zone_id}"
  name    = "cfssl.${var.cluster_name}.${data.aws_route53_zone.main.name}"
  type    = "A"
  ttl     = "300"
  records = ["${aws_instance.cfssl.private_ip}"]
}
