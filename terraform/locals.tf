# =============================================================================
# Local Values and Computed Configurations for Repository Runner
# =============================================================================
# This file contains computed values and GitHub API integrations for the
# repository runner infrastructure

# Local values for computed configurations
locals {
  # Common tags for all repository runner resources
  common_tags = {
    Project     = "github-repository-runner"
    Environment = "repository-level"
    ManagedBy   = "terraform"
    Usage       = "Personal GitHub repositories"
  }
  
  # Availability zones for the region
  availability_zones = data.aws_availability_zones.available.names
  
  # First available AZ for subnet placement
  primary_az = local.availability_zones[0]
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}