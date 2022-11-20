terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

locals {
  hostname = ""
}

provider "aws" {
  region = "eu-west-1"
}

resource "aws_vpc" "exercise-vpc" {
  cidr_block           = "10.0.1.0/24"
  enable_dns_hostnames = true

  tags = {
    "Name" = "exercise-vpc"
  }
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.exercise-vpc.id

  tags = {
    Name = "exercise-vpc-gw"
  }
}

resource "aws_subnet" "vpc-app-subnet-1" {
  vpc_id                  = aws_vpc.exercise-vpc.id
  cidr_block              = "10.0.1.0/28"
  map_public_ip_on_launch = true
  availability_zone       = "eu-west-1a"

  tags = {
    Name = "App-Subnet-1"
  }
}

#
resource "aws_subnet" "vpc-app-subnet-2" {
  vpc_id                  = aws_vpc.exercise-vpc.id
  cidr_block              = "10.0.1.32/28"
  map_public_ip_on_launch = true
  availability_zone       = "eu-west-1b"

  tags = {
    Name = "App-Subnet-2"
  }
}

resource "aws_route_table" "exercise-vpc-rtable" {
  vpc_id = aws_vpc.exercise-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "exercise-rta-app-subnet-1" {
  subnet_id      = aws_subnet.vpc-app-subnet-1.id
  route_table_id = aws_route_table.exercise-vpc-rtable.id
}

resource "aws_route_table_association" "exercise-rta-app-subnet-2" {
  subnet_id      = aws_subnet.vpc-app-subnet-2.id
  route_table_id = aws_route_table.exercise-vpc-rtable.id
}


resource "aws_security_group" "app_traffic" {
  name   = "Allow HTTP To Apps"
  vpc_id = aws_vpc.exercise-vpc.id

  ingress {
    description = "Allow HTTP traffic to App1+2"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH traffic to App1+2"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS traffic to App1+2"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all traffic from App1+2"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "icmp_app_traffic" {
  name   = "Allow ICMP To Apps"
  vpc_id = aws_vpc.exercise-vpc.id

  ingress {
    description = "Allow ICMPs traffic to App1+2"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all traffic from App1+2"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app1_test" {
  ami                    = "ami-0ee415e1b8b71305f"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.vpc-app-subnet-1.id
  vpc_security_group_ids = [aws_security_group.app_traffic.id, aws_security_group.icmp_app_traffic.id]
  user_data              = file("InstallNginX.sh")

  tags = {
    Name        = "AlexandraLeyzerzon"
    Environment = "exercise"
  }
}

resource "aws_instance" "app2_test" {
  ami                    = "ami-0ee415e1b8b71305f"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.vpc-app-subnet-2.id
  vpc_security_group_ids = [aws_security_group.app_traffic.id, aws_security_group.icmp_app_traffic.id]
  user_data              = file("InstallNginX.sh")

  tags = {
    Name        = "AlexandraLeyzerzon"
    Environment = "exercise"
  }
}

resource "aws_eip" "app1_t_EIP" {
  instance = aws_instance.app1_test.id
  vpc      = true
}

resource "aws_eip" "app2_t_EIP" {
  instance = aws_instance.app2_test.id
  vpc      = true
}

output "EIP1" {
  value = aws_eip.app1_t_EIP.public_ip
}

output "EIP2" {
  value = aws_eip.app2_t_EIP.public_ip
}

# Creating a TG for the load balancer
resource "aws_lb_target_group" "lb-target-group" {
  name     = "app-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.exercise-vpc.id
}

# Attaching App1 to the TG
resource "aws_lb_target_group_attachment" "tg_attachment_app1" {
  target_group_arn = aws_lb_target_group.lb-target-group.arn
  target_id        = aws_instance.app1_test.id
  port             = 80
}

# Attaching App2 to the TG
resource "aws_lb_target_group_attachment" "tg_attachment_app2" {
  target_group_arn = aws_lb_target_group.lb-target-group.arn
  target_id        = aws_instance.app2_test.id
  port             = 80
}

# Creating a new Application Load Balancer
resource "aws_lb" "app_http_lb" {
  name               = "app-HTTP-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.app_traffic.id]
  subnets            = [aws_subnet.vpc-app-subnet-1.id, aws_subnet.vpc-app-subnet-2.id]

  #enable_deletion_protection = true

  tags = {
    Environment = "production"
  }
}

# Creating a listener for Load Balancer
resource "aws_lb_listener" "alb_http_listener" {
  load_balancer_arn = aws_lb.app_http_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lb-target-group.arn
  }
}