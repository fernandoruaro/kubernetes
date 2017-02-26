resource "aws_instance" "etcd" {
    count = "${var.servers}"
    ami = "ami-d206bdb2" // Unbuntu 16.04 LTS HVM, EBS-SSD
    instance_type = "${var.instance_type}"
    subnet_id = "${element(var.subnet_ids, count.index)}"
    associate_public_ip_address = true
    availability_zone = "${element(var.azs, count.index)}"
    vpc_security_group_ids = ["${var.security_group_id}"]
    key_name = "${var.key_name}"
    tags {
        ansible_managed = "yes",
        kubernetes_role = "etcd"
        terraform_module = "etcd"
        Name = "etcd"
    }
}

resource "aws_alb" "etcd" {
  name            = "tf-etcd-alb"
  internal        = true
  security_groups = ["${var.security_group_id}"]
  subnets         = ["${var.subnet_ids}"]
  tags {
    terraform_module = "etcd"
  }
}


resource "aws_alb_target_group" "etcd_client" {
  name     = "tf-etcd-${var.cluster_name}"
  port     = 2379
  protocol = "HTTP"
  vpc_id   = "${var.vpc_id}"
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
  count = "${var.servers}"
  target_group_arn = "${aws_alb_target_group.etcd_client.arn}"
  target_id = "${element(aws_instance.etcd.*.id, count.index)}"
  port = 2379
}

resource "aws_alb_target_group" "etcd_peer" {
  name     = "tf-etcd-peer"
  port     = 2380
  protocol = "HTTP"
  vpc_id   = "${var.vpc_id}"
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
  count = "${var.servers}"
  target_group_arn = "${aws_alb_target_group.etcd_peer.arn}"
  target_id = "${element(aws_instance.etcd.*.id, count.index)}"
  port = 2380
}

resource "aws_s3_bucket" "backups" {
    bucket = "tf-etcd-bkp-${var.cluster_name}"
    acl = "private"
}

###############
# ROUTE 53
###############
#resource "aws_route53_zone" "zone" {
#  name = "aws.encorehq.com"
#}

#resource "aws_route53_record" "etcd" {
#  zone_id = "${aws_route53_zone.zone.zone_id}"
#  name = "etcd.${aws_route53_zone.zone.name}"
#  type = "CNAME"
#  records = ["${aws_alb.etcd.dns_name}"]
#  ttl = 300
#}