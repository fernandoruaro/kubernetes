variable "region" {}
variable "cluster_name" {}
variable "availability_zones" { type = "list" }
variable "existing_vpc_ids" { type = "list" }
variable "master_instance_type" { default="m4.large" }
variable "etcd_instance_type" { default="m4.large" }
variable "minion_instance_type" { default="m3.medium" }
variable "control_cidr" { default="" }
variable "public_key" {default=""}
variable "minion_count" { default=2 }
variable "subnet_mask_bytes" { default = 4 }


data "aws_caller_identity" "current" {}




provider "aws" { region = "${var.region}" }

resource "aws_key_pair" "kubernetes" {
  key_name = "tf-${var.cluster_name}" 
  public_key = "${var.public_key}"
}





resource "aws_vpc" "kubernetes" {
  cidr_block = "172.100.0.0/16"
  enable_dns_hostnames = true
  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_vpc_peering_connection" "vpc_peering" {
    count="${length(var.existing_vpc_ids)}"

    peer_owner_id = "${data.aws_caller_identity.current.account_id}"
    peer_vpc_id = "${element(var.existing_vpc_ids, count.index)}"
    vpc_id = "${aws_vpc.kubernetes.id}"
    auto_accept = true

    tags {
      Name = "VPC Peering between ${var.cluster_name} and existing VPC"
    }
}



resource "aws_subnet" "kubernetes" {
  count = "${length(var.availability_zones)}"
  vpc_id = "${aws_vpc.kubernetes.id}"
  cidr_block = "${cidrsubnet(aws_vpc.kubernetes.cidr_block, var.subnet_mask_bytes, count.index)}"
  availability_zone = "${element(var.availability_zones, count.index)}"
}



module "etcd" {
    source = "./modules/etcd"

    vpc_id = "${aws_vpc.kubernetes.id}"
    key_name = "${aws_key_pair.kubernetes.key_name}"
    servers = "3"
    subnet_ids = ["${aws_subnet.kubernetes.*.id}"]
    azs = "${var.availability_zones}"
    security_group_id = "${aws_security_group.kubernetes.id}"
    cluster_name = "${var.cluster_name}"
    region = "${var.region}"
    instance_type = "${var.etcd_instance_type}"
}


resource "aws_security_group" "kubernetes" {
  vpc_id = "${aws_vpc.kubernetes.id}"
  name = "kubernetes"

  # Allow all outbound
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all internal
  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    self = true
  }

  # Allow all traffic from the API ELB
  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    security_groups = ["${aws_security_group.kubernetes_api.id}"]
  }

  # Allow all traffic from control host IP
  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["${var.control_cidr}"]
  }
}




resource "aws_security_group" "kubernetes_api" {
  vpc_id = "${aws_vpc.kubernetes.id}"
  name = "kubernetes-api"

  # Allow inbound traffic to the port used by Kubernetes API HTTPS
  ingress {
    from_port = 6443
    to_port = 6443
    protocol = "TCP"
    cidr_blocks = ["${var.control_cidr}"]
  }

  # Allow all traffic from the API ELB
  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    security_groups = ["${module.deployer.security_group}"]
  }


  # Allow all outbound traffic
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.kubernetes.id}"
}

resource "aws_route_table" "kubernetes" {
    vpc_id = "${aws_vpc.kubernetes.id}"
    route {
      cidr_block = "0.0.0.0/0"
      gateway_id = "${aws_internet_gateway.gw.id}"
    }

    lifecycle {
      ignore_changes = ["*"]
    }
}

resource "aws_route_table_association" "kubernetes" {
  count = "${length(var.availability_zones)}"
  subnet_id = "${element(aws_subnet.kubernetes.*.id, count.index)}"
  route_table_id = "${aws_route_table.kubernetes.id}"
}






#######
# IAM 
#######


resource "aws_iam_role" "kubernetes" {
  name = "tf-kubernetes-${var.cluster_name}"
  assume_role_policy = <<EOF
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
EOF
}

# Role policy
resource "aws_iam_role_policy" "kubernetes" {
  name = "tf-kubernetes-${var.cluster_name}"
  role = "${aws_iam_role.kubernetes.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action" : ["ec2:*"],
      "Effect": "Allow",
      "Resource": ["*"]
    },
    {
      "Action" : ["elasticloadbalancing:*"],
      "Effect": "Allow",
      "Resource": ["*"]
    },
    {
      "Action": "route53:*",
      "Effect": "Allow",
      "Resource": ["*"]
    },
    {
      "Action": "ecr:*",
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}





resource  "aws_iam_instance_profile" "kubernetes" {
 name = "tf-instance-profile-${var.cluster_name}"
 roles = ["${aws_iam_role.kubernetes.name}"]
}



module "master" {
    source = "./modules/master"

    vpc_id = "${aws_vpc.kubernetes.id}"
    key_name = "${aws_key_pair.kubernetes.key_name}"
    servers = "3"
    subnet_ids = ["${aws_subnet.kubernetes.*.id}"]
    azs = "${var.availability_zones}"
    security_group_id = "${aws_security_group.kubernetes.id}"
    api_security_group_id = "${aws_security_group.kubernetes_api.id}"
    iam_instance_profile_id = "${aws_iam_instance_profile.kubernetes.id}"
    cluster_name = "${var.cluster_name}"
    region = "${var.region}"
    instance_type = "${var.master_instance_type}"
}

 

module "minion" {
    source = "./modules/minion"

    key_name = "${aws_key_pair.kubernetes.key_name}"
    servers = "${var.minion_count}"
    subnet_ids = ["${aws_subnet.kubernetes.*.id}"]
    azs = "${var.availability_zones}"
    security_group_id = "${aws_security_group.kubernetes.id}"
    region = "${var.region}"
    instance_type = "${var.minion_instance_type}"
}


module "deployer" {
    source = "./modules/deployer"

    vpc_id = "${aws_vpc.kubernetes.id}"
    key_name = "${aws_key_pair.kubernetes.key_name}"
    subnet_id = "${element(aws_subnet.kubernetes.*.id, 1)}"
    availability_zone = "${element(var.availability_zones, 1)}"
    security_group_id = "${aws_security_group.kubernetes.id}"
    iam_instance_profile_id = "${aws_iam_instance_profile.kubernetes.id}"
    control_cidr = "${var.control_cidr}"
    region = "${var.region}"
}

 
output kubernetes_master_url {
  value = "${module.master.dns_name}"
}

output kubernetes_etcd_url {
  value = "${module.etcd.dns_name}"
}

output kubernetes_route_table_id {
  value = "${aws_route_table.kubernetes.id}"
}

output aws_region {
  value = "${var.region}"
}

output s3_etcd_backup_bucket {
  value = "${module.etcd.backup_bucket}"
}


resource "aws_iam_user" "etcd_backuper" {
  name = "etcd-backuper-${var.cluster_name}"
  path = "/system/"
}


resource "aws_iam_access_key" "etcd_backuper" {
  user    = "${aws_iam_user.etcd_backuper.name}"
}


output "etcd_key_id" {
  value = "${aws_iam_access_key.etcd_backuper.id}"
}

output "etcd_key_secret" {
  value = "${aws_iam_access_key.etcd_backuper.secret}"
}

resource "aws_iam_policy_attachment" "etcd_admin" {
    name = "tf-etcd-admin-${var.cluster_name}"
    users = ["${aws_iam_user.etcd_backuper.name}"]
    policy_arn = "${aws_iam_policy.etcd_backup.arn}"
}

resource "aws_iam_policy" "etcd_backup" {
    name = "tf-etcd-bkp-${var.cluster_name}"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListAllMyBuckets",
      "Resource": "arn:aws:s3:::*"
    },
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${module.etcd.backup_bucket}",
        "arn:aws:s3:::${module.etcd.backup_bucket}/*"
      ]
    }
  ]
}
EOF
}







output "cluster_name" {
  value = "${var.cluster_name}"
}