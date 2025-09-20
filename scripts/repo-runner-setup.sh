#!/bin/bash
set -e

# Repository-Level GitHub Actions Runner Setup Script
# This script configures a persistent GitHub Actions runner at the repository level
# making it available to a specific repository under a personal GitHub account.

# Script version and metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="Repository-Level GitHub Runner Setup"

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Configuration variables with defaults
GITHUB_USERNAME="${GITHUB_USERNAME:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GH_PAT="${GH_PAT:-}"
RUNNER_NAME="${RUNNER_NAME:-gha_aws_runner}"
RUNNER_LABELS="${RUNNER_LABELS:-gha_aws_runner,ubuntu-22.04}"
RUNNER_WORK_DIR="${RUNNER_WORK_DIR:-_work}"
RUNNER_VERSION="${RUNNER_VERSION:-2.311.0}"
RUNNER_ARCH="${RUNNER_ARCH:-linux-x64}"

# Source the validation functions library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/repo-validation-functions.sh" ]; then
    source "$SCRIPT_DIR/repo-validation-functions.sh"
else
    log_error "Validation functions library not found: $SCRIPT_DIR/repo-validation-functions.sh"
    exit 1
fi

# Script usage information
show_usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

USAGE:
    $0 [OPTIONS]

DESCRIPTION:
    Sets up a persistent GitHub Actions runner at the repository level.
    The runner will be available to the specified repository under your personal GitHub account.

REQUIRED ENVIRONMENT VARIABLES:
    GITHUB_USERNAME       GitHub username (personal account)
    GITHUB_REPOSITORY     Repository name (without username)
    GH_PAT               GitHub Personal Access Token with 'repo' scope

OPTIONAL ENVIRONMENT VARIABLES:
    RUNNER_NAME          Runner name (default: gha_aws_runner)
    RUNNER_LABELS        Comma-separated runner labels (default: gha_aws_runner,ubuntu-22.04)
    RUNNER_WORK_DIR      Runner work directory (default: _work)
    RUNNER_VERSION       GitHub Actions runner version (default: 2.311.0)
    RUNNER_ARCH          Runner architecture (default: linux-x64)

OPTIONS:
    -h, --help           Show this help message
    -v, --version        Show script version
    -d, --dry-run        Show what would be done without executing
    --validate-only      Only validate configuration without setting up runner
    --remove             Remove existing runner configuration
    --status             Show current runner status

EXAMPLES:
    # Basic setup
    export GITHUB_USERNAME="myusername"
    export GITHUB_REPOSITORY="my-repo"
    export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
    $0

    # Setup with custom runner name
    export GITHUB_USERNAME="myusername"
    export GITHUB_REPOSITORY="my-repo"
    export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
    export RUNNER_NAME="my-custom-runner"
    $0

    # Validate configuration only
    $0 --validate-only

    # Remove existing runner
    $0 --remove

PREREQUISITES:
    - Repository admin permissions on the target repository
    - GitHub PAT with 'repo' scope
    - curl and jq installed
    - Internet connectivity to GitHub API and download servers

EOF
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Additional required commands for runner setup (beyond what validation library checks)
    local additional_commands=("tar" "shasum")
    for cmd in "${additional_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' is not installed"
            return 1
        fi
    done
    
    # Check required environment variables
    if [ -z "$GITHUB_USERNAME" ]; then
        log_error "GITHUB_USERNAME environment variable is required"
        log_info "Set it with: export GITHUB_USERNAME='your-github-username'"
        return 1
    fi
    
    if [ -z "$GITHUB_REPOSITORY" ]; then
        log_error "GITHUB_REPOSITORY environment variable is required"
        log_info "Set it with: export GITHUB_REPOSITORY='your-repository-name'"
        return 1
    fi
    
    if [ -z "$GH_PAT" ]; then
        log_error "GH_PAT environment variable is required"
        log_info "Set it with: export GH_PAT='your-personal-access-token'"
        return 1
    fi
    
    # Validate username format using validation library
    if ! validate_username_format "$GITHUB_USERNAME"; then
        return 1
    fi
    
    # Validate repository name format using validation library
    if ! validate_repository_format "$GITHUB_REPOSITORY"; then
        return 1
    fi
    
    # Validate required tools using validation library
    if ! validate_required_tools; then
        return 1
    fi
    
    log_success "Prerequisites validation passed"
    return 0
}

# Validate GitHub PAT permissions and repository access using validation library
validate_github_permissions() {
    log_info "Validating GitHub PAT permissions and repository access using validation library..."
    
    # Use the comprehensive validation function from the library
    if validate_repository_configuration "$GITHUB_USERNAME" "$GITHUB_REPOSITORY" "$GH_PAT"; then
        log_success "All repository configuration validations passed"
        return 0
    else
        log_error "Repository configuration validation failed"
        return 1
    fi
}

# Generate repository-level registration token
generate_registration_token() {
    log_info "Generating repository-level registration token..."
    
    local response
    response=$(curl -s -w "%{http_code}" -X POST \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners/registration-token")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" != "201" ]; then
        log_error "Failed to generate registration token (HTTP $http_code)"
        log_error "Response: $body"
        return 1
    fi
    
    local token
    token=$(echo "$body" | jq -r '.token')
    local expires_at
    expires_at=$(echo "$body" | jq -r '.expires_at')
    
    if [ "$token" = "null" ] || [ -z "$token" ]; then
        log_error "Invalid registration token received"
        return 1
    fi
    
    log_success "Registration token generated successfully"
    log_info "Token expires at: $expires_at"
    
    echo "$token"
    return 0
}

# Check for existing runner
check_existing_runner() {
    log_info "Checking for existing runner: $RUNNER_NAME"
    
    local response
    response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" != "200" ]; then
        log_error "Failed to list repository runners (HTTP $http_code)"
        return 1
    fi
    
    local existing_runner_id
    existing_runner_id=$(echo "$body" | jq -r ".runners[] | select(.name==\"$RUNNER_NAME\") | .id")
    
    if [ -n "$existing_runner_id" ] && [ "$existing_runner_id" != "null" ]; then
        local runner_status
        runner_status=$(echo "$body" | jq -r ".runners[] | select(.name==\"$RUNNER_NAME\") | .status")
        
        log_warning "Runner '$RUNNER_NAME' already exists (ID: $existing_runner_id, Status: $runner_status)"
        echo "$existing_runner_id"
        return 0
    fi
    
    log_info "No existing runner found with name: $RUNNER_NAME"
    echo ""
    return 0
}

# Remove existing runner
remove_existing_runner() {
    local runner_id="$1"
    
    if [ -z "$runner_id" ]; then
        log_info "No runner ID provided for removal"
        return 0
    fi
    
    log_info "Removing existing runner (ID: $runner_id)..."
    
    local response
    response=$(curl -s -w "%{http_code}" -X DELETE \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners/$runner_id")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" = "204" ]; then
        log_success "Existing runner removed successfully"
        return 0
    elif [ "$http_code" = "404" ]; then
        log_info "Runner not found (may have been already removed)"
        return 0
    else
        log_error "Failed to remove existing runner (HTTP $http_code)"
        log_error "Response: $body"
        return 1
    fi
}

# Download and extract GitHub Actions runner
download_runner() {
    log_info "Downloading GitHub Actions runner v$RUNNER_VERSION..."
    
    local runner_dir="$HOME/actions-runner"
    local runner_archive="actions-runner-$RUNNER_ARCH-$RUNNER_VERSION.tar.gz"
    local download_url="https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/$runner_archive"
    
    # Create runner directory
    if [ ! -d "$runner_dir" ]; then
        mkdir -p "$runner_dir"
        log_info "Created runner directory: $runner_dir"
    fi
    
    cd "$runner_dir"
    
    # Download runner if not already present
    if [ ! -f "$runner_archive" ]; then
        log_info "Downloading from: $download_url"
        
        if ! curl -o "$runner_archive" -L "$download_url"; then
            log_error "Failed to download GitHub Actions runner"
            return 1
        fi
        
        log_success "Runner downloaded successfully"
    else
        log_info "Runner archive already exists: $runner_archive"
    fi
    
    # Extract runner if not already extracted
    if [ ! -f "config.sh" ]; then
        log_info "Extracting runner archive..."
        
        if ! tar xzf "$runner_archive"; then
            log_error "Failed to extract runner archive"
            return 1
        fi
        
        log_success "Runner extracted successfully"
        
        # Install dependencies
        log_info "Installing runner dependencies..."
        if ! sudo ./bin/installdependencies.sh; then
            log_error "Failed to install runner dependencies"
            return 1
        fi
        
        log_success "Runner dependencies installed"
    else
        log_info "Runner already extracted and configured"
    fi
    
    echo "$runner_dir"
    return 0
}

# Configure the runner
configure_runner() {
    local runner_dir="$1"
    local registration_token="$2"
    
    log_info "Configuring repository-level persistent runner..."
    
    cd "$runner_dir"
    
    # Remove existing configuration if present
    if [ -f ".runner" ]; then
        log_info "Removing existing runner configuration..."
        if ! sudo -u ubuntu ./config.sh remove --token "$registration_token" 2>/dev/null; then
            log_warning "Failed to remove existing configuration (may not exist)"
        fi
    fi
    
    # Configure runner
    log_info "Configuring runner with repository URL..."
    local repo_url="https://github.com/$GITHUB_USERNAME/$GITHUB_REPOSITORY"
    
    if ! sudo -u ubuntu ./config.sh \
        --url "$repo_url" \
        --token "$registration_token" \
        --name "$RUNNER_NAME" \
        --labels "$RUNNER_LABELS" \
        --work "$RUNNER_WORK_DIR" \
        --unattended \
        --replace; then
        log_error "Failed to configure runner"
        return 1
    fi
    
    log_success "Runner configured successfully"
    log_info "Repository URL: $repo_url"
    log_info "Runner Name: $RUNNER_NAME"
    log_info "Labels: $RUNNER_LABELS"
    log_info "Work Directory: $RUNNER_WORK_DIR"
    log_info "Configuration: Persistent (multi-use)"
    
    return 0
}

# Install and start runner service
install_runner_service() {
    local runner_dir="$1"
    
    log_info "Installing runner as system service..."
    
    cd "$runner_dir"
    
    # Install service
    if ! sudo ./svc.sh install ubuntu; then
        log_error "Failed to install runner service"
        return 1
    fi
    
    log_success "Runner service installed"
    
    # Start service
    log_info "Starting runner service..."
    if ! sudo ./svc.sh start; then
        log_error "Failed to start runner service"
        return 1
    fi
    
    # Verify service status
    sleep 3
    if sudo ./svc.sh status | grep -q "active (running)"; then
        log_success "Runner service is active and running"
    else
        log_error "Runner service failed to start properly"
        log_info "Service status:"
        sudo ./svc.sh status
        return 1
    fi
    
    return 0
}

# Show runner status
show_runner_status() {
    log_info "Checking runner status..."
    
    # Check local service status
    local runner_dir="$HOME/actions-runner"
    if [ -d "$runner_dir" ] && [ -f "$runner_dir/svc.sh" ]; then
        log_info "Local runner service status:"
        cd "$runner_dir"
        sudo ./svc.sh status || log_warning "Failed to get local service status"
    else
        log_info "No local runner installation found"
    fi
    
    # Check GitHub repository runners
    log_info "Repository runners:"
    local response
    response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" = "200" ]; then
        echo "$body" | jq -r '.runners[] | "- \(.name) (ID: \(.id), Status: \(.status), Labels: \([.labels[].name] | join(",")))"'
    else
        log_error "Failed to get repository runners (HTTP $http_code)"
    fi
}

# Remove runner configuration
remove_runner() {
    log_info "Removing runner configuration..."
    
    # Check for existing runner
    local existing_runner_id
    existing_runner_id=$(check_existing_runner)
    
    if [ -n "$existing_runner_id" ]; then
        remove_existing_runner "$existing_runner_id"
    fi
    
    # Stop and remove local service
    local runner_dir="$HOME/actions-runner"
    if [ -d "$runner_dir" ] && [ -f "$runner_dir/svc.sh" ]; then
        log_info "Stopping and removing local runner service..."
        cd "$runner_dir"
        
        sudo ./svc.sh stop || log_warning "Failed to stop service"
        sudo ./svc.sh uninstall || log_warning "Failed to uninstall service"
        
        # Remove configuration
        if [ -f "config.sh" ]; then
            local token
            token=$(generate_registration_token)
            if [ -n "$token" ]; then
                sudo -u ubuntu ./config.sh remove --token "$token" || log_warning "Failed to remove configuration"
            fi
        fi
        
        log_success "Local runner configuration removed"
    else
        log_info "No local runner installation found"
    fi
}

# Main setup function
setup_repository_runner() {
    log_info "Starting repository-level GitHub Actions runner setup..."
    log_info "Repository: $GITHUB_USERNAME/$GITHUB_REPOSITORY"
    log_info "Runner Name: $RUNNER_NAME"
    
    # Validate prerequisites
    if ! validate_prerequisites; then
        return 1
    fi
    
    # Validate GitHub permissions and repository access
    if ! validate_github_permissions; then
        return 1
    fi
    
    # Check for existing runner
    local existing_runner_id
    existing_runner_id=$(check_existing_runner)
    
    # Remove existing runner if found
    if [ -n "$existing_runner_id" ]; then
        log_info "Removing existing runner before setup..."
        remove_existing_runner "$existing_runner_id"
    fi
    
    # Generate registration token
    local registration_token
    registration_token=$(generate_registration_token)
    if [ -z "$registration_token" ]; then
        return 1
    fi
    
    # Download and extract runner
    local runner_dir
    runner_dir=$(download_runner)
    if [ -z "$runner_dir" ]; then
        return 1
    fi
    
    # Configure runner
    if ! configure_runner "$runner_dir" "$registration_token"; then
        return 1
    fi
    
    # Install and start service
    if ! install_runner_service "$runner_dir"; then
        return 1
    fi
    
    log_success "Repository-level GitHub Actions runner setup completed successfully!"
    log_info ""
    log_info "Runner Details:"
    log_info "  Repository: $GITHUB_USERNAME/$GITHUB_REPOSITORY"
    log_info "  Runner Name: $RUNNER_NAME"
    log_info "  Labels: $RUNNER_LABELS"
    log_info "  Configuration: Persistent (multi-use)"
    log_info "  Access: Only this repository"
    log_info ""
    log_info "The runner is now available to your repository."
    log_info "Use 'runs-on: [self-hosted, gha_aws_runner]' in your workflows."
    log_info ""
    log_info "To check runner status: $0 --status"
    log_info "To remove runner: $0 --remove"
    
    return 0
}

# Parse command line arguments
DRY_RUN=false
VALIDATE_ONLY=false
REMOVE_RUNNER=false
SHOW_STATUS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--version)
            echo "$SCRIPT_NAME v$SCRIPT_VERSION"
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --validate-only)
            VALIDATE_ONLY=true
            shift
            ;;
        --remove)
            REMOVE_RUNNER=true
            shift
            ;;
        --status)
            SHOW_STATUS=true
            shift
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
    
    if [ "$SHOW_STATUS" = true ]; then
        if ! validate_prerequisites; then
            exit 1
        fi
        show_runner_status
        exit 0
    fi
    
    if [ "$REMOVE_RUNNER" = true ]; then
        if ! validate_prerequisites; then
            exit 1
        fi
        remove_runner
        exit 0
    fi
    
    if [ "$VALIDATE_ONLY" = true ]; then
        if ! validate_prerequisites; then
            exit 1
        fi
        if ! validate_github_permissions; then
            exit 1
        fi
        log_success "All validations passed. Configuration is ready for runner setup."
        exit 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN MODE - No changes will be made"
        log_info "Would setup repository runner with:"
        log_info "  Repository: $GITHUB_USERNAME/$GITHUB_REPOSITORY"
        log_info "  Runner Name: $RUNNER_NAME"
        log_info "  Labels: $RUNNER_LABELS"
        log_info "  Work Directory: $RUNNER_WORK_DIR"
        log_info "  Version: $RUNNER_VERSION"
        exit 0
    fi
    
    # Run the main setup
    if setup_repository_runner; then
        exit 0
    else
        log_error "Runner setup failed"
        exit 1
    fi
}

# Execute main function
main "$@"