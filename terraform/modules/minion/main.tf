module "ami" {
  source = "github.com/terraform-community-modules/tf_aws_ubuntu_ami"
  region = "${var.region}"
  distribution = "xenial"
  virttype = "hvm"
  storagetype = "instance-store"
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
     count = "${var.servers}"
     ami = "${module.ami.ami_id}"
     instance_type = "${var.instance_type}"
     subnet_id = "${element(var.subnet_ids, count.index)}"
     associate_public_ip_address = true # Instances have public, dynamic IP
     source_dest_check = false # TODO Required??
     availability_zone = "${element(var.azs, count.index)}"
     vpc_security_group_ids = ["${var.security_group_id}"]
     key_name = "${var.key_name}"
    
     tags {
       ansible_managed = "yes",
       kubernetes_role = "worker"
       terraform_module = "minion"
       Name = "kube-minion"
     }
 }