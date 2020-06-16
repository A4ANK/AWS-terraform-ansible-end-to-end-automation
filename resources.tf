resource "aws_security_group" "allow_ssh_http" {
  name        = "allow_ssh_http_sg"
  description = "Allow inbound SSH and HTTP"
  vpc_id      = "${var.vpc}"

  ingress {
    description = "inbound ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "inbound http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_ssh_http"
  }
}

resource "aws_instance" "web" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = "mykeypair"
  security_groups = [ "${aws_security_group.allow_ssh_http.name}" ]

  # imperative approach of configuration management
  # connection {
  #   type     = "ssh"
  #   user     = "ec2-user"
  #   private_key = file("C:/Users/D/Downloads/mykeypair.pem")
  #   host     = aws_instance.web.public_ip
  # }

  # provisioner "remote-exec" {
  #   inline = [
  #     "sudo yum install httpd php git -y",
  #     "sudo systemctl restart httpd",
  #     "sudo systemctl enable httpd",
  #   ]
  # }

  tags = {
    Name = "my-webserver-1"
  }

}


#output "webserver-public-ip-output" {
#  value = aws_instance.web.public_ip
#}

resource "null_resource" "nulllocal1"  {

    provisioner "local-exec" {
            command = "echo ${aws_instance.web.public_ip} > publicip.txt"
    }
}

resource "null_resource" "nulllocal2" {

  depends_on = [
     aws_instance.web,
     null_resource.nulllocal1,
    ]
  # using ansible, declarative approach of configuration management
  provisioner "local-exec" {
    command ="ansible-playbook -i inventory  playbook.yml --private-key=${var.private_key}  --user ${var.ansible_user}"
  }
}

resource "aws_ebs_volume" "ebs1" {
   availability_zone = aws_instance.web.availability_zone
   size = 1
   tags = {
     Name = "ebs-volume"
   }
}


resource "aws_volume_attachment" "ebs_attach" {
   device_name = "/dev/sdh"
   volume_id   = "${aws_ebs_volume.ebs1.id}"
   instance_id = "${aws_instance.web.id}"
   force_detach = true
}


resource "null_resource" "nullremote1"  {
  depends_on = [
     null_resource.nulllocal2,
     null_resource.nulllocal1,
     aws_volume_attachment.ebs_attach,
   ]

  connection {
     type     = "ssh"
     user     = "ec2-user"
     private_key = file("mykeypair.pem")
     host     = aws_instance.web.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/A4ANK/AWS-terraform-end-to-end-automation.git /var/www/html/"
    ]
  }

  provisioner "remote-exec" {
    when = destroy
    inline = [
      "sudo rm -rf /var/www/html/*",
      "fuser -k -9 /var/www/html",
      "sudo umount /var/www/html"
    ]
  }  

}

resource "aws_s3_bucket" "s3_distribution" {
  bucket = "de12d54af33958fda0b48c48b5b2be42" 
  acl    = "private"

  tags = {
    Name = "My bucket"
  }
}

locals {
  s3_origin_id = "myS3OriginID"
}

resource "aws_s3_bucket_object" "object" {
  bucket = "${aws_s3_bucket.s3_distribution.id}"
  key    = "my.png"
  source = "/root/terraform/my.png"
  acl    = "public-read"

}
resource "aws_cloudfront_origin_access_identity" "s3_distribution" {
  comment = "Creating OAI"
}

data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.s3_distribution.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.s3_distribution.iam_arn}"]
    }
  }
}

resource "aws_s3_bucket_policy" "s3_distribution" {
  bucket = "${aws_s3_bucket.s3_distribution.id}"
  policy = "${data.aws_iam_policy_document.s3_policy.json}"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.s3_distribution.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"

    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.s3_distribution.cloudfront_access_identity_path}"
    }
  }

  enabled = true
  is_ipv6_enabled = true
  wait_for_deployment = false 

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }


  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}


resource "null_resource" "nullremote2"  {
  depends_on = [
     null_resource.nulllocal1,
     aws_volume_attachment.ebs_attach,
     aws_cloudfront_distribution.s3_distribution,
     aws_s3_bucket.s3_distribution,
   ]

  connection {
     type     = "ssh"
     user     = "ec2-user"
     private_key = file("mykeypair.pem")
     host     = aws_instance.web.public_ip
  }
  
  provisioner "file" {
    content     = "<img src='http://${aws_cloudfront_distribution.s3_distribution.domain_name}/my.png'>"
    destination = "/var/www/html/index.php"
  }
}

