# =============================================================================
# Outputs for GitHub Actions Repository Runner Integration
# =============================================================================
# These outputs are used by GitHub Actions workflows to manage the repository runner

# EC2 instance ID - Add this to your repository secrets as EC2_INSTANCE_ID
output "instance_id" {
  description = "ID of the EC2 instance for GitHub Actions repository runner (use in repository secrets)"
  value       = aws_instance.gha_runner.id
}

# Instance public IP for runner registration and SSH access
output "instance_public_ip" {
  description = "Public IP address of the repository runner EC2 instance"
  value       = aws_instance.gha_runner.public_ip
}

# Security group ID for reference
output "security_group_id" {
  description = "ID of the security group attached to the runner instance"
  value       = aws_security_group.gha_runner.id
}

# VPC ID for documentation
output "vpc_id" {
  description = "ID of the VPC containing the runner infrastructure"
  value       = aws_vpc.gha_runner.id
}

# Subnet ID for documentation
output "subnet_id" {
  description = "ID of the public subnet containing the runner instance"
  value       = aws_subnet.public.id
}