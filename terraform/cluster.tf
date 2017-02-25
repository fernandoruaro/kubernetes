variable "region" { default="us-west-2" }
variable "azs" {
  type = "list"
  default = ["us-west-2a", "us-west-2b", "us-west-2c"]
}
variable "controller_instance_type" { default="t2.micro" }
variable "worker_instance_type" { default="t2.micro" }
variable "control_cidr" { default="54.202.45.150/32" }
variable "controller_count" { default=3 }
variable "worker_count" { default=4 }
variable "key_name" { default="kubernetes_tf" }


provider "aws" { region = "${var.region}" }

resource "aws_key_pair" "kubernetes" {
  key_name = "${var.key_name}" 
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCfCxovRTyz8cGnhj8tgUV7gK+u7CCOKXgICX9BVPo5EAHAP8WSmCofh8RnFTsajUkJA6NBKElzNNe9UpU8mgC9XZ9UQ2viG3KmLwXPxnONKipCGp0mUGWSp4p9uVi97nc4dTmBe7bTGRLoozBGi24Pm/80kDLAxlMnNk+j4jNjEGIvPG58Jc1W0qMqegRLfYup4ZGVOWHkHGPfz9/K3f5fNSDscVur1FLSKHq8pu9n0N43J+p8rpVKYZZt5By1JsJq1+mfdhcrGQyho2ejIyqyr1lS06NMJ9wcVYi5mRldfyNq/oMDYc/utXeLx8hredeA7gRZrWpzlS0cbY/F4ran ec2-user@ip-172-31-26-212"
}



resource "aws_vpc" "kubernetes" {
  cidr_block = "10.43.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_subnet" "kubernetes" {
  count = "${length(var.azs)}"
  vpc_id = "${aws_vpc.kubernetes.id}"
  cidr_block = "${cidrsubnet(aws_vpc.kubernetes.cidr_block, 4, count.index)}"
  availability_zone = "${element(var.azs, count.index)}"
}



module "etcd" {
    source = "etcd"
    vpc_id = "${aws_vpc.kubernetes.id}"
    key_name = "${var.key_name}"
    servers = "3"
    subnet_ids = "${aws_subnet.kubernetes.*.id}"
    azs = "${var.azs}"
    security_group_id = "${aws_security_group.kubernetes.id}"
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



resource "aws_security_group" "deployer" {
  vpc_id = "${aws_vpc.kubernetes.id}"
  name = "deployer"

  # Allow all outbound
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all traffic from control host IP
  ingress {
    from_port = 22
    to_port = 22
    protocol = "TCP"
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
    security_groups = ["${aws_security_group.deployer.id}"]
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






resource "aws_instance" "controller" {

    count = "${var.controller_count}"
    ami = "ami-d206bdb2" // Unbuntu 16.04 LTS HVM, EBS-SSD
    
    instance_type = "${var.controller_instance_type}"

    iam_instance_profile = "${aws_iam_instance_profile.kubernetes.id}"

    subnet_id = "${element(aws_subnet.kubernetes.*.id, count.index)}"
    associate_public_ip_address = true # Instances have public, dynamic IP
    source_dest_check = false # TODO Required??

    availability_zone = "${element(var.azs, count.index)}"
    vpc_security_group_ids = ["${aws_security_group.kubernetes.id}"]
    key_name = "${aws_key_pair.kubernetes.key_name}"
    
    tags {
      ansible_managed = "yes",
      kubernetes_role = "controller"
    }
}


############
# KUBE CONTROLLER ALB
############
resource "aws_alb" "controller" {
  name            = "tf-controller-alb"
  internal        = true
  security_groups = ["${aws_security_group.kubernetes_api.id}","${aws_security_group.kubernetes.id}"]
  subnets         = ["${aws_subnet.kubernetes.*.id}"]
}

## 6443

resource "aws_alb_target_group" "controller" {
  name     = "tf-controller-6443"
  port     = 6443
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.kubernetes.id}"
  health_check {
    path   = "/healthz"
    port   = 8080
  }
}


resource "aws_alb_listener" "controller" {
  load_balancer_arn = "${aws_alb.controller.id}"
  port              = "6443"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.controller.id}"
    type             = "forward"
  }
}

resource "aws_alb_target_group_attachment" "controller" {
  count = "${var.controller_count}"
  target_group_arn = "${aws_alb_target_group.controller.arn}"
  target_id = "${element(aws_instance.controller.*.id, count.index)}"
  port = 6443
}

## 8080

resource "aws_alb_target_group" "controller_8080" {
  name     = "tf-controller-8080"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.kubernetes.id}"
  health_check {
    path   = "/healthz"
    port   = 8080
  }
}

resource "aws_alb_listener" "controller_8080" {
  load_balancer_arn = "${aws_alb.controller.id}"
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.controller_8080.id}"
    type             = "forward"
  }
}


resource "aws_alb_target_group_attachment" "controller_8080" {
  count = "${var.controller_count}"
  target_group_arn = "${aws_alb_target_group.controller_8080.arn}"
  target_id = "${element(aws_instance.controller.*.id, count.index)}"
  port = 8080
}



#######
# IAM 
#######


resource "aws_iam_role" "kubernetes" {
  name = "tf-kubernetes"
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
  name = "tf-kubernetes"
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

# IAM Instance Profile for Controller
resource  "aws_iam_instance_profile" "kubernetes" {
 name = "tf-kubernetes"
 roles = ["${aws_iam_role.kubernetes.name}"]
}



#resource "aws_launch_configuration" "default_worker" {
#    name = "default_worker"
#    image_id = "ami-d206bdb2" // Unbuntu 16.04 LTS HVM, EBS-SSD
#    instance_type = "${var.worker_instance_type}"
#    key_name = "${aws_key_pair.kubernetes.key_name}"
#    security_groups = ["${aws_security_group.kubernetes.id}"]
#    associate_public_ip_address = true
#}


#resource "aws_autoscaling_group" "default_worker" {
#    name = "default_worker"
#    min_size = "${var.worker_count}"
#    max_size = "${var.worker_count}"
#    launch_configuration = "${aws_launch_configuration.default_worker.name}"
#    vpc_zone_identifier = ["${aws_subnet.kubernetes.*.id}"]
#    lifecycle {
#      create_before_destroy = true
#    }
#    tag {
#      key                 = "ansible_managed"
#      value               = "yes"
#      propagate_at_launch = true
#    }
#    tag {
#      key                 = "kubernetes_role"
#      value               = "worker"
#      propagate_at_launch = true
#    }
#}




resource "aws_instance" "worker" {
     count = "${var.worker_count}"
     ami = "ami-d206bdb2" // Unbuntu 16.04 LTS HVM, EBS-SSD
     instance_type = "${var.worker_instance_type}"
     subnet_id = "${element(aws_subnet.kubernetes.*.id, count.index % 3)}"
     associate_public_ip_address = true # Instances have public, dynamic IP
     source_dest_check = false # TODO Required??
     availability_zone = "${element(var.azs, count.index)}"
     vpc_security_group_ids = ["${aws_security_group.kubernetes.id}"]
     key_name = "${aws_key_pair.kubernetes.key_name}"
    
     tags {
       ansible_managed = "yes",
       kubernetes_role = "worker"
     }
 }
 


resource "aws_instance" "deployer" {
    ami = "ami-d206bdb2" // Unbuntu 16.04 LTS HVM, EBS-SSD
    instance_type = "${var.worker_instance_type}"
    iam_instance_profile = "${aws_iam_instance_profile.kubernetes.id}"

    subnet_id = "${element(aws_subnet.kubernetes.*.id, 1)}"
    associate_public_ip_address = true
    source_dest_check = false

    availability_zone = "${element(var.azs, 1)}"
    vpc_security_group_ids = ["${aws_security_group.deployer.id}"]
    key_name = "${aws_key_pair.kubernetes.key_name}"
    
    tags {
      ansible_managed = "yes",
      kubernetes_role = "deployer"
    }
}


resource "aws_s3_bucket" "backups" {
    bucket = "ea-tf-backups"
    acl = "private"
}


output kubernetes_master_url {
  value = "${aws_alb.controller.dns_name}"
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
