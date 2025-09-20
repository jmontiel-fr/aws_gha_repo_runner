#!/bin/bash
set -e

# Repository Runner Switching Script
# This script provides functionality to cleanly switch a GitHub Actions runner
# from one repository to another, ensuring proper unregistration and re-registration.

# Script version and metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="Repository Runner Switching"

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

# Configuration variables
CURRENT_GITHUB_USERNAME="${CURRENT_GITHUB_USERNAME:-}"
CURRENT_GITHUB_REPOSITORY="${CURRENT_GITHUB_REPOSITORY:-}"
NEW_GITHUB_USERNAME="${NEW_GITHUB_USERNAME:-}"
NEW_GITHUB_REPOSITORY="${NEW_GITHUB_REPOSITORY:-}"
GH_PAT="${GH_PAT:-}"
RUNNER_NAME="${RUNNER_NAME:-gha_aws_runner}"
RUNNER_LABELS="${RUNNER_LABELS:-gha_aws_runner,ubuntu-22.04}"
RUNNER_WORK_DIR="${RUNNER_WORK_DIR:-_work}"

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
    Switches a GitHub Actions runner from one repository to another.
    Performs clean unregistration from the current repository and 
    registration with the new repository.

REQUIRED ENVIRONMENT VARIABLES:
    CURRENT_GITHUB_USERNAME    Current repository username
    CURRENT_GITHUB_REPOSITORY  Current repository name
    NEW_GITHUB_USERNAME        New repository username  
    NEW_GITHUB_REPOSITORY      New repository name
    GH_PAT                     GitHub Personal Access Token with 'repo' scope

OPTIONAL ENVIRONMENT VARIABLES:
    RUNNER_NAME               Runner name (default: gha_aws_runner)
    RUNNER_LABELS             Comma-separated runner labels (default: gha_aws_runner,ubuntu-22.04)
    RUNNER_WORK_DIR           Runner work directory (default: _work)

OPTIONS:
    -h, --help               Show this help message
    -v, --version            Show script version
    -d, --dry-run            Show what would be done without executing
    --validate-only          Only validate configuration without switching
    --status                 Show current runner status
    --force                  Force switch even if validation warnings exist

EXAMPLES:
    # Basic repository switch
    export CURRENT_GITHUB_USERNAME="myusername"
    export CURRENT_GITHUB_REPOSITORY="old-repo"
    export NEW_GITHUB_USERNAME="myusername"
    export NEW_GITHUB_REPOSITORY="new-repo"
    export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
    $0

    # Switch to different user's repository (if you have access)
    export CURRENT_GITHUB_USERNAME="myusername"
    export CURRENT_GITHUB_REPOSITORY="my-repo"
    export NEW_GITHUB_USERNAME="otheruser"
    export NEW_GITHUB_REPOSITORY="their-repo"
    export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
    $0

    # Validate configuration only
    $0 --validate-only

    # Show current runner status
    $0 --status

PREREQUISITES:
    - Repository admin permissions on both current and new repositories
    - GitHub PAT with 'repo' scope
    - curl and jq installed
    - Existing runner installation in ~/actions-runner

EOF
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites for repository switching..."
    
    # Check required environment variables
    local missing_vars=()
    
    if [ -z "$CURRENT_GITHUB_USERNAME" ]; then
        missing_vars+=("CURRENT_GITHUB_USERNAME")
    fi
    
    if [ -z "$CURRENT_GITHUB_REPOSITORY" ]; then
        missing_vars+=("CURRENT_GITHUB_REPOSITORY")
    fi
    
    if [ -z "$NEW_GITHUB_USERNAME" ]; then
        missing_vars+=("NEW_GITHUB_USERNAME")
    fi
    
    if [ -z "$NEW_GITHUB_REPOSITORY" ]; then
        missing_vars+=("NEW_GITHUB_REPOSITORY")
    fi
    
    if [ -z "$GH_PAT" ]; then
        missing_vars+=("GH_PAT")
    fi
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_info "Set them with:"
        for var in "${missing_vars[@]}"; do
            log_info "  export $var='value'"
        done
        return 1
    fi
    
    # Validate username and repository formats
    if ! validate_username_format "$CURRENT_GITHUB_USERNAME"; then
        log_error "Invalid current username format"
        return 1
    fi
    
    if ! validate_repository_format "$CURRENT_GITHUB_REPOSITORY"; then
        log_error "Invalid current repository format"
        return 1
    fi
    
    if ! validate_username_format "$NEW_GITHUB_USERNAME"; then
        log_error "Invalid new username format"
        return 1
    fi
    
    if ! validate_repository_format "$NEW_GITHUB_REPOSITORY"; then
        log_error "Invalid new repository format"
        return 1
    fi
    
    # Check if trying to switch to the same repository
    if [ "$CURRENT_GITHUB_USERNAME" = "$NEW_GITHUB_USERNAME" ] && [ "$CURRENT_GITHUB_REPOSITORY" = "$NEW_GITHUB_REPOSITORY" ]; then
        log_error "Current and new repository are the same: $CURRENT_GITHUB_USERNAME/$CURRENT_GITHUB_REPOSITORY"
        log_error "No switching needed"
        return 1
    fi
    
    # Validate required tools
    if ! validate_required_tools; then
        return 1
    fi
    
    # Check if runner directory exists
    local runner_dir="$HOME/actions-runner"
    if [ ! -d "$runner_dir" ]; then
        log_error "Runner directory not found: $runner_dir"
        log_error "Please install the GitHub Actions runner first"
        return 1
    fi
    
    if [ ! -f "$runner_dir/config.sh" ]; then
        log_error "Runner configuration script not found: $runner_dir/config.sh"
        log_error "Runner installation appears to be incomplete"
        return 1
    fi
    
    log_success "Prerequisites validation passed"
    return 0
}

# Validate both repositories and permissions
validate_repositories() {
    log_info "Validating current and new repository configurations..."
    
    local validation_failed=false
    
    # Validate current repository configuration
    log_info "=== Validating Current Repository ==="
    log_info "Repository: $CURRENT_GITHUB_USERNAME/$CURRENT_GITHUB_REPOSITORY"
    
    if ! validate_repository_configuration "$CURRENT_GITHUB_USERNAME" "$CURRENT_GITHUB_REPOSITORY" "$GH_PAT"; then
        log_error "Current repository validation failed"
        validation_failed=true
    fi
    
    # Validate new repository configuration
    log_info "=== Validating New Repository ==="
    log_info "Repository: $NEW_GITHUB_USERNAME/$NEW_GITHUB_REPOSITORY"
    
    if ! validate_repository_configuration "$NEW_GITHUB_USERNAME" "$NEW_GITHUB_REPOSITORY" "$GH_PAT"; then
        log_error "New repository validation failed"
        validation_failed=true
    fi
    
    if [ "$validation_failed" = true ]; then
        log_error "Repository validation failed - cannot proceed with switching"
        return 1
    fi
    
    log_success "Both repositories validated successfully"
    return 0
}

# Get current runner information
get_current_runner_info() {
    log_info "Getting current runner information..."
    
    local runner_dir="$HOME/actions-runner"
    
    # Check if runner is configured
    if [ ! -f "$runner_dir/.runner" ]; then
        log_info "No runner configuration found"
        echo ""
        return 0
    fi
    
    # Read runner configuration
    local runner_config
    runner_config=$(cat "$runner_dir/.runner" 2>/dev/null || echo "{}")
    
    local configured_url
    configured_url=$(echo "$runner_config" | jq -r '.gitHubUrl // ""')
    
    if [ -n "$configured_url" ] && [ "$configured_url" != "null" ]; then
        log_info "Runner is currently configured for: $configured_url"
        echo "$configured_url"
        return 0
    fi
    
    log_info "Runner configuration exists but URL not found"
    echo ""
    return 0
}

# Check if runner exists in current repository
check_runner_in_current_repository() {
    log_info "Checking if runner exists in current repository..."
    
    local response
    response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$CURRENT_GITHUB_USERNAME/$CURRENT_GITHUB_REPOSITORY/actions/runners")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" != "200" ]; then
        log_warning "Failed to list runners in current repository (HTTP $http_code)"
        echo ""
        return 1
    fi
    
    local runner_id
    runner_id=$(echo "$body" | jq -r ".runners[] | select(.name==\"$RUNNER_NAME\") | .id")
    
    if [ -n "$runner_id" ] && [ "$runner_id" != "null" ]; then
        local runner_status
        runner_status=$(echo "$body" | jq -r ".runners[] | select(.name==\"$RUNNER_NAME\") | .status")
        
        log_info "Runner '$RUNNER_NAME' found in current repository (ID: $runner_id, Status: $runner_status)"
        echo "$runner_id"
        return 0
    fi
    
    log_info "Runner '$RUNNER_NAME' not found in current repository"
    echo ""
    return 0
}

# Check if runner exists in new repository
check_runner_in_new_repository() {
    log_info "Checking if runner exists in new repository..."
    
    local response
    response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$NEW_GITHUB_USERNAME/$NEW_GITHUB_REPOSITORY/actions/runners")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" != "200" ]; then
        log_warning "Failed to list runners in new repository (HTTP $http_code)"
        echo ""
        return 1
    fi
    
    local runner_id
    runner_id=$(echo "$body" | jq -r ".runners[] | select(.name==\"$RUNNER_NAME\") | .id")
    
    if [ -n "$runner_id" ] && [ "$runner_id" != "null" ]; then
        local runner_status
        runner_status=$(echo "$body" | jq -r ".runners[] | select(.name==\"$RUNNER_NAME\") | .status")
        
        log_warning "Runner '$RUNNER_NAME' already exists in new repository (ID: $runner_id, Status: $runner_status)"
        echo "$runner_id"
        return 0
    fi
    
    log_info "Runner '$RUNNER_NAME' not found in new repository (this is expected)"
    echo ""
    return 0
}

# Generate registration token for new repository
generate_new_registration_token() {
    log_info "Generating registration token for new repository..."
    
    local response
    response=$(curl -s -w "%{http_code}" -X POST \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$NEW_GITHUB_USERNAME/$NEW_GITHUB_REPOSITORY/actions/runners/registration-token")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" != "201" ]; then
        log_error "Failed to generate registration token for new repository (HTTP $http_code)"
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
    
    log_success "Registration token generated for new repository"
    log_info "Token expires at: $expires_at"
    
    echo "$token"
    return 0
}

# Unregister runner from current repository
unregister_from_current_repository() {
    local runner_id="$1"
    
    log_info "Unregistering runner from current repository..."
    
    # Stop the runner service first
    local runner_dir="$HOME/actions-runner"
    cd "$runner_dir"
    
    log_info "Stopping runner service..."
    if sudo ./svc.sh stop; then
        log_success "Runner service stopped"
    else
        log_warning "Failed to stop runner service (may not be running)"
    fi
    
    # Uninstall the service
    log_info "Uninstalling runner service..."
    if sudo ./svc.sh uninstall; then
        log_success "Runner service uninstalled"
    else
        log_warning "Failed to uninstall runner service (may not be installed)"
    fi
    
    # Remove runner from GitHub if it exists
    if [ -n "$runner_id" ]; then
        log_info "Removing runner from GitHub (ID: $runner_id)..."
        
        local response
        response=$(curl -s -w "%{http_code}" -X DELETE \
            -H "Authorization: token $GH_PAT" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$CURRENT_GITHUB_USERNAME/$CURRENT_GITHUB_REPOSITORY/actions/runners/$runner_id")
        
        local http_code="${response: -3}"
        local body="${response%???}"
        
        if [ "$http_code" = "204" ]; then
            log_success "Runner removed from GitHub successfully"
        elif [ "$http_code" = "404" ]; then
            log_info "Runner not found in GitHub (may have been already removed)"
        else
            log_warning "Failed to remove runner from GitHub (HTTP $http_code)"
            log_warning "Response: $body"
        fi
    fi
    
    # Remove local runner configuration
    log_info "Removing local runner configuration..."
    
    # Generate a token for removal (if needed)
    local removal_token
    removal_token=$(curl -s -X POST \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$CURRENT_GITHUB_USERNAME/$CURRENT_GITHUB_REPOSITORY/actions/runners/registration-token" | \
        jq -r '.token // ""')
    
    if [ -n "$removal_token" ] && [ "$removal_token" != "null" ]; then
        if sudo -u ubuntu ./config.sh remove --token "$removal_token"; then
            log_success "Local runner configuration removed"
        else
            log_warning "Failed to remove local configuration (may not exist)"
        fi
    else
        log_warning "Could not generate token for configuration removal"
        # Try to remove configuration file directly
        if [ -f ".runner" ]; then
            rm -f .runner .credentials .credentials_rsaparams
            log_info "Removed configuration files directly"
        fi
    fi
    
    log_success "Runner unregistered from current repository"
    return 0
}

# Register runner with new repository
register_with_new_repository() {
    local registration_token="$1"
    
    log_info "Registering runner with new repository..."
    
    local runner_dir="$HOME/actions-runner"
    cd "$runner_dir"
    
    # Configure runner with new repository
    log_info "Configuring runner for new repository..."
    local new_repo_url="https://github.com/$NEW_GITHUB_USERNAME/$NEW_GITHUB_REPOSITORY"
    
    if ! sudo -u ubuntu ./config.sh \
        --url "$new_repo_url" \
        --token "$registration_token" \
        --name "$RUNNER_NAME" \
        --labels "$RUNNER_LABELS" \
        --work "$RUNNER_WORK_DIR" \
        --unattended \
        --replace; then
        log_error "Failed to configure runner for new repository"
        return 1
    fi
    
    log_success "Runner configured for new repository"
    log_info "Repository URL: $new_repo_url"
    log_info "Runner Name: $RUNNER_NAME"
    log_info "Labels: $RUNNER_LABELS"
    
    # Install and start service
    log_info "Installing runner service..."
    if ! sudo ./svc.sh install ubuntu; then
        log_error "Failed to install runner service"
        return 1
    fi
    
    log_success "Runner service installed"
    
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
    
    log_success "Runner registered with new repository successfully"
    return 0
}

# Show current runner status
show_runner_status() {
    log_info "=== Current Runner Status ==="
    
    # Show local runner information
    local current_url
    current_url=$(get_current_runner_info)
    
    if [ -n "$current_url" ]; then
        log_info "Local runner configured for: $current_url"
    else
        log_info "No local runner configuration found"
    fi
    
    # Show local service status
    local runner_dir="$HOME/actions-runner"
    if [ -d "$runner_dir" ] && [ -f "$runner_dir/svc.sh" ]; then
        log_info "Local runner service status:"
        cd "$runner_dir"
        sudo ./svc.sh status || log_warning "Failed to get local service status"
    else
        log_info "No local runner installation found"
    fi
    
    # Show runners in current repository (if configured)
    if [ -n "$CURRENT_GITHUB_USERNAME" ] && [ -n "$CURRENT_GITHUB_REPOSITORY" ] && [ -n "$GH_PAT" ]; then
        log_info "=== Current Repository Runners ==="
        log_info "Repository: $CURRENT_GITHUB_USERNAME/$CURRENT_GITHUB_REPOSITORY"
        
        local response
        response=$(curl -s -w "%{http_code}" \
            -H "Authorization: token $GH_PAT" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$CURRENT_GITHUB_USERNAME/$CURRENT_GITHUB_REPOSITORY/actions/runners")
        
        local http_code="${response: -3}"
        local body="${response%???}"
        
        if [ "$http_code" = "200" ]; then
            echo "$body" | jq -r '.runners[] | "- \(.name) (ID: \(.id), Status: \(.status), Labels: \([.labels[].name] | join(",")))"'
        else
            log_error "Failed to get current repository runners (HTTP $http_code)"
        fi
    fi
    
    # Show runners in new repository (if configured)
    if [ -n "$NEW_GITHUB_USERNAME" ] && [ -n "$NEW_GITHUB_REPOSITORY" ] && [ -n "$GH_PAT" ]; then
        log_info "=== New Repository Runners ==="
        log_info "Repository: $NEW_GITHUB_USERNAME/$NEW_GITHUB_REPOSITORY"
        
        local response
        response=$(curl -s -w "%{http_code}" \
            -H "Authorization: token $GH_PAT" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$NEW_GITHUB_USERNAME/$NEW_GITHUB_REPOSITORY/actions/runners")
        
        local http_code="${response: -3}"
        local body="${response%???}"
        
        if [ "$http_code" = "200" ]; then
            echo "$body" | jq -r '.runners[] | "- \(.name) (ID: \(.id), Status: \(.status), Labels: \([.labels[].name] | join(",")))"'
        else
            log_error "Failed to get new repository runners (HTTP $http_code)"
        fi
    fi
}

# Perform conflict validation
validate_no_conflicts() {
    log_info "Validating for potential conflicts..."
    
    local conflicts_found=false
    
    # Check if runner already exists in new repository
    local existing_runner_id
    existing_runner_id=$(check_runner_in_new_repository)
    
    if [ -n "$existing_runner_id" ]; then
        log_warning "Runner '$RUNNER_NAME' already exists in new repository"
        log_warning "This may cause conflicts during registration"
        conflicts_found=true
    fi
    
    # Check if local runner is configured for a different repository
    local current_url
    current_url=$(get_current_runner_info)
    
    if [ -n "$current_url" ]; then
        local expected_current_url="https://github.com/$CURRENT_GITHUB_USERNAME/$CURRENT_GITHUB_REPOSITORY"
        if [ "$current_url" != "$expected_current_url" ]; then
            log_warning "Local runner is configured for: $current_url"
            log_warning "Expected: $expected_current_url"
            log_warning "This may indicate configuration mismatch"
            conflicts_found=true
        fi
    fi
    
    if [ "$conflicts_found" = true ]; then
        log_warning "Potential conflicts detected"
        return 1
    fi
    
    log_success "No conflicts detected"
    return 0
}

# Main switching function
switch_repository_runner() {
    log_info "Starting repository runner switching process..."
    log_info "From: $CURRENT_GITHUB_USERNAME/$CURRENT_GITHUB_REPOSITORY"
    log_info "To: $NEW_GITHUB_USERNAME/$NEW_GITHUB_REPOSITORY"
    log_info "Runner: $RUNNER_NAME"
    
    # Validate prerequisites
    if ! validate_prerequisites; then
        return 1
    fi
    
    # Validate both repositories
    if ! validate_repositories; then
        return 1
    fi
    
    # Check for conflicts
    if ! validate_no_conflicts; then
        if [ "$FORCE_SWITCH" != true ]; then
            log_error "Conflicts detected. Use --force to proceed anyway"
            return 1
        else
            log_warning "Proceeding despite conflicts due to --force flag"
        fi
    fi
    
    # Get current runner information
    local current_runner_id
    current_runner_id=$(check_runner_in_current_repository)
    
    # Generate registration token for new repository
    local registration_token
    registration_token=$(generate_new_registration_token)
    if [ -z "$registration_token" ]; then
        return 1
    fi
    
    # Unregister from current repository
    if ! unregister_from_current_repository "$current_runner_id"; then
        log_error "Failed to unregister from current repository"
        return 1
    fi
    
    # Register with new repository
    if ! register_with_new_repository "$registration_token"; then
        log_error "Failed to register with new repository"
        log_error "Runner may be in an inconsistent state"
        return 1
    fi
    
    log_success "Repository runner switching completed successfully!"
    log_info ""
    log_info "Runner Details:"
    log_info "  Previous Repository: $CURRENT_GITHUB_USERNAME/$CURRENT_GITHUB_REPOSITORY"
    log_info "  New Repository: $NEW_GITHUB_USERNAME/$NEW_GITHUB_REPOSITORY"
    log_info "  Runner Name: $RUNNER_NAME"
    log_info "  Labels: $RUNNER_LABELS"
    log_info "  Configuration: Persistent (multi-use)"
    log_info ""
    log_info "The runner is now available to the new repository."
    log_info "Use 'runs-on: [self-hosted, gha_aws_runner]' in your workflows."
    log_info ""
    log_info "To check runner status: $0 --status"
    
    return 0
}

# Parse command line arguments
DRY_RUN=false
VALIDATE_ONLY=false
SHOW_STATUS=false
FORCE_SWITCH=false

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
        --status)
            SHOW_STATUS=true
            shift
            ;;
        --force)
            FORCE_SWITCH=true
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
        show_runner_status
        exit 0
    fi
    
    if [ "$VALIDATE_ONLY" = true ]; then
        if ! validate_prerequisites; then
            exit 1
        fi
        if ! validate_repositories; then
            exit 1
        fi
        if ! validate_no_conflicts; then
            log_warning "Validation completed with warnings"
            exit 0
        fi
        log_success "All validations passed. Ready for repository switching."
        exit 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN MODE - No changes will be made"
        log_info "Would switch runner from:"
        log_info "  Current: $CURRENT_GITHUB_USERNAME/$CURRENT_GITHUB_REPOSITORY"
        log_info "  New: $NEW_GITHUB_USERNAME/$NEW_GITHUB_REPOSITORY"
        log_info "  Runner Name: $RUNNER_NAME"
        log_info "  Labels: $RUNNER_LABELS"
        exit 0
    fi
    
    # Run the main switching process
    if switch_repository_runner; then
        exit 0
    else
        log_error "Repository runner switching failed"
        exit 1
    fi
}

# Execute main function
main "$@"