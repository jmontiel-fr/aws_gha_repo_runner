#!/bin/bash

# Create Repository Runner Script
# This script provisions a dedicated EC2 instance for a specific repository runner
# using Terraform and configures it for GitHub Actions.

set -e

# Script version and metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="Create Repository Runner"

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "${CYAN}=== $1 ===${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
DEFAULT_INSTANCE_TYPE="t3.micro"
DEFAULT_REGION="us-east-1"
DEFAULT_ENVIRONMENT="dev"
DEFAULT_COST_CENTER="github-actions"

# Configuration variables
GITHUB_USERNAME=""
REPOSITORY_NAME=""
INSTANCE_TYPE="$DEFAULT_INSTANCE_TYPE"
AWS_REGION="$DEFAULT_REGION"
KEY_PAIR_NAME=""
ENVIRONMENT="$DEFAULT_ENVIRONMENT"
COST_CENTER="$DEFAULT_COST_CENTER"
VPC_ID=""
SUBNET_ID=""
ALLOWED_SSH_CIDR=""
ENABLE_MONITORING=false
ENABLE_LOGS=false
ALLOCATE_ELASTIC_IP=false
CREATE_IAM_ROLE=false
ENABLE_AUTO_RECOVERY=false
DRY_RUN=false
FORCE=false

# AWS CLI variables (set during execution)
AMI_ID=""
SECURITY_GROUP_ID=""
INSTANCE_ID=""
PUBLIC_IP=""
PRIVATE_IP=""
AVAILABILITY_ZONE=""

# =============================================================================
# Helper Functions
# =============================================================================

# Show usage information
show_usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

USAGE:
    $0 [OPTIONS]

DESCRIPTION:
    Provisions a dedicated EC2 instance for a GitHub Actions runner using Terraform.
    Creates an instance with parametrized naming: runner-{username}-{repository}

REQUIRED OPTIONS:
    -u, --username USERNAME     GitHub username
    -r, --repository REPO       Repository name
    -k, --key-pair KEY         AWS key pair name for SSH access

OPTIONAL OPTIONS:
    -t, --instance-type TYPE    EC2 instance type (default: $DEFAULT_INSTANCE_TYPE)
    -R, --region REGION         AWS region (default: $DEFAULT_REGION)
    -e, --environment ENV       Environment (dev/staging/prod, default: $DEFAULT_ENVIRONMENT)
    -c, --cost-center CENTER    Cost center for billing (default: $DEFAULT_COST_CENTER)
    
    --vpc-id VPC_ID            VPC ID (uses default VPC if not specified)
    --subnet-id SUBNET_ID      Subnet ID (uses first available if not specified)
    --ssh-cidr CIDR            Allowed SSH CIDR blocks (default: 0.0.0.0/0)
    
    --enable-monitoring        Enable detailed CloudWatch monitoring
    --enable-logs             Enable CloudWatch logs
    --allocate-eip            Allocate Elastic IP
    --create-iam-role         Create IAM role for the instance
    --enable-auto-recovery    Enable auto recovery with Auto Scaling Group
    
    --dry-run                 Show what would be created without actually creating
    --force                   Skip confirmation prompts
    
    -h, --help                Show this help message
    -v, --version             Show script version

EXAMPLES:
    # Basic runner creation
    $0 --username johndoe --repository my-app --key-pair my-key

    # Production runner with monitoring
    $0 --username company --repository api-service --key-pair prod-key \\
       --instance-type t3.medium --environment prod --enable-monitoring \\
       --enable-logs --allocate-eip

    # Development runner with custom VPC
    $0 --username dev-team --repository test-app --key-pair dev-key \\
       --vpc-id vpc-12345678 --subnet-id subnet-12345678 \\
       --ssh-cidr "10.0.0.0/8"

    # Dry run to see what would be created
    $0 --username johndoe --repository my-app --key-pair my-key --dry-run

PREREQUISITES:
    - AWS CLI configured with appropriate permissions
    - Terraform installed (>= 1.0)
    - Valid AWS key pair for SSH access
    - GitHub repository with admin permissions

OUTPUT:
    - EC2 instance ID and connection details
    - Terraform state files in $TERRAFORM_WORK_DIR
    - Instance configuration and setup scripts

EOF
}

# Validate required tools
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    for tool in aws jq; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install the missing tools and try again"
        return 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        log_error "Please run 'aws configure' or set AWS environment variables"
        return 1
    fi
    
    log_success "Prerequisites validated"
    return 0
}

# Validate input parameters
validate_parameters() {
    log_info "Validating parameters..."
    
    # Required parameters
    if [ -z "$GITHUB_USERNAME" ]; then
        log_error "GitHub username is required (--username)"
        return 1
    fi
    
    if [ -z "$REPOSITORY_NAME" ]; then
        log_error "Repository name is required (--repository)"
        return 1
    fi
    
    if [ -z "$KEY_PAIR_NAME" ]; then
        log_error "Key pair name is required (--key-pair)"
        return 1
    fi
    
    # Validate GitHub username format
    if [[ ! "$GITHUB_USERNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
        log_error "Invalid GitHub username format: $GITHUB_USERNAME"
        log_error "Username must contain only alphanumeric characters and hyphens"
        return 1
    fi
    
    # Validate repository name format
    if [[ ! "$REPOSITORY_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log_error "Invalid repository name format: $REPOSITORY_NAME"
        log_error "Repository name can only contain alphanumeric characters, hyphens, underscores, and periods"
        return 1
    fi
    
    # Validate environment
    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        log_error "Invalid environment: $ENVIRONMENT"
        log_error "Environment must be one of: dev, staging, prod"
        return 1
    fi
    
    # Check if key pair exists, create if it doesn't
    if ! aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" --region "$AWS_REGION" &> /dev/null; then
        log_info "Key pair '$KEY_PAIR_NAME' not found in region $AWS_REGION"
        log_info "Creating key pair and saving to ~/.ssh/${KEY_PAIR_NAME}.pem"
        
        # Create the SSH directory if it doesn't exist
        mkdir -p ~/.ssh
        
        # Remove existing key file if it exists
        rm -f ~/.ssh/${KEY_PAIR_NAME}.pem
        
        # Create the key pair and save the private key
        aws ec2 create-key-pair \
            --region "$AWS_REGION" \
            --key-name "$KEY_PAIR_NAME" \
            --query 'KeyMaterial' \
            --output text > ~/.ssh/${KEY_PAIR_NAME}.pem
        
        # Set proper permissions
        chmod 400 ~/.ssh/${KEY_PAIR_NAME}.pem
        
        log_success "Key pair '$KEY_PAIR_NAME' created and saved to ~/.ssh/${KEY_PAIR_NAME}.pem"
    else
        log_info "Using existing key pair: $KEY_PAIR_NAME"
    fi
    
    log_success "Parameters validated"
    return 0
}

# Check if instance already exists
check_existing_instance() {
    log_info "Checking for existing instance..."
    
    local instance_name="runner-$GITHUB_USERNAME-$REPOSITORY_NAME"
    
    local existing_instance
    existing_instance=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=$instance_name" "Name=instance-state-name,Values=running,stopped,pending" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$existing_instance" != "None" ] && [ "$existing_instance" != "null" ]; then
        log_warning "Instance already exists: $existing_instance"
        log_warning "Instance name: $instance_name"
        
        if [ "$FORCE" = false ]; then
            echo ""
            read -p "Do you want to continue and potentially replace the existing instance? (y/N): " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Operation cancelled by user"
                exit 0
            fi
        fi
    else
        log_info "No existing instance found"
    fi
}

# Prepare AWS CLI configuration
prepare_aws_resources() {
    log_info "Preparing AWS resources..."
    
    # Get the latest Ubuntu 22.04 LTS AMI
    log_info "Getting latest Ubuntu 22.04 LTS AMI..."
    AMI_ID=$(aws ec2 describe-images \
        --region "$AWS_REGION" \
        --owners 099720109477 \
        --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
                  "Name=virtualization-type,Values=hvm" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    if [ "$AMI_ID" = "None" ] || [ -z "$AMI_ID" ]; then
        log_error "Failed to find Ubuntu 22.04 LTS AMI"
        return 1
    fi
    
    log_success "Found AMI: $AMI_ID"
    
    # Use existing security group created by Terraform
    log_info "Finding existing security group..."
    
    # If VPC_ID is not provided, find the security group by name pattern only
    if [ -n "$VPC_ID" ]; then
        SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
            --region "$AWS_REGION" \
            --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=gha-repo-runner-*" \
            --query 'SecurityGroups[0].GroupId' \
            --output text)
    else
        SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
            --region "$AWS_REGION" \
            --filters "Name=group-name,Values=gha-repo-runner-*" \
            --query 'SecurityGroups[0].GroupId' \
            --output text)
    fi
    
    if [ "$SECURITY_GROUP_ID" = "None" ] || [ -z "$SECURITY_GROUP_ID" ]; then
        log_error "Failed to find existing security group created by Terraform"
        log_error "Please ensure the base infrastructure is deployed with Terraform first"
        return 1
    fi
    
    log_success "Using existing security group: $SECURITY_GROUP_ID"
    
    # Get the VPC ID from the security group
    VPC_ID=$(aws ec2 describe-security-groups \
        --region "$AWS_REGION" \
        --group-ids "$SECURITY_GROUP_ID" \
        --query 'SecurityGroups[0].VpcId' \
        --output text)
    
    # If SUBNET_ID is not provided, find a public subnet in the same VPC
    if [ -z "$SUBNET_ID" ]; then
        log_info "Finding public subnet in VPC: $VPC_ID"
        SUBNET_ID=$(aws ec2 describe-subnets \
            --region "$AWS_REGION" \
            --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*public*" \
            --query 'Subnets[0].SubnetId' \
            --output text)
        
        # If no subnet with "public" tag found, get the first available subnet
        if [ "$SUBNET_ID" = "None" ] || [ -z "$SUBNET_ID" ]; then
            SUBNET_ID=$(aws ec2 describe-subnets \
                --region "$AWS_REGION" \
                --filters "Name=vpc-id,Values=$VPC_ID" \
                --query 'Subnets[0].SubnetId' \
                --output text)
        fi
        
        if [ "$SUBNET_ID" = "None" ] || [ -z "$SUBNET_ID" ]; then
            log_error "Failed to find subnet in VPC: $VPC_ID"
            return 1
        fi
        
        log_success "Using subnet: $SUBNET_ID"
    fi
    
    log_success "AWS resources prepared"
    return 0
}

# Dummy function to avoid errors
dummy_function() {
    cat > /dev/null << EOF
variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "github_username" {
  description = "GitHub username"
  type        = string
}

variable "repository_name" {
  description = "Repository name"
  type        = string
}

variable "key_pair_name" {
  description = "AWS key pair name"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID"
  type        = string
}

variable "allowed_ssh_cidr_blocks" {
  description = "Allowed SSH CIDR blocks"
  type        = list(string)
}

variable "environment" {
  description = "Environment"
  type        = string
}

variable "cost_center" {
  description = "Cost center"
  type        = string
}

variable "allocate_elastic_ip" {
  description = "Allocate Elastic IP"
  type        = bool
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring"
  type        = bool
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs"
  type        = bool
}

variable "create_iam_role" {
  description = "Create IAM role"
  type        = bool
}

variable "enable_auto_recovery" {
  description = "Enable auto recovery"
  type        = bool
}
EOF
    
    # Create outputs.tf
    cat > "$TERRAFORM_WORK_DIR/outputs.tf" << EOF
output "instance_id" {
  description = "EC2 instance ID"
  value       = module.repository_runner.instance_id
}

output "instance_name" {
  description = "EC2 instance name"
  value       = module.repository_runner.instance_name
}

output "instance_public_ip" {
  description = "EC2 instance public IP"
  value       = module.repository_runner.instance_public_ip
}

output "instance_private_ip" {
  description = "EC2 instance private IP"
  value       = module.repository_runner.instance_private_ip
}

output "security_group_id" {
  description = "Security group ID"
  value       = module.repository_runner.security_group_id
}

output "ssh_connection_command" {
  description = "SSH connection command"
  value       = module.repository_runner.ssh_connection_command
}

output "runner_url" {
  description = "GitHub repository URL"
  value       = module.repository_runner.runner_url
}

output "repository_full_name" {
  description = "Full repository name"
  value       = module.repository_runner.repository_full_name
}
EOF
    
    # Create terraform.tfvars
    local ssh_cidr_blocks="[\"0.0.0.0/0\"]"
    if [ -n "$ALLOWED_SSH_CIDR" ]; then
        ssh_cidr_blocks="[\"$ALLOWED_SSH_CIDR\"]"
    fi
    
    cat > "$TERRAFORM_WORK_DIR/terraform.tfvars" << EOF
aws_region     = "$AWS_REGION"
github_username = "$GITHUB_USERNAME"
repository_name = "$REPOSITORY_NAME"
key_pair_name   = "$KEY_PAIR_NAME"
instance_type   = "$INSTANCE_TYPE"
vpc_id         = "$VPC_ID"
subnet_id      = "$SUBNET_ID"
allowed_ssh_cidr_blocks = $ssh_cidr_blocks
environment    = "$ENVIRONMENT"
cost_center    = "$COST_CENTER"
allocate_elastic_ip = $ALLOCATE_EIP
enable_detailed_monitoring = $ENABLE_MONITORING
enable_cloudwatch_logs = $ENABLE_LOGS
create_iam_role = $CREATE_IAM_ROLE
enable_auto_recovery = $ENABLE_AUTO_RECOVERY
EOF
}

# Show configuration summary
show_configuration() {
    log_header "Configuration Summary"
    
    echo "Repository: $GITHUB_USERNAME/$REPOSITORY_NAME"
    echo "Instance Name: runner-$GITHUB_USERNAME-$REPOSITORY_NAME"
    echo "Instance Type: $INSTANCE_TYPE"
    echo "AWS Region: $AWS_REGION"
    echo "Key Pair: $KEY_PAIR_NAME"
    echo "Environment: $ENVIRONMENT"
    echo "Cost Center: $COST_CENTER"
    
    if [ -n "$VPC_ID" ]; then
        echo "VPC ID: $VPC_ID"
    fi
    
    if [ -n "$SUBNET_ID" ]; then
        echo "Subnet ID: $SUBNET_ID"
    fi
    
    if [ -n "$ALLOWED_SSH_CIDR" ]; then
        echo "SSH CIDR: $ALLOWED_SSH_CIDR"
    fi
    
    echo ""
    echo "Optional Features:"
    echo "  Detailed Monitoring: $ENABLE_MONITORING"
    echo "  CloudWatch Logs: $ENABLE_LOGS"
    echo "  Elastic IP: $ALLOCATE_EIP"
    echo "  IAM Role: $CREATE_IAM_ROLE"
    echo "  Auto Recovery: $ENABLE_AUTO_RECOVERY"
    
    echo ""
    echo "Terraform Working Directory: $TERRAFORM_WORK_DIR"
}

# Create EC2 instance using AWS CLI
create_ec2_instance() {
    log_header "Creating EC2 Instance"
    
    # Create user data script
    USER_DATA_SCRIPT=$(cat << 'EOF'
#!/bin/bash
set -e

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/runner-setup.log
}

log "Starting GitHub Actions runner setup"

# Update system packages
log "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# Install essential packages
log "Installing essential packages..."
apt-get install -y \
    curl \
    wget \
    git \
    jq \
    unzip \
    build-essential \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release

# Install Docker
log "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Install Node.js
log "Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Install Python 3 and pip
log "Installing Python..."
apt-get install -y python3 python3-pip python3-venv

# Install AWS CLI v2
log "Installing AWS CLI v2..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install Java (OpenJDK 17)
log "Installing Java..."
apt-get install -y openjdk-17-jdk

# Install Terraform
log "Installing Terraform..."
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com jammy main" | tee /etc/apt/sources.list.d/hashicorp.list
apt-get update
apt-get install -y terraform

# Install kubectl
log "Installing kubectl..."
curl -LO "https://dl.k8s.io/release/v1.29.1/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# Install Helm
log "Installing Helm..."
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Create runner user and directory
log "Setting up runner user..."
useradd -m -s /bin/bash runner || true
mkdir -p /home/runner/actions-runner
chown -R runner:runner /home/runner

log "GitHub Actions runner instance setup completed!"
log "Instance ready for configuration"
EOF
)

    # Encode user data
    USER_DATA_B64=$(echo "$USER_DATA_SCRIPT" | base64 -w 0)
    
    # Instance name
    INSTANCE_NAME="runner-${GITHUB_USERNAME}-${REPOSITORY_NAME}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "Dry run - would create instance: $INSTANCE_NAME"
        log_info "AMI ID: $AMI_ID"
        log_info "Instance Type: $INSTANCE_TYPE"
        log_info "Security Group: $SECURITY_GROUP_ID"
        log_info "Subnet: $SUBNET_ID"
        return 0
    fi
    
    # Confirm before creating
    if [ "$FORCE" = false ]; then
        echo ""
        read -p "Do you want to create the EC2 instance? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled by user"
            return 0
        fi
    fi
    
    # Create EC2 instance
    log_info "Creating EC2 instance: $INSTANCE_NAME"
    INSTANCE_ID=$(aws ec2 run-instances \
        --region "$AWS_REGION" \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_PAIR_NAME" \
        --security-group-ids "$SECURITY_GROUP_ID" \
        --subnet-id "$SUBNET_ID" \
        --user-data "$USER_DATA_B64" \
        --associate-public-ip-address \
        --tag-specifications "ResourceType=instance,Tags=[
            {Key=Name,Value=$INSTANCE_NAME},
            {Key=GitHubUsername,Value=$GITHUB_USERNAME},
            {Key=Repository,Value=${GITHUB_USERNAME}/${REPOSITORY_NAME}},
            {Key=RepositoryName,Value=$REPOSITORY_NAME},
            {Key=Environment,Value=$ENVIRONMENT},
            {Key=CostCenter,Value=$COST_CENTER},
            {Key=CreatedBy,Value=repository-runner-script},
            {Key=ManagedBy,Value=aws-cli},
            {Key=Purpose,Value=GitHub Actions Runner},
            {Key=AutoShutdown,Value=true}
        ]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    if [ "$INSTANCE_ID" = "None" ] || [ -z "$INSTANCE_ID" ]; then
        log_error "Failed to create EC2 instance"
        return 1
    fi
    
    log_success "EC2 instance created: $INSTANCE_ID"
    
    # Wait for instance to be running
    log_info "Waiting for instance to be running..."
    aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids "$INSTANCE_ID"
    
    # Get instance details
    INSTANCE_DETAILS=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].[PublicIpAddress,PrivateIpAddress,Placement.AvailabilityZone]' \
        --output text)
    
    PUBLIC_IP=$(echo "$INSTANCE_DETAILS" | cut -f1)
    PRIVATE_IP=$(echo "$INSTANCE_DETAILS" | cut -f2)
    AVAILABILITY_ZONE=$(echo "$INSTANCE_DETAILS" | cut -f3)
    
    # Allocate Elastic IP if requested
    if [ "$ALLOCATE_ELASTIC_IP" = true ]; then
        log_info "Allocating Elastic IP..."
        EIP_ALLOCATION=$(aws ec2 allocate-address \
            --region "$AWS_REGION" \
            --domain vpc \
            --tag-specifications "ResourceType=elastic-ip,Tags=[
                {Key=Name,Value=${INSTANCE_NAME}-eip},
                {Key=GitHubUsername,Value=$GITHUB_USERNAME},
                {Key=Repository,Value=${GITHUB_USERNAME}/${REPOSITORY_NAME}},
                {Key=RepositoryName,Value=$REPOSITORY_NAME},
                {Key=Environment,Value=$ENVIRONMENT},
                {Key=CostCenter,Value=$COST_CENTER},
                {Key=CreatedBy,Value=repository-runner-script},
                {Key=ManagedBy,Value=aws-cli},
                {Key=Purpose,Value=GitHub Actions Runner},
                {Key=AutoShutdown,Value=true}
            ]" \
            --query '[AllocationId,PublicIp]' \
            --output text)
        
        EIP_ALLOCATION_ID=$(echo "$EIP_ALLOCATION" | cut -f1)
        EIP_PUBLIC_IP=$(echo "$EIP_ALLOCATION" | cut -f2)
        
        # Associate Elastic IP with instance
        aws ec2 associate-address \
            --region "$AWS_REGION" \
            --instance-id "$INSTANCE_ID" \
            --allocation-id "$EIP_ALLOCATION_ID"
        
        PUBLIC_IP="$EIP_PUBLIC_IP"
        log_success "Elastic IP allocated and associated: $PUBLIC_IP"
    fi
    
    log_success "EC2 instance creation completed"
    return 0
}

# Show results
show_results() {
    log_header "Deployment Results"
    
    local instance_name="runner-${GITHUB_USERNAME}-${REPOSITORY_NAME}"
    local ssh_command="ssh -i ~/.ssh/${KEY_PAIR_NAME}.pem ubuntu@${PUBLIC_IP}"
    local runner_url="https://github.com/${GITHUB_USERNAME}/${REPOSITORY_NAME}"
    
    echo "Instance ID: $INSTANCE_ID"
    echo "Instance Name: $instance_name"
    echo "Public IP: $PUBLIC_IP"
    echo "Private IP: $PRIVATE_IP"
    echo "Availability Zone: $AVAILABILITY_ZONE"
    echo "Repository URL: $runner_url"
    echo ""
    echo "SSH Connection:"
    echo "  $ssh_command"
    echo ""
    echo "Next Steps:"
    echo "1. Wait for instance to complete initialization (2-3 minutes)"
    echo "2. Configure the runner using:"
    echo "   export PATH=\$PATH:. && ../scripts/configure-repository-runner.sh \\"
    echo "     --username $GITHUB_USERNAME \\"
    echo "     --repository $REPOSITORY_NAME \\"
    echo "     --instance-id $INSTANCE_ID \\"
    echo "     --region $AWS_REGION \\"
    echo "     --key-pair $KEY_PAIR_NAME \\"
    echo "     --pat YOUR_GITHUB_PAT"
    echo ""
    echo "3. Test the runner with a GitHub Actions workflow"
}

# Cleanup on error
cleanup_on_error() {
    if [ $? -ne 0 ]; then
        log_error "Script failed."
        if [ ! -z "$INSTANCE_ID" ]; then
            log_error "To clean up the created instance, run:"
            log_error "aws ec2 terminate-instances --region $AWS_REGION --instance-ids $INSTANCE_ID"
        fi
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--username)
            GITHUB_USERNAME="$2"
            shift 2
            ;;
        -r|--repository)
            REPOSITORY_NAME="$2"
            shift 2
            ;;
        -k|--key-pair)
            KEY_PAIR_NAME="$2"
            shift 2
            ;;
        -t|--instance-type)
            INSTANCE_TYPE="$2"
            shift 2
            ;;
        -R|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -c|--cost-center)
            COST_CENTER="$2"
            shift 2
            ;;
        --vpc-id)
            VPC_ID="$2"
            shift 2
            ;;
        --subnet-id)
            SUBNET_ID="$2"
            shift 2
            ;;
        --ssh-cidr)
            ALLOWED_SSH_CIDR="$2"
            shift 2
            ;;
        --enable-monitoring)
            ENABLE_MONITORING=true
            shift
            ;;
        --enable-logs)
            ENABLE_LOGS=true
            shift
            ;;
        --allocate-eip)
            ALLOCATE_EIP=true
            shift
            ;;
        --create-iam-role)
            CREATE_IAM_ROLE=true
            shift
            ;;
        --enable-auto-recovery)
            ENABLE_AUTO_RECOVERY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--version)
            echo "$SCRIPT_NAME v$SCRIPT_VERSION"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Set up error handling
trap cleanup_on_error EXIT

# Main execution
main() {
    echo "=== $SCRIPT_NAME v$SCRIPT_VERSION ==="
    echo ""
    
    # Validate prerequisites
    if ! validate_prerequisites; then
        exit 1
    fi
    
    # Validate parameters
    if ! validate_parameters; then
        exit 1
    fi
    
    # Check for existing instance
    check_existing_instance
    
    # Show configuration
    show_configuration
    
    # Prepare AWS resources
    if ! prepare_aws_resources; then
        exit 1
    fi
    
    # Create EC2 instance
    if ! create_ec2_instance; then
        exit 1
    fi
    
    # Show results (only if not dry run)
    if [ "$DRY_RUN" = false ]; then
        show_results
    fi
    
    log_success "Repository runner creation completed successfully"
}

# Execute main function
main "$@"