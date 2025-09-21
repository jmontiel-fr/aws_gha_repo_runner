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
SYSTEM_READINESS_LIB="$SCRIPT_DIR/system-readiness-functions.sh"
PACKAGE_MANAGER_LIB="$SCRIPT_DIR/package-manager-functions.sh"
ERROR_HANDLER_LIB="$SCRIPT_DIR/installation-error-handler.sh"

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
    
    # Check required libraries
    local required_libs=(
        "$VALIDATION_LIB"
        "$SYSTEM_READINESS_LIB"
        "$PACKAGE_MANAGER_LIB"
        "$ERROR_HANDLER_LIB"
    )
    
    for lib in "${required_libs[@]}"; do
        if [ ! -f "$lib" ]; then
            log_error "Required library not found: $lib"
            return 1
        fi
    done
    
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
    
    # Set up SSH key option
    local ssh_key_option=""
    if [ -n "$KEY_PAIR_NAME" ]; then
        ssh_key_option="-i ~/.ssh/${KEY_PAIR_NAME}.pem"
        
        # Check if key file exists
        if [ ! -f ~/.ssh/${KEY_PAIR_NAME}.pem ]; then
            log_error "SSH key file not found: ~/.ssh/${KEY_PAIR_NAME}.pem"
            log_error "Make sure the key pair was created properly"
            return 1
        fi
    fi
    
    # Test SSH connection with more robust error handling
    log_info "Attempting SSH connection to ubuntu@$INSTANCE_PUBLIC_IP..."
    
    if ssh $ssh_key_option -o ConnectTimeout=15 -o StrictHostKeyChecking=no -o BatchMode=yes ubuntu@"$INSTANCE_PUBLIC_IP" "echo 'SSH connection successful'" 2>/dev/null; then
        log_success "SSH connectivity confirmed"
        return 0
    else
        log_warning "Direct SSH test failed, but this might be due to environment issues"
        log_info "Proceeding with configuration attempt..."
        log_info "If configuration fails, check:"
        log_info "  - Security group allows SSH from your IP: $(curl -s -4 icanhazip.com 2>/dev/null || echo 'unknown')"
        log_info "  - Instance is running and accessible"
        log_info "  - SSH key file exists: ~/.ssh/${KEY_PAIR_NAME}.pem"
        return 0  # Continue anyway, let the actual configuration attempt fail if there's a real issue
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
    
    # Create enhanced configuration script with robust installation
    local config_script=$(cat << 'EOF'
#!/bin/bash
set -e

# Enhanced GitHub Actions Runner Configuration Script
# This script uses robust installation methods with system readiness validation,
# package manager monitoring, and comprehensive error handling.

GITHUB_USERNAME="$1"
REPOSITORY_NAME="$2"
REGISTRATION_TOKEN="$3"
RUNNER_NAME="$4"

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

# Installation start time for metrics
INSTALL_START_TIME=$(date +%s)

echo "==============================================================================="
echo "ENHANCED GITHUB ACTIONS RUNNER CONFIGURATION"
echo "==============================================================================="
echo "Repository: https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME"
echo "Runner Name: $RUNNER_NAME"
echo "Timestamp: $(date)"
echo "Installation ID: $(date +%s)-$$"
echo ""

# =============================================================================
# System Readiness Validation Functions (Embedded)
# =============================================================================

# Check if cloud-init has completed
check_cloud_init_status() {
    if ! command -v cloud-init &> /dev/null; then
        return 0  # cloud-init not installed, assume complete
    fi
    
    local status_output
    if status_output=$(cloud-init status 2>&1); then
        if echo "$status_output" | grep -q "status: done"; then
            return 0
        elif echo "$status_output" | grep -q "status: running"; then
            return 1
        elif echo "$status_output" | grep -q "status: error"; then
            log_warning "cloud-init completed with errors"
            return 0  # Continue anyway
        fi
    fi
    
    # Alternative checks
    if pgrep -f "cloud-init" > /dev/null; then
        return 1
    fi
    
    if [ -f /var/lib/cloud/instance/boot-finished ]; then
        return 0
    fi
    
    return 0  # Assume complete if can't determine
}

# Wait for cloud-init to complete
wait_for_cloud_init() {
    local timeout=${1:-600}  # 10 minutes default
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    log_info "Checking cloud-init status (timeout: ${timeout}s)"
    
    if check_cloud_init_status; then
        log_success "cloud-init is already complete"
        return 0
    fi
    
    log_info "cloud-init is running, waiting for completion..."
    local dots=""
    
    while [ $(date +%s) -lt $end_time ]; do
        if check_cloud_init_status; then
            echo ""
            log_success "cloud-init completed successfully"
            return 0
        fi
        
        dots="${dots}."
        if [ ${#dots} -gt 3 ]; then
            dots="."
        fi
        printf "\r${BLUE}[INFO]${NC} Waiting for cloud-init to complete${dots}   "
        
        sleep 10
    done
    
    echo ""
    log_warning "Timeout waiting for cloud-init, continuing anyway"
    return 1
}

# =============================================================================
# Package Manager Monitoring Functions (Embedded)
# =============================================================================

# Check if package managers are busy
check_package_managers() {
    # Check for apt processes
    if pgrep -f "apt\|dpkg\|unattended-upgrade" > /dev/null; then
        return 0  # busy
    fi
    
    # Check for dpkg locks
    local lock_files=(
        "/var/lib/dpkg/lock"
        "/var/lib/dpkg/lock-frontend"
        "/var/cache/apt/archives/lock"
        "/var/lib/apt/lists/lock"
    )
    
    for lock_file in "${lock_files[@]}"; do
        if [ -f "$lock_file" ]; then
            if ! flock -n 9 2>/dev/null 9<"$lock_file"; then
                return 0  # locked
            fi
        fi
    done
    
    return 1  # free
}

# Wait for package managers to become available
wait_for_package_managers() {
    local timeout=${1:-300}  # 5 minutes default
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    log_info "Checking package manager availability (timeout: ${timeout}s)"
    
    if ! check_package_managers; then
        log_success "Package managers are already available"
        return 0
    fi
    
    log_info "Package managers are busy, waiting for availability..."
    
    local current_wait=0
    while [ $(date +%s) -lt $end_time ]; do
        if ! check_package_managers; then
            echo ""
            log_success "Package managers are now available"
            return 0
        fi
        
        # Show progress
        local percentage=$((current_wait * 100 / timeout))
        printf "\r${BLUE}[INFO]${NC} Waiting for package managers... %d%% (%ds remaining)" \
            "$percentage" "$((timeout - current_wait))"
        
        sleep 10
        current_wait=$((current_wait + 10))
    done
    
    echo ""
    log_warning "Timeout waiting for package managers, attempting to continue"
    return 1
}

# Install packages with retry
install_with_retry() {
    local command="$1"
    local max_retries=3
    local base_delay=30
    
    log_info "Installing with retry: $command"
    
    for ((retry=0; retry<=max_retries; retry++)); do
        if [ $retry -eq 0 ]; then
            log_info "Attempt $((retry + 1))/$((max_retries + 1)): $command"
        else
            log_info "Retry $retry/$max_retries: $command"
        fi
        
        # Wait for package managers before each attempt
        wait_for_package_managers 120
        
        # Set environment for non-interactive installation
        export DEBIAN_FRONTEND=noninteractive
        export NEEDRESTART_MODE=a
        
        if sudo -E bash -c "$command"; then
            if [ $retry -eq 0 ]; then
                log_success "Installation succeeded on first attempt"
            else
                log_success "Installation succeeded after $retry retries"
            fi
            return 0
        fi
        
        local exit_code=$?
        
        if [ $retry -lt $max_retries ]; then
            local delay=$((base_delay * (1 << retry)))
            if [ $delay -gt 300 ]; then
                delay=300  # Cap at 5 minutes
            fi
            
            log_warning "Installation failed (exit code: $exit_code), retrying in ${delay}s..."
            
            # Show countdown
            for ((i=delay; i>0; i--)); do
                printf "\r${YELLOW}[WARNING]${NC} Retrying in %ds..." "$i"
                sleep 1
            done
            echo ""
        else
            log_error "Installation failed after $max_retries retries (exit code: $exit_code)"
            return 1
        fi
    done
    
    return 1
}

# =============================================================================
# Enhanced Runner Installation Process
# =============================================================================

# Step 1: System Readiness Validation
log_info "=== Step 1: System Readiness Validation ==="
if ! wait_for_cloud_init 600; then
    log_warning "Cloud-init validation completed with timeout, continuing"
fi

# Check basic system resources
log_info "Checking system resources..."
available_mb=$(df -m / | awk 'NR==2 {print $4}')
if [ "$available_mb" -lt 2048 ]; then
    log_error "Insufficient disk space (${available_mb}MB available, 2048MB required)"
    exit 1
else
    log_success "Sufficient disk space available (${available_mb}MB)"
fi

log_success "System readiness validation completed"

# Step 2: Package Manager Preparation
log_info "=== Step 2: Package Manager Preparation ==="
if ! wait_for_package_managers 300; then
    log_warning "Package managers may still be busy, attempting to continue"
fi

# Update package lists with retry
log_info "Updating package lists..."
if ! install_with_retry "sudo apt-get update -y"; then
    log_error "Failed to update package lists after retries"
    exit 1
fi

log_success "Package manager preparation completed"

# Step 3: Runner Directory Setup
log_info "=== Step 3: Runner Directory Setup ==="
RUNNER_DIR="$HOME/actions-runner"

if [ ! -d "$RUNNER_DIR" ]; then
    log_info "Creating actions-runner directory..."
    mkdir -p "$RUNNER_DIR"
    cd "$RUNNER_DIR"
    
    # Download latest runner
    log_info "Downloading GitHub Actions runner..."
    RUNNER_VERSION=$(curl -s --max-time 30 https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
    
    if [ -z "$RUNNER_VERSION" ] || [ "$RUNNER_VERSION" = "null" ]; then
        log_error "Failed to get runner version from GitHub API"
        exit 1
    fi
    
    log_info "Downloading runner version: $RUNNER_VERSION"
    RUNNER_ARCHIVE="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
    DOWNLOAD_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_ARCHIVE}"
    
    if ! curl -o "$RUNNER_ARCHIVE" -L --max-time 300 "$DOWNLOAD_URL"; then
        log_error "Failed to download GitHub Actions runner"
        exit 1
    fi
    
    log_info "Extracting runner archive..."
    if ! tar xzf "./$RUNNER_ARCHIVE"; then
        log_error "Failed to extract runner archive"
        exit 1
    fi
    
    rm "$RUNNER_ARCHIVE"
    log_success "Runner downloaded and extracted successfully"
    
    # Install dependencies with enhanced retry
    log_info "Installing runner dependencies..."
    if ! install_with_retry "./bin/installdependencies.sh"; then
        log_error "Failed to install runner dependencies after retries"
        exit 1
    fi
    
    log_success "Runner dependencies installed successfully"
else
    log_info "Using existing runner directory: $RUNNER_DIR"
    cd "$RUNNER_DIR"
fi

# Step 4: Service Management
log_info "=== Step 4: Service Management ==="

# Stop existing service if running
log_info "Stopping existing runner service..."
sudo ./svc.sh stop 2>/dev/null || true
sudo ./svc.sh uninstall 2>/dev/null || true

# Remove existing configuration
log_info "Removing existing runner configuration..."
./config.sh remove --token "$REGISTRATION_TOKEN" 2>/dev/null || true

# Step 5: Runner Configuration
log_info "=== Step 5: Runner Configuration ==="
log_info "Configuring new runner..."

REPO_URL="https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME"
log_info "Repository URL: $REPO_URL"
log_info "Runner Name: $RUNNER_NAME"
log_info "Labels: self-hosted,gha_aws_runner"

if ! ./config.sh \
    --url "$REPO_URL" \
    --token "$REGISTRATION_TOKEN" \
    --name "$RUNNER_NAME" \
    --labels "self-hosted,gha_aws_runner" \
    --work "_work" \
    --unattended \
    --replace; then
    log_error "Failed to configure runner"
    exit 1
fi

log_success "Runner configured successfully"

# Step 6: Service Installation and Startup
log_info "=== Step 6: Service Installation and Startup ==="
log_info "Installing runner service..."

if ! sudo ./svc.sh install ubuntu; then
    log_error "Failed to install runner service"
    exit 1
fi

log_info "Starting runner service..."
if ! sudo ./svc.sh start; then
    log_error "Failed to start runner service"
    exit 1
fi

# Verify service status
log_info "Verifying runner service status..."
sleep 3

if sudo ./svc.sh status | grep -q "active (running)"; then
    log_success "Runner service is active and running"
else
    log_error "Runner service failed to start properly"
    sudo ./svc.sh status
    exit 1
fi

# Step 7: Installation Summary
INSTALL_END_TIME=$(date +%s)
INSTALL_DURATION=$((INSTALL_END_TIME - INSTALL_START_TIME))

echo ""
echo "==============================================================================="
echo "RUNNER CONFIGURATION COMPLETED SUCCESSFULLY"
echo "==============================================================================="
echo "Repository: $GITHUB_USERNAME/$REPOSITORY_NAME"
echo "Runner Name: $RUNNER_NAME"
echo "Installation Duration: ${INSTALL_DURATION}s"
echo "Completion Time: $(date)"
echo ""
# Step 8: Post-Installation Verification
log_info "=== Step 8: Post-Installation Verification ==="

# Verify runner dependencies
log_info "Verifying runner dependencies..."
missing_deps=()
required_commands=("curl" "tar" "ps" "id" "systemctl")

for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        missing_deps+=("$cmd")
    fi
done

if [ ${#missing_deps[@]} -eq 0 ]; then
    log_success "All runner dependencies are installed"
else
    log_warning "Missing dependencies: ${missing_deps[*]}"
fi

# Verify runner service is properly configured
log_info "Verifying runner service configuration..."
if [ -f "$RUNNER_DIR/.runner" ]; then
    log_success "Runner configuration file exists"
else
    log_warning "Runner configuration file not found"
fi

if [ -f "$RUNNER_DIR/.credentials" ]; then
    log_success "Runner credentials file exists"
else
    log_warning "Runner credentials file not found"
fi

# Final service status check
log_info "Final service status verification..."
if sudo ./svc.sh status | grep -q "active (running)"; then
    log_success "Runner service is confirmed active and running"
else
    log_warning "Runner service status unclear"
    sudo ./svc.sh status
fi

log_success "Post-installation verification completed"

echo ""
echo "==============================================================================="
echo "ENHANCED RUNNER CONFIGURATION COMPLETED SUCCESSFULLY"
echo "==============================================================================="
echo "Repository: $GITHUB_USERNAME/$REPOSITORY_NAME"
echo "Runner Name: $RUNNER_NAME"
echo "Installation Duration: ${INSTALL_DURATION}s"
echo "Completion Time: $(date)"
echo ""
echo "✓ System readiness validated"
echo "✓ Package managers monitored and conflicts resolved"
echo "✓ Dependencies installed with retry mechanisms"
echo "✓ Runner configured and service started"
echo "✓ Post-installation verification completed"
echo ""
echo "The runner is now configured and running. It should appear in your repository's"
echo "Actions settings within a few moments."
echo ""
echo "Repository Settings: https://github.com/$GITHUB_USERNAME/$REPOSITORY_NAME/settings/actions/runners"
echo "==============================================================================="
EOF
)
    
    # Execute configuration on remote instance
    log_info "Executing configuration on remote instance..."
    log_info "SSH command: ssh $ssh_key_option ubuntu@$INSTANCE_PUBLIC_IP"
    
    # Execute enhanced configuration on remote instance
    log_info "Executing enhanced configuration with robust installation process..."
    
    if echo "$config_script" | ssh $ssh_key_option -o ConnectTimeout=60 -o StrictHostKeyChecking=no ubuntu@"$INSTANCE_PUBLIC_IP" \
        "bash -s -- '$GITHUB_USERNAME' '$REPOSITORY_NAME' '$REGISTRATION_TOKEN' '$RUNNER_NAME'" 2>&1; then
        log_success "Enhanced runner configuration completed successfully"
        return 0
    else
        local exit_code=$?
        log_error "Enhanced runner configuration failed (exit code: $exit_code)"
        
        # Use enhanced error handling
        handle_installation_error "RUNNER_CONFIG_FAILED" \
            "Runner configuration failed during remote execution" \
            "SSH command failed with exit code $exit_code" \
            "$GITHUB_USERNAME" "$REPOSITORY_NAME" "$GITHUB_PAT"
        
        log_error "Additional troubleshooting steps:"
        log_error "  1. Verify SSH access: ssh $ssh_key_option ubuntu@$INSTANCE_PUBLIC_IP"
        log_error "  2. Check instance console output: aws ec2 get-console-output --instance-id $INSTANCE_ID --region $AWS_REGION"
        log_error "  3. Verify security group allows SSH from your IP: $(curl -s -4 icanhazip.com 2>/dev/null || echo 'unknown')"
        log_error "  4. Check instance system logs: ssh $ssh_key_option ubuntu@$INSTANCE_PUBLIC_IP 'sudo journalctl -xe'"
        
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
    local start_time=$(date +%s)
    
    echo "=== $SCRIPT_NAME v$SCRIPT_VERSION ==="
    echo "Enhanced with robust installation and comprehensive error handling"
    echo ""
    
    # Load enhanced libraries first (before any function calls)
    if [ -f "$SYSTEM_READINESS_LIB" ]; then
        source "$SYSTEM_READINESS_LIB"
    fi
    if [ -f "$PACKAGE_MANAGER_LIB" ]; then
        source "$PACKAGE_MANAGER_LIB"
    fi
    if [ -f "$ERROR_HANDLER_LIB" ]; then
        source "$ERROR_HANDLER_LIB"
    fi
    
    # Show installation progress
    show_installation_progress "Starting Configuration" 1 7 "Initializing enhanced runner configuration process"
    
    # Validate prerequisites
    show_installation_progress "Validating Prerequisites" 2 7 "Checking required tools and AWS credentials"
    if ! validate_prerequisites; then
        handle_installation_error "SYSTEM_NOT_READY" "Prerequisites validation failed" "Missing required tools or AWS credentials"
        exit 1
    fi
    
    # Validate parameters
    show_installation_progress "Validating Parameters" 3 7 "Checking GitHub username, repository, and instance details"
    if ! validate_parameters; then
        handle_installation_error "SYSTEM_NOT_READY" "Parameter validation failed" "Invalid or missing required parameters"
        exit 1
    fi
    
    # Validate repository access
    show_installation_progress "Validating Repository Access" 4 7 "Checking GitHub repository permissions and Actions availability"
    if ! validate_repository_access; then
        handle_installation_error "GITHUB_AUTH_FAILED" "Repository access validation failed" "Cannot access repository or insufficient permissions"
        exit 1
    fi
    
    # Get instance information
    show_installation_progress "Getting Instance Information" 5 7 "Retrieving EC2 instance details and status"
    if ! get_instance_info; then
        handle_installation_error "SYSTEM_NOT_READY" "Failed to get instance information" "Cannot retrieve EC2 instance details"
        exit 1
    fi
    
    # Test SSH connectivity
    if ! test_ssh_connectivity; then
        exit 1
    fi
    
    # Validate system readiness on remote instance
    log_info "Validating remote system readiness..."
    local ssh_key_option=""
    if [ -n "$KEY_PAIR_NAME" ]; then
        ssh_key_option="-i ~/.ssh/${KEY_PAIR_NAME}.pem"
    fi
    
    # Create a simple system readiness check script
    local readiness_check=$(cat << 'READINESS_EOF'
#!/bin/bash
# Quick system readiness check
echo "Performing system readiness check..."

# Check if cloud-init is complete
if command -v cloud-init &> /dev/null; then
    if cloud-init status 2>&1 | grep -q "status: running"; then
        echo "WARNING: cloud-init is still running"
        echo "This may cause package installation conflicts"
    else
        echo "cloud-init status: OK"
    fi
else
    echo "cloud-init: Not installed (OK)"
fi

# Check package managers
if pgrep -f "apt\|dpkg\|unattended-upgrade" > /dev/null; then
    echo "WARNING: Package managers are currently busy"
    echo "Active processes:"
    pgrep -f "apt\|dpkg\|unattended-upgrade" | while read pid; do
        ps -p $pid -o pid,cmd --no-headers 2>/dev/null || echo "  PID $pid (process ended)"
    done
else
    echo "Package managers: Available"
fi

# Check disk space
available_mb=$(df -m / | awk 'NR==2 {print $4}')
if [ "$available_mb" -lt 2048 ]; then
    echo "ERROR: Insufficient disk space (${available_mb}MB available, 2048MB required)"
    exit 1
else
    echo "Disk space: OK (${available_mb}MB available)"
fi

echo "System readiness check completed"
READINESS_EOF
)
    
    # Execute readiness check on remote instance
    if echo "$readiness_check" | ssh $ssh_key_option -o ConnectTimeout=30 -o StrictHostKeyChecking=no ubuntu@"$INSTANCE_PUBLIC_IP" "bash -s" 2>&1; then
        log_success "Remote system readiness validation passed"
    else
        log_warning "Remote system readiness check completed with warnings"
        log_info "Proceeding with enhanced installation process to handle any issues"
    fi
    
    # Generate registration token
    show_installation_progress "Generating Registration Token" 6 7 "Creating GitHub Actions runner registration token"
    if ! generate_registration_token; then
        handle_installation_error "GITHUB_AUTH_FAILED" "Failed to generate registration token" "Cannot create runner registration token"
        exit 1
    fi
    
    # Configure runner
    show_installation_progress "Configuring Runner" 7 7 "Installing and configuring GitHub Actions runner on EC2 instance"
    local start_time=$(date +%s)
    if ! configure_runner; then
        exit 1
    fi
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Verify registration (only if not dry run)
    if [ "$DRY_RUN" = false ]; then
        if ! verify_runner_registration; then
            log_warning "Runner configuration completed but verification failed"
            log_warning "Check repository settings manually"
        fi
    fi
    
    # Show completion summary
    local total_time=$(($(date +%s) - start_time))
    show_completion_summary "true" "$total_time" 0
    
    # Show configuration summary
    show_configuration_summary
    
    log_success "Enhanced repository runner configuration completed successfully"
    log_info "Configuration completed with robust installation process and comprehensive error handling"
}

# Execute main function
main "$@"