output "etcd_security_group_id" {
  value = aws_security_group.etcd.id
}

output "etcd_data_volumeids" {
  value = split(",", replace(join(",", aws_ebs_volume.etcd-data.*.id), "-", ""))
}
