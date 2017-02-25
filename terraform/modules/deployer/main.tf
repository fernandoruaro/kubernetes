
resource "aws_security_group" "deployer" {
  vpc_id = "${var.vpc_id}"
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

resource "aws_instance" "deployer" {
    ami = "ami-d206bdb2" // Unbuntu 16.04 LTS HVM, EBS-SSD
    instance_type = "${var.instance_type}"
    iam_instance_profile = "${var.iam_instance_profile_id}"

    subnet_id = "${var.subnet_id}"
    associate_public_ip_address = true
    source_dest_check = false

    availability_zone = "${var.availability_zone}"
    vpc_security_group_ids = ["${aws_security_group.deployer.id}"]
    key_name = "${var.key_name}"
    
    tags {
      ansible_managed = "yes",
      kubernetes_role = "deployer"
      terraform_module = "deployer"
      Name = "deployer"
    }
}
