output "master_address" {
  value = "${aws_route53_record.master-lb.name}"
}

output "etcd_security_group_id" {
  value = "${aws_security_group.etcd.id}"
}

output "master_security_group_id" {
  value = "${aws_security_group.master.id}"
}

output "worker_security_group_id" {
  value = "${aws_security_group.worker.id}"
}

output "cfssl_data_volumeid" {
  value = "${join("", split("-", aws_ebs_volume.cfssl-data.id))}"
}

output "etcd_data_volumeids" {
  value = "${split(",", join("", split("-", join(",", aws_ebs_volume.etcd-data.*.id))))}"
}
