# =============================================================================
# Outputs for Repository Runner Base Infrastructure
# =============================================================================
# These outputs provide shared infrastructure details for repository-specific runners

# VPC ID - Used by repository-specific runner modules
output "vpc_id" {
  description = "ID of the VPC for repository runners (used by repository-runner module)"
  value       = aws_vpc.gha_runner.id
}

# Subnet ID - Used by repository-specific runner modules
output "subnet_id" {
  description = "ID of the public subnet for repository runners (used by repository-runner module)"
  value       = aws_subnet.public.id
}

# Security group ID - Can be referenced by repository-specific runners
output "base_security_group_id" {
  description = "ID of the base security group (repository runners create their own)"
  value       = aws_security_group.gha_runner.id
}

# Latest Ubuntu AMI ID - Used by repository-specific runner modules
output "ubuntu_ami_id" {
  description = "ID of the latest Ubuntu 22.04 LTS AMI (used by repository-runner module)"
  value       = data.aws_ami.ubuntu.id
}

# Region information
output "aws_region" {
  description = "AWS region where infrastructure is deployed"
  value       = var.region
}

# Instructions for creating repository-specific runners
output "next_steps" {
  description = "Instructions for creating repository-specific runners"
  value       = <<-EOT
    Base infrastructure created successfully!
    
    To create repository-specific runners:
    
    1. Create a runner for your repository:
       ./scripts/create-repository-runner.sh \
         --username YOUR_GITHUB_USERNAME \
         --repository YOUR_REPO_NAME \
         --key-pair ${var.key_pair_name}
    
    2. Configure the runner:
       ./scripts/configure-repository-runner.sh \
         --username YOUR_GITHUB_USERNAME \
         --repository YOUR_REPO_NAME \
         --instance-id INSTANCE_ID_FROM_STEP_1 \
         --pat YOUR_GITHUB_PAT
    
    Each repository will get its own dedicated EC2 instance with the naming pattern:
    runner-{username}-{repository}
    
    Shared Infrastructure:
    - VPC ID: ${aws_vpc.gha_runner.id}
    - Subnet ID: ${aws_subnet.public.id}
    - Region: ${var.region}
  EOT
}
