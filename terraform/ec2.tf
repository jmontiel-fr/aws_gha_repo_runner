# =============================================================================
# EC2 Instance Configuration for GitHub Actions Repository Runner
# =============================================================================
# This creates an EC2 instance that will be registered as a self-hosted runner
# with individual GitHub repositories (not organizations)

# Data source to get the latest Ubuntu 22.04 LTS AMI
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

# EC2 Instance for GitHub Actions Repository Runner
resource "aws_instance" "gha_runner" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name              = var.key_pair_name
  subnet_id             = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.gha_runner.id]
  
  # Assign public IP but don't use EIP for cost optimization
  # The runner will re-register with the repository on each startup
  associate_public_ip_address = true
  
  # User data script for tool installation
  user_data = templatefile("${path.module}/user_data.sh", {
    docker_version    = var.docker_version
    aws_cli_version   = var.aws_cli_version
    python_version    = var.python_version
    openjdk_version   = var.openjdk_version
    terraform_version = var.terraform_version
    kubectl_version   = var.kubectl_version
    helm_version      = var.helm_version
  })

  tags = merge(local.common_tags, {
    Name        = "gha-repository-runner"
    Purpose     = "GitHub Actions Repository Runner"
    Environment = "repository-level"
    Usage       = "Personal repositories with repo-scope PAT"
  })
}