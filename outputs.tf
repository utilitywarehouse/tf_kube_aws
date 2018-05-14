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
  value = "${var.cfssl_data_device_name}"
}

data "null_data_source" "etcd_data_volumeids" {
  count = "${var.etcd_instance_count}"

  inputs = {
    name = "${var.etcd_data_device_name}"
  }
}

output "etcd_data_volumeids" {
  value = "${data.null_data_source.etcd_data_volumeids.*.outputs.name}"
}
