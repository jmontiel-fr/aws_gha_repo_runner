# Repository-Specific GitHub Actions Runner Module Variables

# Required Variables
variable "github_username" {
  description = "GitHub username for instance naming and tagging"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$", var.github_username))
    error_message = "GitHub username must contain only alphanumeric characters and hyphens, and cannot begin or end with a hyphen."
  }
}

variable "repository_name" {
  description = "Repository name for instance naming and tagging"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.repository_name))
    error_message = "Repository name can only contain alphanumeric characters, hyphens, underscores, and periods."
  }
}

variable "key_pair_name" {
  description = "AWS key pair name for SSH access to the instance"
  type        = string
}

# Instance Configuration
variable "instance_type" {
  description = "EC2 instance type for the runner"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition = contains([
      "t3.nano", "t3.micro", "t3.small", "t3.medium", "t3.large",
      "t3a.nano", "t3a.micro", "t3a.small", "t3a.medium", "t3a.large",
      "t4g.nano", "t4g.micro", "t4g.small", "t4g.medium", "t4g.large",
      "m5.large", "m5.xlarge", "m5.2xlarge",
      "c5.large", "c5.xlarge", "c5.2xlarge"
    ], var.instance_type)
    error_message = "Instance type must be a supported type for GitHub Actions runners."
  }
}

variable "ami_id" {
  description = "AMI ID for the instance (leave empty to use latest Ubuntu 22.04 LTS)"
  type        = string
  default     = ""
}

# Networking Configuration
variable "vpc_id" {
  description = "VPC ID for the instance (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet ID for the instance (leave empty to use first available subnet)"
  type        = string
  default     = ""
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Restrict this in production
}

# Storage Configuration
variable "root_volume_type" {
  description = "Root volume type"
  type        = string
  default     = "gp3"
  
  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.root_volume_type)
    error_message = "Root volume type must be one of: gp2, gp3, io1, io2."
  }
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 20
  
  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 100
    error_message = "Root volume size must be between 8 and 100 GB."
  }
}

# Environment and Tagging
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "cost_center" {
  description = "Cost center for billing and cost tracking"
  type        = string
  default     = "github-actions"
}

# Runner Configuration
variable "runner_version" {
  description = "GitHub Actions runner version (leave empty for latest)"
  type        = string
  default     = ""
}

variable "additional_tools" {
  description = "List of additional tools to install on the runner"
  type        = list(string)
  default     = []
}

# Optional Features
variable "allocate_elastic_ip" {
  description = "Whether to allocate an Elastic IP for the instance"
  type        = bool
  default     = false
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = false
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for the runner"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# IAM Configuration
variable "create_iam_role" {
  description = "Whether to create an IAM role for the instance"
  type        = bool
  default     = false
}

variable "iam_policy_arns" {
  description = "List of IAM policy ARNs to attach to the instance role"
  type        = list(string)
  default     = []
}

# Auto Recovery Configuration
variable "enable_auto_recovery" {
  description = "Enable auto recovery using Auto Scaling Group"
  type        = bool
  default     = false
}

variable "auto_recovery_desired_capacity" {
  description = "Desired capacity for auto recovery (0 or 1)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.auto_recovery_desired_capacity >= 0 && var.auto_recovery_desired_capacity <= 1
    error_message = "Auto recovery desired capacity must be 0 or 1."
  }
}

# Advanced Configuration
variable "user_data_script" {
  description = "Custom user data script (overrides default if provided)"
  type        = string
  default     = ""
}

variable "additional_security_group_ids" {
  description = "Additional security group IDs to attach to the instance"
  type        = list(string)
  default     = []
}

variable "enable_termination_protection" {
  description = "Enable termination protection for the instance"
  type        = bool
  default     = false
}