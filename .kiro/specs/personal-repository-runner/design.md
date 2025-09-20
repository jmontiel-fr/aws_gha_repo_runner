# Design Document

## Overview

This design outlines the conversion of the existing organization-level GitHub Actions runner to work with personal GitHub account repositories. The solution creates dedicated EC2 instances for each repository runner with automated provisioning and parametrized naming. Each repository gets its own isolated infrastructure while maintaining cost-optimized runner capabilities and simplified permission requirements.

## Architecture

### Current Organization-Level Architecture
```
GitHub Organization
├── Multiple Repositories
├── Organization Runner API (admin:org scope)
├── Centralized Runner Management
└── Cross-Repository Access

AWS Infrastructure
├── EC2 Instance (t3.micro)
├── VPC and Security Groups
├── Organization-Level Runner Registration
└── Ephemeral Configuration
```

### New Repository-Level Architecture
```
Personal GitHub Account
├── Repository A
│   ├── Repository Runner API (repo scope)
│   ├── Dedicated EC2 Instance (runner-{username}-{repo-a})
│   └── Repository-Specific Configuration
├── Repository B
│   ├── Repository Runner API (repo scope)
│   ├── Dedicated EC2 Instance (runner-{username}-{repo-b})
│   └── Repository-Specific Configuration
└── Repository N...

AWS Infrastructure (Per Repository)
├── Dedicated EC2 Instance (t3.micro)
│   ├── Parametrized Name: runner-{username}-{repository}
│   ├── Repository-Specific Tags
│   └── Isolated Security Groups
├── VPC and Networking (Shared)
├── Repository-Level Runner Registration
└── Persistent Configuration
```

## Components and Interfaces

### 1. GitHub API Integration

#### Current Organization Endpoints
- `POST /orgs/{org}/actions/runners/registration-token`
- `GET /orgs/{org}/actions/runners`
- `DELETE /orgs/{org}/actions/runners/{runner_id}`

#### New Repository Endpoints
- `POST /repos/{owner}/{repo}/actions/runners/registration-token`
- `GET /repos/{owner}/{repo}/actions/runners`
- `DELETE /repos/{owner}/{repo}/actions/runners/{runner_id}`

#### Authentication Changes
- **Current**: GitHub PAT with `repo` + `admin:org` scopes
- **New**: GitHub PAT with `repo` scope only
- **Validation**: Repository admin permissions instead of organization admin

### 2. Configuration Management

#### Environment Variables
```bash
# Current Organization Variables
GITHUB_ORGANIZATION="org-name"
GH_PAT="token-with-admin-org-scope"

# New Repository Variables  
GITHUB_USERNAME="username"
GITHUB_REPOSITORY="repo-name"
GH_PAT="token-with-repo-scope"
```

#### Runner Configuration
```bash
# Current Organization URL
--url https://github.com/{organization}

# New Repository URL
--url https://github.com/{username}/{repository}
```

### 3. Script Modifications

#### Repository Runner Setup Script
- **File**: `scripts/repo-runner-setup.sh`
- **Purpose**: Replace organization-specific logic with repository-specific logic
- **Key Changes**:
  - Repository URL format validation
  - Repository-level API endpoint usage
  - Simplified permission validation
  - Repository existence verification

#### Workflow Integration Scripts
- **Start Runner**: Register with specific repository
- **Stop Runner**: Unregister from specific repository
- **Status Check**: Query repository runners

### 4. EC2 Instance Provisioning

#### Automated Instance Creation
The system automatically provisions dedicated EC2 instances for each repository runner using Terraform modules and parametrized naming.

#### Instance Naming Convention
```bash
# Instance Name Pattern
runner-{github-username}-{repository-name}

# Examples
runner-johndoe-my-web-app
runner-johndoe-api-service
runner-johndoe-mobile-app
```

#### Instance Configuration
```hcl
# Terraform Module for Repository Runner Instance
module "repository_runner" {
  source = "./modules/repository-runner"
  
  # Repository Information
  github_username   = var.github_username
  repository_name   = var.repository_name
  
  # Instance Configuration
  instance_type     = var.instance_type     # Default: t3.micro
  ami_id           = var.ami_id            # Ubuntu 22.04 LTS
  key_pair_name    = var.key_pair_name
  
  # Networking
  vpc_id           = var.vpc_id
  subnet_id        = var.subnet_id
  security_groups  = var.security_groups
  
  # Tags
  tags = {
    Name                = "runner-${var.github_username}-${var.repository_name}"
    Purpose            = "GitHub Actions Runner"
    Repository         = "${var.github_username}/${var.repository_name}"
    Environment        = var.environment
    CostCenter         = var.cost_center
    AutoShutdown       = "true"
    ManagedBy          = "terraform"
  }
}
```

#### Instance Lifecycle Management
```bash
# Create Instance for Repository
./scripts/create-repository-runner.sh \
  --username "johndoe" \
  --repository "my-app" \
  --instance-type "t3.micro" \
  --region "us-east-1"

# Configure Runner on Instance
./scripts/configure-repository-runner.sh \
  --username "johndoe" \
  --repository "my-app" \
  --pat "ghp_xxxxxxxxxxxxxxxxxxxx"

# Destroy Instance and Cleanup
./scripts/destroy-repository-runner.sh \
  --username "johndoe" \
  --repository "my-app"
```

### 5. GitHub Actions Workflows

#### Repository Setup Requirements

**Step 1: Configure Repository Secrets**
Navigate to your repository Settings → Secrets and variables → Actions and add:

```yaml
# Required Repository Secrets
AWS_ACCESS_KEY_ID: "AKIA..."           # AWS access key for EC2 management
AWS_SECRET_ACCESS_KEY: "wJal..."       # AWS secret access key
AWS_REGION: "us-east-1"                # AWS region for EC2 deployment
GH_PAT: "ghp_..."                      # GitHub PAT with 'repo' scope only
GITHUB_USERNAME: "johndoe"             # GitHub username for instance naming
REPOSITORY_NAME: "my-app"              # Repository name for instance naming
RUNNER_NAME: "gha_aws_runner"          # Name for the GitHub runner
INSTANCE_TYPE: "t3.micro"              # EC2 instance type (optional, default: t3.micro)
KEY_PAIR_NAME: "my-runner-key"         # AWS key pair for SSH access
```

**Step 2: Create Workflow Files**

Create `.github/workflows/runner-demo.yml`:
```yaml
name: Repository Self-Hosted Runner Demo
on: 
  workflow_dispatch:
    inputs:
      job_type:
        description: 'Type of job to run'
        required: true
        default: 'build'
        type: choice
        options:
        - build
        - test
        - deploy
      provision_instance:
        description: 'Create new EC2 instance if needed'
        required: false
        default: false
        type: boolean

jobs:
  provision-runner:
    name: Provision dedicated EC2 runner instance
    runs-on: ubuntu-latest
    if: ${{ github.event.inputs.provision_instance == 'true' }}
    outputs:
      instance-id: ${{ steps.provision.outputs.instance-id }}
      instance-ip: ${{ steps.provision.outputs.instance-ip }}
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Provision EC2 instance for repository
        id: provision
        run: |
          # Generate instance name
          INSTANCE_NAME="runner-${{ secrets.GITHUB_USERNAME }}-${{ secrets.REPOSITORY_NAME }}"
          echo "Provisioning instance: $INSTANCE_NAME"
          
          # Check if instance already exists
          EXISTING_INSTANCE=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running,stopped" \
            --query 'Reservations[0].Instances[0].InstanceId' \
            --output text 2>/dev/null || echo "None")
          
          if [ "$EXISTING_INSTANCE" != "None" ] && [ "$EXISTING_INSTANCE" != "null" ]; then
            echo "Instance already exists: $EXISTING_INSTANCE"
            INSTANCE_ID="$EXISTING_INSTANCE"
          else
            # Create new instance using Terraform
            cd terraform/modules/repository-runner
            
            terraform init
            terraform apply -auto-approve \
              -var="github_username=${{ secrets.GITHUB_USERNAME }}" \
              -var="repository_name=${{ secrets.REPOSITORY_NAME }}" \
              -var="instance_type=${{ secrets.INSTANCE_TYPE || 't3.micro' }}" \
              -var="key_pair_name=${{ secrets.KEY_PAIR_NAME }}" \
              -var="aws_region=${{ secrets.AWS_REGION }}"
            
            INSTANCE_ID=$(terraform output -raw instance_id)
            echo "Created new instance: $INSTANCE_ID"
          fi
          
          # Wait for instance to be running
          aws ec2 start-instances --instance-ids $INSTANCE_ID || true
          aws ec2 wait instance-running --instance-ids $INSTANCE_ID
          
          # Get instance IP
          INSTANCE_IP=$(aws ec2 describe-instances \
            --instance-ids $INSTANCE_ID \
            --query 'Reservations[0].Instances[0].PublicIpAddress' \
            --output text)
          
          echo "instance-id=$INSTANCE_ID" >> $GITHUB_OUTPUT
          echo "instance-ip=$INSTANCE_IP" >> $GITHUB_OUTPUT

  start-runner:
    name: Start self-hosted EC2 runner
    runs-on: ubuntu-latest
    needs: [provision-runner]
    if: always() && !failure()
    outputs:
      runner-name: ${{ steps.start.outputs.runner-name }}
      instance-id: ${{ steps.get-instance.outputs.instance-id }}
    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Get or use existing instance
        id: get-instance
        run: |
          if [ "${{ needs.provision-runner.outputs.instance-id }}" != "" ]; then
            # Use newly provisioned instance
            INSTANCE_ID="${{ needs.provision-runner.outputs.instance-id }}"
            INSTANCE_IP="${{ needs.provision-runner.outputs.instance-ip }}"
          else
            # Find existing instance by name
            INSTANCE_NAME="runner-${{ secrets.GITHUB_USERNAME }}-${{ secrets.REPOSITORY_NAME }}"
            INSTANCE_ID=$(aws ec2 describe-instances \
              --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running,stopped" \
              --query 'Reservations[0].Instances[0].InstanceId' \
              --output text)
            
            if [ "$INSTANCE_ID" = "None" ] || [ "$INSTANCE_ID" = "null" ]; then
              echo "No instance found. Please run with provision_instance=true first."
              exit 1
            fi
            
            # Start instance if stopped
            aws ec2 start-instances --instance-ids $INSTANCE_ID || true
            aws ec2 wait instance-running --instance-ids $INSTANCE_ID
            
            # Get instance IP
            INSTANCE_IP=$(aws ec2 describe-instances \
              --instance-ids $INSTANCE_ID \
              --query 'Reservations[0].Instances[0].PublicIpAddress' \
              --output text)
          fi
          
          echo "instance-id=$INSTANCE_ID" >> $GITHUB_OUTPUT
          echo "instance-ip=$INSTANCE_IP" >> $GITHUB_OUTPUT

      - name: Generate registration token
        id: token
        run: |
          TOKEN=$(curl -s -X POST \
            -H "Authorization: token ${{ secrets.GH_PAT }}" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/${{ github.repository }}/actions/runners/registration-token" | \
            jq -r '.token')
          echo "registration-token=$TOKEN" >> $GITHUB_OUTPUT

      - name: Register runner with repository
        run: |
          # Wait for instance to be ready
          sleep 30
          
          # SSH and configure runner
          ssh -o StrictHostKeyChecking=no -i ~/.ssh/${{ secrets.KEY_PAIR_NAME }}.pem ubuntu@${{ steps.get-instance.outputs.instance-ip }} << 'EOF'
            # Install GitHub Actions runner if not present
            if [ ! -d ~/actions-runner ]; then
              mkdir -p ~/actions-runner && cd ~/actions-runner
              
              # Download latest runner
              RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
              curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
                https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
              
              tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
              sudo ./bin/installdependencies.sh
            fi
            
            cd ~/actions-runner
            
            # Remove existing configuration if present
            sudo ./svc.sh stop || true
            sudo ./svc.sh uninstall || true
            sudo -u ubuntu ./config.sh remove --token ${{ steps.token.outputs.registration-token }} || true
            
            # Configure new runner
            sudo -u ubuntu ./config.sh \
              --url https://github.com/${{ github.repository }} \
              --token ${{ steps.token.outputs.registration-token }} \
              --name ${{ secrets.RUNNER_NAME }} \
              --labels gha_aws_runner \
              --work _work \
              --unattended \
              --replace
            
            # Install and start service
            sudo ./svc.sh install ubuntu
            sudo ./svc.sh start
          EOF

      - name: Set runner name output
        id: start
        run: echo "runner-name=${{ secrets.RUNNER_NAME }}" >> $GITHUB_OUTPUT

  your-job:
    name: Run job on self-hosted runner
    needs: start-runner
    runs-on: [self-hosted, gha_aws_runner]
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Show runner environment
        run: |
          echo "=== Runner Environment ==="
          echo "Runner name: ${{ needs.start-runner.outputs.runner-name }}"
          echo "Repository: ${{ github.repository }}"
          echo "Workflow: ${{ github.workflow }}"
          echo "Job type: ${{ github.event.inputs.job_type }}"
          echo ""
          echo "=== System Information ==="
          uname -a
          echo ""
          echo "=== Available Tools ==="
          docker --version
          aws --version
          python3 --version
          java -version
          terraform --version
          kubectl version --client
          helm version

      - name: Run job based on input
        run: |
          case "${{ github.event.inputs.job_type }}" in
            "build")
              echo "Running build job..."
              # Add your build commands here
              ;;
            "test")
              echo "Running test job..."
              # Add your test commands here
              ;;
            "deploy")
              echo "Running deploy job..."
              # Add your deploy commands here
              ;;
          esac

  stop-runner:
    name: Stop self-hosted EC2 runner
    needs: [start-runner, your-job]
    runs-on: ubuntu-latest
    if: always()
    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Unregister runner from repository
        run: |
          # Get runner ID
          RUNNER_ID=$(curl -s \
            -H "Authorization: token ${{ secrets.GH_PAT }}" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/${{ github.repository }}/actions/runners" | \
            jq -r ".runners[] | select(.name==\"${{ secrets.RUNNER_NAME }}\") | .id")
          
          if [ "$RUNNER_ID" != "null" ] && [ -n "$RUNNER_ID" ]; then
            echo "Unregistering runner ID: $RUNNER_ID"
            curl -X DELETE \
              -H "Authorization: token ${{ secrets.GH_PAT }}" \
              -H "Accept: application/vnd.github.v3+json" \
              "https://api.github.com/repos/${{ github.repository }}/actions/runners/$RUNNER_ID"
          else
            echo "Runner not found or already unregistered"
          fi

      - name: Stop EC2 instance
        run: |
          INSTANCE_ID="${{ needs.start-runner.outputs.instance-id }}"
          if [ -n "$INSTANCE_ID" ]; then
            aws ec2 stop-instances --instance-ids $INSTANCE_ID
            echo "EC2 instance stopped: $INSTANCE_ID"
          else
            echo "No instance ID available to stop"
          fi
```

**Step 3: Create Manual Runner Configuration Workflow**

Create `.github/workflows/configure-runner.yml`:
```yaml
name: Configure Repository Runner
on:
  workflow_dispatch:
    inputs:
      action:
        description: 'Runner action'
        required: true
        default: 'configure'
        type: choice
        options:
        - configure
        - remove
        - status

jobs:
  manage-runner:
    runs-on: ubuntu-latest
    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Get EC2 instance status
        id: ec2-status
        run: |
          STATUS=$(aws ec2 describe-instances \
            --instance-ids ${{ secrets.EC2_INSTANCE_ID }} \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text)
          echo "status=$STATUS" >> $GITHUB_OUTPUT
          echo "EC2 instance status: $STATUS"

      - name: Start EC2 if needed
        if: steps.ec2-status.outputs.status != 'running'
        run: |
          echo "Starting EC2 instance..."
          aws ec2 start-instances --instance-ids ${{ secrets.EC2_INSTANCE_ID }}
          aws ec2 wait instance-running --instance-ids ${{ secrets.EC2_INSTANCE_ID }}

      - name: Configure runner
        if: github.event.inputs.action == 'configure'
        run: |
          # Generate registration token
          TOKEN=$(curl -s -X POST \
            -H "Authorization: token ${{ secrets.GH_PAT }}" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/${{ github.repository }}/actions/runners/registration-token" | \
            jq -r '.token')
          
          # Get instance IP
          INSTANCE_IP=$(aws ec2 describe-instances \
            --instance-ids ${{ secrets.EC2_INSTANCE_ID }} \
            --query 'Reservations[0].Instances[0].PublicIpAddress' \
            --output text)
          
          echo "Configuring runner on $INSTANCE_IP for repository ${{ github.repository }}"
          
          # Configure runner via SSH
          ssh -o StrictHostKeyChecking=no ubuntu@$INSTANCE_IP << EOF
            cd ~/actions-runner
            
            # Stop existing service
            sudo ./svc.sh stop || true
            sudo ./svc.sh uninstall || true
            
            # Remove existing configuration
            sudo -u ubuntu ./config.sh remove --token $TOKEN || true
            
            # Configure new runner
            sudo -u ubuntu ./config.sh \
              --url https://github.com/${{ github.repository }} \
              --token $TOKEN \
              --name ${{ secrets.RUNNER_NAME }} \
              --labels gha_aws_runner \
              --work _work \
              --unattended \
              --replace
            
            # Install and start service
            sudo ./svc.sh install ubuntu
            sudo ./svc.sh start
            
            echo "Runner configured successfully for ${{ github.repository }}"
          EOF

      - name: Remove runner
        if: github.event.inputs.action == 'remove'
        run: |
          # Get runner ID and remove
          RUNNER_ID=$(curl -s \
            -H "Authorization: token ${{ secrets.GH_PAT }}" \
            "https://api.github.com/repos/${{ github.repository }}/actions/runners" | \
            jq -r ".runners[] | select(.name==\"${{ secrets.RUNNER_NAME }}\") | .id")
          
          if [ "$RUNNER_ID" != "null" ] && [ -n "$RUNNER_ID" ]; then
            curl -X DELETE \
              -H "Authorization: token ${{ secrets.GH_PAT }}" \
              "https://api.github.com/repos/${{ github.repository }}/actions/runners/$RUNNER_ID"
            echo "Runner removed from repository"
          fi

      - name: Show runner status
        if: github.event.inputs.action == 'status'
        run: |
          echo "=== Repository Runners ==="
          curl -s \
            -H "Authorization: token ${{ secrets.GH_PAT }}" \
            "https://api.github.com/repos/${{ github.repository }}/actions/runners" | \
            jq -r '.runners[] | "Name: \(.name), Status: \(.status), Labels: \([.labels[].name] | join(","))"'
```

## Terraform Module for Repository Runner

### Module Structure
```
terraform/
├── modules/
│   └── repository-runner/
│       ├── main.tf              # EC2 instance and security group
│       ├── variables.tf         # Input variables
│       ├── outputs.tf           # Instance ID and IP outputs
│       ├── user-data.sh         # Instance initialization script
│       └── README.md            # Module documentation
├── environments/
│   ├── dev/
│   ├── staging/
│   └── prod/
└── main.tf                      # Root module
```

### Module Variables
```hcl
variable "github_username" {
  description = "GitHub username for instance naming"
  type        = string
}

variable "repository_name" {
  description = "Repository name for instance naming"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "key_pair_name" {
  description = "AWS key pair name for SSH access"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the instance"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the instance"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}
```

### Module Outputs
```hcl
output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.runner.id
}

output "instance_ip" {
  description = "EC2 instance public IP"
  value       = aws_instance.runner.public_ip
}

output "instance_name" {
  description = "EC2 instance name"
  value       = local.instance_name
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.runner.id
}
```

### Instance User Data Script
```bash
#!/bin/bash
# user-data.sh - Initialize GitHub Actions runner instance

set -e

# Update system
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y \
  curl \
  jq \
  git \
  docker.io \
  awscli \
  unzip

# Configure Docker
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Install additional tools
# Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
apt-get install -y nodejs

# Python
apt-get install -y python3 python3-pip

# Create actions-runner directory
mkdir -p /home/ubuntu/actions-runner
chown ubuntu:ubuntu /home/ubuntu/actions-runner

# Download and extract GitHub Actions runner
cd /home/ubuntu/actions-runner
RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
  https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
chown -R ubuntu:ubuntu /home/ubuntu/actions-runner

# Install runner dependencies
sudo -u ubuntu ./bin/installdependencies.sh

# Create systemd service template
cat > /etc/systemd/system/actions-runner.service << 'EOF'
[Unit]
Description=GitHub Actions Runner
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/actions-runner
ExecStart=/home/ubuntu/actions-runner/run.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

echo "GitHub Actions runner instance initialized successfully"
```

## Data Models

### Repository Configuration
```json
{
  "github": {
    "username": "string",
    "repository": "string", 
    "pat": "string (repo scope)",
    "api_base": "https://api.github.com"
  },
  "runner": {
    "name": "string",
    "labels": ["self-hosted", "gha_aws_runner"],
    "work_directory": "_work",
    "ephemeral": false
  },
  "aws": {
    "instance_id": "string",
    "region": "string",
    "access_key_id": "string",
    "secret_access_key": "string"
  }
}
```

### GitHub Secrets Structure
```yaml
# Repository Secrets (Settings → Secrets and variables → Actions)
AWS_ACCESS_KEY_ID: "AKIA..."
AWS_SECRET_ACCESS_KEY: "wJal..."
AWS_REGION: "eu-west-1"
GH_PAT: "ghp_..." # repo scope only
EC2_INSTANCE_ID: "i-1234567890abcdef0"
RUNNER_NAME: "gha_aws_runner"
GITHUB_USERNAME: "your-username"
GITHUB_REPOSITORY: "your-repo-name"
```

## Error Handling

### Permission Validation
```bash
# Repository Access Check
validate_repository_access() {
    local response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GH_PAT" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY")
    
    local http_code="${response: -3}"
    
    case $http_code in
        200) return 0 ;;
        404) log_error "Repository not found or no access" ;;
        403) log_error "Insufficient permissions - need repo admin access" ;;
        *) log_error "API error: HTTP $http_code" ;;
    esac
    
    return 1
}
```

### Repository Existence Validation
```bash
# Repository Existence Check
check_repository_exists() {
    local repo_info=$(curl -s \
        -H "Authorization: token $GH_PAT" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY")
    
    local repo_name=$(echo "$repo_info" | jq -r '.name')
    local repo_private=$(echo "$repo_info" | jq -r '.private')
    
    if [ "$repo_name" = "null" ]; then
        log_error "Repository $GITHUB_USERNAME/$GITHUB_REPOSITORY not found"
        return 1
    fi
    
    log_info "Repository found: $repo_name (private: $repo_private)"
    return 0
}
```

### Runner Registration Error Handling
```bash
# Registration Token Generation with Error Handling
generate_registration_token() {
    local response=$(curl -s -w "%{http_code}" -X POST \
        -H "Authorization: token $GH_PAT" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners/registration-token")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    case $http_code in
        201)
            local token=$(echo "$body" | jq -r '.token')
            echo "$token"
            return 0
            ;;
        403)
            log_error "Insufficient permissions - ensure PAT has repo scope and you have admin access"
            return 1
            ;;
        404)
            log_error "Repository not found or Actions not enabled"
            return 1
            ;;
        *)
            log_error "Failed to generate token: HTTP $http_code"
            log_error "Response: $body"
            return 1
            ;;
    esac
}
```

## Testing Strategy

### Unit Tests
1. **API Endpoint Validation**
   - Test repository URL format validation
   - Test GitHub API response handling
   - Test error condition handling

2. **Configuration Validation**
   - Test environment variable parsing
   - Test repository parameter validation
   - Test PAT scope verification

### Integration Tests
1. **End-to-End Runner Setup**
   - Test complete runner registration process
   - Test runner configuration with real repository
   - Test runner unregistration and cleanup

2. **Workflow Integration**
   - Test GitHub Actions workflow execution
   - Test runner start/stop automation
   - Test job execution on repository runner

### Manual Testing Scenarios
1. **Repository Access Scenarios**
   - Public repository with repo scope PAT
   - Private repository with repo scope PAT
   - Repository without admin permissions
   - Non-existent repository

2. **Migration Scenarios**
   - Convert existing organization runner to repository runner
   - Switch runner between different repositories
   - Handle conflicts during migration

## Migration Strategy

### Phase 1: Preparation
1. Backup existing organization runner configuration
2. Document current environment variables and secrets
3. Prepare new repository-specific configuration

### Phase 2: Script Updates
1. Create new repository runner setup script
2. Update GitHub Actions workflows
3. Modify documentation and examples

### Phase 3: Configuration Migration
1. Update GitHub secrets with repository-specific values
2. Reconfigure runner with repository endpoints
3. Test runner functionality with new configuration

### Phase 4: Validation
1. Run test workflows to validate functionality
2. Verify runner appears in repository settings
3. Confirm cost optimization features still work

## Security Considerations

### Reduced Permission Requirements
- **Benefit**: No longer requires organization admin permissions
- **Risk**: Repository admin permissions still required
- **Mitigation**: Clear documentation on required permissions

### Repository Isolation
- **Benefit**: Runner only accessible to specific repository
- **Risk**: Less flexibility for multi-repository workflows
- **Mitigation**: Document how to switch repositories when needed

### PAT Scope Reduction
- **Benefit**: Reduced attack surface with repo-only scope
- **Risk**: Cannot manage organization-level resources
- **Mitigation**: This is the intended behavior for repository-level usage

## Performance Considerations

### Single Repository Focus
- **Impact**: Runner dedicated to one repository at a time
- **Benefit**: No cross-repository job queuing issues
- **Trade-off**: Less efficient resource utilization compared to organization-level

### Registration Overhead
- **Impact**: Need to re-register when switching repositories
- **Mitigation**: Provide scripts for easy repository switching
- **Optimization**: Cache registration tokens when possible

## Repository Configuration Guide

### Quick Setup Checklist

1. **Deploy AWS Infrastructure** (if not already done)
   ```bash
   cd terraform
   terraform init
   terraform apply
   ```

2. **Configure Repository Secrets**
   - Go to your repository Settings → Secrets and variables → Actions
   - Add all required secrets listed in the workflow section above

3. **Add Workflow Files**
   - Copy the workflow files to `.github/workflows/` in your repository
   - Commit and push the changes

4. **Configure Runner**
   - Go to Actions tab in your repository
   - Run "Configure Repository Runner" workflow
   - Select "configure" action

5. **Test Runner**
   - Run "Repository Self-Hosted Runner Demo" workflow
   - Verify the runner appears in Settings → Actions → Runners

### Troubleshooting Common Issues

#### Runner Not Appearing in Repository
```bash
# Check if runner is registered
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$USERNAME/$REPO/actions/runners"

# Check EC2 instance status
aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID

# SSH to instance and check runner service
ssh ubuntu@$INSTANCE_IP
cd ~/actions-runner
sudo ./svc.sh status
```

#### Permission Errors
- Ensure GitHub PAT has `repo` scope
- Verify you have admin permissions on the repository
- Check that Actions are enabled in repository settings

#### Workflow Failures
- Verify all repository secrets are configured correctly
- Check EC2 instance is in running state
- Ensure security groups allow SSH access from GitHub Actions

## Monitoring and Maintenance

### Repository Runner Status
```bash
# Check repository runners
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners"
```

### Health Monitoring
- Monitor runner status in repository Settings → Actions → Runners
- Track job execution success rates in Actions tab
- Monitor AWS costs and usage patterns in AWS console
- Set up alerts for runner registration failures

### Maintenance Tasks
- Rotate GitHub PAT regularly (recommended: every 90 days)
- Update runner version when new releases available
- Monitor and update tool versions on EC2 instance
- Review and update security group rules as needed
- Test runner functionality monthly with demo workflow