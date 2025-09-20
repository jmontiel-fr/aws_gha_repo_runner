# =============================================================================
# Terraform Version Constraints and Required Providers
# =============================================================================
# This configuration is compatible with both organization and repository-level
# GitHub Actions runners. The provider versions are maintained for backward
# compatibility with existing infrastructure.
#
# Repository runner changes are limited to:
# - Runner registration scripts (not Terraform resources)
# - GitHub Actions workflows (not infrastructure)
# - Documentation and examples (not core configuration)

terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}