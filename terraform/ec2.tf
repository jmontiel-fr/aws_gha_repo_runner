# =============================================================================
# EC2 Instance Configuration - MOVED TO REPOSITORY-SPECIFIC MODULE
# =============================================================================
# 
# EC2 instances are now created per repository using the repository-runner module.
# This allows each repository to have its own dedicated, isolated runner instance.
#
# To create a repository-specific runner:
# ./scripts/create-repository-runner.sh --username johndoe --repository my-app --key-pair my-key
#
# The base infrastructure (VPC, subnets, security groups) is shared across all
# repository runners for cost efficiency, while each repository gets its own
# dedicated EC2 instance with parametrized naming: runner-{username}-{repository}
#
# This approach provides:
# - Complete isolation between repositories
# - Cost tracking per repository via tags
# - Scalable provisioning for multiple repositories
# - Automated lifecycle management

# Data source to get the latest Ubuntu 22.04 LTS AMI (used by repository modules)
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
