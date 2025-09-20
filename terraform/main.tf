# Main Terraform configuration for GitHub Actions Repository Runner
# This configuration creates AWS infrastructure for a self-hosted GitHub Actions runner
# that registers with individual repositories (not organizations).
#
# Key Features:
# - Repository-level runner registration (requires 'repo' scope PAT)
# - Cost-optimized with automatic start/stop via GitHub Actions workflows
# - Secure access restricted to personal IP and GitHub IP ranges
# - Compatible with personal GitHub accounts and repositories
#
# This file contains the core configuration and provider setup



# Configure the AWS Provider
provider "aws" {
  region = var.region
  
  default_tags {
    tags = local.common_tags
  }
}