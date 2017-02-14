variable "region" { default="us-west-2" }
variable "azs" {
  type = "list"
  default = ["us-west-2a", "us-west-2b", "us-west-2c"]
}
variable "controller_instance_type" { default="t2.micro" }
variable "worker_instance_type" { default="t2.micro" }
variable "control_cidr" { default="54.202.45.150/32" }
provider "aws" { region = "${var.region}" }

resource "aws_key_pair" "kubernetes" {
  key_name = "kubernetes_tf" 
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCfCxovRTyz8cGnhj8tgUV7gK+u7CCOKXgICX9BVPo5EAHAP8WSmCofh8RnFTsajUkJA6NBKElzNNe9UpU8mgC9XZ9UQ2viG3KmLwXPxnONKipCGp0mUGWSp4p9uVi97nc4dTmBe7bTGRLoozBGi24Pm/80kDLAxlMnNk+j4jNjEGIvPG58Jc1W0qMqegRLfYup4ZGVOWHkHGPfz9/K3f5fNSDscVur1FLSKHq8pu9n0N43J+p8rpVKYZZt5By1JsJq1+mfdhcrGQyho2ejIyqyr1lS06NMJ9wcVYi5mRldfyNq/oMDYc/utXeLx8hredeA7gRZrWpzlS0cbY/F4ran ec2-user@ip-172-31-26-212"
}


resource "aws_vpc" "kubernetes" {
  cidr_block = "10.43.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_subnet" "kubernetes" {
  count = 3
  vpc_id = "${aws_vpc.kubernetes.id}"
  cidr_block = "${cidrsubnet(aws_vpc.kubernetes.cidr_block, 4, count.index)}"
  availability_zone = "${element(var.azs, count.index)}"
}

resource "aws_instance" "etcd" {
    count = 3
    ami = "ami-d206bdb2" // Unbuntu 16.04 LTS HVM, EBS-SSD
    instance_type = "t2.micro"

    subnet_id = "${element(aws_subnet.kubernetes.*.id, count.index)}"
    associate_public_ip_address = true
    availability_zone = "${element(var.azs, count.index)}"
    vpc_security_group_ids = ["${aws_security_group.kubernetes.id}"]
    key_name = "${aws_key_pair.kubernetes.key_name}"
    tags {
        ansible_managed = "yes",
        kubernetes_role = "etcd"
    }
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
}

resource "aws_route_table_association" "kubernetes" {
  count = 3
  subnet_id = "${element(aws_subnet.kubernetes.*.id, count.index)}"
  route_table_id = "${aws_route_table.kubernetes.id}"
}



############
# ETCD ALB
############
resource "aws_alb" "etcd" {
  name            = "tf-etcd-alb"
  internal        = true
  security_groups = ["${aws_security_group.kubernetes.id}"]
  subnets         = ["${aws_subnet.kubernetes.*.id}"]
}


############
# ETCD CLIENT
############
resource "aws_alb_target_group" "etcd_client" {
  name     = "tf-etcd-client"
  port     = 2379
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.kubernetes.id}"
  health_check {
    path   = "/health"
  }
}

resource "aws_alb_listener" "etcd_client" {
  load_balancer_arn = "${aws_alb.etcd.id}"
  port              = "2379"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.etcd_client.id}"
    type             = "forward"
  }
}

resource "aws_alb_target_group_attachment" "etcd_client" {
  count = 3
  target_group_arn = "${aws_alb_target_group.etcd_client.arn}"
  target_id = "${element(aws_instance.etcd.*.id, count.index)}"
  port = 2379
}


############
# ETCD PEER
############
resource "aws_alb_target_group" "etcd_peer" {
  name     = "tf-etcd-peer"
  port     = 2380
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.kubernetes.id}"
  health_check {
    path   = "/health"
    port   = 2379
  }
}

resource "aws_alb_listener" "etcd_peer" {
  load_balancer_arn = "${aws_alb.etcd.id}"
  port              = "2380"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.etcd_peer.id}"
    type             = "forward"
  }
}

resource "aws_alb_target_group_attachment" "etcd_peer" {
  count = 3
  target_group_arn = "${aws_alb_target_group.etcd_peer.arn}"
  target_id = "${element(aws_instance.etcd.*.id, count.index)}"
  port = 2380
}

###############
# ROUTE 53
###############
resource "aws_route53_zone" "zone" {
  name = "aws.encorehq.com"
}

resource "aws_route53_record" "etcd" {
  zone_id = "${aws_route53_zone.zone.zone_id}"
  name = "etcd.${aws_route53_zone.zone.name}"
  type = "CNAME"
  records = ["${aws_alb.etcd.dns_name}"]
  ttl = 300
}


variable amis {
  description = "Default AMIs to use for nodes depending on the region"
  type = "map"
  default = {
    ap-northeast-1 = "ami-0567c164"
    ap-southeast-1 = "ami-a1288ec2"
    cn-north-1 = "ami-d9f226b4"
    eu-central-1 = "ami-8504fdea"
    eu-west-1 = "ami-0d77397e"
    sa-east-1 = "ami-e93da085"
    us-east-1 = "ami-40d28157"
    us-west-1 = "ami-6e165d0e"
    us-west-2 = "ami-a9d276c9"
  }
}

resource "aws_instance" "controller" {

    count = 3
    ami = "ami-d206bdb2" // Unbuntu 16.04 LTS HVM, EBS-SSD
    #ami = "${lookup(var.amis, var.region)}"
    
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
  security_groups = ["${aws_security_group.kubernetes_api.id}"]
  subnets         = ["${aws_subnet.kubernetes.*.id}"]
}

resource "aws_alb_target_group" "controller" {
  name     = "tf-controller"
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
  count = 3
  target_group_arn = "${aws_alb_target_group.controller.arn}"
  target_id = "${element(aws_instance.controller.*.id, count.index)}"
  port = 6443
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



resource "aws_instance" "worker" {
    count = 3
    ami = "ami-d206bdb2" // Unbuntu 16.04 LTS HVM, EBS-SSD
    instance_type = "${var.worker_instance_type}"

    subnet_id = "${element(aws_subnet.kubernetes.*.id, count.index)}"
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