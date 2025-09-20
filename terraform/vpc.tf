# =============================================================================
# VPC Configuration for GitHub Actions Repository Runner
# =============================================================================
# Creates a dedicated VPC for the repository runner infrastructure
# This provides network isolation and security for the runner instance
resource "aws_vpc" "gha_runner" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "gha-repository-runner-vpc"
  })
}

# Public subnet in the first availability zone
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.gha_runner.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = local.primary_az
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "gha-repository-runner-public-subnet"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "gha_runner" {
  vpc_id = aws_vpc.gha_runner.id

  tags = merge(local.common_tags, {
    Name = "gha-repository-runner-igw"
  })
}

# Route table for public subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.gha_runner.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gha_runner.id
  }

  tags = merge(local.common_tags, {
    Name = "gha-repository-runner-public-rt"
  })
}

# Associate route table with public subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
