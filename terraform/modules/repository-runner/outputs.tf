# Repository-Specific GitHub Actions Runner Module Outputs

# Instance Information
output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.runner.id
}

output "instance_arn" {
  description = "EC2 instance ARN"
  value       = aws_instance.runner.arn
}

output "instance_name" {
  description = "EC2 instance name"
  value       = local.instance_name
}

output "instance_type" {
  description = "EC2 instance type"
  value       = aws_instance.runner.instance_type
}

output "instance_state" {
  description = "EC2 instance state"
  value       = aws_instance.runner.instance_state
}

# Network Information
output "instance_public_ip" {
  description = "EC2 instance public IP address"
  value       = aws_instance.runner.public_ip
}

output "instance_private_ip" {
  description = "EC2 instance private IP address"
  value       = aws_instance.runner.private_ip
}

output "instance_public_dns" {
  description = "EC2 instance public DNS name"
  value       = aws_instance.runner.public_dns
}

output "instance_private_dns" {
  description = "EC2 instance private DNS name"
  value       = aws_instance.runner.private_dns
}

output "elastic_ip" {
  description = "Elastic IP address (if allocated)"
  value       = var.allocate_elastic_ip ? aws_eip.runner[0].public_ip : null
}

# Security Information
output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.runner.id
}

output "security_group_arn" {
  description = "Security group ARN"
  value       = aws_security_group.runner.arn
}

output "key_pair_name" {
  description = "Key pair name used for the instance"
  value       = var.key_pair_name
}

# Repository Information
output "github_username" {
  description = "GitHub username"
  value       = var.github_username
}

output "repository_name" {
  description = "Repository name"
  value       = var.repository_name
}

output "repository_full_name" {
  description = "Full repository name (username/repository)"
  value       = "${var.github_username}/${var.repository_name}"
}

# IAM Information (if created)
output "iam_role_arn" {
  description = "IAM role ARN (if created)"
  value       = var.create_iam_role ? aws_iam_role.runner[0].arn : null
}

output "iam_role_name" {
  description = "IAM role name (if created)"
  value       = var.create_iam_role ? aws_iam_role.runner[0].name : null
}

output "iam_instance_profile_arn" {
  description = "IAM instance profile ARN (if created)"
  value       = var.create_iam_role ? aws_iam_instance_profile.runner[0].arn : null
}

# CloudWatch Information (if enabled)
output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name (if enabled)"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.runner[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch log group ARN (if enabled)"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.runner[0].arn : null
}

# Auto Scaling Information (if enabled)
output "autoscaling_group_name" {
  description = "Auto Scaling Group name (if enabled)"
  value       = var.enable_auto_recovery ? aws_autoscaling_group.runner[0].name : null
}

output "autoscaling_group_arn" {
  description = "Auto Scaling Group ARN (if enabled)"
  value       = var.enable_auto_recovery ? aws_autoscaling_group.runner[0].arn : null
}

output "launch_template_id" {
  description = "Launch template ID (if auto recovery enabled)"
  value       = var.enable_auto_recovery ? aws_launch_template.runner[0].id : null
}

# Connection Information
output "ssh_connection_command" {
  description = "SSH connection command"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ubuntu@${aws_instance.runner.public_ip}"
}

output "runner_url" {
  description = "GitHub repository URL for runner registration"
  value       = "https://github.com/${var.github_username}/${var.repository_name}"
}

# Cost Tracking Information
output "cost_center" {
  description = "Cost center for billing"
  value       = var.cost_center
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# Tags
output "instance_tags" {
  description = "Instance tags"
  value       = aws_instance.runner.tags
}

# Availability Zone
output "availability_zone" {
  description = "Availability zone of the instance"
  value       = aws_instance.runner.availability_zone
}

# Subnet Information
output "subnet_id" {
  description = "Subnet ID where the instance is deployed"
  value       = aws_instance.runner.subnet_id
}

output "vpc_id" {
  description = "VPC ID where the instance is deployed"
  value       = aws_security_group.runner.vpc_id
}

# AMI Information
output "ami_id" {
  description = "AMI ID used for the instance"
  value       = aws_instance.runner.ami
}

# Volume Information
output "root_volume_id" {
  description = "Root volume ID"
  value       = aws_instance.runner.root_block_device[0].volume_id
}

output "root_volume_size" {
  description = "Root volume size in GB"
  value       = aws_instance.runner.root_block_device[0].volume_size
}

output "root_volume_type" {
  description = "Root volume type"
  value       = aws_instance.runner.root_block_device[0].volume_type
}