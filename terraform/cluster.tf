variable "region" { default="us-west-2" }
variable "cluster_name" { default="kube-01"}
variable "azs" {
  type = "list"
  default = ["us-west-2a", "us-west-2b", "us-west-2c"]
}
variable "controller_instance_type" { default="t2.micro" }
variable "worker_instance_type" { default="t2.micro" }
variable "control_cidr" { default="54.202.45.150/32" }
variable "worker_count" { default=4 }

#When creating subnet inside an existing vpc, use this variable to skip an cidrs
variable "subnet_mask_bytes" { default = 4 }


data "aws_caller_identity" "current" {}


provider "aws" { region = "${var.region}" }

resource "aws_key_pair" "kubernetes" {
  key_name = "tf-${var.cluster_name}" 
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCfCxovRTyz8cGnhj8tgUV7gK+u7CCOKXgICX9BVPo5EAHAP8WSmCofh8RnFTsajUkJA6NBKElzNNe9UpU8mgC9XZ9UQ2viG3KmLwXPxnONKipCGp0mUGWSp4p9uVi97nc4dTmBe7bTGRLoozBGi24Pm/80kDLAxlMnNk+j4jNjEGIvPG58Jc1W0qMqegRLfYup4ZGVOWHkHGPfz9/K3f5fNSDscVur1FLSKHq8pu9n0N43J+p8rpVKYZZt5By1JsJq1+mfdhcrGQyho2ejIyqyr1lS06NMJ9wcVYi5mRldfyNq/oMDYc/utXeLx8hredeA7gRZrWpzlS0cbY/F4ran ec2-user@ip-172-31-26-212"
}


resource "aws_vpc" "existing_vpc" {
  cidr_block = "172.20.0.0/16"
}


resource "aws_vpc" "kubernetes" {
  cidr_block = "172.100.0.0/16"
  enable_dns_hostnames = true
  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_vpc_peering_connection" "vpc_peering" {
    peer_owner_id = "${data.aws_caller_identity.current.account_id}"
    peer_vpc_id = "${aws_vpc.existing_vpc.id}"
    vpc_id = "${aws_vpc.kubernetes.id}"
    auto_accept = true

    tags {
      Name = "VPC Peering between ${var.cluster_name} and existing VPC"
    }
}



resource "aws_subnet" "kubernetes" {
  count = "${length(var.azs)}"
  vpc_id = "${aws_vpc.kubernetes.id}"
  cidr_block = "${cidrsubnet(aws_vpc.kubernetes.cidr_block, var.subnet_mask_bytes, count.index)}"
  availability_zone = "${element(var.azs, count.index)}"
}



module "etcd" {
    source = "./modules/etcd"

    vpc_id = "${aws_vpc.kubernetes.id}"
    key_name = "${aws_key_pair.kubernetes.key_name}"
    servers = "3"
    subnet_ids = ["${aws_subnet.kubernetes.*.id}"]
    azs = "${var.azs}"
    security_group_id = "${aws_security_group.kubernetes.id}"
    cluster_name = "${var.cluster_name}"
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
  count = "${length(var.azs)}"
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
    azs = "${var.azs}"
    security_group_id = "${aws_security_group.kubernetes.id}"
    api_security_group_id = "${aws_security_group.kubernetes_api.id}"
    iam_instance_profile_id = "${aws_iam_instance_profile.kubernetes.id}"
    cluster_name = "${var.cluster_name}"
}

 

module "minion" {
    source = "./modules/minion"

    key_name = "${aws_key_pair.kubernetes.key_name}"
    servers = "4"
    subnet_ids = ["${aws_subnet.kubernetes.*.id}"]
    azs = "${var.azs}"
    security_group_id = "${aws_security_group.kubernetes.id}"
}


module "deployer" {
    source = "./modules/deployer"

    vpc_id = "${aws_vpc.kubernetes.id}"
    key_name = "${aws_key_pair.kubernetes.key_name}"
    subnet_id = "${element(aws_subnet.kubernetes.*.id, 1)}"
    availability_zone = "${element(var.azs, 1)}"
    security_group_id = "${aws_security_group.kubernetes.id}"
    iam_instance_profile_id = "${aws_iam_instance_profile.kubernetes.id}"
    control_cidr = "${var.control_cidr}"
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




