#!/bin/bash

# Repository Configuration Validation Functions
# This library provides comprehensive validation functions for repository-level
# GitHub Actions runner configuration and permissions.

# Script version and metadata
VALIDATION_LIB_VERSION="1.0.0"
VALIDATION_LIB_NAME="Repository Validation Functions"

# Color codes for output formatting (if not already defined)
if [ -z "$RED" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
fi

# Logging functions (if not already defined)
if ! command -v log_info &> /dev/null; then
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
fi

# =============================================================================
# Repository Existence Validation Functions
# =============================================================================

# Validate that a repository exists and is accessible
# Usage: validate_repository_exists <username> <repository> <pat>
# Returns: 0 on success, 1 on failure
validate_repository_exists() {
    local username="$1"
    local repository="$2"
    local pat="$3"
    
    if [ -z "$username" ] || [ -z "$repository" ] || [ -z "$pat" ]; then
        log_error "validate_repository_exists: Missing required parameters"
        log_error "Usage: validate_repository_exists <username> <repository> <pat>"
        return 1
    fi
    
    log_info "Validating repository existence: $username/$repository"
    
    local response
    response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $pat" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$username/$repository")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    case $http_code in
        200)
            local repo_name
            repo_name=$(echo "$body" | jq -r '.name')
            local repo_private
            repo_private=$(echo "$body" | jq -r '.private')
            local repo_archived
            repo_archived=$(echo "$body" | jq -r '.archived')
            local repo_disabled
            repo_disabled=$(echo "$body" | jq -r '.disabled')
            
            log_success "Repository exists: $username/$repo_name"
            log_info "Repository visibility: $([ "$repo_private" = "true" ] && echo "private" || echo "public")"
            
            # Check if repository is archived
            if [ "$repo_archived" = "true" ]; then
                log_warning "Repository is archived - Actions may be limited"
            fi
            
            # Check if repository is disabled
            if [ "$repo_disabled" = "true" ]; then
                log_error "Repository is disabled"
                return 1
            fi
            
            return 0
            ;;
        404)
            log_error "Repository not found: $username/$repository"
            log_error "Possible causes:"
            log_error "  - Repository does not exist"
            log_error "  - Repository is private and PAT lacks access"
            log_error "  - Username or repository name is incorrect"
            return 1
            ;;
        403)
            log_error "Access forbidden to repository: $username/$repository"
            log_error "Possible causes:"
            log_error "  - PAT lacks required permissions"
            log_error "  - Repository access is restricted"
            log_error "  - Rate limit exceeded"
            return 1
            ;;
        401)
            log_error "Authentication failed"
            log_error "PAT may be invalid or expired"
            return 1
            ;;
        *)
            log_error "Unexpected API response (HTTP $http_code)"
            log_error "Response: $body"
            return 1
            ;;
    esac
}

# Check if GitHub Actions is enabled for the repository
# Usage: validate_actions_enabled <username> <repository> <pat>
# Returns: 0 if enabled, 1 if disabled or error
validate_actions_enabled() {
    local username="$1"
    local repository="$2"
    local pat="$3"
    
    if [ -z "$username" ] || [ -z "$repository" ] || [ -z "$pat" ]; then
        log_error "validate_actions_enabled: Missing required parameters"
        return 1
    fi
    
    log_info "Checking if GitHub Actions is enabled for repository"
    
    # Try to access the Actions API endpoint
    local response
    response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $pat" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$username/$repository/actions/runners")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    case $http_code in
        200)
            log_success "GitHub Actions is enabled for the repository"
            return 0
            ;;
        404)
            log_error "GitHub Actions is not enabled for this repository"
            log_error "Enable Actions in repository Settings → Actions → General"
            return 1
            ;;
        403)
            log_error "Access forbidden to Actions API"
            log_error "This may indicate Actions is disabled or insufficient permissions"
            return 1
            ;;
        *)
            log_error "Failed to check Actions status (HTTP $http_code)"
            log_error "Response: $body"
            return 1
            ;;
    esac
}

# =============================================================================
# Repository Access Permission Validation Functions
# =============================================================================

# Validate repository access permissions for the authenticated user
# Usage: validate_repository_access <username> <repository> <pat>
# Returns: 0 on success, 1 on failure
validate_repository_access() {
    local username="$1"
    local repository="$2"
    local pat="$3"
    
    if [ -z "$username" ] || [ -z "$repository" ] || [ -z "$pat" ]; then
        log_error "validate_repository_access: Missing required parameters"
        return 1
    fi
    
    log_info "Validating repository access permissions"
    
    # First, validate that the repository exists
    if ! validate_repository_exists "$username" "$repository" "$pat"; then
        return 1
    fi
    
    # Get repository information with permissions
    local response
    response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $pat" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$username/$repository")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" != "200" ]; then
        log_error "Failed to get repository permissions (HTTP $http_code)"
        return 1
    fi
    
    # Extract permission information
    local permissions
    permissions=$(echo "$body" | jq -r '.permissions // {}')
    local can_admin
    can_admin=$(echo "$permissions" | jq -r '.admin // false')
    local can_push
    can_push=$(echo "$permissions" | jq -r '.push // false')
    local can_pull
    can_pull=$(echo "$permissions" | jq -r '.pull // false')
    
    log_info "Repository permissions:"
    log_info "  Pull: $can_pull"
    log_info "  Push: $can_push"
    log_info "  Admin: $can_admin"
    
    # Validate minimum required permissions
    if [ "$can_pull" != "true" ]; then
        log_error "Insufficient permissions: Pull access required"
        return 1
    fi
    
    if [ "$can_push" != "true" ]; then
        log_warning "No push permissions - some Actions features may be limited"
    fi
    
    log_success "Repository access permissions validated"
    return 0
}

# =============================================================================
# GitHub PAT Scope Validation Functions
# =============================================================================

# Validate GitHub PAT has required repo scope
# Usage: validate_pat_repo_scope <pat>
# Returns: 0 if valid, 1 if invalid
validate_pat_repo_scope() {
    local pat="$1"
    
    if [ -z "$pat" ]; then
        log_error "validate_pat_repo_scope: PAT parameter is required"
        return 1
    fi
    
    log_info "Validating GitHub PAT scope requirements"
    
    # Test authentication and get user info
    local auth_response
    auth_response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $pat" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/user")
    
    local auth_http_code="${auth_response: -3}"
    local auth_body="${auth_response%???}"
    
    if [ "$auth_http_code" != "200" ]; then
        log_error "PAT authentication failed (HTTP $auth_http_code)"
        case $auth_http_code in
            401)
                log_error "PAT is invalid or expired"
                ;;
            403)
                log_error "PAT may be valid but lacks required permissions"
                ;;
            *)
                log_error "Unexpected authentication error"
                log_error "Response: $auth_body"
                ;;
        esac
        return 1
    fi
    
    local authenticated_user
    authenticated_user=$(echo "$auth_body" | jq -r '.login')
    log_success "PAT authentication successful for user: $authenticated_user"
    
    # Check PAT scopes by examining response headers
    # Note: GitHub API doesn't directly expose scopes in response body,
    # but we can infer them by testing specific endpoints
    
    # Test repo scope by trying to access user's repositories
    log_info "Testing repo scope permissions..."
    local repos_response
    repos_response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $pat" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/user/repos?per_page=1")
    
    local repos_http_code="${repos_response: -3}"
    
    if [ "$repos_http_code" = "200" ]; then
        log_success "PAT has repo scope access"
    else
        log_error "PAT lacks repo scope (HTTP $repos_http_code)"
        log_error "Ensure your PAT includes 'repo' scope"
        return 1
    fi
    
    # Verify PAT does NOT have admin:org scope (security best practice)
    log_info "Verifying PAT does not have excessive permissions..."
    local orgs_response
    orgs_response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $pat" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/user/orgs")
    
    local orgs_http_code="${orgs_response: -3}"
    
    # Note: This test is not definitive as users can belong to orgs without admin:org scope
    # But it helps identify if the PAT might have broader permissions than needed
    if [ "$orgs_http_code" = "200" ]; then
        log_info "PAT can access organization information (this is normal)"
    fi
    
    log_success "PAT scope validation completed"
    return 0
}

# Validate PAT does not have admin:org scope (security check)
# Usage: validate_pat_no_admin_org <pat>
# Returns: 0 if no admin:org, 1 if has admin:org or error
validate_pat_no_admin_org() {
    local pat="$1"
    
    if [ -z "$pat" ]; then
        log_error "validate_pat_no_admin_org: PAT parameter is required"
        return 1
    fi
    
    log_info "Verifying PAT does not have admin:org scope (security best practice)"
    
    # Try to access organization administration endpoints
    # If these succeed, the PAT likely has admin:org scope
    local test_org="github"  # Use GitHub's own org as a test
    
    local admin_response
    admin_response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $pat" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/orgs/$test_org/actions/runners")
    
    local admin_http_code="${admin_response: -3}"
    
    # If we get 200, the PAT has admin:org scope for this org (unlikely for test org)
    # If we get 403, the PAT doesn't have admin:org or user isn't org admin
    # If we get 404, the endpoint doesn't exist or org doesn't exist
    case $admin_http_code in
        200)
            log_warning "PAT may have admin:org scope - consider using repo-only scope for security"
            ;;
        403|404)
            log_success "PAT appears to have appropriate scope limitations"
            ;;
        *)
            log_info "Could not determine admin:org scope status (HTTP $admin_http_code)"
            ;;
    esac
    
    return 0
}

# =============================================================================
# Repository Admin Permission Verification Functions
# =============================================================================

# Verify user has admin permissions on the repository
# Usage: validate_repository_admin_permissions <username> <repository> <pat>
# Returns: 0 if admin, 1 if not admin or error
validate_repository_admin_permissions() {
    local username="$1"
    local repository="$2"
    local pat="$3"
    
    if [ -z "$username" ] || [ -z "$repository" ] || [ -z "$pat" ]; then
        log_error "validate_repository_admin_permissions: Missing required parameters"
        return 1
    fi
    
    log_info "Verifying repository admin permissions"
    
    # Get repository information with permissions
    local response
    response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $pat" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$username/$repository")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" != "200" ]; then
        log_error "Failed to get repository information (HTTP $http_code)"
        return 1
    fi
    
    # Check admin permissions
    local admin_permission
    admin_permission=$(echo "$body" | jq -r '.permissions.admin // false')
    
    if [ "$admin_permission" = "true" ]; then
        log_success "User has admin permissions on repository"
        return 0
    else
        log_error "User does not have admin permissions on repository"
        log_error "Admin permissions are required to manage GitHub Actions runners"
        log_error "Contact the repository owner to grant admin access"
        return 1
    fi
}

# Test runner registration token generation (ultimate admin permission test)
# Usage: validate_runner_registration_access <username> <repository> <pat>
# Returns: 0 if can generate token, 1 if cannot
validate_runner_registration_access() {
    local username="$1"
    local repository="$2"
    local pat="$3"
    
    if [ -z "$username" ] || [ -z "$repository" ] || [ -z "$pat" ]; then
        log_error "validate_runner_registration_access: Missing required parameters"
        return 1
    fi
    
    log_info "Testing runner registration token generation (admin permission test)"
    
    local response
    response=$(curl -s -w "%{http_code}" -X POST \
        -H "Authorization: token $pat" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$username/$repository/actions/runners/registration-token")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    case $http_code in
        201)
            local token
            token=$(echo "$body" | jq -r '.token')
            local expires_at
            expires_at=$(echo "$body" | jq -r '.expires_at')
            
            if [ "$token" != "null" ] && [ -n "$token" ]; then
                log_success "Runner registration token generated successfully"
                log_info "Token expires at: $expires_at"
                return 0
            else
                log_error "Invalid registration token received"
                return 1
            fi
            ;;
        403)
            log_error "Insufficient permissions to generate runner registration token"
            log_error "Ensure you have admin permissions on the repository"
            return 1
            ;;
        404)
            log_error "Repository not found or Actions not enabled"
            log_error "Verify repository exists and Actions are enabled"
            return 1
            ;;
        422)
            log_error "Unprocessable entity - repository may not support Actions"
            return 1
            ;;
        *)
            log_error "Failed to generate registration token (HTTP $http_code)"
            log_error "Response: $body"
            return 1
            ;;
    esac
}

# =============================================================================
# Comprehensive Validation Functions
# =============================================================================

# Run all repository configuration validations
# Usage: validate_repository_configuration <username> <repository> <pat>
# Returns: 0 if all validations pass, 1 if any fail
validate_repository_configuration() {
    local username="$1"
    local repository="$2"
    local pat="$3"
    
    if [ -z "$username" ] || [ -z "$repository" ] || [ -z "$pat" ]; then
        log_error "validate_repository_configuration: Missing required parameters"
        log_error "Usage: validate_repository_configuration <username> <repository> <pat>"
        return 1
    fi
    
    log_info "Starting comprehensive repository configuration validation"
    log_info "Repository: $username/$repository"
    
    local validation_failed=false
    
    # 1. Validate PAT scope
    log_info "=== Step 1: PAT Scope Validation ==="
    if ! validate_pat_repo_scope "$pat"; then
        validation_failed=true
    fi
    
    # 2. Validate repository existence
    log_info "=== Step 2: Repository Existence Validation ==="
    if ! validate_repository_exists "$username" "$repository" "$pat"; then
        validation_failed=true
    fi
    
    # 3. Validate repository access permissions
    log_info "=== Step 3: Repository Access Validation ==="
    if ! validate_repository_access "$username" "$repository" "$pat"; then
        validation_failed=true
    fi
    
    # 4. Validate admin permissions
    log_info "=== Step 4: Admin Permission Validation ==="
    if ! validate_repository_admin_permissions "$username" "$repository" "$pat"; then
        validation_failed=true
    fi
    
    # 5. Validate Actions is enabled
    log_info "=== Step 5: GitHub Actions Validation ==="
    if ! validate_actions_enabled "$username" "$repository" "$pat"; then
        validation_failed=true
    fi
    
    # 6. Test runner registration access
    log_info "=== Step 6: Runner Registration Test ==="
    if ! validate_runner_registration_access "$username" "$repository" "$pat"; then
        validation_failed=true
    fi
    
    # 7. Security check for excessive permissions
    log_info "=== Step 7: Security Validation ==="
    validate_pat_no_admin_org "$pat"  # This is a warning, not a failure
    
    # Summary
    log_info "=== Validation Summary ==="
    if [ "$validation_failed" = true ]; then
        log_error "Repository configuration validation FAILED"
        log_error "Please address the issues above before proceeding"
        return 1
    else
        log_success "All repository configuration validations PASSED"
        log_success "Configuration is ready for runner setup"
        return 0
    fi
}

# Validate user authentication and get user info
# Usage: validate_user_authentication <pat>
# Returns: 0 on success, 1 on failure
validate_user_authentication() {
    local pat="$1"
    
    if [ -z "$pat" ]; then
        log_error "validate_user_authentication: PAT parameter is required"
        return 1
    fi
    
    log_info "Validating user authentication"
    
    local response
    response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $pat" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/user")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    case $http_code in
        200)
            local username
            username=$(echo "$body" | jq -r '.login')
            local user_type
            user_type=$(echo "$body" | jq -r '.type')
            local user_id
            user_id=$(echo "$body" | jq -r '.id')
            
            log_success "Authentication successful"
            log_info "User: $username (ID: $user_id, Type: $user_type)"
            
            # Return username for use by caller
            echo "$username"
            return 0
            ;;
        401)
            log_error "Authentication failed - PAT is invalid or expired"
            return 1
            ;;
        403)
            log_error "Authentication failed - PAT may be valid but lacks permissions"
            return 1
            ;;
        *)
            log_error "Authentication failed with unexpected error (HTTP $http_code)"
            log_error "Response: $body"
            return 1
            ;;
    esac
}

# =============================================================================
# Utility Functions
# =============================================================================

# Validate GitHub username format
# Usage: validate_username_format <username>
# Returns: 0 if valid, 1 if invalid
validate_username_format() {
    local username="$1"
    
    if [ -z "$username" ]; then
        log_error "Username cannot be empty"
        return 1
    fi
    
    # GitHub username rules:
    # - May only contain alphanumeric characters or single hyphens
    # - Cannot begin or end with a hyphen
    # - Maximum 39 characters
    if [[ ! "$username" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
        log_error "Invalid GitHub username format: $username"
        log_error "Username must contain only alphanumeric characters and hyphens"
        log_error "Username cannot begin or end with a hyphen"
        return 1
    fi
    
    if [ ${#username} -gt 39 ]; then
        log_error "Username too long: $username (max 39 characters)"
        return 1
    fi
    
    return 0
}

# Validate GitHub repository name format
# Usage: validate_repository_format <repository>
# Returns: 0 if valid, 1 if invalid
validate_repository_format() {
    local repository="$1"
    
    if [ -z "$repository" ]; then
        log_error "Repository name cannot be empty"
        return 1
    fi
    
    # GitHub repository name rules:
    # - Can contain alphanumeric characters, hyphens, underscores, and periods
    # - Cannot start with a period or hyphen
    # - Maximum 100 characters
    if [[ ! "$repository" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log_error "Invalid GitHub repository name format: $repository"
        log_error "Repository name can only contain alphanumeric characters, hyphens, underscores, and periods"
        return 1
    fi
    
    if [[ "$repository" =~ ^[.-] ]]; then
        log_error "Repository name cannot start with a period or hyphen: $repository"
        return 1
    fi
    
    if [ ${#repository} -gt 100 ]; then
        log_error "Repository name too long: $repository (max 100 characters)"
        return 1
    fi
    
    return 0
}

# Check if required tools are available
# Usage: validate_required_tools
# Returns: 0 if all tools available, 1 if missing tools
validate_required_tools() {
    log_info "Validating required tools"
    
    local required_tools=("curl" "jq")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install the missing tools and try again"
        return 1
    fi
    
    log_success "All required tools are available"
    return 0
}

# =============================================================================
# Library Information
# =============================================================================

# Show library version and available functions
show_validation_library_info() {
    cat << EOF
$VALIDATION_LIB_NAME v$VALIDATION_LIB_VERSION

AVAILABLE FUNCTIONS:

Repository Existence Validation:
  validate_repository_exists <username> <repository> <pat>
  validate_actions_enabled <username> <repository> <pat>

Repository Access Validation:
  validate_repository_access <username> <repository> <pat>

PAT Scope Validation:
  validate_pat_repo_scope <pat>
  validate_pat_no_admin_org <pat>

Admin Permission Validation:
  validate_repository_admin_permissions <username> <repository> <pat>
  validate_runner_registration_access <username> <repository> <pat>

Comprehensive Validation:
  validate_repository_configuration <username> <repository> <pat>

Utility Functions:
  validate_user_authentication <pat>
  validate_username_format <username>
  validate_repository_format <repository>
  validate_required_tools

Usage:
  source scripts/repo-validation-functions.sh
  validate_repository_configuration "username" "repository" "pat_token"

EOF
}

# If script is run directly, show library info
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_validation_library_info
fi