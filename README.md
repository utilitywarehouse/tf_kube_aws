# tf_kube_aws

This terraform module creates a kubernetes cluster in AWS. It's designed to synergise well with [tf_kube_ignition](https://github.com/utilitywarehouse/tf_kube_ignition).

## Input Variables

The input variables are documented in their description and it's best to refer to [variables.tf](variables.tf).

## Ouputs

- `etcd_ip_list` - a list with the IP addresses of the created etcd nodes
- `master_address` - the endpoint on which the kubernetes api is made available
- `etcd_security_group_id` - the id of the security group to which kubernetes etcd nodes belong
- `master_security_group_id` - the id of the security group to which kubernetes master nodes belong
- `worker_security_group_id` - the id of the security group to which kubernetes worker nodes belong

## Usage

Below is an example of how you might use this terraform module:

```hcl
module "aws_cluster" {
  source = "github.com/utilitywarehouse/tf_kube_aws"

  region                         = "eu-west-1"
  cluster_name                   = "example-kube"
  vpc_id                         = "${aws_vpc.example.id}"
  ssl_s3_bucket_name             = "example-kube-ssl"
  containerlinux_ami_id          = "ami-xxxxxxxxx"
  route53_zone_id                = "${aws_route53_zone.example.id}"
  route53_inaddr_arpa_zone_id    = "${aws_route53_zone.example-reverse.id}"
  private_subnet_ids             = "${aws_subnet.private.*.id}"
  public_subnet_ids              = "${aws_subnet.public.*.id}"
  key_name                       = "${aws_key_pair.example.key_name}"
  ssh_security_group_id          = "${aws_security_group.ssh.id}"
  etcd_user_data                 = "${module.ignition.etcd}"
  master_user_data               = "${module.ignition.master}"
  worker_user_data               = "${module.ignition.worker}"
}
```
