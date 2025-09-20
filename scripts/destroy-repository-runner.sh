#!/bin/bash

# Destroy Repository Runner Script
# This script safely destroys a repository-specific EC2 instance and all
# associated resources, with proper cleanup and validation.

set -e

# Script version and metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="Destroy Repository Runner"

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
TERRAFORM_WORK_DIR="/tmp/repository-runner-terraform"

# Configuration variables
GITHUB_USERNAME=""
REPOSITORY_NAME=""
AWS_REGION="us-east-1"
FORCE=false
DRY_RUN=false
CLEANUP_RUNNER=true
GITHUB_PAT=""

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
    Safely destroys a repository-specific EC2 instance and all associated
    resources. Includes runner unregistration and Terraform cleanup.

REQUIRED OPTIONS:
    -u, --username USERNAME     GitHub username
    -r, --repository REPO       Repository name

OPTIONAL OPTIONS:
    -R, --region REGION         AWS region (default: us-east-1)
    -p, --pat TOKEN            GitHub PAT for runner cleanup
    
    --no-runner-cleanup        Skip GitHub runner unregistration
    --force                    Skip confirmation prompts
    --dry-run                  Show what would be destroyed without executing
    
    -h, --help                 Show this help message
    -v, --version              Show script version

EXAMPLES:
    # Basic destruction with confirmation
    $0 --username johndoe --repository my-app

    # Destruction with runner cleanup
    $0 --username johndoe --repository my-app \\
       --pat ghp_xxxxxxxxxxxxxxxxxxxx

    # Force destruction without prompts
    $0 --username johndoe --repository my-app --force

    # Dry run to see what would be destroyed
    $0 --username johndoe --repository my-app --dry-run

    # Skip runner unregistration
    $0 --username johndoe --repository my-app --no-runner-cleanup

PREREQUISITES:
    - AWS CLI configured with appropriate permissions
    - Terraform installed (if using Terraform-managed resources)
    - GitHub PAT with repo scope (for runner cleanup)

RESOURCES DESTROYED:
    - EC2 instance: runner-{username}-{repository}
    - Security groups associated with the instance
    - Elastic IP (if allocated)
    - CloudWatch logs (if enabled)
    - IAM roles and policies (if created)
    - Auto Scaling Groups (if enabled)

EOF
}

# Validate prerequisites
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
        return 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        return 1
    fi
    
    log_success "Prerequisites validated"
    return 0
}

# Validate parameters
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
    
    # Validate formats
    if [[ ! "$GITHUB_USERNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
        log_error "Invalid GitHub username format: $GITHUB_USERNAME"
        return 1
    fi
    
    if [[ ! "$REPOSITORY_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log_error "Invalid repository name format: $REPOSITORY_NAME"
        return 1
    fi
    
    log_success "Parameters validated"
    return 0
}

# Find repository instance
find_repository_instance() {
    log_info "Finding repository instance..."
    
    local instance_name="runner-$GITHUB_USERNAME-$REPOSITORY_NAME"
    
    local instance_info
    instance_info=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=$instance_name" "Name=instance-state-name,Values=running,stopped,stopping,pending" \
        --query 'Reservations[0].Instances[0]' 2>/dev/null || echo "null")
    
    if [ "$instance_info" = "null" ]; then
        log_warning "No instance found with name: $instance_name"
        return 1
    fi
    
    local instance_id=$(echo "$instance_info" | jq -r '.InstanceId')
    local instance_state=$(echo "$instance_info" | jq -r '.State.Name')
    local public_ip=$(echo "$instance_info" | jq -r '.PublicIpAddress // "none"')
    
    echo "Found instance:"
    echo "  Instance ID: $instance_id"
    echo "  Instance Name: $instance_name"
    echo "  State: $instance_state"
    echo "  Public IP: $public_ip"
    
    # Export for use in other functions
    export INSTANCE_ID="$instance_id"
    export INSTANCE_NAME="$instance_name"
    export INSTANCE_STATE="$instance_state"
    export INSTANCE_PUBLIC_IP="$public_ip"
    
    log_success "Repository instance found"
    return 0
}

# Unregister runner from GitHub
unregister_github_runner() {
    if [ "$CLEANUP_RUNNER" = false ]; then
        log_info "Skipping GitHub runner cleanup (--no-runner-cleanup specified)"
        return 0
    fi
    
    if [ -z "$GITHUB_PAT" ]; then
        log_warning "GitHub PAT not provided - skipping runner unregistration"
        log_warning "You may need to manually remove the runner from repository settings"
        return 0
    fi
    
    log_info "Unregistering runner from GitHub repository..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would unregister runner from repository $GITHUB_USERNAME/$REPOSITORY_NAME"
        return 0
    fi
    
    # Get repository runners
    local runners_response
    runners_response=$(curl -s -H "Authorization: token $GITHUB_PAT" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$REPOSITORY_NAME/actions/runners" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        log_warning "Failed to get repository runners - continuing with instance destruction"
        return 0
    fi
    
    # Find runners associated with this instance
    local runners_to_remove=()
    
    if echo "$runners_response" | jq -e '.runners[]' > /dev/null 2>&1; then
        while IFS= read -r runner; do
            local runner_id=$(echo "$runner" | jq -r '.id')
            local runner_name=$(echo "$runner" | jq -r '.name')
            local runner_status=$(echo "$runner" | jq -r '.status')
            
            # Check if runner name matches expected pattern or is associated with this instance
            if [[ "$runner_name" =~ gha_aws_runner ]] || [[ "$runner_name" =~ $GITHUB_USERNAME.*$REPOSITORY_NAME ]]; then
                runners_to_remove+=("$runner_id:$runner_name")
                echo "Found runner to remove: $runner_name (ID: $runner_id, Status: $runner_status)"
            fi
        done < <(echo "$runners_response" | jq -c '.runners[]')
    fi
    
    # Remove found runners
    if [ ${#runners_to_remove[@]} -gt 0 ]; then
        for runner_info in "${runners_to_remove[@]}"; do
            local runner_id="${runner_info%%:*}"
            local runner_name="${runner_info##*:}"
            
            log_info "Removing runner: $runner_name (ID: $runner_id)"
            
            local delete_response
            delete_response=$(curl -s -w "%{http_code}" -X DELETE \
                -H "Authorization: token $GITHUB_PAT" \
                "https://api.github.com/repos/$GITHUB_USERNAME/$REPOSITORY_NAME/actions/runners/$runner_id")
            
            local http_code="${delete_response: -3}"
            
            if [ "$http_code" = "204" ]; then
                log_success "Runner removed: $runner_name"
            else
                log_warning "Failed to remove runner $runner_name (HTTP $http_code)"
            fi
        done
    else
        log_info "No runners found to remove"
    fi
}

# Get associated resources
get_associated_resources() {
    log_info "Finding associated resources..."
    
    if [ -z "$INSTANCE_ID" ]; then
        log_warning "No instance ID available - cannot find associated resources"
        return 0
    fi
    
    # Get security groups
    local security_groups
    security_groups=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" \
        --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' --output text 2>/dev/null || echo "")
    
    # Get volumes
    local volumes
    volumes=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" \
        --query 'Reservations[0].Instances[0].BlockDeviceMappings[].Ebs.VolumeId' --output text 2>/dev/null || echo "")
    
    # Check for Elastic IP
    local elastic_ip
    elastic_ip=$(aws ec2 describe-addresses --region "$AWS_REGION" \
        --filters "Name=instance-id,Values=$INSTANCE_ID" \
        --query 'Addresses[0].AllocationId' --output text 2>/dev/null || echo "None")
    
    # Check for Auto Scaling Group
    local asg_name
    asg_name=$(aws autoscaling describe-auto-scaling-instances --region "$AWS_REGION" \
        --instance-ids "$INSTANCE_ID" \
        --query 'AutoScalingInstances[0].AutoScalingGroupName' --output text 2>/dev/null || echo "None")
    
    echo "Associated resources:"
    echo "  Security Groups: ${security_groups:-none}"
    echo "  Volumes: ${volumes:-none}"
    echo "  Elastic IP: ${elastic_ip}"
    echo "  Auto Scaling Group: ${asg_name}"
    
    # Export for use in destruction
    export SECURITY_GROUPS="$security_groups"
    export VOLUMES="$volumes"
    export ELASTIC_IP="$elastic_ip"
    export ASG_NAME="$asg_name"
    
    return 0
}

# Check for Terraform state
check_terraform_state() {
    log_info "Checking for Terraform state..."
    
    # Check if Terraform working directory exists
    if [ -d "$TERRAFORM_WORK_DIR" ]; then
        log_info "Found Terraform working directory: $TERRAFORM_WORK_DIR"
        
        # Check if state file exists
        if [ -f "$TERRAFORM_WORK_DIR/terraform.tfstate" ]; then
            log_info "Found Terraform state file"
            export USE_TERRAFORM=true
            return 0
        fi
    fi
    
    # Check for remote state or other Terraform configurations
    local terraform_dirs=(
        "$PROJECT_ROOT/terraform/environments/repository-runners"
        "$PROJECT_ROOT/terraform/repository-runners"
        "$HOME/.terraform-repository-runners"
    )
    
    for dir in "${terraform_dirs[@]}"; do
        if [ -d "$dir" ] && [ -f "$dir/terraform.tfstate" ]; then
            log_info "Found Terraform state in: $dir"
            export TERRAFORM_STATE_DIR="$dir"
            export USE_TERRAFORM=true
            return 0
        fi
    done
    
    log_info "No Terraform state found - will use direct AWS resource destruction"
    export USE_TERRAFORM=false
    return 0
}

# Destroy with Terraform
destroy_with_terraform() {
    log_info "Destroying resources with Terraform..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would destroy Terraform-managed resources"
        return 0
    fi
    
    local terraform_dir="${TERRAFORM_STATE_DIR:-$TERRAFORM_WORK_DIR}"
    
    if [ ! -d "$terraform_dir" ]; then
        log_error "Terraform directory not found: $terraform_dir"
        return 1
    fi
    
    cd "$terraform_dir"
    
    # Initialize Terraform if needed
    if [ ! -d ".terraform" ]; then
        log_info "Initializing Terraform..."
        terraform init
    fi
    
    # Plan destruction
    log_info "Planning Terraform destruction..."
    if ! terraform plan -destroy -out=destroy.tfplan; then
        log_error "Terraform destroy plan failed"
        return 1
    fi
    
    # Confirm destruction
    if [ "$FORCE" = false ]; then
        echo ""
        read -p "Do you want to proceed with Terraform destroy? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Terraform destruction cancelled by user"
            return 0
        fi
    fi
    
    # Execute destruction
    log_info "Executing Terraform destruction..."
    if terraform apply destroy.tfplan; then
        log_success "Terraform destruction completed"
        
        # Clean up Terraform directory
        if [ "$FORCE" = true ]; then
            rm -rf "$terraform_dir"
            log_info "Terraform working directory cleaned up"
        fi
        
        return 0
    else
        log_error "Terraform destruction failed"
        return 1
    fi
}

# Destroy resources directly
destroy_resources_directly() {
    log_info "Destroying resources directly via AWS CLI..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would destroy the following resources:"
        echo "  Instance: $INSTANCE_ID"
        echo "  Security Groups: $SECURITY_GROUPS"
        echo "  Elastic IP: $ELASTIC_IP"
        echo "  Auto Scaling Group: $ASG_NAME"
        return 0
    fi
    
    # Stop Auto Scaling Group if exists
    if [ "$ASG_NAME" != "None" ] && [ -n "$ASG_NAME" ]; then
        log_info "Updating Auto Scaling Group to 0 capacity..."
        aws autoscaling update-auto-scaling-group \
            --auto-scaling-group-name "$ASG_NAME" \
            --desired-capacity 0 \
            --min-size 0 \
            --max-size 0 \
            --region "$AWS_REGION"
        
        log_info "Waiting for Auto Scaling Group to scale down..."
        sleep 30
    fi
    
    # Terminate instance
    if [ -n "$INSTANCE_ID" ]; then
        log_info "Terminating EC2 instance: $INSTANCE_ID"
        aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
        
        log_info "Waiting for instance termination..."
        aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
        log_success "Instance terminated: $INSTANCE_ID"
    fi
    
    # Release Elastic IP
    if [ "$ELASTIC_IP" != "None" ] && [ -n "$ELASTIC_IP" ]; then
        log_info "Releasing Elastic IP: $ELASTIC_IP"
        aws ec2 release-address --allocation-id "$ELASTIC_IP" --region "$AWS_REGION"
        log_success "Elastic IP released: $ELASTIC_IP"
    fi
    
    # Delete Auto Scaling Group
    if [ "$ASG_NAME" != "None" ] && [ -n "$ASG_NAME" ]; then
        log_info "Deleting Auto Scaling Group: $ASG_NAME"
        aws autoscaling delete-auto-scaling-group \
            --auto-scaling-group-name "$ASG_NAME" \
            --force-delete \
            --region "$AWS_REGION"
        log_success "Auto Scaling Group deleted: $ASG_NAME"
    fi
    
    # Clean up security groups (only if they're not default and not used by other instances)
    if [ -n "$SECURITY_GROUPS" ]; then
        for sg in $SECURITY_GROUPS; do
            # Skip default security group
            if [[ "$sg" =~ ^sg-[0-9a-f]+$ ]]; then
                local sg_name
                sg_name=$(aws ec2 describe-security-groups --group-ids "$sg" --region "$AWS_REGION" \
                    --query 'SecurityGroups[0].GroupName' --output text 2>/dev/null || echo "")
                
                if [ "$sg_name" != "default" ] && [[ "$sg_name" =~ runner-$GITHUB_USERNAME-$REPOSITORY_NAME ]]; then
                    log_info "Deleting security group: $sg ($sg_name)"
                    
                    # Wait a bit for instance termination to complete
                    sleep 10
                    
                    if aws ec2 delete-security-group --group-id "$sg" --region "$AWS_REGION" 2>/dev/null; then
                        log_success "Security group deleted: $sg"
                    else
                        log_warning "Could not delete security group: $sg (may be in use or have dependencies)"
                    fi
                fi
            fi
        done
    fi
    
    log_success "Direct resource destruction completed"
}

# Show destruction summary
show_destruction_summary() {
    log_header "Destruction Summary"
    
    echo "Repository: $GITHUB_USERNAME/$REPOSITORY_NAME"
    echo "Instance Name: ${INSTANCE_NAME:-N/A}"
    echo "Instance ID: ${INSTANCE_ID:-N/A}"
    echo "AWS Region: $AWS_REGION"
    
    if [ "$DRY_RUN" = true ]; then
        echo ""
        echo "DRY RUN COMPLETED - No resources were actually destroyed"
        echo "Run without --dry-run to perform actual destruction"
    else
        echo ""
        echo "Resources destroyed:"
        echo "  ✓ EC2 instance (if found)"
        echo "  ✓ Security groups (if repository-specific)"
        echo "  ✓ Elastic IP (if allocated)"
        echo "  ✓ Auto Scaling Group (if configured)"
        echo "  ✓ GitHub runner registration (if PAT provided)"
        
        echo ""
        echo "Manual cleanup may be needed for:"
        echo "  - CloudWatch logs (if enabled)"
        echo "  - IAM roles and policies (if created separately)"
        echo "  - VPC resources (if dedicated VPC was used)"
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
        -R|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -p|--pat)
            GITHUB_PAT="$2"
            shift 2
            ;;
        --no-runner-cleanup)
            CLEANUP_RUNNER=false
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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
    
    # Find repository instance
    if ! find_repository_instance; then
        log_warning "No repository instance found to destroy"
        if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
            echo ""
            read -p "Continue with cleanup anyway? (y/N): " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Operation cancelled by user"
                exit 0
            fi
        fi
    fi
    
    # Get associated resources
    get_associated_resources
    
    # Unregister GitHub runner
    unregister_github_runner
    
    # Check for Terraform state
    check_terraform_state
    
    # Confirm destruction
    if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
        echo ""
        log_warning "This will permanently destroy the repository runner and all associated resources!"
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled by user"
            exit 0
        fi
    fi
    
    # Destroy resources
    if [ "$USE_TERRAFORM" = true ]; then
        if ! destroy_with_terraform; then
            log_warning "Terraform destruction failed - falling back to direct destruction"
            destroy_resources_directly
        fi
    else
        destroy_resources_directly
    fi
    
    # Show summary
    show_destruction_summary
    
    if [ "$DRY_RUN" = false ]; then
        log_success "Repository runner destruction completed successfully"
    else
        log_success "Dry run completed successfully"
    fi
}

# Execute main function
main "$@"