terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
}

provider "aws" {
  default_tags {
    tags = {
      ManagedBy = "terraform"
      Project   = "comfyui-hunyuan3d"
    }
  }
}

# ============================================================
# Data sources
# ============================================================

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["137112412989"] # AWS

  filter {
    name   = "name"
    values = [var.ami_name]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Running instances launched by the ASG (for outputs)
data "aws_instances" "comfyui" {
  instance_state_names = ["running"]

  filter {
    name   = "tag:Name"
    values = ["comfyui-hunyuan3d"]
  }
}

# ============================================================
# VPC
# ============================================================

resource "aws_vpc" "comfyui" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "comfyui-vpc"
  }
}

# ============================================================
# Internet Gateway
# ============================================================

resource "aws_internet_gateway" "comfyui" {
  vpc_id = aws_vpc.comfyui.id

  tags = {
    Name = "comfyui-igw"
  }
}

# ============================================================
# Subnet
# ============================================================

resource "aws_subnet" "comfyui" {
  vpc_id                  = aws_vpc.comfyui.id
  cidr_block              = var.subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "comfyui-subnet"
  }
}

# ============================================================
# Route Table
# ============================================================

resource "aws_route_table" "comfyui" {
  vpc_id = aws_vpc.comfyui.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.comfyui.id
  }

  tags = {
    Name = "comfyui-rt"
  }
}

resource "aws_route_table_association" "comfyui" {
  subnet_id      = aws_subnet.comfyui.id
  route_table_id = aws_route_table.comfyui.id
}

# ============================================================
# Security Group
# ============================================================

resource "aws_security_group" "comfyui" {
  name        = "comfyui-hunyuan3d"
  description = "Allow SSH and ComfyUI access"
  vpc_id      = aws_vpc.comfyui.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ComfyUI web interface"
    from_port   = var.comfyui_port
    to_port     = var.comfyui_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "comfyui-sg"
  }
}

# ============================================================
# Auto Scaling Group (launch template + ASG)
# ============================================================

resource "aws_launch_template" "comfyui" {
  name          = "comfyui-hunyuan3d"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.comfyui.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.comfyui.id]
  }

  # EBS root volume
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = var.ebs_volume_size_gb
      volume_type = "gp3"
      encrypted   = true
    }
  }

  # Additional volume when using Spot (kept for parity with prior config)
  dynamic "block_device_mappings" {
    for_each = var.use_spot ? [1] : []
    content {
      device_name = "/dev/sdf"
      ebs {
        volume_size = 100
        volume_type = "gp3"
      }
    }
  }

  # User data script
  user_data = base64encode(templatefile("${path.module}/userdata.sh.tftpl", {
    hf_token      = var.hf_token
    model_version = var.model_version
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "comfyui-hunyuan3d"
    }
  }

  # Prevent Terraform from churning instances on user_data change
  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "aws_autoscaling_group" "comfyui" {
  name                = "comfyui-hunyuan3d"
  vpc_zone_identifier = [aws_subnet.comfyui.id]
  desired_capacity    = 1
  min_size            = 1
  max_size            = 1

  launch_template {
    id      = aws_launch_template.comfyui.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "comfyui-hunyuan3d"
    propagate_at_launch = true
  }
}

# ============================================================
# IAM Role for EC2
# ============================================================

resource "aws_iam_role" "comfyui" {
  name = "comfyui-hunyuan3d"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "comfyui-iam-role"
  }
}

resource "aws_iam_instance_profile" "comfyui" {
  name = "comfyui-hunyuan3d"
  role = aws_iam_role.comfyui.name
}

# S3 read/write access to the models bucket for the instance profile
resource "aws_iam_role_policy" "s3_models" {
  name = "s3-models-read-write"
  role = aws_iam_role.comfyui.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListModelsBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${var.s3_models_bucket}"
      },
      {
        Sid    = "ReadWriteModelObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${var.s3_models_bucket}/*"
      }
    ]
  })
}
