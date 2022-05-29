provider "aws"{
  profile ="task2profile"
  region ="ap-south-1"
}


resource "tls_private_key" "T-key" {
  algorithm = "RSA"
}
resource "aws_key_pair" "Task2-key"{
  key_name   = "task2-key"
  public_key = tls_private_key.T-key.public_key_openssh
}
resource "local_file" "keylocally" {
  content  = tls_private_key.T-key.private_key_pem
  filename = "task2-key.pem"

 depends_on = [
    tls_private_key.T-key
  ]
}

resource "aws_security_group" "my-task2-sg" {
  name        = "my-task2-sg"
  description = "Allow SSH and HTTP"
  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

ingress {
     description = "Allow NFS"
     from_port   = 2049
     to_port     = 2049
     protocol    = "tcp"
     cidr_blocks = [ "0.0.0.0/0" ]	
    }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "my-task2-sg"
  }

}


resource "aws_instance" "webserver" {

  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = aws_key_pair.Task2-key.key_name
  security_groups = ["my-task2-sg"]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.T-key.private_key_pem
    host     = aws_instance.webserver.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git amazon-efs-utils nfs-utils -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }
    tags = {
    Name = "webserver"
  }

}

resource "aws_efs_file_system" "task2-efs" {
  creation_token = "task2-efs"

  tags = {
    Name = "task2-efs"
  }
}

resource "aws_efs_mount_target" "mount-target" {

	file_system_id = aws_efs_file_system.task2-efs.id
	subnet_id      = aws_instance.webserver.subnet_id
	security_groups = ["${aws_security_group.my-task2-sg.id}"]

       	depends_on = [ aws_efs_file_system.task2-efs] 

}


resource "null_resource" "Run_cmds"  {

depends_on = [
    aws_efs_mount_target.mount-target
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.T-key.private_key_pem
    host     = aws_instance.webserver.public_ip
  }

provisioner "remote-exec" {
    inline = [
     "sudo mount  ${aws_efs_file_system.task2-efs.dns_name}:/  /var/www/html",
     "sudo echo ${aws_efs_file_system.task2-efs.dns_name}:/ /var/www/html efs defaults,_netdev 0 0 >> sudo /etc/fstab",
     "sudo git clone https://github.com/vamsi-01/task2-code.git /var/www/html/"
     
    ]
  }
}




output "pub_ip"{
value=aws_instance.webserver.public_ip
}


resource "aws_s3_bucket" "My_task2_bucket" {

  bucket = "my-task2-image-bucket"
  acl    = "public-read"

  tags = {
    Name        = "My bucket"
  }

  provisioner "local-exec"{
        command="git clone https://github.com/vamsi-01/Task-2-image.git Img_down"
  }

  provisioner "local-exec" {	
		when = destroy
		command = "rd /S/Q Img_down"
  }
}

resource "aws_s3_bucket_object" "task2-bucket" {
  depends_on=[
      aws_s3_bucket.My_task2_bucket
  ]
  key = "s3_image.jpg"
  bucket = aws_s3_bucket.My_task2_bucket.bucket
  acl    = "public-read"
  source ="Img_down/s3_image.jpg"
}

locals {
	s3_origin_id = "S3-${aws_s3_bucket.My_task2_bucket.bucket}"
}


resource "aws_cloudfront_distribution" "Cloudfront-S3" {
        depends_on=[
             null_resource.Run_cmds
        ]

	enabled = true
	is_ipv6_enabled = true
	
	origin {
		domain_name = aws_s3_bucket.My_task2_bucket.bucket_domain_name
		origin_id = local.s3_origin_id
	}
        default_cache_behavior {
    		allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    		cached_methods   = ["GET", "HEAD"]
    		target_origin_id = local.s3_origin_id

    		forwarded_values {
      			query_string = false

      			cookies {
        			forward = "none"
      			}
                      
    		}
                  viewer_protocol_policy = "allow-all"
        }
        restrictions {
    		geo_restriction {
    			restriction_type = "none"
    		}
    	}
        viewer_certificate {
    
    		cloudfront_default_certificate = true
  	}




    connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.T-key.private_key_pem
    host     = aws_instance.webserver.public_ip
    }

    provisioner "remote-exec" {
  		
  		inline = [
  			 
  			"sudo su << EOF",
            		" echo \"<img src='http://${self.domain_name}/${aws_s3_bucket_object.task2-bucket.key}' width='1200' height='300'>\" >> /var/www/html/index.php",
            		"EOF"
  		]
  	}
}


resource "null_resource" "Auto_access_website"  {


depends_on = [
   aws_cloudfront_distribution.Cloudfront-S3
  ]

	provisioner "local-exec" {
	    command = "start firefox  ${aws_instance.webserver.public_ip}"
  	}
}
     

















































