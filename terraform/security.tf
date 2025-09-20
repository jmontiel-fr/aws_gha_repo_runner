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

  # SSH access from personal IP only
  ingress {
    description = "SSH access from personal IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.personal_ip]
  }

  # HTTPS inbound access from GitHub IP ranges
  dynamic "ingress" {
    for_each = local.github_all_ips
    content {
      description = "HTTPS from GitHub (${ingress.value})"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

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