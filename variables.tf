// generic
variable "region" {
  description = "The AWS region to deploy the cluster in."
}

variable "cluster_name" {
  description = "And identifier for the cluster."
}

variable "cluster_subdomain" {
  description = "A subdomain cluster components dns records"
  default     = "k8s"
}

variable "vpc_id" {
  description = "The ID of the VPC to create resources in."
}

variable "public_subnet_count" {
  description = "The number of public subnets"
}

variable "public_subnet_ids" {
  description = "A list of the available public subnets in which EC2 instances can be created."
  type        = list(string)
}

variable "private_subnet_count" {
  description = "The number of private subnets"
}

variable "private_subnet_ids" {
  description = "A list of the available private subnets in which EC2 instances can be created."
  type        = list(string)
}

variable "key_name" {
  default     = ""
  description = "The name of the AWS Key Pair to be used when launching EC2 instances. Default empty string will result in no key"
}

variable "ssh_security_group_ids" {
  description = "The IDs of the Security Groups to open port 22 to."
  type        = list(string)
}

variable "containerlinux_ami_id" {
  description = "The ID of the Container Linux AMI to use for instances."
}

variable "route53_zone_id" {
  description = "The ID of the Route53 Zone to add records to."
}

variable "route53_inaddr_arpa_zone_id" {
  description = "The ID of the Route53 Zone to add pointer records to."
}

variable "iam_path" {
  description = "path where iam resources should be created"
  default     = "/"
}

variable "iam_prefix" {
  description = "prefix to be added to iam resources names"
  default     = ""
}

variable "permissions_boundary" {
  description = "permission_boudnary to apply to iam resources"
  default     = ""
}

variable "bucket_prefix" {
  description = "prefix to be added to the userdata bucket"
  default     = ""
}

// etcd nodes
variable "etcd_instance_count" {
  description = "The number of etcd instances to launch."
}

variable "etcd_addresses" {
  description = "A list of ip adrresses for etcd instances"
  type        = list(string)
}

variable "etcd_instance_type" {
  default     = "t2.small"
  description = "The type of etcd instances to launch."
}

variable "etcd_user_data" {
  description = "A list of the user data to provide to the etcd instances. Must be the same length as etcd_instance_count."
  type        = list(string)
}

variable "etcd_data_volume_size" {
  description = "The size (in GB) of the data volumes used in etcd nodes."
  default     = "5"
}


locals {
  iam_prefix = "${var.iam_prefix}${var.iam_prefix == "" ? "" : "-"}"
}
