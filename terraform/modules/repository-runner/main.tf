# Repository-Specific GitHub Actions Runner EC2 Instance
# This module creates a dedicated EC2 instance for each repository runner
# with parametrized naming and proper tagging for cost tracking.

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Local values for consistent naming and tagging
locals {
  instance_name = "runner-${var.github_username}-${var.repository_name}"
  
  common_tags = {
    Name                = local.instance_name
    Purpose            = "GitHub Actions Runner"
    Repository         = "${var.github_username}/${var.repository_name}"
    GitHubUsername     = var.github_username
    RepositoryName     = var.repository_name
    Environment        = var.environment
    ManagedBy          = "terraform"
    AutoShutdown       = "true"
    CostCenter         = var.cost_center
    CreatedBy          = "repository-runner-module"
    CreatedAt          = timestamp()
  }
}

# Data sources
data "aws_vpc" "selected" {
  count = var.vpc_id != "" ? 1 : 0
  id    = var.vpc_id
}

data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

data "aws_subnets" "available" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id]
  }
  
  filter {
    name   = "availability-zone"
    values = [data.aws_availability_zones.available.names[0]]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Get the latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group for the runner instance
resource "aws_security_group" "runner" {
  name_prefix = "${local.instance_name}-"
  description = "Security group for GitHub Actions runner ${local.instance_name}"
  vpc_id      = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id

  # SSH access (restrict to your IP or VPN)
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr_blocks
  }

  # Outbound internet access (required for GitHub Actions)
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.instance_name}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# EC2 Instance for the GitHub Actions runner
resource "aws_instance" "runner" {
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name              = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.runner.id]
  subnet_id             = var.subnet_id != "" ? var.subnet_id : data.aws_subnets.available.ids[0]
  
  # Enable detailed monitoring for better cost tracking
  monitoring = var.enable_detailed_monitoring

  # Instance metadata options for security
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # Root volume configuration
  root_block_device {
    volume_type           = var.root_volume_type
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = merge(local.common_tags, {
      Name = "${local.instance_name}-root-volume"
    })
  }

  # User data script for initial setup
  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    github_username   = var.github_username
    repository_name   = var.repository_name
    runner_version    = var.runner_version
    additional_tools  = var.additional_tools
  }))

  tags = local.common_tags

  # Prevent accidental termination in production
  disable_api_termination = var.environment == "prod" ? true : false

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      # Ignore changes to user_data to prevent unnecessary instance replacement
      user_data,
      # Ignore AMI changes unless explicitly updated
      ami,
    ]
  }
}

# Elastic IP (optional, for static IP requirements)
resource "aws_eip" "runner" {
  count    = var.allocate_elastic_ip ? 1 : 0
  instance = aws_instance.runner.id
  domain   = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.instance_name}-eip"
  })

  depends_on = [aws_instance.runner]
}

# CloudWatch Log Group for runner logs (optional)
resource "aws_cloudwatch_log_group" "runner" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/ec2/${local.instance_name}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# IAM role for the EC2 instance (optional, for AWS service access)
resource "aws_iam_role" "runner" {
  count = var.create_iam_role ? 1 : 0
  name  = "${local.instance_name}-role"

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

  tags = local.common_tags
}

# IAM instance profile
resource "aws_iam_instance_profile" "runner" {
  count = var.create_iam_role ? 1 : 0
  name  = "${local.instance_name}-profile"
  role  = aws_iam_role.runner[0].name

  tags = local.common_tags
}

# Attach IAM policies to the role
resource "aws_iam_role_policy_attachment" "runner_policies" {
  count      = var.create_iam_role ? length(var.iam_policy_arns) : 0
  role       = aws_iam_role.runner[0].name
  policy_arn = var.iam_policy_arns[count.index]
}

# Auto Scaling Group for automatic recovery (optional)
resource "aws_launch_template" "runner" {
  count       = var.enable_auto_recovery ? 1 : 0
  name_prefix = "${local.instance_name}-"
  
  image_id      = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_pair_name
  
  vpc_security_group_ids = [aws_security_group.runner.id]
  
  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    github_username   = var.github_username
    repository_name   = var.repository_name
    runner_version    = var.runner_version
    additional_tools  = var.additional_tools
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = local.common_tags
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "runner" {
  count               = var.enable_auto_recovery ? 1 : 0
  name                = "${local.instance_name}-asg"
  vpc_zone_identifier = [var.subnet_id != "" ? var.subnet_id : data.aws_subnets.available.ids[0]]
  
  min_size         = 0
  max_size         = 1
  desired_capacity = var.auto_recovery_desired_capacity
  
  launch_template {
    id      = aws_launch_template.runner[0].id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.instance_name}-asg"
    propagate_at_launch = false
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}