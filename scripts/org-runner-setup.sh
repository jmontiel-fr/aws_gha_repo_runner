#!/bin/bash
set -e

# GitHub Actions Runner Setup Script
# This script configures a GitHub Actions runner for both organization and repository levels
# Can be used for organization-wide access or single repository access.

# Script version and metadata
SCRIPT_VERSION="2.0.0"
SCRIPT_NAME="GitHub Runner Setup (Organization/Repository)"

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
GITHUB_ORGANIZATION="${GITHUB_ORGANIZATION:-}"
GITHUB_USERNAME="${GITHUB_USERNAME:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GH_PAT="${GH_PAT:-}"
RUNNER_NAME="${RUNNER_NAME:-gha_aws_runner}"
RUNNER_LABELS="${RUNNER_LABELS:-gha_aws_runner,ubuntu-22.04,ephemeral}"
RUNNER_WORK_DIR="${RUNNER_WORK_DIR:-_work}"
RUNNER_VERSION="${RUNNER_VERSION:-2.311.0}"
RUNNER_ARCH="${RUNNER_ARCH:-linux-x64}"
RUNNER_MODE="${RUNNER_MODE:-auto}" # auto, organization, repository

# Script usage information
show_usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

USAGE:
    $0 [OPTIONS]

DESCRIPTION:
    Sets up a GitHub Actions runner for organization or repository level access.
    Automatically detects the appropriate mode based on provided environment variables.

REQUIRED ENVIRONMENT VARIABLES (Organization Mode):
    GITHUB_ORGANIZATION    GitHub organization name
    GH_PAT                GitHub Personal Access Token with 'repo' and 'admin:org' scopes

REQUIRED ENVIRONMENT VARIABLES (Repository Mode):
    GITHUB_USERNAME       GitHub username
    GITHUB_REPOSITORY     GitHub repository name
    GH_PAT                GitHub Personal Access Token with 'repo' scope

OPTIONAL ENVIRONMENT VARIABLES:
    RUNNER_NAME           Runner name (default: gha_aws_runner)
    RUNNER_LABELS         Comma-separated runner labels (default: gha_aws_runner,ubuntu-22.04,ephemeral)
    RUNNER_WORK_DIR       Runner work directory (default: _work)
    RUNNER_VERSION        GitHub Actions runner version (default: 2.311.0)
    RUNNER_ARCH           Runner architecture (default: linux-x64)
    RUNNER_MODE           Force mode: auto, organization, repository (default: auto)

OPTIONS:
    -h, --help           Show this help message
    -v, --version        Show script version
    -d, --dry-run        Show what would be done without executing
    --validate-only      Only validate configuration without setting up runner
    --remove             Remove existing runner configuration
    --status             Show current runner status

EXAMPLES:
    # Organization setup
    export GITHUB_ORGANIZATION="my-org"
    export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
    $0

    # Repository setup
    export GITHUB_USERNAME="my-username"
    export GITHUB_REPOSITORY="my-repo"
    export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
    $0

    # Force repository mode
    export RUNNER_MODE="repository"
    export GITHUB_USERNAME="my-username"
    export GITHUB_REPOSITORY="my-repo"
    export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
    $0

    # Validate configuration only
    $0 --validate-only

    # Remove existing runner
    $0 --remove

PREREQUISITES:
    Organization Mode:
    - GitHub organization admin permissions
    - GitHub PAT with 'repo' and 'admin:org' scopes
    
    Repository Mode:
    - GitHub repository admin permissions
    - GitHub PAT with 'repo' scope only
    
    Common:
    - curl and jq installed
    - Internet connectivity to GitHub API and download servers

EOF
}

# Determine runner mode based on environment variables
determine_runner_mode() {
    if [ "$RUNNER_MODE" = "organization" ] || [ "$RUNNER_MODE" = "repository" ]; then
        log_info "Using forced runner mode: $RUNNER_MODE"
        return 0
    fi
    
    # Auto-detect mode based on available environment variables
    if [ -n "$GITHUB_ORGANIZATION" ] && [ -z "$GITHUB_USERNAME" ] && [ -z "$GITHUB_REPOSITORY" ]; then
        RUNNER_MODE="organization"
        log_info "Auto-detected organization mode"
    elif [ -n "$GITHUB_USERNAME" ] && [ -n "$GITHUB_REPOSITORY" ] && [ -z "$GITHUB_ORGANIZATION" ]; then
        RUNNER_MODE="repository"
        log_info "Auto-detected repository mode"
    elif [ -n "$GITHUB_ORGANIZATION" ] && [ -n "$GITHUB_USERNAME" ] && [ -n "$GITHUB_REPOSITORY" ]; then
        # Both sets provided, prefer repository mode
        RUNNER_MODE="repository"
        log_info "Both organization and repository variables provided, using repository mode"
    else
        log_error "Cannot determine runner mode. Please provide either:"
        log_error "  Organization mode: GITHUB_ORGANIZATION"
        log_error "  Repository mode: GITHUB_USERNAME and GITHUB_REPOSITORY"
        return 1
    fi
    
    return 0
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check required commands
    local required_commands=("curl" "jq" "tar" "shasum")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' is not installed"
            return 1
        fi
    done
    
    # Determine runner mode first
    if ! determine_runner_mode; then
        return 1
    fi
    
    # Check required environment variables based on mode
    if [ "$RUNNER_MODE" = "organization" ]; then
        if [ -z "$GITHUB_ORGANIZATION" ]; then
            log_error "GITHUB_ORGANIZATION environment variable is required for organization mode"
            log_info "Set it with: export GITHUB_ORGANIZATION='your-organization-name'"
            return 1
        fi
        
        # Validate organization name format
        if [[ ! "$GITHUB_ORGANIZATION" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
            log_error "Invalid GitHub organization name format: $GITHUB_ORGANIZATION"
            return 1
        fi
    elif [ "$RUNNER_MODE" = "repository" ]; then
        if [ -z "$GITHUB_USERNAME" ]; then
            log_error "GITHUB_USERNAME environment variable is required for repository mode"
            log_info "Set it with: export GITHUB_USERNAME='your-username'"
            return 1
        fi
        
        if [ -z "$GITHUB_REPOSITORY" ]; then
            log_error "GITHUB_REPOSITORY environment variable is required for repository mode"
            log_info "Set it with: export GITHUB_REPOSITORY='your-repository-name'"
            return 1
        fi
        
        # Validate username and repository name format
        if [[ ! "$GITHUB_USERNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
            log_error "Invalid GitHub username format: $GITHUB_USERNAME"
            return 1
        fi
        
        if [[ ! "$GITHUB_REPOSITORY" =~ ^[a-zA-Z0-9._-]+$ ]]; then
            log_error "Invalid GitHub repository name format: $GITHUB_REPOSITORY"
            return 1
        fi
    fi
    
    if [ -z "$GH_PAT" ]; then
        log_error "GH_PAT environment variable is required"
        log_info "Set it with: export GH_PAT='your-personal-access-token'"
        return 1
    fi
    
    log_success "Prerequisites validation passed"
    return 0
}

# Validate GitHub PAT permissions
validate_github_permissions() {
    log_info "Validating GitHub PAT permissions for $RUNNER_MODE mode..."
    
    # Test basic authentication
    local auth_response
    auth_response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/user")
    
    local auth_http_code="${auth_response: -3}"
    local auth_body="${auth_response%???}"
    
    if [ "$auth_http_code" != "200" ]; then
        log_error "GitHub PAT authentication failed (HTTP $auth_http_code)"
        log_error "Response: $auth_body"
        return 1
    fi
    
    local username
    username=$(echo "$auth_body" | jq -r '.login')
    log_success "Authenticated as GitHub user: $username"
    
    if [ "$RUNNER_MODE" = "organization" ]; then
        # Organization mode validation
        local org_response
        org_response=$(curl -s -w "%{http_code}" \
            -H "Authorization: token $GH_PAT" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/orgs/$GITHUB_ORGANIZATION")
        
        local org_http_code="${org_response: -3}"
        local org_body="${org_response%???}"
        
        if [ "$org_http_code" != "200" ]; then
            log_error "Failed to access organization '$GITHUB_ORGANIZATION' (HTTP $org_http_code)"
            if [ "$org_http_code" = "404" ]; then
                log_error "Organization not found or insufficient permissions"
            elif [ "$org_http_code" = "403" ]; then
                log_error "Access forbidden. Ensure your PAT has 'admin:org' scope"
            fi
            return 1
        fi
        
        log_success "Organization access validated: $GITHUB_ORGANIZATION"
        
        # Test organization membership and role
        local membership_response
        membership_response=$(curl -s -w "%{http_code}" \
            -H "Authorization: token $GH_PAT" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/orgs/$GITHUB_ORGANIZATION/memberships/$username")
        
        local membership_http_code="${membership_response: -3}"
        local membership_body="${membership_response%???}"
        
        if [ "$membership_http_code" = "200" ]; then
            local role
            role=$(echo "$membership_body" | jq -r '.role')
            local state
            state=$(echo "$membership_body" | jq -r '.state')
            
            log_info "Organization membership - Role: $role, State: $state"
            
            if [ "$role" != "admin" ]; then
                log_warning "You have '$role' role. 'admin' role is recommended for runner management"
            fi
            
            if [ "$state" != "active" ]; then
                log_error "Organization membership is not active (state: $state)"
                return 1
            fi
        else
            log_warning "Could not verify organization membership (HTTP $membership_http_code)"
        fi
        
        # Test organization runner registration token generation
        log_info "Testing organization runner registration token generation..."
        local token_response
        token_response=$(curl -s -w "%{http_code}" -X POST \
            -H "Authorization: token $GH_PAT" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners/registration-token")
        
        local token_http_code="${token_response: -3}"
        local token_body="${token_response%???}"
        
        if [ "$token_http_code" != "201" ]; then
            log_error "Failed to generate organization registration token (HTTP $token_http_code)"
            log_error "This indicates insufficient permissions. Ensure your PAT has 'admin:org' scope"
            log_error "Response: $token_body"
            return 1
        fi
        
        log_success "Organization registration token generation test passed"
        
    elif [ "$RUNNER_MODE" = "repository" ]; then
        # Repository mode validation
        local repo_response
        repo_response=$(curl -s -w "%{http_code}" \
            -H "Authorization: token $GH_PAT" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY")
        
        local repo_http_code="${repo_response: -3}"
        local repo_body="${repo_response%???}"
        
        if [ "$repo_http_code" != "200" ]; then
            log_error "Failed to access repository '$GITHUB_USERNAME/$GITHUB_REPOSITORY' (HTTP $repo_http_code)"
            if [ "$repo_http_code" = "404" ]; then
                log_error "Repository not found or insufficient permissions"
            elif [ "$repo_http_code" = "403" ]; then
                log_error "Access forbidden. Ensure your PAT has 'repo' scope and you have admin access"
            fi
            return 1
        fi
        
        local repo_name
        repo_name=$(echo "$repo_body" | jq -r '.name')
        local repo_private
        repo_private=$(echo "$repo_body" | jq -r '.private')
        local repo_permissions
        repo_permissions=$(echo "$repo_body" | jq -r '.permissions.admin // false')
        
        log_success "Repository access validated: $GITHUB_USERNAME/$repo_name"
        log_info "Repository private: $repo_private"
        
        if [ "$repo_permissions" != "true" ]; then
            log_error "Insufficient repository permissions. Admin access required for runner management"
            return 1
        fi
        
        log_success "Repository admin permissions confirmed"
        
        # Test repository runner registration token generation
        log_info "Testing repository runner registration token generation..."
        local token_response
        token_response=$(curl -s -w "%{http_code}" -X POST \
            -H "Authorization: token $GH_PAT" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners/registration-token")
        
        local token_http_code="${token_response: -3}"
        local token_body="${token_response%???}"
        
        if [ "$token_http_code" != "201" ]; then
            log_error "Failed to generate repository registration token (HTTP $token_http_code)"
            log_error "This indicates insufficient permissions. Ensure your PAT has 'repo' scope and admin access"
            log_error "Response: $token_body"
            return 1
        fi
        
        log_success "Repository registration token generation test passed"
    fi
    
    log_success "GitHub PAT permissions validation completed for $RUNNER_MODE mode"
    return 0
}

# Generate registration token (organization or repository level)
generate_registration_token() {
    log_info "Generating $RUNNER_MODE-level registration token..."
    
    local api_endpoint
    if [ "$RUNNER_MODE" = "organization" ]; then
        api_endpoint="https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners/registration-token"
    elif [ "$RUNNER_MODE" = "repository" ]; then
        api_endpoint="https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners/registration-token"
    else
        log_error "Invalid runner mode: $RUNNER_MODE"
        return 1
    fi
    
    local response
    response=$(curl -s -w "%{http_code}" -X POST \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "$api_endpoint")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" != "201" ]; then
        log_error "Failed to generate $RUNNER_MODE registration token (HTTP $http_code)"
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
    
    log_success "$RUNNER_MODE registration token generated successfully"
    log_info "Token expires at: $expires_at"
    
    echo "$token"
    return 0
}

# Check for existing runner
check_existing_runner() {
    log_info "Checking for existing $RUNNER_MODE runner: $RUNNER_NAME"
    
    local api_endpoint
    if [ "$RUNNER_MODE" = "organization" ]; then
        api_endpoint="https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners"
    elif [ "$RUNNER_MODE" = "repository" ]; then
        api_endpoint="https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners"
    else
        log_error "Invalid runner mode: $RUNNER_MODE"
        return 1
    fi
    
    local response
    response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "$api_endpoint")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" != "200" ]; then
        log_error "Failed to list $RUNNER_MODE runners (HTTP $http_code)"
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
    
    log_info "No existing $RUNNER_MODE runner found with name: $RUNNER_NAME"
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
    
    log_info "Removing existing $RUNNER_MODE runner (ID: $runner_id)..."
    
    local api_endpoint
    if [ "$RUNNER_MODE" = "organization" ]; then
        api_endpoint="https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners/$runner_id"
    elif [ "$RUNNER_MODE" = "repository" ]; then
        api_endpoint="https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners/$runner_id"
    else
        log_error "Invalid runner mode: $RUNNER_MODE"
        return 1
    fi
    
    local response
    response=$(curl -s -w "%{http_code}" -X DELETE \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "$api_endpoint")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" = "204" ]; then
        log_success "Existing $RUNNER_MODE runner removed successfully"
        return 0
    elif [ "$http_code" = "404" ]; then
        log_info "Runner not found (may have been already removed)"
        return 0
    else
        log_error "Failed to remove existing $RUNNER_MODE runner (HTTP $http_code)"
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
    
    log_info "Configuring $RUNNER_MODE-level ephemeral runner..."
    
    cd "$runner_dir"
    
    # Remove existing configuration if present
    if [ -f ".runner" ]; then
        log_info "Removing existing runner configuration..."
        if ! sudo -u ubuntu ./config.sh remove --token "$registration_token" 2>/dev/null; then
            log_warning "Failed to remove existing configuration (may not exist)"
        fi
    fi
    
    # Determine the appropriate URL based on runner mode
    local runner_url
    if [ "$RUNNER_MODE" = "organization" ]; then
        runner_url="https://github.com/$GITHUB_ORGANIZATION"
        log_info "Configuring runner with organization URL..."
    elif [ "$RUNNER_MODE" = "repository" ]; then
        runner_url="https://github.com/$GITHUB_USERNAME/$GITHUB_REPOSITORY"
        log_info "Configuring runner with repository URL..."
    else
        log_error "Invalid runner mode: $RUNNER_MODE"
        return 1
    fi
    
    if ! sudo -u ubuntu ./config.sh \
        --url "$runner_url" \
        --token "$registration_token" \
        --name "$RUNNER_NAME" \
        --labels "$RUNNER_LABELS" \
        --work "$RUNNER_WORK_DIR" \
        --ephemeral \
        --unattended \
        --replace; then
        log_error "Failed to configure runner"
        return 1
    fi
    
    log_success "Runner configured successfully"
    log_info "Runner URL: $runner_url"
    log_info "Runner Name: $RUNNER_NAME"
    log_info "Labels: $RUNNER_LABELS"
    log_info "Work Directory: $RUNNER_WORK_DIR"
    log_info "Configuration: Ephemeral (single-use)"
    log_info "Mode: $RUNNER_MODE"
    
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
    
    # Determine runner mode first
    if ! determine_runner_mode; then
        log_error "Cannot determine runner mode for status check"
        return 1
    fi
    
    # Check local service status
    local runner_dir="$HOME/actions-runner"
    if [ -d "$runner_dir" ] && [ -f "$runner_dir/svc.sh" ]; then
        log_info "Local runner service status:"
        cd "$runner_dir"
        sudo ./svc.sh status || log_warning "Failed to get local service status"
    else
        log_info "No local runner installation found"
    fi
    
    # Check GitHub runners based on mode
    local api_endpoint
    if [ "$RUNNER_MODE" = "organization" ]; then
        log_info "Organization runners:"
        api_endpoint="https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners"
    elif [ "$RUNNER_MODE" = "repository" ]; then
        log_info "Repository runners:"
        api_endpoint="https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners"
    else
        log_error "Invalid runner mode: $RUNNER_MODE"
        return 1
    fi
    
    local response
    response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "$api_endpoint")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" = "200" ]; then
        echo "$body" | jq -r '.runners[] | "- \(.name) (ID: \(.id), Status: \(.status), Labels: \([.labels[].name] | join(",")))"'
    else
        log_error "Failed to get $RUNNER_MODE runners (HTTP $http_code)"
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
setup_github_runner() {
    log_info "Starting $RUNNER_MODE-level GitHub Actions runner setup..."
    
    if [ "$RUNNER_MODE" = "organization" ]; then
        log_info "Organization: $GITHUB_ORGANIZATION"
    elif [ "$RUNNER_MODE" = "repository" ]; then
        log_info "Repository: $GITHUB_USERNAME/$GITHUB_REPOSITORY"
    fi
    
    log_info "Runner Name: $RUNNER_NAME"
    
    # Validate prerequisites
    if ! validate_prerequisites; then
        return 1
    fi
    
    # Validate GitHub permissions
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
    
    log_success "$RUNNER_MODE-level GitHub Actions runner setup completed successfully!"
    log_info ""
    log_info "Runner Details:"
    
    if [ "$RUNNER_MODE" = "organization" ]; then
        log_info "  Organization: $GITHUB_ORGANIZATION"
        log_info "  Access: All repositories in organization"
        log_info ""
        log_info "The runner is now available to all repositories in your organization."
    elif [ "$RUNNER_MODE" = "repository" ]; then
        log_info "  Repository: $GITHUB_USERNAME/$GITHUB_REPOSITORY"
        log_info "  Access: Single repository only"
        log_info ""
        log_info "The runner is now available to the $GITHUB_USERNAME/$GITHUB_REPOSITORY repository."
    fi
    
    log_info "  Runner Name: $RUNNER_NAME"
    log_info "  Labels: $RUNNER_LABELS"
    log_info "  Configuration: Ephemeral (single-use)"
    log_info "  Mode: $RUNNER_MODE"
    log_info ""
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
        log_info "Would setup organization runner with:"
        log_info "  Organization: $GITHUB_ORGANIZATION"
        log_info "  Runner Name: $RUNNER_NAME"
        log_info "  Labels: $RUNNER_LABELS"
        log_info "  Work Directory: $RUNNER_WORK_DIR"
        log_info "  Version: $RUNNER_VERSION"
        exit 0
    fi
    
    # Run the main setup
    if setup_github_runner; then
        exit 0
    else
        log_error "Runner setup failed"
        exit 1
    fi
}

# Execute main function
main "$@"