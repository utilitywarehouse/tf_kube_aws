// IAM instance role
resource "aws_iam_role" "etcd" {
  name                 = "${local.iam_prefix}${var.cluster_name}-etcd"
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

resource "aws_iam_instance_profile" "etcd" {
  name = "${local.iam_prefix}${var.cluster_name}-etcd"
  role = aws_iam_role.etcd.name
  path = var.iam_path
}

resource "aws_iam_role_policy" "etcd" {
  count  = var.etcd_role_additional_permissions == "" ? 0 : 1
  name   = "${local.iam_prefix}${var.cluster_name}-etcd"
  role   = aws_iam_role.etcd.id
  policy = var.etcd_role_additional_permissions
}

// EC2 Instances
resource "aws_instance" "etcd" {
  count                  = var.etcd_instance_count
  ami                    = var.containerlinux_ami_id
  instance_type          = var.etcd_instance_type
  user_data              = var.etcd_user_data[count.index]
  iam_instance_profile   = aws_iam_instance_profile.etcd.name
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.etcd.id]
  subnet_id              = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  private_ip             = var.etcd_addresses[count.index]

  lifecycle {
    ignore_changes = [ami]
  }

  root_block_device {
    volume_type = "gp2"
    volume_size = 10
  }

  // kube uses the kubernetes.io tag to learn its cluster name and tag managed resources
  tags = {
    "Name"                                      = "etcd ${var.cluster_name} ${count.index}"
    "terraform.io/component"                    = "${var.cluster_name}/etcd/${count.index}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_ebs_volume" "etcd-data" {
  count             = var.etcd_instance_count
  availability_zone = data.aws_subnet.private[count.index % length(var.private_subnet_ids)].availability_zone
  size              = var.etcd_data_volume_size
  type              = "gp2"

  // kube uses the kubernetes.io tag to learn its cluster name and tag managed resources
  tags = {
    "Name"                                      = "etcd ${var.cluster_name} data vol ${count.index}"
    "terraform.io/component"                    = "${var.cluster_name}/etcd/${count.index}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_volume_attachment" "etcd-data" {
  count = var.etcd_instance_count

  // This is a terraform workaround. The device_name is ignored by the
  // instance, but terraform insists that it needs to be set. Actual device
  // name will be something like: /dev/nvme1n1
  device_name = "/dev/xvdf"

  volume_id   = aws_ebs_volume.etcd-data[count.index].id
  instance_id = aws_instance.etcd[count.index].id

  // Skip destroying the attachment. In case of instance recreation the os will handle that for us.
  skip_destroy = true
}

// VPC Security Group
resource "aws_security_group" "etcd" {
  name        = "${var.cluster_name}-etcd"
  description = "k8s etcd security group"
  vpc_id      = var.vpc_id

  // kube uses the kubernetes.io tag to learn its cluster name and tag managed resources
  tags = {
    "Name"                                      = "etcd ${var.cluster_name}"
    "terraform.io/component"                    = "${var.cluster_name}/etcd"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_security_group_rule" "egress-from-etcd" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.etcd.id
}

resource "aws_security_group_rule" "ingress-etcd-to-self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.etcd.id
  self              = true
}

resource "aws_security_group_rule" "ingress-master-to-etcd" {
  type                     = "ingress"
  from_port                = 2379
  to_port                  = 2379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.master.id
  security_group_id        = aws_security_group.etcd.id
}

resource "aws_security_group_rule" "ingress-worker-insecure-metrics" {
  type                     = "ingress"
  from_port                = 9378
  to_port                  = 9378
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.worker.id
  security_group_id        = aws_security_group.etcd.id
}

resource "aws_security_group_rule" "ingress-worker-to-etcd-node-exporter" {
  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.worker.id
  security_group_id        = aws_security_group.etcd.id
}

resource "aws_security_group_rule" "etcd-ssh" {
  count                    = length(var.ssh_security_group_ids)
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = element(var.ssh_security_group_ids, count.index)
  security_group_id        = aws_security_group.etcd.id
}

// Route53 records
resource "aws_route53_record" "etcd-all" {
  zone_id = var.route53_zone_id
  count   = 1
  name    = "etcd.${var.cluster_subdomain}.${data.aws_route53_zone.main.name}"
  type    = "A"
  ttl     = "30"
  records = aws_instance.etcd.*.private_ip
}

resource "aws_route53_record" "etcd-by-instance" {
  count   = var.etcd_instance_count
  zone_id = var.route53_zone_id
  name    = "${count.index}.etcd.${var.cluster_subdomain}.${data.aws_route53_zone.main.name}"
  type    = "A"
  ttl     = "30"
  records = [aws_instance.etcd[count.index].private_ip]
}

resource "aws_route53_record" "etcd-PTR-by-instance" {
  count   = var.etcd_instance_count
  zone_id = var.route53_inaddr_arpa_zone_id
  name    = "${element(split(".", aws_instance.etcd[count.index].private_ip), 3)}.${element(split(".", aws_instance.etcd[count.index].private_ip), 2)}.${data.aws_route53_zone.inaddr_arpa.name}"
  type    = "PTR"
  ttl     = "30"
  records = ["${aws_route53_record.etcd-by-instance[count.index].name}."]
}
