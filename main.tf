terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = var.region
}

# VPC
resource "aws_vpc" "vpc_main" {
  cidr_block = "10.0.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.prefix}-vpc"
    Team = var.team_tag_value
  }
}

# Subnets
resource "aws_subnet" "subnet_a" {
  vpc_id                  = aws_vpc.vpc_main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.prefix}-subnet-a"
    Team = var.team_tag_value
  }
}

resource "aws_subnet" "subnet_b" {
  vpc_id                  = aws_vpc.vpc_main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.prefix}-subnet-b"
    Team = var.team_tag_value
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc_main.id

  tags = {
    Name = "${var.prefix}-igw"
    Team = var.team_tag_value
  }
}

# Route Table
resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.vpc_main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.prefix}-rt"
    Team = var.team_tag_value
  }
}

resource "aws_route_table_association" "assoc_a" {
  route_table_id = aws_route_table.rt.id
  subnet_id      = aws_subnet.subnet_a.id
}

resource "aws_route_table_association" "assoc_b" {
  route_table_id = aws_route_table.rt.id
  subnet_id      = aws_subnet.subnet_b.id
}

# Security Group
resource "aws_security_group" "sg" {
  name   = "${var.prefix}-sg"
  vpc_id = aws_vpc.vpc_main.id

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # 혹시 제한하려면 여기를 수정
  }

  # HTTP
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Nginx Proxy Manager Admin Panel (Port 81)
  ingress {
    description = "NPM Admin Page"
    from_port   = 81
    to_port     = 81
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: 모든 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.prefix}-sg"
    Team = var.team_tag_value
  }
}


# IAM Role for EC2
resource "aws_iam_role" "ec2_role" {
  name = "${var.prefix}-ec2-role"

  assume_role_policy = <<EOF
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Effect":"Allow",
      "Principal":{"Service":"ec2.amazonaws.com"},
      "Action":"sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ssm_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "s3_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "${var.prefix}-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# USER DATA
locals {
  ec2_user_data = templatefile("${path.module}/user_data.tpl", {
    db_root_password       = var.db_root_password
    app_db_name            = var.app_db_name
    redis_password         = var.redis_password
    ghcr_owner             = var.ghcr_owner
    ghcr_token             = var.ghcr_token
    npm_admin_email        = var.npm_admin_email
    npm_admin_password     = var.npm_admin_password
    jwt_secret             = var.jwt_secret
    ai_openai_api_key      = var.ai_openai_api_key
    ai_huggingface_api_key = var.ai_huggingface_api_key
    pinecone_api_key       = var.pinecone_api_key
    pinecone_index_name    = var.pinecone_index_name
    gmail_sender_email     = var.gmail_sender_email
    gmail_sender_password  = var.gmail_sender_password
    unsplash_access_key    = var.unsplash_access_key
    google_api_key         = var.google_api_key
    google_cx_id           = var.google_cx_id
    kakao_client_id        = var.kakao_client_id
    naver_client_id        = var.naver_client_id
    naver_client_secret    = var.naver_client_secret
    google_client_id       = var.google_client_id
    google_client_secret   = var.google_client_secret
    s3_bucket_name         = var.s3_bucket_name
    app_domain             = var.app_domain
  })
}


# EC2 Instance
resource "aws_instance" "ec2" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.ec2_instance_type
  key_name               = var.ec2_key_name
  subnet_id              = aws_subnet.subnet_a.id
  vpc_security_group_ids = [aws_security_group.sg.id]

  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.instance_profile.name

  user_data = local.ec2_user_data

  root_block_device {
    volume_size = 40
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.prefix}-backend"
    Team = var.team_tag_value
  }
}

# Elastic IP
resource "aws_eip" "eip" {
  domain = "vpc"

  tags = {
    Name = "${var.prefix}-eip"
    Team = var.team_tag_value
  }
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.ec2.id
  allocation_id = aws_eip.eip.id
}

# S3 Bucket
resource "aws_s3_bucket" "app_bucket" {
  bucket = var.s3_bucket_name

  tags = {
    Name = "${var.prefix}-bucket"
    Team = var.team_tag_value
  }
}
