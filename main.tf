terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.8.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
  access_key = AWS_ACCESS_KEY
  secret_key = AWS_SECRET_KEY
  token = AWS_SECURITY_TOKEN
}

# Mini Project

# step 1: Create a vpc

resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "production"
  }
}

# step 2: Create an Internet gateway

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id
}

# step 3: Create a custom route table

resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "prod"
  }
}

# step 4: Create a Subnet

variable "subnet_prefix" {
  description = "cidr block for the subnet"
}

resource "aws_subnet" "subnet-1" {
  vpc_id     = aws_vpc.prod-vpc.id
  cidr_block = var.subnet_prefix
  availability_zone = "us-west-2a"

  tags = {
    Name = "prod-subnet"
  }
}

# step 5: Associate subnet with route table

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

# step 6: Create a security group to allow ports 22, 80, 443

resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH from VPC"
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
    Name = "allow_web"
  }
}

# step 7: Create a network interface with an IP in the subnet that was created in step 4

resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]
}

# step 8: Assign an elastic IP to the network interface created in step 7

resource "aws_eip" "one" {
  vpc                       = true
  instance                  = aws_instance.web-server.id
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"

  depends_on = [aws_internet_gateway.gw]
}

# step 9: Create an ubuntu server and install/enable apache2

resource "aws_instance" "web-server" {
  ami           = "ami-07a29e5e945228fa1"
  instance_type = "t2.micro"
  availability_zone = "us-west-2a"
  key_name = "terraform-tutor"

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install apache2 -y
              sudo systemctl start apache2
              sudo bash -c "echo your first web server with terraform > /var/www/html/index.html"
              EOF 

  tags = {
    Name = "ubuntu-web-server"
  }
}