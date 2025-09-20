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
TERRAFORM_MODULE_DIR="$PROJECT_ROOT/terraform/modules/repository-runner"
TERRAFORM_WORK_DIR="/tmp/repository-runner-terraform"

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
ALLOCATE_EIP=false
CREATE_IAM_ROLE=false
ENABLE_AUTO_RECOVERY=false
DRY_RUN=false
FORCE=false

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
    for tool in aws terraform jq; do
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
    
    # Check Terraform module
    if [ ! -d "$TERRAFORM_MODULE_DIR" ]; then
        log_error "Terraform module not found: $TERRAFORM_MODULE_DIR"
        log_error "Please ensure the repository-runner module exists"
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
    
    # Check if key pair exists
    if ! aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" --region "$AWS_REGION" &> /dev/null; then
        log_error "Key pair '$KEY_PAIR_NAME' not found in region $AWS_REGION"
        log_error "Please create the key pair or specify an existing one"
        return 1
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

# Prepare Terraform configuration
prepare_terraform() {
    log_info "Preparing Terraform configuration..."
    
    # Create working directory
    mkdir -p "$TERRAFORM_WORK_DIR"
    
    # Create main.tf
    cat > "$TERRAFORM_WORK_DIR/main.tf" << EOF
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "repository_runner" {
  source = "$TERRAFORM_MODULE_DIR"
  
  # Required variables
  github_username = var.github_username
  repository_name = var.repository_name
  key_pair_name   = var.key_pair_name
  
  # Instance configuration
  instance_type = var.instance_type
  
  # Networking
  vpc_id                   = var.vpc_id
  subnet_id               = var.subnet_id
  allowed_ssh_cidr_blocks = var.allowed_ssh_cidr_blocks
  
  # Environment
  environment = var.environment
  cost_center = var.cost_center
  
  # Optional features
  allocate_elastic_ip      = var.allocate_elastic_ip
  enable_detailed_monitoring = var.enable_detailed_monitoring
  enable_cloudwatch_logs   = var.enable_cloudwatch_logs
  create_iam_role         = var.create_iam_role
  enable_auto_recovery    = var.enable_auto_recovery
}
EOF
    
    # Create variables.tf
    cat > "$TERRAFORM_WORK_DIR/variables.tf" << EOF
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
    
    log_success "Terraform configuration prepared"
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

# Execute Terraform
execute_terraform() {
    log_header "Executing Terraform"
    
    cd "$TERRAFORM_WORK_DIR"
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    if ! terraform init; then
        log_error "Terraform initialization failed"
        return 1
    fi
    
    # Validate configuration
    log_info "Validating Terraform configuration..."
    if ! terraform validate; then
        log_error "Terraform validation failed"
        return 1
    fi
    
    # Plan
    log_info "Creating Terraform plan..."
    if ! terraform plan -out=tfplan; then
        log_error "Terraform plan failed"
        return 1
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "Dry run completed. No resources were created."
        log_info "Plan saved to: $TERRAFORM_WORK_DIR/tfplan"
        return 0
    fi
    
    # Confirm before apply
    if [ "$FORCE" = false ]; then
        echo ""
        read -p "Do you want to apply this Terraform plan? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled by user"
            return 0
        fi
    fi
    
    # Apply
    log_info "Applying Terraform configuration..."
    if ! terraform apply tfplan; then
        log_error "Terraform apply failed"
        return 1
    fi
    
    log_success "Terraform execution completed"
    return 0
}

# Show results
show_results() {
    log_header "Deployment Results"
    
    cd "$TERRAFORM_WORK_DIR"
    
    # Get outputs
    local instance_id
    instance_id=$(terraform output -raw instance_id 2>/dev/null || echo "N/A")
    
    local instance_name
    instance_name=$(terraform output -raw instance_name 2>/dev/null || echo "N/A")
    
    local public_ip
    public_ip=$(terraform output -raw instance_public_ip 2>/dev/null || echo "N/A")
    
    local private_ip
    private_ip=$(terraform output -raw instance_private_ip 2>/dev/null || echo "N/A")
    
    local ssh_command
    ssh_command=$(terraform output -raw ssh_connection_command 2>/dev/null || echo "N/A")
    
    local runner_url
    runner_url=$(terraform output -raw runner_url 2>/dev/null || echo "N/A")
    
    echo "Instance ID: $instance_id"
    echo "Instance Name: $instance_name"
    echo "Public IP: $public_ip"
    echo "Private IP: $private_ip"
    echo "Repository URL: $runner_url"
    echo ""
    echo "SSH Connection:"
    echo "  $ssh_command"
    echo ""
    echo "Next Steps:"
    echo "1. Wait for instance to complete initialization (2-3 minutes)"
    echo "2. Configure the runner using:"
    echo "   ./scripts/configure-repository-runner.sh \\"
    echo "     --username $GITHUB_USERNAME \\"
    echo "     --repository $REPOSITORY_NAME \\"
    echo "     --instance-id $instance_id \\"
    echo "     --pat YOUR_GITHUB_PAT"
    echo ""
    echo "3. Test the runner with a GitHub Actions workflow"
    echo ""
    echo "Terraform State: $TERRAFORM_WORK_DIR"
}

# Cleanup on error
cleanup_on_error() {
    if [ $? -ne 0 ]; then
        log_error "Script failed. Terraform state preserved at: $TERRAFORM_WORK_DIR"
        log_error "To clean up resources, run: cd $TERRAFORM_WORK_DIR && terraform destroy"
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
    
    # Prepare Terraform
    prepare_terraform
    
    # Execute Terraform
    if ! execute_terraform; then
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