resource "null_resource" "cfssl_address" {
  triggers {
    subnet            = "${var.private_subnet_ids[0]}"
    availability_zone = "${data.aws_subnet.private.*.availability_zone[0]}"
    address           = "${cidrhost(data.aws_subnet.private.*.cidr_block[0], 5)}"
  }
}

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
  instance_type          = "t2.nano"
  iam_instance_profile   = "${aws_iam_instance_profile.cfssl.name}"
  user_data              = "${var.cfssl_user_data}"
  key_name               = "${var.key_name}"
  vpc_security_group_ids = ["${aws_security_group.cfssl.id}"]
  subnet_id              = "${null_resource.cfssl_address.triggers.subnet}"
  private_ip             = "${null_resource.cfssl_address.triggers.address}"

  lifecycle {
    ignore_changes = ["ami"]
  }

  root_block_device = {
    volume_type = "gp2"
    volume_size = 5
  }

  // kube uses the kubernetes.io tag to learn its cluster name and tag managed resources
  tags = "${map(
    "Name", "cfssl ${var.cluster_name}",
    "terraform.io/component", "${var.cluster_name}/cfssl",
    "kubernetes.io/cluster/${var.cluster_name}", "owned",
  )}"
}

resource "aws_ebs_volume" "cfssl-data" {
  availability_zone = "${null_resource.cfssl_address.triggers.availability_zone}"
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
  device_name = "/dev/xvdf"
  volume_id   = "${aws_ebs_volume.cfssl-data.*.id[count.index]}"
  instance_id = "${aws_instance.cfssl.*.id[count.index]}"
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
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = "${var.ssh_security_group_id}"
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
