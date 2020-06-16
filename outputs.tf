output "AWS-instance-Public-IP" {
  value = "${aws_instance.web.public_ip}"
}

output "AWS-cloudfront-domain-name" {
  value = "${aws_cloudfront_distribution.s3_distribution.domain_name}"
}


resource "local_file" "ansible_inventory_hosts" {
 content = templatefile("inventory.template",
 {
  web_public_ip = aws_instance.web.public_ip,
  web_id = aws_instance.web.id,
 }
 )
 filename = "inventory"
}

resource "null_resource" "nulllocal3"  {

 depends_on = [
     null_resource.nullremote1,
   ]

       provisioner "local-exec" {
           command = "echo  ${aws_instance.web.public_ip}"
       }
}

resource "null_resource" "nulllocal4"  {

 depends_on = [
     null_resource.nullremote2,
   ]

       provisioner "local-exec" {
           command = "echo  ${aws_cloudfront_distribution.s3_distribution.domain_name}"
       }
}
