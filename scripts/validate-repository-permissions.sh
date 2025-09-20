#!/bin/bash

# Repository Permission Validation Script
# This script validates all necessary permissions and configurations for repository-level GitHub Actions runners

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
GITHUB_USERNAME="${GITHUB_USERNAME:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GH_PAT="${GH_PAT:-}"
EC2_INSTANCE_ID="${EC2_INSTANCE_ID:-}"
RUNNER_NAME="${RUNNER_NAME:-gha_aws_runner}"

# Validation results
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
    ((VALIDATION_WARNINGS++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((VALIDATION_ERRORS++))
}

# Validation functions
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check required commands
    local commands=("curl" "jq" "aws")
    for cmd in "${commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log_success "$cmd is installed"
        else
            log_error "$cmd is not installed or not in PATH"
        fi
    done
    
    # Check required environment variables
    local vars=("GITHUB_USERNAME" "GITHUB_REPOSITORY" "GH_PAT" "EC2_INSTANCE_ID")
    for var in "${vars[@]}"; do
        if [ -n "${!var}" ]; then
            log_success "$var is set"
        else
            log_error "$var environment variable is not set"
        fi
    done
    
    # Validate environment variable formats
    if [ -n "$GITHUB_USERNAME" ]; then
        if [[ "$GITHUB_USERNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
            log_success "GITHUB_USERNAME format is valid"
        else
            log_error "GITHUB_USERNAME format is invalid (contains invalid characters)"
        fi
    fi
    
    if [ -n "$GITHUB_REPOSITORY" ]; then
        if [[ "$GITHUB_REPOSITORY" =~ ^[a-zA-Z0-9._-]+$ ]]; then
            log_success "GITHUB_REPOSITORY format is valid"
        else
            log_error "GITHUB_REPOSITORY format is invalid (contains invalid characters)"
        fi
    fi
    
    if [ -n "$EC2_INSTANCE_ID" ]; then
        if [[ "$EC2_INSTANCE_ID" =~ ^i-[0-9a-f]{8,17}$ ]]; then
            log_success "EC2_INSTANCE_ID format is valid"
        else
            log_error "EC2_INSTANCE_ID format is invalid (should be i-xxxxxxxxx)"
        fi
    fi
}

validate_github_api_access() {
    log_info "Validating GitHub API access..."
    
    # Test basic API access
    local user_response
    user_response=$(curl -s -w "%{http_code}" -H "Authorization: token $GH_PAT" \
        "https://api.github.com/user" 2>/dev/null)
    
    local http_code="${user_response: -3}"
    local user_body="${user_response%???}"
    
    case "$http_code" in
        200)
            local username
            username=$(echo "$user_body" | jq -r '.login')
            log_success "GitHub API access working (authenticated as: $username)"
            
            # Verify the authenticated user matches GITHUB_USERNAME
            if [ "$username" = "$GITHUB_USERNAME" ]; then
                log_success "Authenticated user matches GITHUB_USERNAME"
            else
                log_warning "Authenticated user ($username) differs from GITHUB_USERNAME ($GITHUB_USERNAME)"
            fi
            ;;
        401)
            log_error "GitHub API authentication failed - invalid or expired PAT"
            ;;
        403)
            log_error "GitHub API access forbidden - check PAT permissions"
            ;;
        *)
            log_error "GitHub API access failed (HTTP $http_code)"
            ;;
    esac
    
    # Check PAT scopes
    local scopes_header
    scopes_header=$(curl -s -I -H "Authorization: token $GH_PAT" \
        "https://api.github.com/user" 2>/dev/null | grep -i "x-oauth-scopes:" || echo "")
    
    if [ -n "$scopes_header" ]; then
        local scopes
        scopes=$(echo "$scopes_header" | cut -d: -f2 | tr -d ' \r\n')
        log_info "PAT scopes: $scopes"
        
        if echo "$scopes" | grep -q "repo"; then
            log_success "PAT has 'repo' scope"
        else
            log_error "PAT missing 'repo' scope (required for repository-level runners)"
        fi
        
        if echo "$scopes" | grep -q "admin:org"; then
            log_warning "PAT has 'admin:org' scope (not needed for repository-level runners)"
        fi
    else
        log_warning "Could not determine PAT scopes"
    fi
}

validate_repository_access() {
    log_info "Validating repository access..."
    
    # Test repository access
    local repo_response
    repo_response=$(curl -s -w "%{http_code}" -H "Authorization: token $GH_PAT" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY" 2>/dev/null)
    
    local http_code="${repo_response: -3}"
    local repo_body="${repo_response%???}"
    
    case "$http_code" in
        200)
            log_success "Repository access working"
            
            # Extract repository information
            local repo_name private_repo default_branch
            repo_name=$(echo "$repo_body" | jq -r '.name')
            private_repo=$(echo "$repo_body" | jq -r '.private')
            default_branch=$(echo "$repo_body" | jq -r '.default_branch')
            
            log_info "Repository name: $repo_name"
            log_info "Private repository: $private_repo"
            log_info "Default branch: $default_branch"
            
            # Check if Actions are enabled
            local has_actions
            has_actions=$(echo "$repo_body" | jq -r '.has_actions // false')
            if [ "$has_actions" = "true" ]; then
                log_success "GitHub Actions are enabled for this repository"
            else
                log_warning "GitHub Actions may not be enabled for this repository"
            fi
            ;;
        404)
            log_error "Repository not found or no access (check repository name and PAT permissions)"
            ;;
        403)
            log_error "Repository access forbidden (insufficient permissions)"
            ;;
        *)
            log_error "Repository access failed (HTTP $http_code)"
            ;;
    esac
}

validate_repository_permissions() {
    log_info "Validating repository permissions..."
    
    # Check user's permission level on the repository
    local perm_response
    perm_response=$(curl -s -w "%{http_code}" -H "Authorization: token $GH_PAT" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/collaborators/$GITHUB_USERNAME/permission" 2>/dev/null)
    
    local http_code="${perm_response: -3}"
    local perm_body="${perm_response%???}"
    
    case "$http_code" in
        200)
            local permission
            permission=$(echo "$perm_body" | jq -r '.permission')
            
            case "$permission" in
                "admin")
                    log_success "Repository admin permissions confirmed"
                    ;;
                "write"|"maintain")
                    log_warning "Repository permission level: $permission (admin required for runner management)"
                    ;;
                "read")
                    log_error "Repository permission level: read (admin required for runner management)"
                    ;;
                *)
                    log_warning "Unknown repository permission level: $permission"
                    ;;
            esac
            ;;
        404)
            log_error "Could not check repository permissions (user may not be a collaborator)"
            ;;
        403)
            log_error "Insufficient permissions to check repository permissions"
            ;;
        *)
            log_error "Repository permission check failed (HTTP $http_code)"
            ;;
    esac
}

validate_actions_permissions() {
    log_info "Validating GitHub Actions permissions..."
    
    # Check repository Actions permissions
    local actions_response
    actions_response=$(curl -s -w "%{http_code}" -H "Authorization: token $GH_PAT" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/permissions" 2>/dev/null)
    
    local http_code="${actions_response: -3}"
    local actions_body="${actions_response%???}"
    
    case "$http_code" in
        200)
            local enabled allowed_actions
            enabled=$(echo "$actions_body" | jq -r '.enabled')
            allowed_actions=$(echo "$actions_body" | jq -r '.allowed_actions')
            
            if [ "$enabled" = "true" ]; then
                log_success "GitHub Actions are enabled for this repository"
                log_info "Allowed actions: $allowed_actions"
            else
                log_error "GitHub Actions are disabled for this repository"
            fi
            ;;
        404)
            log_warning "Could not check Actions permissions (may not be available for this repository type)"
            ;;
        403)
            log_error "Insufficient permissions to check Actions settings"
            ;;
        *)
            log_warning "Actions permission check failed (HTTP $http_code)"
            ;;
    esac
    
    # Test runner registration token generation
    log_info "Testing runner registration token generation..."
    local token_response
    token_response=$(curl -s -w "%{http_code}" -X POST \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners/registration-token" 2>/dev/null)
    
    local http_code="${token_response: -3}"
    local token_body="${token_response%???}"
    
    case "$http_code" in
        201)
            log_success "Runner registration token generation working"
            local expires_at
            expires_at=$(echo "$token_body" | jq -r '.expires_at')
            log_info "Token expires at: $expires_at"
            ;;
        403)
            log_error "Cannot generate runner registration token (insufficient permissions)"
            ;;
        404)
            log_error "Runner registration endpoint not found (Actions may be disabled)"
            ;;
        *)
            log_error "Runner registration token generation failed (HTTP $http_code)"
            ;;
    esac
}

validate_existing_runners() {
    log_info "Checking existing repository runners..."
    
    # List existing runners
    local runners_response
    runners_response=$(curl -s -w "%{http_code}" -H "Authorization: token $GH_PAT" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners" 2>/dev/null)
    
    local http_code="${runners_response: -3}"
    local runners_body="${runners_response%???}"
    
    case "$http_code" in
        200)
            local runner_count
            runner_count=$(echo "$runners_body" | jq '.total_count')
            
            if [ "$runner_count" -eq 0 ]; then
                log_info "No existing runners found in repository"
            else
                log_info "Found $runner_count existing runner(s):"
                echo "$runners_body" | jq -r '.runners[] | "  - \(.name) (\(.status)) - Labels: \([.labels[].name] | join(","))"'
                
                # Check if our target runner name already exists
                local existing_runner
                existing_runner=$(echo "$runners_body" | jq -r ".runners[] | select(.name==\"$RUNNER_NAME\") | .name")
                
                if [ "$existing_runner" = "$RUNNER_NAME" ]; then
                    log_warning "Runner with name '$RUNNER_NAME' already exists in repository"
                else
                    log_success "Target runner name '$RUNNER_NAME' is available"
                fi
            fi
            ;;
        403)
            log_error "Cannot list repository runners (insufficient permissions)"
            ;;
        404)
            log_error "Repository runners endpoint not found"
            ;;
        *)
            log_error "Failed to list repository runners (HTTP $http_code)"
            ;;
    esac
}

validate_aws_access() {
    log_info "Validating AWS access..."
    
    # Test AWS CLI access
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI access failed (check credentials and configuration)"
        return
    fi
    
    log_success "AWS CLI access working"
    
    # Get caller identity
    local caller_identity
    caller_identity=$(aws sts get-caller-identity 2>/dev/null)
    local aws_account
    aws_account=$(echo "$caller_identity" | jq -r '.Account')
    local aws_user_arn
    aws_user_arn=$(echo "$caller_identity" | jq -r '.Arn')
    
    log_info "AWS Account: $aws_account"
    log_info "AWS User/Role: $aws_user_arn"
    
    # Test EC2 instance access
    if [ -n "$EC2_INSTANCE_ID" ]; then
        log_info "Validating EC2 instance access..."
        
        local instance_info
        if instance_info=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" 2>/dev/null); then
            log_success "EC2 instance access working"
            
            local instance_state instance_type
            instance_state=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].State.Name')
            instance_type=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].InstanceType')
            
            log_info "Instance state: $instance_state"
            log_info "Instance type: $instance_type"
            
            if [ "$instance_state" = "running" ]; then
                local public_ip
                public_ip=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].PublicIpAddress')
                if [ "$public_ip" != "null" ]; then
                    log_success "Instance has public IP: $public_ip"
                else
                    log_warning "Instance does not have a public IP address"
                fi
            fi
        else
            log_error "Cannot access EC2 instance (check instance ID and IAM permissions)"
        fi
    fi
    
    # Test required EC2 permissions
    log_info "Testing EC2 permissions..."
    
    local permissions=("ec2:DescribeInstances" "ec2:StartInstances" "ec2:StopInstances")
    for permission in "${permissions[@]}"; do
        # This is a simplified check - in practice, you'd need to test actual operations
        log_info "Required permission: $permission"
    done
}

validate_network_connectivity() {
    log_info "Validating network connectivity..."
    
    # Test GitHub connectivity
    if curl -I https://github.com >/dev/null 2>&1; then
        log_success "GitHub.com is accessible"
    else
        log_error "Cannot reach GitHub.com"
    fi
    
    if curl -I https://api.github.com >/dev/null 2>&1; then
        log_success "GitHub API is accessible"
    else
        log_error "Cannot reach GitHub API"
    fi
    
    # Test repository-specific endpoint
    local repo_url="https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY"
    if curl -I "$repo_url" >/dev/null 2>&1; then
        log_success "Repository API endpoint is accessible"
    else
        log_warning "Cannot reach repository API endpoint"
    fi
    
    # Test EC2 connectivity if instance is running
    if [ -n "$EC2_INSTANCE_ID" ]; then
        local instance_state
        instance_state=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" \
            --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null)
        
        if [ "$instance_state" = "running" ]; then
            local public_ip
            public_ip=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" \
                --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null)
            
            if [ "$public_ip" != "null" ] && [ -n "$public_ip" ]; then
                log_info "Testing SSH connectivity to EC2 instance..."
                if nc -z -w5 "$public_ip" 22 2>/dev/null; then
                    log_success "SSH port (22) is accessible on EC2 instance"
                else
                    log_warning "SSH port (22) is not accessible on EC2 instance"
                fi
            fi
        fi
    fi
}

validate_repository_secrets() {
    log_info "Validating repository secrets configuration..."
    
    # List repository secrets (names only)
    local secrets_response
    secrets_response=$(curl -s -w "%{http_code}" -H "Authorization: token $GH_PAT" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/secrets" 2>/dev/null)
    
    local http_code="${secrets_response: -3}"
    local secrets_body="${secrets_response%???}"
    
    case "$http_code" in
        200)
            log_success "Repository secrets API access working"
            
            local secret_names
            secret_names=$(echo "$secrets_body" | jq -r '.secrets[].name')
            
            # Required secrets for repository runner
            local required_secrets=("AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_REGION" "GH_PAT" "EC2_INSTANCE_ID" "RUNNER_NAME")
            
            for secret in "${required_secrets[@]}"; do
                if echo "$secret_names" | grep -q "^$secret$"; then
                    log_success "Required secret '$secret' is configured"
                else
                    log_warning "Required secret '$secret' is not configured"
                fi
            done
            
            # Optional but recommended secrets
            local optional_secrets=("GITHUB_USERNAME" "GITHUB_REPOSITORY")
            for secret in "${optional_secrets[@]}"; do
                if echo "$secret_names" | grep -q "^$secret$"; then
                    log_info "Optional secret '$secret' is configured"
                else
                    log_info "Optional secret '$secret' is not configured"
                fi
            done
            ;;
        403)
            log_error "Cannot access repository secrets (insufficient permissions)"
            ;;
        404)
            log_error "Repository secrets endpoint not found"
            ;;
        *)
            log_warning "Repository secrets check failed (HTTP $http_code)"
            ;;
    esac
}

generate_summary_report() {
    echo ""
    echo "=================================="
    echo "VALIDATION SUMMARY REPORT"
    echo "=================================="
    echo "Repository: $GITHUB_USERNAME/$GITHUB_REPOSITORY"
    echo "Timestamp: $(date -u)"
    echo ""
    
    if [ $VALIDATION_ERRORS -eq 0 ] && [ $VALIDATION_WARNINGS -eq 0 ]; then
        log_success "All validations passed! Repository is ready for runner setup."
    elif [ $VALIDATION_ERRORS -eq 0 ]; then
        log_warning "Validation completed with $VALIDATION_WARNINGS warning(s). Repository should work but may have minor issues."
    else
        log_error "Validation failed with $VALIDATION_ERRORS error(s) and $VALIDATION_WARNINGS warning(s)."
        echo ""
        echo "Please address the errors before setting up the repository runner."
    fi
    
    echo ""
    echo "Next steps:"
    if [ $VALIDATION_ERRORS -eq 0 ]; then
        echo "1. Configure repository secrets if not already done"
        echo "2. Run the repository runner setup script"
        echo "3. Test with a simple workflow"
    else
        echo "1. Fix the validation errors listed above"
        echo "2. Re-run this validation script"
        echo "3. Proceed with runner setup once all errors are resolved"
    fi
    
    echo ""
    echo "For troubleshooting help, see:"
    echo "- docs/repository-troubleshooting-guide.md"
    echo "- docs/repository-migration-guide.md"
}

# Main execution
main() {
    echo "=================================="
    echo "REPOSITORY PERMISSION VALIDATION"
    echo "=================================="
    echo "This script validates all necessary permissions and configurations"
    echo "for setting up repository-level GitHub Actions runners."
    echo ""
    echo "Repository: $GITHUB_USERNAME/$GITHUB_REPOSITORY"
    echo "Runner Name: $RUNNER_NAME"
    echo "EC2 Instance: $EC2_INSTANCE_ID"
    echo ""
    
    # Run all validation checks
    validate_prerequisites
    echo ""
    
    validate_github_api_access
    echo ""
    
    validate_repository_access
    echo ""
    
    validate_repository_permissions
    echo ""
    
    validate_actions_permissions
    echo ""
    
    validate_existing_runners
    echo ""
    
    validate_aws_access
    echo ""
    
    validate_network_connectivity
    echo ""
    
    validate_repository_secrets
    
    # Generate summary report
    generate_summary_report
    
    # Exit with appropriate code
    if [ $VALIDATION_ERRORS -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Script usage information
usage() {
    echo "Usage: $0"
    echo ""
    echo "Environment variables required:"
    echo "  GITHUB_USERNAME      - Your GitHub username"
    echo "  GITHUB_REPOSITORY    - Repository name"
    echo "  GH_PAT              - GitHub Personal Access Token with 'repo' scope"
    echo "  EC2_INSTANCE_ID     - EC2 instance ID for the runner"
    echo ""
    echo "Optional environment variables:"
    echo "  RUNNER_NAME         - Runner name (default: gha_aws_runner)"
    echo ""
    echo "Example:"
    echo "  export GITHUB_USERNAME='myusername'"
    echo "  export GITHUB_REPOSITORY='myrepo'"
    echo "  export GH_PAT='ghp_xxxxxxxxxxxx'"
    echo "  export EC2_INSTANCE_ID='i-1234567890abcdef0'"
    echo "  $0"
}

# Check if help is requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
    exit 0
fi

# Check if required variables are set
if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPOSITORY" ] || [ -z "$GH_PAT" ] || [ -z "$EC2_INSTANCE_ID" ]; then
    echo "Error: Required environment variables are not set."
    echo ""
    usage
    exit 1
fi

# Run main function
main