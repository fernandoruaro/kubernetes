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
  vpc_id = "${aws_vpc.kubernetes.id}"
  cidr_block = "10.43.0.0/16"
  availability_zone = "us-west-2a"
}

resource "aws_instance" "etcd" {
    count = 3
    ami = "ami-d206bdb2" // Unbuntu 16.04 LTS HVM, EBS-SSD
    instance_type = "t2.micro"

    subnet_id = "${aws_subnet.kubernetes.id}"
    private_ip = "${cidrhost("10.43.0.0/16", 10 + count.index)}"
    associate_public_ip_address = true

    availability_zone = "us-west-2a"
    vpc_security_group_ids = ["${aws_security_group.kubernetes.id}"]
    key_name = "${aws_key_pair.kubernetes.key_name}"
    tags {
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


resource "aws_security_group" "kubernetes_extra" {
  name = "kubernetes_extra"

  # Allow all outbound
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all traffic from control host IP
  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["${var.control_cidr}"]
  }
}

resource "aws_instance" "etcd_extra" {
    count = 1
    ami = "ami-d206bdb2" // Unbuntu 16.04 LTS HVM, EBS-SSD
    instance_type = "t2.micro"

    associate_public_ip_address = true

    availability_zone = "us-west-2a"
    vpc_security_group_ids = ["${aws_security_group.kubernetes_extra.id}"]
    key_name = "${aws_key_pair.kubernetes.key_name}"
    tags {
        kubernetes_role = "etcd"
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
  subnet_id = "${aws_subnet.kubernetes.id}"
  route_table_id = "${aws_route_table.kubernetes.id}"
}