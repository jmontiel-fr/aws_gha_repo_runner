#!/bin/bash

# Configure Repository Runner Script
# This script configures a GitHub Actions runner on an existing EC2 instance
# for a specific repository with proper validation and error handling.

set -e

# Script version and metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="Configure Repository Runner"

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
VALIDATION_LIB="$SCRIPT_DIR/repo-validation-functions.sh"

# Configuration variables
GITHUB_USERNAME=""
REPOSITORY_NAME=""
INSTANCE_ID=""
GITHUB_PAT=""
RUNNER_NAME="gha_aws_runner"
AWS_REGION="us-east-1"
KEY_PAIR_NAME=""
FORCE=false
DRY_RUN=false

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
    Configures a GitHub Actions runner on an existing EC2 instance for a specific
    repository. Handles runner registration, service setup, and validation.

REQUIRED OPTIONS:
    -u, --username USERNAME     GitHub username
    -r, --repository REPO       Repository name
    -i, --instance-id ID        EC2 instance ID
    -p, --pat TOKEN            GitHub Personal Access Token

OPTIONAL OPTIONS:
    -n, --runner-name NAME      Runner name (default: gha_aws_runner)
    -R, --region REGION         AWS region (default: us-east-1)
    -k, --key-pair KEY         AWS key pair name for SSH
    
    --force                    Skip confirmation prompts
    --dry-run                  Show what would be done without executing
    
    -h, --help                 Show this help message
    -v, --version              Show script version

EXAMPLES:
    # Basic runner configuration
    $0 --username johndoe --repository my-app \\
       --instance-id i-1234567890abcdef0 \\
       --pat ghp_xxxxxxxxxxxxxxxxxxxx

    # Configuration with custom runner name
    $0 --username johndoe --repository api-service \\
       --instance-id i-0987654321fedcba0 \\
       --pat ghp_xxxxxxxxxxxxxxxxxxxx \\
       --runner-name api-runner

    # Dry run to see what would be configured
    $0 --username johndoe --repository my-app \\
       --instance-id i-1234567890abcdef0 \\
       --pat ghp_xxxxxxxxxxxxxxxxxxxx \\
       --dry-run

PREREQUISITES:
    - AWS CLI configured with appropriate permissions
    - EC2 instance running and accessible via SSH
    - GitHub repository with admin permissions
    - GitHub PAT with repo scope

EOF
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    for tool in aws ssh jq curl; do
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
    
    # Check validation library
    if [ ! -f "$VALIDATION_LIB" ]; then
        log_error "Validation library not found: $VALIDATION_LIB"
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
    
    if [ -z "$INSTANCE_ID" ]; then
        log_error "Instance ID is required (--instance-id)"
        return 1
    fi
    
    if [ -z "$GITHUB_PAT" ]; then
        log_error "GitHub PAT is required (--pat)"
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
    
    # Check if instance exists
    if ! aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" &> /dev/null; then
        log_error "Instance '$INSTANCE_ID' not found in region $AWS_REGION"
        return 1
    fi
    
    log_success "Parameters validated"
    return 0
}

# Validate repository access
validate_repository_access() {
    log_info "Validating repository access..."
    
    # Source validation library
    source "$VALIDATION_LIB"
    
    # Validate repository configuration
    if validate_repository_configuration "$GITHUB_USERNAME" "$REPOSITORY_NAME" "$GITHUB_PAT"; then
        log_success "Repository access validated"
        return 0
    else
        log_error "Repository access validation failed"
        return 1
    fi
}

# Get instance information
get_instance_info() {
    log_info "Getting instance information..."
    
    local instance_info
    instance_info=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" 2>&1)
    
    if [ $? -ne 0 ]; then
        log_error "Failed to get instance information: $instance_info"
        return 1
    fi
    
    local instance_state
    instance_state=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].State.Name')
    
    local public_ip
    public_ip=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].PublicIpAddress // "none"')
    
    local instance_name
    instance_name=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].Tags[]? | select(.Key=="Name") | .Value // "unnamed"')
    
    echo "Instance ID: $INSTANCE_ID"
    echo "Instance Name: $instance_name"
    echo "Instance State: $instance_state"
    echo "Public IP: $public_ip"
    
    if [ "$instance_state" != "running" ]; then
        log_warning "Instance is not running (state: $instance_state)"
        
        if [ "$FORCE" = false ]; then
            echo ""
            read -p "Do you want to start the instance? (y/N): " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "Starting instance..."
                aws ec2 start-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
                aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
                log_success "Instance started"
                
                # Get updated IP
                public_ip=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" \
                    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
                echo "Updated Public IP: $public_ip"
            else
                log_error "Instance must be running to configure runner"
                return 1
            fi
        fi
    fi
    
    if [ "$public_ip" = "none" ] || [ "$public_ip" = "null" ]; then
        log_error "Instance has no public IP address"
        return 1
    fi
    
    # Export for use in other functions
    export INSTANCE_PUBLIC_IP="$public_ip"
    
    log_success "Instance information retrieved"
    return 0
}

# Test SSH connectivity
test_ssh_connectivity() {
    log_info "Testing SSH connectivity..."
    
    if [ -z "$INSTANCE_PUBLIC_IP" ]; then
        log_error "Instance public IP not available"
        return 1
    fi
    
    # Test SSH port
    if ! nc -z -w5 "$INSTANCE_PUBLIC_IP" 22 2>/dev/null; then
        log_error "SSH port (22) not accessible on $INSTANCE_PUBLIC_IP"
        log_error "Check security group rules and instance state"
        return 1
    fi
    
    # Test SSH connection
    local ssh_key_option=""
    if [ -n "$KEY_PAIR_NAME" ]; then
        ssh_key_option="-i ~/.ssh/${KEY_PAIR_NAME}.pem"
    fi
    
    if ssh $ssh_key_option -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@"$INSTANCE_PUBLIC_IP" "echo 'SSH connection successful'" 2>/dev/null; then
        log_success "SSH connectivity confirmed"
        return 0
    else
        log_error "SSH connection failed to ubuntu@$INSTANCE_PUBLIC_IP"
        log_error "Check SSH key configuration and security groups"
        return 1
    fi
}

# Generate registration token
generate_registration_token() {
    log_info "Generating runner registration token..."
    
    local token_response
    token_response=$(curl -s -w "%{http_code}" -X POST \
        -H "Authorization: token $GITHUB_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$REPOSITORY_NAME/actions/runners/registration-token")
    
    local http_code="${token_response: -3}"
    local token_body="${token_response%???}"
    
    case $http_code in
        201)
            local token=$(echo "$token_body" | jq -r '.token')
            local expires_at=$(echo "$token_body" | jq -r '.expires_at')
            
            if [ "$token" != "null" ] && [ -n "$token" ]; then
                log_success "Registration token generated successfully"
                log_info "Token expires at: $expires_at"
                export REGISTRATION_TOKEN="$token"
                return 0
            else
                log_error "Invalid registration token received"
                return 1
            fi
            ;;
        403)
            log_error "Insufficient permissions to generate registration token"
            log_error "Ensure PAT has repo scope and you have admin access to the repository"
            return 1
            ;;
        404)
            log_error "Repository not found or Actions not enabled"
            return 1
            ;;
        *)
            log_error "Failed to generate registration token (HTTP $http_code)"
            log_error "Response: $token_body"
            return 1
            ;;
    esac
}

# Configure runner on instance
configure_runner() {
    log_info "Configuring runner on EC2 instance..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would configure runner with the following settings:"
        echo "  Repository: https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME"
        echo "  Runner Name: $RUNNER_NAME"
        echo "  Instance: $INSTANCE_PUBLIC_IP"
        echo "  Labels: self-hosted,gha_aws_runner"
        return 0
    fi
    
    local ssh_key_option=""
    if [ -n "$KEY_PAIR_NAME" ]; then
        ssh_key_option="-i ~/.ssh/${KEY_PAIR_NAME}.pem"
    fi
    
    # Create configuration script
    local config_script=$(cat << 'EOF'
#!/bin/bash
set -e

GITHUB_USERNAME="$1"
REPOSITORY_NAME="$2"
REGISTRATION_TOKEN="$3"
RUNNER_NAME="$4"

echo "=== Configuring GitHub Actions Runner ==="
echo "Repository: https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME"
echo "Runner Name: $RUNNER_NAME"
echo "Timestamp: $(date)"

# Check if actions-runner directory exists
if [ ! -d ~/actions-runner ]; then
    echo "Creating actions-runner directory..."
    mkdir -p ~/actions-runner
    cd ~/actions-runner
    
    # Download latest runner
    echo "Downloading GitHub Actions runner..."
    RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
    curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
        "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
    
    tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
    rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
    
    # Install dependencies
    sudo ./bin/installdependencies.sh
else
    cd ~/actions-runner
fi

# Stop existing service if running
echo "Stopping existing runner service..."
sudo ./svc.sh stop 2>/dev/null || true
sudo ./svc.sh uninstall 2>/dev/null || true

# Remove existing configuration
echo "Removing existing runner configuration..."
./config.sh remove --token "$REGISTRATION_TOKEN" 2>/dev/null || true

# Configure new runner
echo "Configuring new runner..."
./config.sh \
    --url "https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME" \
    --token "$REGISTRATION_TOKEN" \
    --name "$RUNNER_NAME" \
    --labels "self-hosted,gha_aws_runner" \
    --work "_work" \
    --unattended \
    --replace

# Install and start service
echo "Installing and starting runner service..."
sudo ./svc.sh install ubuntu
sudo ./svc.sh start

# Verify service status
echo "Verifying runner service status..."
sudo ./svc.sh status

echo "=== Runner Configuration Complete ==="
echo "Runner '$RUNNER_NAME' configured for repository: $GITHUB_USERNAME/$REPOSITORY_NAME"
EOF
)
    
    # Execute configuration on remote instance
    log_info "Executing configuration on remote instance..."
    echo "$config_script" | ssh $ssh_key_option -o StrictHostKeyChecking=no ubuntu@"$INSTANCE_PUBLIC_IP" \
        "bash -s -- '$GITHUB_USERNAME' '$REPOSITORY_NAME' '$REGISTRATION_TOKEN' '$RUNNER_NAME'"
    
    if [ $? -eq 0 ]; then
        log_success "Runner configured successfully"
        return 0
    else
        log_error "Runner configuration failed"
        return 1
    fi
}

# Verify runner registration
verify_runner_registration() {
    log_info "Verifying runner registration..."
    
    # Wait a moment for registration to complete
    sleep 5
    
    local runners_response
    runners_response=$(curl -s -H "Authorization: token $GITHUB_PAT" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$REPOSITORY_NAME/actions/runners")
    
    local runner_found=false
    local runner_status=""
    
    if echo "$runners_response" | jq -e '.runners[]' > /dev/null 2>&1; then
        while IFS= read -r runner; do
            local name=$(echo "$runner" | jq -r '.name')
            local status=$(echo "$runner" | jq -r '.status')
            local labels=$(echo "$runner" | jq -r '.labels[].name' | tr '\n' ',' | sed 's/,$//')
            
            if [ "$name" = "$RUNNER_NAME" ]; then
                runner_found=true
                runner_status="$status"
                echo "Runner found: $name"
                echo "Status: $status"
                echo "Labels: $labels"
                break
            fi
        done < <(echo "$runners_response" | jq -c '.runners[]')
    fi
    
    if [ "$runner_found" = true ]; then
        if [ "$runner_status" = "online" ]; then
            log_success "Runner is online and ready"
            return 0
        else
            log_warning "Runner is registered but status is: $runner_status"
            log_warning "It may take a few moments to come online"
            return 0
        fi
    else
        log_error "Runner not found in repository"
        return 1
    fi
}

# Show configuration summary
show_configuration_summary() {
    log_header "Configuration Summary"
    
    echo "Repository: $GITHUB_USERNAME/$REPOSITORY_NAME"
    echo "Runner Name: $RUNNER_NAME"
    echo "Instance ID: $INSTANCE_ID"
    echo "Instance IP: $INSTANCE_PUBLIC_IP"
    echo "AWS Region: $AWS_REGION"
    
    echo ""
    echo "Repository URL: https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME"
    echo "Runner Settings: https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME/settings/actions/runners"
    
    echo ""
    echo "SSH Connection: ssh ubuntu@$INSTANCE_PUBLIC_IP"
    if [ -n "$KEY_PAIR_NAME" ]; then
        echo "SSH with key: ssh -i ~/.ssh/${KEY_PAIR_NAME}.pem ubuntu@$INSTANCE_PUBLIC_IP"
    fi
    
    echo ""
    echo "Next Steps:"
    echo "1. Verify runner appears in repository settings"
    echo "2. Test runner with a simple workflow"
    echo "3. Monitor runner logs if needed: ssh ubuntu@$INSTANCE_PUBLIC_IP 'sudo journalctl -u actions.runner.* -f'"
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
        -i|--instance-id)
            INSTANCE_ID="$2"
            shift 2
            ;;
        -p|--pat)
            GITHUB_PAT="$2"
            shift 2
            ;;
        -n|--runner-name)
            RUNNER_NAME="$2"
            shift 2
            ;;
        -R|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -k|--key-pair)
            KEY_PAIR_NAME="$2"
            shift 2
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
    
    # Validate repository access
    if ! validate_repository_access; then
        exit 1
    fi
    
    # Get instance information
    if ! get_instance_info; then
        exit 1
    fi
    
    # Test SSH connectivity
    if ! test_ssh_connectivity; then
        exit 1
    fi
    
    # Generate registration token
    if ! generate_registration_token; then
        exit 1
    fi
    
    # Configure runner
    if ! configure_runner; then
        exit 1
    fi
    
    # Verify registration (only if not dry run)
    if [ "$DRY_RUN" = false ]; then
        if ! verify_runner_registration; then
            log_warning "Runner configuration completed but verification failed"
            log_warning "Check repository settings manually"
        fi
    fi
    
    # Show summary
    show_configuration_summary
    
    log_success "Repository runner configuration completed successfully"
}

# Execute main function
main "$@"