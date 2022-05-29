provider "aws"{
  profile ="task3-profile"
  region ="ap-south-1"
}


resource "tls_private_key" "T-key" {
  algorithm = "RSA"
}
resource "aws_key_pair" "Task4-key"{
  key_name   = "task4-key"
  public_key = tls_private_key.T-key.public_key_openssh
}
resource "local_file" "keylocally" {
  content  = tls_private_key.T-key.private_key_pem
  filename = "task4-key.pem"

 depends_on = [
    tls_private_key.T-key
  ]
}




resource "aws_vpc" "my-secure-vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "my-secure-vpc"
  }
  enable_dns_hostnames="true"
}


resource "aws_subnet" "mysubnet1a" {
  depends_on = [
    aws_vpc.my-secure-vpc
  ]

  vpc_id     = aws_vpc.my-secure-vpc.id
  cidr_block = "10.0.0.0/24"

  availability_zone="ap-south-1a"
  map_public_ip_on_launch="true"

  tags = {
    Name = "mysubnet1a"
  }
}


resource "aws_subnet" "mysubnet1b" {
  depends_on = [
    aws_vpc.my-secure-vpc
  ]
  vpc_id     = aws_vpc.my-secure-vpc.id
  cidr_block = "10.0.1.0/24"

  availability_zone="ap-south-1b"
  map_public_ip_on_launch="false"

  tags = {
    Name = "mysubnet1b"
  }
}

resource "aws_internet_gateway" "mysecurevpc-gw" {
  vpc_id = aws_vpc.my-secure-vpc.id

  tags = {
    Name = "mysecurevpc-gw"
  }
  depends_on = [
    aws_vpc.my-secure-vpc
  ]
}

resource "aws_route_table" "new-routing-table" {
  vpc_id = aws_vpc.my-secure-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mysecurevpc-gw.id
  }
  tags = {
    Name = "new-routing-table"
  }
  depends_on = [
    aws_internet_gateway.mysecurevpc-gw
  ]

}

resource "aws_route_table_association" "public-route" {
  subnet_id      = aws_subnet.mysubnet1a.id
  route_table_id = aws_route_table.new-routing-table.id
  depends_on = [
    aws_route_table.new-routing-table
  ]
}

resource "aws_eip" "Nat_Pub_Ip"{
  vpc = true 
   depends_on =[
     aws_route_table_association.public-route
   ]
} 

resource "aws_nat_gateway" "nat_db"{

  allocation_id = aws_eip.Nat_Pub_Ip.id 
  subnet_id = aws_subnet.mysubnet1a.id   

  tags={
    Name="nat_db"
  }

  depends_on = [
    aws_eip.Nat_Pub_Ip
  ]
}

resource "aws_route_table" "private-route-table"{

  vpc_id = aws_vpc.my-secure-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_db.id  
  }
  tags={
    Name = "private-route-table",
    description = "Route table for instances in private network ,to gain outbound traffic",
  }

  depends_on =[
    aws_nat_gateway.nat_db
  ]
}

resource "aws_route_table_association" "private-route"{

  subnet_id = aws_subnet.mysubnet1b.id 
  route_table_id = aws_route_table.private-route-table.id  
  
  depends_on =[
    aws_route_table.private-route-table
  ]
}



resource "aws_security_group" "sec-grp-Wordpress" {
  name        = "sec-grp-Wordpress"
  description = "Allow SSH and HTTP"
  vpc_id = aws_vpc.my-secure-vpc.id

   depends_on = [
    aws_vpc.my-secure-vpc
  ]

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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "sec-grp-Wordpress"
  }
}

resource "aws_security_group" "sec-grp-Bastion_host" {
  name        = "sec-grp-Bastion_host"
  description = "Allow SSH "
  vpc_id = aws_vpc.my-secure-vpc.id

  depends_on = [
    aws_security_group.sec-grp-Wordpress
  ]
    ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
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
    Name = "sec-grp-Wordpress"
  }

  }


resource "aws_security_group" "sec-grp-Mysql" {
  name        = "sec-grp-Mysql"
  description = "Allow mysql "
  vpc_id = aws_vpc.my-secure-vpc.id

   ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = [aws_security_group.sec-grp-Bastion_host.id]
  }

   ingress {
    description = "Allow Mysql"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.sec-grp-Wordpress.id]
  }

   egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "sec-grp-Mysql"
  }
  depends_on = [
    aws_security_group.sec-grp-Wordpress,aws_security_group.sec-grp-Bastion_host
  ]
}


resource "aws_instance" "mysql_instance" {
 
  depends_on = [aws_security_group.sec-grp-Mysql,aws_route_table_association.private-route ] 

  ami           = "ami-0fe5394cc0e02c698"
  instance_type = "t2.micro"
  key_name = aws_key_pair.Task4-key.key_name
  vpc_security_group_ids = [aws_security_group.sec-grp-Mysql.id]
  subnet_id = aws_subnet.mysubnet1b.id
  tags = {
    Name = "mysql_instance"
  }
}

resource "aws_instance" "wp_instance" {
 
  depends_on = [aws_instance.mysql_instance] 

  ami           = "ami-7e257211"
  instance_type = "t2.micro"
  key_name = aws_key_pair.Task4-key.key_name
  vpc_security_group_ids = [aws_security_group.sec-grp-Wordpress.id]
  subnet_id = aws_subnet.mysubnet1a.id
  
  tags = {
    Name = "wp_instance"
  }

}

resource "aws_instance" "Bastion_instance" {
 
  depends_on = [aws_instance.mysql_instance] 

  ami           = "ami-07db4adf15d7719d1"
  instance_type = "t2.micro"
  key_name = aws_key_pair.Task4-key.key_name
  vpc_security_group_ids = [aws_security_group.sec-grp-Bastion_host.id]
  subnet_id = aws_subnet.mysubnet1a.id
  
  tags = {
    Name = "Bastion_instance"
  }

}

resource "null_resource" "run_cmds"{

  depends_on = [
   aws_instance.wp_instance
  ]
  connection {
    type     = "ssh"
    user     = "ubuntu"
    private_key = tls_private_key.T-key.private_key_pem
    host     = aws_instance.wp_instance.public_ip
  }

  provisioner "remote-exec" {
    inline = [
     "sudo sed -i -e '/DB_NAME/s/wordpress/wordpressdb2/' /var/www/wordpress/wp-config.php",
     "sudo sed -i -e '/DB_USER/s/aurora/wordpressuser/' /var/www/wordpress/wp-config.php",
     "sudo sed -i -e '/DB_PASSWORD/s/${aws_instance.wp_instance.id}/wordpresspass/' /var/www/wordpress/wp-config.php",
     "sudo sed -i 's/localhost/${aws_instance.mysql_instance.private_ip}/g' /var/www/wordpress/wp-config.php",
      
    ]
  }
}


output "pub_ip"{
value=aws_instance.wp_instance.public_ip
}

resource "null_resource" "Auto_access_wordpress"  {

depends_on = [
   null_resource.run_cmds
  ]

	provisioner "local-exec" {
	    command = "start firefox  ${aws_instance.wp_instance.public_ip}"
  	}
}





