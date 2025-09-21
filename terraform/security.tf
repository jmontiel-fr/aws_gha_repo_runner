# =============================================================================
# Security Group Configuration for GitHub Actions Repository Runner
# =============================================================================
# This security group restricts access to the repository runner instance:
# - SSH access only from personal IP
# - HTTPS access only from GitHub IP ranges (for runner communication)
# - All outbound traffic allowed (for package downloads and GitHub API calls)
# GitHub IP ranges are dynamically fetched from locals.tf

# Security group for GitHub Actions repository runner
resource "aws_security_group" "gha_runner" {
  name_prefix = "gha-repo-runner-"
  description = "Security group for GitHub Actions repository runner EC2 instance"
  vpc_id      = aws_vpc.gha_runner.id

  # SSH access from personal IP only (for administration and debugging)
  ingress {
    description = "SSH access from personal IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.personal_ip]
  }

  # Note: GitHub Actions runners only need outbound HTTPS access to GitHub.
  # No inbound HTTPS is required as the runner initiates all connections.
  # Removing unnecessary inbound HTTPS rule for better security.

  # Outbound rules for all traffic (package downloads and GitHub communication)
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name    = "gha-repository-runner-sg"
    Purpose = "GitHub Actions Repository Runner Security"
  })
}