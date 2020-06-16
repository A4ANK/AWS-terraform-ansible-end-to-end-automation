variable "profile" {
  default = "mumbai-iam-user"
}

variable "region" {
  default = "ap-south-1"
}

variable "vpc" {
  default = "vpc-07d7d26f"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "instance_count" {
  default = "1"
}

# variable "public_key" {
#   default = ""
# }

variable "private_key" {
  default = "mykeypair.pem"
}

variable "ansible_user" {
  default = "ec2-user"
}

variable "ami" {
  default = "ami-0447a12f28fddb066"
}
