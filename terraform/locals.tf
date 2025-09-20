# =============================================================================
# Local Values and Computed Configurations for Repository Runner
# =============================================================================
# This file contains computed values and GitHub API integrations for the
# repository runner infrastructure

# Data source to fetch GitHub IP ranges from GitHub Meta API
data "http" "github_meta" {
  url = "https://api.github.com/meta"
  
  request_headers = {
    Accept = "application/vnd.github.v3+json"
  }
}

# Local values for computed configurations
locals {
  # Parse GitHub IP ranges from API response
  github_meta = jsondecode(data.http.github_meta.response_body)
  
  # GitHub IP ranges for Actions runners
  github_actions_ips = local.github_meta.actions
  
  # GitHub API IP ranges
  github_api_ips = local.github_meta.api
  
  # Combined GitHub IP ranges for security group rules
  github_all_ips = concat(
    local.github_actions_ips,
    local.github_api_ips
  )
  
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