variable "vpc_id" {
  default     = ""
}

variable "control_cidr" {
  default     = ""
  description = "CIDR of the instace used for running ansible"
}



variable "security_group_id" {
  description = "Security group for master."
  default     = ""
}

variable "subnet_id" {
  default     = ""
  description = "A list of subnet ids (1 for each az)"
}

variable "availability_zone" {
  default     = ""
}

variable "key_name" {
 default = ""
}

variable "instance_type" {
 default = "t2.micro"
}

variable "iam_instance_profile_id" {
 default = ""
}

