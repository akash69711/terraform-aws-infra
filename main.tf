terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

variable "credentials" {
  description = "AWS access key and secret key"
  
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
  access_key = var.credentials[0]
  secret_key = var.credentials[1]
}

#1. Create VPC

resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "Production VPC"
  }
}

#2. Create IG
resource "aws_internet_gateway" "prod-gw" {
  vpc_id = aws_vpc.prod-vpc.id

  tags = {
    Name = "Production IG"
  }
}

#3. Create Custom Route table

resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.prod-gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.prod-gw.id
  }

  tags = {
    Name = "Production route table"
  }
}


# Create a variable to pass in cidr_block
variable "cidr_prefix" {
  description = "Cidr block value"
  default = "10.0.20.0/24" #If a user doesnt enter a value this value will be used.
  #type = string #acceptable type of variable
}


#4. Create a Subnet
resource "aws_subnet" "prod-subnet-1" {
  vpc_id     = aws_vpc.prod-vpc.id
  cidr_block = var.cidr_prefix[0]
  availability_zone = "us-east-1a"

  tags = {
    Name = "prod-subnet-1"
  }
}

#4. Create a Subnet
resource "aws_subnet" "dev-subnet-2" {
  vpc_id     = aws_vpc.prod-vpc.id
  cidr_block = var.cidr_prefix[1]
  availability_zone = "us-east-1a"

  tags = {
    Name = "dev-subnet-2"
  }
}

#5. Associate Subnet with Route table

resource "aws_route_table_association" "prod-route-association" {
  subnet_id      = aws_subnet.prod-subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

#6. Create a security group to allow ports 22,80,443

resource "aws_security_group" "prod-sg" {
  name        = "allow_web_traffic"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 20
    to_port     = 20
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
    Name = "Prod-SG"
  }
}

#7. Create a network interface with an IP in the subnet that was created in step 4 

resource "aws_network_interface" "prod-nic" {
  subnet_id       = aws_subnet.prod-subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.prod-sg.id]

}

#8. Assign an elastic IP to the network interface created in step 7

resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.prod-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.prod-gw]
}

#9. Create Ubuntu server and install nginx

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "prod-web-server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  availability_zone = "us-east-1a"
  key_name = "windhigh-key"
  network_interface {
    device_index = 0
    network_interface_id =  aws_network_interface.prod-nic.id
  }

  user_data = <<-EOF
               #!/bin/bash
               sudo apt update -y
               sudo apt upgrade -y
               sudo apt install nginx -y
               sudo systemctl start nginx
               sudo echo "Hello WOrld" > /var/www/html/index.html
               EOF

  tags = {
    Name = "Prod Web Server"
  }
}

#Gives output of public IP
output "server-public-ip" {
  value = aws_eip.one.public_ip
}

output "server-private-ip" {
  value = aws_eip.one.private_ip
}