data "aws_availability_zones" "all" {}

data "aws_availability_zone" "all" {
  count = length(data.aws_availability_zones.all.names)
  name  = data.aws_availability_zones.all.names[count.index]
}

data "aws_route53_zone" "main" {
  zone_id = var.route53_zone_id
}

data "aws_route53_zone" "inaddr_arpa" {
  zone_id = var.route53_inaddr_arpa_zone_id
}

data "aws_vpc" "main" {
  id = var.vpc_id
}

data "aws_subnet" "private" {
  count = var.private_subnet_count
  id    = var.private_subnet_ids[count.index]
}

data "aws_subnet" "public" {
  count = var.public_subnet_count
  id    = var.public_subnet_ids[count.index]
}

resource "aws_s3_bucket" "userdata" {
  bucket = "${var.bucket_prefix}-ignition-userdata-${var.cluster_name}"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}
