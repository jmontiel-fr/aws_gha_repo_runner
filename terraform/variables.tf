# =============================================================================
# AWS Configuration for GitHub Actions Repository Runner
# =============================================================================
# This configuration supports repository-level GitHub Actions runners for
# personal GitHub accounts. The infrastructure is designed to be cost-effective
# and secure while maintaining compatibility with existing setups.

variable "region" {
  description = "AWS region for repository runner deployment"
  type        = string
  default     = "eu-west-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region format (e.g., us-east-1, eu-west-1)."
  }
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid CIDR block."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "Public subnet CIDR must be a valid CIDR block."
  }
}

# =============================================================================
# Security Configuration
# =============================================================================
# Personal IP address for SSH access to the repository runner instance
variable "personal_ip" {
  description = "Personal IP address in CIDR format for SSH access to repository runner"
  type        = string
  
  validation {
    condition     = can(cidrhost(var.personal_ip, 0)) && can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", var.personal_ip))
    error_message = "Personal IP must be a valid CIDR block with proper IP format (e.g., 192.168.1.100/32). Find your IP at https://whatismyipaddress.com/"
  }
}

# =============================================================================
# Instance Configuration
# =============================================================================
# EC2 instance configuration for the repository runner
variable "instance_type" {
  description = "EC2 instance type for the GitHub Actions repository runner (t3.micro recommended for cost efficiency)"
  type        = string
  default     = "t3.micro"
}

variable "key_pair_name" {
  description = "Name of the AWS key pair for SSH access to repository runner instance"
  type        = string
}

# =============================================================================
# Tool Versions for Repository Runner
# =============================================================================
# These versions are installed on the EC2 instance to support various
# repository workflows. Update these based on your project requirements.
variable "docker_version" {
  description = "Docker version to install"
  type        = string
  default     = "24.0.7"
  
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.docker_version))
    error_message = "Docker version must be in semantic version format (e.g., 24.0.7)."
  }
}

variable "aws_cli_version" {
  description = "AWS CLI v2 version to install"
  type        = string
  default     = "2.15.17"
  
  validation {
    condition     = can(regex("^2\\.[0-9]+\\.[0-9]+$", var.aws_cli_version))
    error_message = "AWS CLI version must be v2.x.x format (e.g., 2.15.17)."
  }
}

variable "python_version" {
  description = "Python version to install"
  type        = string
  default     = "3.12"
  
  validation {
    condition     = can(regex("^3\\.[0-9]+$", var.python_version))
    error_message = "Python version must be 3.x format (e.g., 3.12)."
  }
}

variable "openjdk_version" {
  description = "OpenJDK version to install"
  type        = string
  default     = "17"
  
  validation {
    condition     = can(regex("^[0-9]+$", var.openjdk_version))
    error_message = "OpenJDK version must be a major version number (e.g., 17, 21)."
  }
}

variable "terraform_version" {
  description = "Terraform version to install"
  type        = string
  default     = "1.6.6"
  
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.terraform_version))
    error_message = "Terraform version must be in semantic version format (e.g., 1.6.6)."
  }
}

variable "kubectl_version" {
  description = "kubectl version to install"
  type        = string
  default     = "1.29.1"
  
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubectl_version))
    error_message = "kubectl version must be in semantic version format (e.g., 1.29.1)."
  }
}

variable "helm_version" {
  description = "Helm version to install"
  type        = string
  default     = "3.14.0"
  
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_version))
    error_message = "Helm version must be in semantic version format (e.g., 3.14.0)."
  }
}