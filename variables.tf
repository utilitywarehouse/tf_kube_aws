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

variable "control_plane_private_subnet_count" {
  description = "The number of private subnets used for control plane resources"
}

variable "control_plane_private_subnet_ids" {
  description = "A list of the available private subnets in which control plane nodes can be created."
  type        = list(string)
}

variable "worker_node_private_subnet_count" {
  description = "The number of private subnets used to spawn worker node instances"
}

variable "worker_node_private_subnet_ids" {
  description = "A list of the available private subnets in which worker EC2 instances can be created."
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

// cfssl server
variable "cfssl_server_address" {
  description = "The address of the cfssl server"
}

variable "cfssl_user_data" {
  description = "The user data to provide to the cfssl server."
}

variable "cfssl_data_device_name" {
  description = "Device name to use for the cfssl data volume"
  default     = "xvdf"
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

variable "etcd_data_volume_type" {
  description = "https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_volume#type"
  default     = "gp2"
}

variable "etcd_data_volume_iops" {
  description = "https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_volume#iops"
  default     = "3600"
}

// master nodes
variable "master_instance_count" {
  default     = "3"
  description = "The number of kubernetes master instances to launch."
}

variable "master_instance_type" {
  default     = "t2.small"
  description = "The type of kubernetes master instances to launch."
}

variable "master_user_data" {
  description = "The user data to provide to the kubernetes master instances."
}

// worker nodes
variable "worker_ondemand_instance_count" {
  default     = "3"
  description = "The number of kubernetes worker on-demand instances to launch."
}

variable "worker_spot_instance_count" {
  default     = "0"
  description = "The number of kubernetes worker spot instances to launch."
}

variable "worker_instance_type" {
  default     = "m5.large"
  description = "The type of kubernetes worker instances to launch."
}

variable "worker_user_data" {
  description = "The user data to provide to the kubernetes worker instances."
}

variable "worker_elb_names" {
  default     = []
  description = "A list of Classic ELB names to be attached to the worker autoscaling groups."
  type        = list(string)
}

variable "worker_target_group_arns" {
  default     = []
  description = "A list of ALB Target Group ARNs to register the worker instances with."
  type        = list(string)
}

variable "master_kms_ebs_key_arns" {
  default     = []
  description = "KMS keys used by masters to manage EBS volumes. This should be the same value as `kmsKeyId` in the storageClass (https://kubernetes.io/docs/concepts/storage/storage-classes/#aws-ebs)"
  type        = list(string)
}

locals {
  iam_prefix = "${var.iam_prefix}${var.iam_prefix == "" ? "" : "-"}"
}
