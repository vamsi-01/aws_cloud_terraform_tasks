#Login using profile
provider "aws"{
  profile ="vamsi"
  region ="ap-south-1"
}

#Creating a Key-Pair
resource "tls_private_key" "key" {
  algorithm = "RSA"
}
resource "aws_key_pair" "Mykey"{
  key_name   = "mykey"
  public_key = tls_private_key.key.public_key_openssh
}

#Storing the key locally
resource "local_file" "keylocally" {
  content  = tls_private_key.key.private_key_pem
  filename = "mykey.pem"

 depends_on = [
    tls_private_key.key
  ]
}

#Creating a Security-Group
resource "aws_security_group" "Mysec_grp_tera" {
  name        = "Mysec_grp_tera"
  description = "Allow SSH and HTTP"
  vpc_id      = "vpc-7ce4f914"
  ingress {
    description = "allow SSH"
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
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Mysec_grp_tera"
  }

}

#Creating an EC2 Instance and downloading softwares.

resource "aws_instance" "WebOs" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = "mykey"
  security_groups = ["Mysec_grp_tera"]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.key.private_key_pem
    host     = aws_instance.WebOs.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }
    tags = {
    Name = "WebOs"
  }

}

#Creating an EBS Volume

resource "aws_ebs_volume" "ebs_tera" {
  availability_zone = aws_instance.WebOs.availability_zone
  size              = 1
  tags = {
    Name = "myweb"
  }
}

#Attaching the EBS volume to EC2 Instance.

resource "aws_volume_attachment" "attach_ebs" {
  device_name = "/dev/sdb"
  volume_id   = aws_ebs_volume.ebs_tera.id
  instance_id = aws_instance.WebOs.id
  force_detach = true
}
output "pub_ip"{
value=aws_instance.WebOs.public_ip
}
resource "null_resource" "save_ip"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.WebOs.public_ip} > Wpublic_ip.txt"
  	}
}

#Formatting and Mounting the volume , also downloading developer code from Git-Hub into Web-server directory.

resource "null_resource" "Run_cmds"  {

depends_on = [
    aws_volume_attachment.attach_ebs
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.key.private_key_pem
    host     = aws_instance.WebOs.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdb",
      "sudo mount  /dev/xvdb  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/vamsi-01/Mywebserver.git /var/www/html/"
    ]
  }
}

#Creating S3 Bucket.

resource "aws_s3_bucket" "My_tera_bucket" {
  depends_on = [
		null_resource.Run_cmds,
	]
  bucket = "my-tera-image-bucket"
  acl    = "public-read"

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
  provisioner "local-exec"{

   command="git clone https://github.com/vamsi-01/Webserver-image.git Img_down"

  }
 
   provisioner "local-exec" {
	
		when = destroy
		command = "rd /S/Q Img_down"
	}
}

#Creating an object for above S3 Bucket .

resource "aws_s3_bucket_object" "Obj_bucket" {
  depends_on=[
      aws_s3_bucket.My_tera_bucket
  ]
  key = "HMC.jpg"
  bucket = aws_s3_bucket.My_tera_bucket.bucket
  acl    = "public-read"
  source ="Img_down/Hybrid_Multi_Cloud-788x360.jpg"
}

locals {
	s3_origin_id = "S3-${aws_s3_bucket.My_tera_bucket.bucket}"
}

#Creating A CloudFront Distribution for S3 bucket.

resource "aws_cloudfront_distribution" "Cloudfront-S3" {

	enabled = true
	is_ipv6_enabled = true
	
	origin {
		domain_name = aws_s3_bucket.My_tera_bucket.bucket_domain_name
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
    private_key = tls_private_key.key.private_key_pem
    host     = aws_instance.WebOs.public_ip
    }
    provisioner "remote-exec" {
  		
  		inline = [
  			
  			"sudo su << EOF",
            		" echo \"<img src='http://${self.domain_name}/${aws_s3_bucket_object.Obj_bucket.key}' width='600' height='300'>\" >> /var/www/html/index.php",
            		"EOF"
  		]
  	}
}

#Accessing Web-site

resource "null_resource" "Auto_access"  {
depends_on = [
   aws_cloudfront_distribution.Cloudfront-S3
  ]

	provisioner "local-exec" {
	    command = "start firefox  ${aws_instance.WebOs.public_ip}"
  	}
}
     
