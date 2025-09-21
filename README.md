# Personal Repository GitHub Actions Runner on AWS

A scalable, repository-specific GitHub Actions runner infrastructure deployed on AWS using Terraform. This solution automatically provisions dedicated EC2 instances for each repository with parametrized naming and comprehensive management. **Each repository gets its own isolated EC2 instance with automated provisioning, providing complete separation and security while maintaining cost optimization.**

## 🚀 Features

- **Dedicated EC2 Per Repository**: Each repository gets its own isolated EC2 instance
- **Automated Provisioning**: Terraform modules automatically create instances with parametrized naming
- **Instance Naming**: Consistent naming convention: `runner-{username}-{repository}`
- **Complete Isolation**: No cross-repository access or data leakage
- **Simplified Permissions**: Requires only `repo` scope GitHub PAT, no organization admin needed
- **Cost Tracking**: Comprehensive tagging for precise cost allocation per repository
- **Fast Startup**: Pre-configured instances with all tools installed, ready in ~2 minutes
- **Scalable**: Easy provisioning of runners for multiple repositories
- **Pre-installed Tools**: Docker, AWS CLI, Python, Node.js, Java 17, Terraform, kubectl, Helm, Git
- **Secure**: Restricted network access and encrypted storage
- **Automated Management**: Complete lifecycle management via scripts and workflows

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           Personal GitHub Account                               │
│                                                                                 │
│  ┌─────────────────────────┐  ┌─────────────────────────┐  ┌─────────────────┐ │
│  │ Repository A            │  │ Repository B            │  │ Repository N... │ │
│  │ (username/web-app)      │  │ (username/api-service)  │  │ (username/...)  │ │
│  └─────────────────────────┘  └─────────────────────────┘  └─────────────────┘ │
│              │                             │                         │         │
└──────────────┼─────────────────────────────┼─────────────────────────┼─────────┘
               │                             │                         │
               ▼                             ▼                         ▼
┌──────────────────────────────────────────────────────────────────────────────────┐
│                                AWS Infrastructure                                 │
│                                                                                  │
│  ┌─────────────────────────┐  ┌─────────────────────────┐  ┌─────────────────┐  │
│  │ EC2: runner-username-   │  │ EC2: runner-username-   │  │ EC2: runner-    │  │
│  │      web-app            │  │      api-service        │  │      ...        │  │
│  │ ┌─────────────────────┐ │  │ ┌─────────────────────┐ │  │ ┌─────────────┐ │  │
│  │ │ Ubuntu 22.04 LTS    │ │  │ │ Ubuntu 22.04 LTS    │ │  │ │ Ubuntu 22.04│ │  │
│  │ │ Docker, AWS CLI     │ │  │ │ Docker, AWS CLI     │ │  │ │ Docker, AWS │ │  │
│  │ │ Python, Node.js     │ │  │ │ Python, Node.js     │ │  │ │ Python, Node│ │  │
│  │ │ Java, Terraform     │ │  │ │ Java, Terraform     │ │  │ │ Java, Terraform │ │  │
│  │ │ kubectl, Helm       │ │  │ │ kubectl, Helm       │ │  │ │ kubectl, Helm   │ │  │
│  │ │ GitHub Actions      │ │  │ │ GitHub Actions      │ │  │ │ GitHub      │ │  │
│  │ │ Runner              │ │  │ │ Runner              │ │  │ │ Actions     │ │  │
│  │ └─────────────────────┘ │  │ └─────────────────────┘ │  │ └─────────────┘ │  │
│  └─────────────────────────┘  └─────────────────────────┘  └─────────────────┘  │
│                                                                                  │
│  ┌──────────────────────────────────────────────────────────────────────────┐  │
│  │                        Shared VPC & Networking                           │  │
│  │  - Security Groups (per instance)                                       │  │
│  │  - SSH access control                                                   │  │
│  │  - GitHub API access                                                    │  │
│  └──────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────┐
│ Developer       │──────────────────────────────────────────────────────────────────
│ (SSH Access)    │    SSH to any instance for debugging and management
└─────────────────┘
```

## 🚀 Quick Start

**TL;DR - Get a runner up in 5 minutes:**

1. **Clone and setup base infrastructure:**
   ```bash
   git clone <repo-url> && cd aws-gha-repo-runner
   cd terraform && cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your IP (key pair auto-created)
   terraform init && terraform apply
   ```

2. **Create EC2 instance for your repository:**
   ```bash
   ./scripts/create-repository-runner.sh \
     --username YOUR_GITHUB_USERNAME \
     --repository YOUR_REPO_NAME \
     --key-pair YOUR_KEY_PAIR \
     --region eu-west-1
   ```

3. **Register runner with GitHub:**
   ```bash
   ./scripts/configure-repository-runner.sh \
     --username YOUR_GITHUB_USERNAME \
     --repository YOUR_REPO_NAME \
     --instance-id i-xxxxxxxxxxxxx \
     --pat YOUR_GITHUB_PAT
   ```

4. **Add minimal secrets to your target repository:**
   - Only 5 variables needed: AWS credentials, region, GitHub PAT, key pair
   - Username and repository name are auto-derived from GitHub context

5. **Use in workflows:**
   ```yaml
   jobs:
     build:
       runs-on: [self-hosted, gha_aws_runner]
   ```

## 📋 Prerequisites

### AWS Requirements
- AWS CLI configured with appropriate credentials
- AWS account with permissions to create VPC, EC2, Key Pairs, and Security Group resources
- ✨ **Key pairs are auto-created** by the script (no manual setup needed)

### GitHub Requirements  
- Personal GitHub account with repository admin permissions
- GitHub Personal Access Token (PAT) with `repo` scope only
- Admin permissions on the target repository for runner registration
- Repository secrets configured (see Configuration section)

### Local Requirements
- Terraform >= 1.6.0
- Git

## 🛠️ Installation

### 1. Clone Repository
```bash
git clone <repository-url>
cd aws-gha-repo-runner
```

### 2. Set Up Base Infrastructure (One-time)
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your base configuration:
```hcl
# Network Configuration (shared across all repository runners)
personal_ip        = "YOUR_PUBLIC_IP/32"  # Get from: curl ifconfig.me
vpc_cidr          = "10.0.0.0/16"
public_subnet_cidr = "10.0.1.0/24"

# Default Configuration
default_instance_type = "t3.micro"
key_pair_name        = "your-existing-key-pair"
aws_region          = "us-east-1"
```

### 3. Deploy Base Infrastructure (One-time Setup)
```bash
# Initialize Terraform
terraform init

# Deploy shared infrastructure (VPC, networking, security groups)
terraform plan
terraform apply
```

**Important:** This creates the shared infrastructure (VPC, subnets, security groups) but **does not create any EC2 instances**. Each repository will get its own dedicated EC2 instance created in the next step.

### 4. Create Repository-Specific Runners

For each repository that needs a dedicated runner:

```bash
# Create dedicated EC2 instance for a repository
./scripts/create-repository-runner.sh \
  --username your-github-username \
  --repository your-repo-name \
  --key-pair your-key-pair-name \
  --instance-type t3.micro \
  --region us-east-1

# Example: Create runner for web application
./scripts/create-repository-runner.sh \
  --username johndoe \
  --repository my-web-app \
  --key-pair my-runner-key

# Example: Create runner for API service with monitoring
./scripts/create-repository-runner.sh \
  --username johndoe \
  --repository api-service \
  --key-pair my-runner-key \
  --instance-type t3.small \
  --enable-monitoring \
  --enable-logs
```

**Instance Naming:** Each repository gets an instance named `runner-{username}-{repository}`
- `runner-johndoe-my-web-app`
- `runner-johndoe-api-service`
- `runner-johndoe-mobile-app`

**Architecture Clarification:**
- **Base Terraform** (`terraform apply`) = Shared infrastructure (VPC, networking)
- **Repository Scripts** (`create-repository-runner.sh`) = Individual EC2 instances per repository

### 5. Configure Repository Secrets

⚠️ **IMPORTANT**: These secrets and variables must be configured in **each individual repository** where you want to use the self-hosted runner, **NOT** in this infrastructure repository.

For **each target repository** that will use a dedicated runner, add these variables (Settings → Secrets and variables → Actions):

## Required Variables (Minimum Setup)

| Variable Name           | Type        | Description                                         | Example                                    |
| ----------------------- | ----------- | --------------------------------------------------- | ------------------------------------------ |
| `AWS_ACCESS_KEY_ID`     | **Secret**  | AWS access key for EC2 management                   | `AKIAIOSFODNN7EXAMPLE`                     |
| `AWS_SECRET_ACCESS_KEY` | **Secret**  | AWS secret access key                               | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `AWS_REGION`            | Variable    | AWS region where infrastructure is deployed         | `us-east-1`                                |
| `GH_PAT`                | **Secret**  | GitHub Personal Access Token with `repo` scope only | `ghp_xxxxxxxxxxxxxxxxxxxx`                 |
| `KEY_PAIR_NAME`         | Variable    | AWS EC2 Key Pair name (must exist in your AWS region) | `gha-runner-key-pair`                      |

## Optional Variables (Auto-derived if not set)

| Variable Name           | Type        | Description                                         | Auto-derived Value                         |
| ----------------------- | ----------- | --------------------------------------------------- | ------------------------------------------ |
| `GH_USERNAME`           | Variable    | Your GitHub username                                | `${{ github.repository_owner }}`           |
| `REPOSITORY_NAME`       | Variable    | This repository's name                              | `${{ github.event.repository.name }}`      |
| `RUNNER_NAME`           | Variable    | GitHub runner name                                  | `runner-${{ github.repository_owner }}-${{ github.event.repository.name }}` |
| `INSTANCE_TYPE`         | Variable    | EC2 instance type                                   | `t3.micro` (default)                       |

## Why So Many Variables? 🤔

**The Reality**: You only need **5 required variables** per repository. The rest can be auto-derived!

**Why Each Variable is Needed:**
- **AWS Credentials** (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`): To manage EC2 instances
- **AWS Region** (`AWS_REGION`): To know which region to create/manage instances
- **GitHub PAT** (`GH_PAT`): To register/unregister runners with GitHub
- **Key Pair** (`KEY_PAIR_NAME`): To enable SSH access to instances

**Auto-Derived Variables** (GitHub provides these automatically):
- **Username**: `${{ github.repository_owner }}` (e.g., "johndoe")
- **Repository**: `${{ github.event.repository.name }}` (e.g., "my-web-app")
- **Runner Name**: Automatically constructed as `runner-{username}-{repository}`

**Minimal Setup**: Only set the 5 required variables, let GitHub auto-derive the rest!

**Variable Types:**
- **Secrets** (🔒): Sensitive data that is encrypted and masked in logs (AWS keys, GitHub PAT)
- **Variables** (📝): Non-sensitive configuration data that can be visible in logs (regions, key pairs)

**How to Add Variables:**
1. Go to your repository → **Settings** → **Secrets and variables** → **Actions**
2. **For Secrets**: Click **"New repository secret"** tab
3. **For Variables**: Click **"Variables"** tab → **"New repository variable"**

**Repository-Specific Configuration:**
- **Each target repository** needs its own complete set of variables and secrets
- The `REPOSITORY_NAME` variable should match the actual repository name where you're adding these secrets
- The `RUNNER_NAME` should follow the pattern: `runner-{GH_USERNAME}-{REPOSITORY_NAME}` (same as instance name)
- Instance will be automatically named: `runner-{GH_USERNAME}-{REPOSITORY_NAME}`

**Minimal Setup Example:**
```
Repository: johndoe/my-web-app
├── Settings → Secrets and variables → Actions
    ├── Secrets: 
    │   ├── AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
    │   ├── AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
    │   └── GH_PAT=ghp_xxxxxxxxxxxxxxxxxxxx
    └── Variables: 
        ├── AWS_REGION=us-east-1
        └── KEY_PAIR_NAME=gha-runner-key-pair
        
    # Auto-derived (no need to set):
    # - GH_USERNAME = johndoe (from github.repository_owner)
    # - REPOSITORY_NAME = my-web-app (from github.event.repository.name)
    # - RUNNER_NAME = runner-johndoe-my-web-app (auto-constructed)

Repository: johndoe/my-api-service  
├── Settings → Secrets and variables → Actions
    ├── Secrets: (same 3 secrets as above)
    └── Variables: (same 2 variables as above)
    
    # Auto-derived (different per repo):
    # - REPOSITORY_NAME = my-api-service
    # - RUNNER_NAME = runner-johndoe-my-api-service
```

**Result**: Only **5 variables** per repository instead of 9! 🎉

**Key Points:**
- 🏗️ **Infrastructure repo** (`aws-gha-repo-runner`): Only needs `terraform.tfvars` configuration
- 🎯 **Target repositories**: Each needs only **5 minimal variables** (not 9!)
- 🔄 **Same AWS credentials**: Can be reused across all target repositories
- 🤖 **Auto-derived values**: Username and repository name come from GitHub context
- 🔑 **KEY_PAIR_NAME**: Must be an existing EC2 Key Pair in your AWS region (created beforehand)
- ✨ **Simplified setup**: Less configuration, fewer errors, easier maintenance

**About KEY_PAIR_NAME:**
- **Auto-created**: If the key pair doesn't exist, the script will create it automatically
- **Saved locally**: Private key is automatically saved to `~/.ssh/{KEY_PAIR_NAME}.pem`
- **Same key pair** can be used across all repositories for consistency
- **Proper permissions**: Script automatically sets `chmod 400` on the private key file
- **No manual setup needed**: Just specify the name, script handles the rest!

### 6. Register Runner with GitHub

After creating the EC2 instance, you need to register it as a GitHub Actions runner for your repository:

```bash
# Configure the runner for your repository
./scripts/configure-repository-runner.sh \
  --username johndoe \
  --repository my-web-app \
  --instance-id i-1234567890abcdef0 \
  --pat ghp_xxxxxxxxxxxxxxxxxxxx

# The runner will be registered as: runner-johndoe-my-web-app
```

**What this step does:**
1. **Connects to your EC2 instance** via SSH
2. **Downloads GitHub Actions runner software** to the instance
3. **Generates a registration token** from GitHub API using your PAT
4. **Registers the runner** with your specific repository
5. **Configures the runner service** to start automatically
6. **Labels the runner** with `self-hosted` and `gha_aws_runner` tags

**After successful registration:**
- Your runner will appear in GitHub → Repository → Settings → Actions → Runners
- The runner status will show as "Idle" and ready to accept jobs
- You can now use `runs-on: [self-hosted, gha_aws_runner]` in your workflows

### 7. Verify Runner Registration

Check that your runner is properly registered:

**In GitHub Web Interface:**
1. Go to your repository on GitHub
2. Navigate to **Settings** → **Actions** → **Runners**
3. You should see your runner listed as: `runner-{username}-{repository}`
4. Status should show as **"Idle"** (green dot)

**Via Command Line:**
```bash
# Check runner status via GitHub API
curl -H "Authorization: token YOUR_GITHUB_PAT" \
  "https://api.github.com/repos/johndoe/my-web-app/actions/runners"

# SSH to instance and check runner service
ssh -i ~/.ssh/gha-runner-key-pair.pem ubuntu@54.229.40.93
sudo systemctl status actions.runner.*
```

**Test with a Simple Workflow:**
Create `.github/workflows/test-runner.yml`:
```yaml
name: Test Self-Hosted Runner
on: workflow_dispatch

jobs:
  test:
    runs-on: [self-hosted, gha_aws_runner]
    steps:
      - name: Test runner
        run: |
          echo "Running on: $(hostname)"
          echo "Instance: runner-${{ github.repository_owner }}-${{ github.event.repository.name }}"
          docker --version
          aws --version
```

## 🎯 Usage

### Automated Repository Workflow (Recommended)

Use the provided example workflow in `.github/workflows/runner-demo-minimal.yml`. This workflow uses **minimal variables** and auto-derives repository information from GitHub context:

```yaml
name: Repository Self-Hosted Runner Demo
on: 
  workflow_dispatch:
    inputs:
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
    steps:
      - name: Provision EC2 instance for repository
        run: |
          # Creates instance: runner-${{ github.repository_owner }}-${{ github.event.repository.name }}
          
  start-runner:
    runs-on: ubuntu-latest
    needs: [provision-runner]
    if: always() && !failure()
    outputs:
      runner-name: ${{ steps.start.outputs.runner-name }}
    steps:
      - name: Start dedicated repository runner
        # Starts the dedicated instance and registers repository runner
        
  your-job:
    needs: start-runner  
    runs-on: [self-hosted, gha_aws_runner]
    steps:
      - name: Your workflow steps here
        run: |
          echo "Running on dedicated AWS runner for ${{ github.repository }}"
          echo "Instance: runner-${{ github.repository_owner }}-${{ github.event.repository.name }}"
          docker --version
          aws --version

# ✨ Benefits of Minimal Variables Approach:
# - Only 5 secrets/variables to configure per repository
# - Username and repository name auto-derived from GitHub context
# - Less configuration, fewer errors
# - Consistent naming across all repositories
          
  stop-runner:
    needs: [start-runner, your-job]
    runs-on: ubuntu-latest
    if: always()
    steps:
      - name: Stop dedicated repository runner
        # Stops the dedicated instance for cost optimization
```

### Manual Runner Setup

For manual runner installation, see [docs/github-runner-setup.md](docs/github-runner-setup.md).

### Using Dedicated Runners in Your Workflows

Each repository uses its own dedicated runner with the `gha_aws_runner` label:

#### Example Web Application Workflow:
```yaml
# Repository: johndoe/my-web-app
# Uses instance: runner-johndoe-my-web-app
jobs:
  build:
    runs-on: [self-hosted, gha_aws_runner]
    steps:
      - uses: actions/checkout@v4
      - name: Build frontend with Docker
        run: |
          echo "Building on dedicated runner: runner-johndoe-my-web-app"
          docker build -t my-web-app .
      - name: Deploy with Terraform
        run: terraform apply -auto-approve
```

#### Example API Service Workflow:
```yaml
# Repository: johndoe/api-service  
# Uses instance: runner-johndoe-api-service
jobs:
  test:
    runs-on: [self-hosted, gha_aws_runner]
    steps:
      - uses: actions/checkout@v4
      - name: Run API tests
        run: |
          echo "Testing on dedicated runner: runner-johndoe-api-service"
          python -m pytest
          docker build -t api-service .
```

#### Example Mobile App Workflow:
```yaml
# Repository: johndoe/mobile-app
# Uses instance: runner-johndoe-mobile-app
jobs:
  build:
    runs-on: [self-hosted, gha_aws_runner]
    steps:
      - uses: actions/checkout@v4
      - name: Build mobile app
        run: |
          echo "Building on dedicated runner: runner-johndoe-mobile-app"
          # Mobile-specific build commands
```

### Multiple Repository Management

```bash
# Create runners for multiple repositories
./scripts/create-repository-runner.sh --username johndoe --repository web-app --key-pair gha-runner-key-pair
./scripts/create-repository-runner.sh --username johndoe --repository api-service --key-pair gha-runner-key-pair  
./scripts/create-repository-runner.sh --username johndoe --repository mobile-app --key-pair gha-runner-key-pair

# Results in:
# - runner-johndoe-web-app
# - runner-johndoe-api-service  
# - runner-johndoe-mobile-app

# Each repository gets complete isolation and dedicated resources
```

**Dedicated Runner Benefits:**
- **Complete Isolation**: No cross-repository contamination or access
- **Cost Tracking**: Precise cost allocation per repository via tagging
- **Custom Configuration**: Each repository can have different instance types and tools
- **Security**: No shared state or credentials between repositories
- **Scalability**: Easy to add/remove runners for different projects

## 🏗️ Managing Your Runners

### List All Repository Runners

```bash
# List all repository runners
aws ec2 describe-instances \
  --filters "Name=tag:Purpose,Values=GitHub Actions Runner" \
  --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name]' \
  --output table

# Start specific repository runner
aws ec2 start-instances --instance-ids i-1234567890abcdef0

# Stop specific repository runner  
aws ec2 stop-instances --instance-ids i-1234567890abcdef0

# Get runner status for repository
./scripts/health-check-runner.sh \
  --username johndoe \
  --repository my-web-app
```

### Cleaning Up Repository Runners

```bash
# Destroy repository runner and all resources
./scripts/destroy-repository-runner.sh \
  --username johndoe \
  --repository my-web-app \
  --force

# Dry run to see what would be destroyed
./scripts/destroy-repository-runner.sh \
  --username johndoe \
  --repository api-service \
  --dry-run
```

## 💰 Cost Optimization Features

### Per-Repository Cost Tracking
- **Comprehensive Tagging**: Each instance tagged with repository information
- **Cost Allocation**: Precise cost tracking per repository via AWS Cost Explorer
- **Budget Control**: Set up AWS budgets per repository or project

### Instance Optimization
- **Default t3.micro**: Eligible for AWS Free Tier (750 hours/month)
- **Configurable Sizing**: Upgrade to t3.small/medium for resource-intensive repositories
- **Burstable Performance**: T3 instances provide CPU credits for occasional high usage
- **GP3 Storage**: Cost-optimized storage with better price/performance than GP2

### Auto-Shutdown Features
- **Auto-Shutdown Tags**: Instances tagged for automated shutdown scripts
- **Start/Stop Workflows**: Instances stopped when not in use
- **No Elastic IPs**: Uses dynamic IPs to avoid EIP charges ($0.005/hour)

### Multi-Repository Cost Examples (us-east-1)

#### Single Repository (Light Usage)
```
Repository: johndoe/web-app
Instance: runner-johndoe-web-app (t3.micro)
Usage: 2 hours/day, 20 days/month = 40 hours/month
Cost: ~$3.40/month
```

#### Multiple Repositories (Mixed Usage)
```
Repository: johndoe/web-app (t3.micro, 40 hours/month) = $3.40
Repository: johndoe/api-service (t3.small, 60 hours/month) = $12.60  
Repository: johndoe/mobile-app (t3.micro, 20 hours/month) = $1.70
Total: ~$17.70/month for 3 dedicated runners
```

#### Cost Optimization Strategies
- **Shared Base Infrastructure**: VPC and networking shared across all runners
- **Instance Scheduling**: Use AWS Instance Scheduler for predictable workloads
- **Spot Instances**: Consider spot instances for non-critical development work
- **Right-Sizing**: Monitor usage and adjust instance types per repository needs

## 🔧 Advanced Configuration

### Network Security (Per Instance)
- **SSH Access**: Configurable CIDR blocks (default: your IP only)
- **GitHub Access**: HTTPS (443) outbound for GitHub API and Actions
- **Outbound**: All traffic allowed for package downloads and deployments
- **Security Groups**: Dedicated security group per instance
- **Encryption**: EBS volumes encrypted by default

### Instance Tagging Strategy
```hcl
tags = {
  Name                = "runner-johndoe-my-app"
  Purpose            = "GitHub Actions Runner"
  Repository         = "johndoe/my-app"
  GitHubUsername     = "johndoe"
  RepositoryName     = "my-app"
  Environment        = "prod"
  ManagedBy          = "terraform"
  AutoShutdown       = "true"
  CostCenter         = "engineering"
}
```

## 🔍 Troubleshooting

### Quick Validation

Before troubleshooting issues, run the comprehensive validation script:

```bash
# Set required environment variables for CLI troubleshooting
# Note: These are shell variables, not GitHub Actions secrets
export GITHUB_USERNAME="your-username"
export GITHUB_REPOSITORY="your-repository"
export GH_PAT="your-github-pat"
export EC2_INSTANCE_ID="your-instance-id"

# Run validation script
./scripts/validate-repository-permissions.sh
```

This script validates:
- GitHub API access and PAT permissions
- Repository access and admin permissions
- AWS credentials and EC2 instance access
- Network connectivity to GitHub
- Repository secrets configuration
- Actions permissions and runner registration capability

### Common Issues

#### 1. Runner Registration Fails
```bash
# Check GitHub PAT permissions (should have repo scope only)
curl -H "Authorization: token $GH_PAT" https://api.github.com/user

# Check repository access and permissions
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/collaborators/$GITHUB_USERNAME/permission"

# Test runner registration token generation
curl -X POST -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners/registration-token"

# Verify instance can reach GitHub
ssh -i ~/.ssh/key.pem ubuntu@<instance-ip>
curl -I https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY
```

#### 2. Instance Won't Start
```bash
# Check instance status
aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID

# Check security group rules
aws ec2 describe-security-groups --group-ids <security-group-id>

# Check AWS service limits
aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A
```

#### 3. SSH Connection Issues
```bash
# Verify your IP is whitelisted
curl ifconfig.me

# Update security group if IP changed
terraform apply -var="personal_ip=$(curl -s ifconfig.me)/32"

# Test SSH connectivity
nc -z -w5 <instance-ip> 22
```

#### 4. Repository Permission Issues
```bash
# Check if Actions are enabled for repository
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/permissions"

# List existing repository runners
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners"

# Check repository secrets
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/secrets"
```

### Comprehensive Troubleshooting

For detailed troubleshooting procedures, see:
- **[Repository Troubleshooting Guide](docs/repository-troubleshooting-guide.md)** - Complete troubleshooting procedures for repository-level runners
- **[Repository Migration Guide](docs/repository-migration-guide.md)** - Migration issues and solutions

### Debug Commands

```bash
# Get instance public IP
aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress'

# Check instance logs
aws ec2 get-console-output --instance-id $EC2_INSTANCE_ID

# SSH to instance for debugging
ssh -i ~/.ssh/key.pem ubuntu@<instance-ip>

# Check runner status on instance
cd ~/actions-runner
sudo ./svc.sh status

# Check runner logs
sudo journalctl -u actions.runner.* -f
```

## 🔒 Security Considerations

### Network Security
- Security group restricts access to personal IP and GitHub IPs only
- No public services exposed except SSH (port 22)
- All package downloads use HTTPS

### Runner Security  
- Ephemeral runners minimize attack surface
- Each job runs on a "clean" runner instance
- No persistent data or credentials stored on runner

### AWS Security
- Use IAM roles with minimal required permissions
- Regularly rotate AWS access keys
- Monitor CloudTrail logs for EC2 operations

### GitHub Security
- Use fine-grained PATs with minimal scopes
- Regularly rotate GitHub PAT
- Monitor runner activity in Actions logs

## 📚 Additional Resources

### Documentation
- [GitHub Runner Installation Guide](docs/github-runner-setup.md) - Complete setup instructions for repository-level runners
- [Repository Migration Guide](docs/repository-migration-guide.md) - Step-by-step migration from organization to repository setup
- [Repository Switching Guide](docs/repository-switching-guide.md) - How to switch runner between different repositories
- [Repository Troubleshooting Guide](docs/repository-troubleshooting-guide.md) - Comprehensive troubleshooting for repository-level issues
- [Repository Validation Guide](docs/repository-validation-guide.md) - Existing validation procedures
- [Cross-Repository Testing](docs/cross-repository-testing.md) - Testing across multiple repositories

### Scripts and Tools
- [Create Repository Runner Script](scripts/create-repository-runner.sh) - Provision dedicated EC2 instance for repository
- [Configure Repository Runner Script](scripts/configure-repository-runner.sh) - Configure runner on provisioned instance  
- [Destroy Repository Runner Script](scripts/destroy-repository-runner.sh) - Clean up repository-specific resources
- [Repository Validation Script](scripts/validate-repository-configuration.sh) - Comprehensive validation of repository setup
- [Health Check Script](scripts/health-check-runner.sh) - Monitor repository runner health and status
- [Comprehensive Test Suite](scripts/run-comprehensive-tests.sh) - Run all validation and integration tests

### External Resources
- [GitHub Actions Self-hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [AWS EC2 Pricing](https://aws.amazon.com/ec2/pricing/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with your AWS account
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## ⚠️ Disclaimer

This infrastructure creates AWS resources that may incur costs. Monitor your AWS billing and adjust instance types/usage patterns according to your budget. The authors are not responsible for any AWS charges incurred.