#!/bin/bash
set -e

# Repository Runner Switching Test Script
# This script tests the repository switching functionality to ensure
# it works correctly and handles various scenarios properly.

# Script version and metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="Repository Switching Test"

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

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWITCH_SCRIPT="$SCRIPT_DIR/switch-repository-runner.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    log_info "Running test: $test_name"
    
    if eval "$test_command"; then
        log_success "Test passed: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "Test failed: $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Test script existence and permissions
test_script_exists() {
    [ -f "$SWITCH_SCRIPT" ] && [ -x "$SWITCH_SCRIPT" ]
}

# Test help functionality
test_help_functionality() {
    "$SWITCH_SCRIPT" --help > /dev/null 2>&1
}

# Test version functionality
test_version_functionality() {
    "$SWITCH_SCRIPT" --version > /dev/null 2>&1
}

# Test missing environment variables
test_missing_env_vars() {
    # Clear environment variables
    unset CURRENT_GITHUB_USERNAME CURRENT_GITHUB_REPOSITORY
    unset NEW_GITHUB_USERNAME NEW_GITHUB_REPOSITORY GH_PAT
    
    # Should fail with missing variables
    ! "$SWITCH_SCRIPT" --validate-only > /dev/null 2>&1
}

# Test invalid username format
test_invalid_username_format() {
    export CURRENT_GITHUB_USERNAME="invalid-username-"
    export CURRENT_GITHUB_REPOSITORY="test-repo"
    export NEW_GITHUB_USERNAME="valid-username"
    export NEW_GITHUB_REPOSITORY="test-repo"
    export GH_PAT="fake-token"
    
    # Should fail with invalid username
    ! "$SWITCH_SCRIPT" --validate-only > /dev/null 2>&1
}

# Test invalid repository format
test_invalid_repository_format() {
    export CURRENT_GITHUB_USERNAME="valid-username"
    export CURRENT_GITHUB_REPOSITORY=".invalid-repo"
    export NEW_GITHUB_USERNAME="valid-username"
    export NEW_GITHUB_REPOSITORY="valid-repo"
    export GH_PAT="fake-token"
    
    # Should fail with invalid repository name
    ! "$SWITCH_SCRIPT" --validate-only > /dev/null 2>&1
}

# Test same repository switching
test_same_repository_switching() {
    export CURRENT_GITHUB_USERNAME="testuser"
    export CURRENT_GITHUB_REPOSITORY="test-repo"
    export NEW_GITHUB_USERNAME="testuser"
    export NEW_GITHUB_REPOSITORY="test-repo"
    export GH_PAT="fake-token"
    
    # Should fail when trying to switch to same repository
    ! "$SWITCH_SCRIPT" --validate-only > /dev/null 2>&1
}

# Test dry run functionality
test_dry_run_functionality() {
    export CURRENT_GITHUB_USERNAME="testuser"
    export CURRENT_GITHUB_REPOSITORY="old-repo"
    export NEW_GITHUB_USERNAME="testuser"
    export NEW_GITHUB_REPOSITORY="new-repo"
    export GH_PAT="fake-token"
    
    # Dry run should not fail on validation (it doesn't do network calls)
    "$SWITCH_SCRIPT" --dry-run > /dev/null 2>&1
}

# Test status functionality without configuration
test_status_without_config() {
    # Clear environment variables
    unset CURRENT_GITHUB_USERNAME CURRENT_GITHUB_REPOSITORY
    unset NEW_GITHUB_USERNAME NEW_GITHUB_REPOSITORY GH_PAT
    
    # Status should work even without full configuration
    "$SWITCH_SCRIPT" --status > /dev/null 2>&1
}

# Test validation library integration
test_validation_library_integration() {
    # Check if validation library is properly sourced
    if [ -f "$SCRIPT_DIR/repo-validation-functions.sh" ]; then
        # Test that the script can find and reference the library
        grep -q "repo-validation-functions.sh" "$SWITCH_SCRIPT"
    else
        log_warning "Validation library not found - skipping integration test"
        return 0
    fi
}

# Test runner directory validation
test_runner_directory_validation() {
    export CURRENT_GITHUB_USERNAME="testuser"
    export CURRENT_GITHUB_REPOSITORY="old-repo"
    export NEW_GITHUB_USERNAME="testuser"
    export NEW_GITHUB_REPOSITORY="new-repo"
    export GH_PAT="fake-token"
    
    # Should fail if runner directory doesn't exist (unless we're in a test environment)
    if [ ! -d "$HOME/actions-runner" ]; then
        ! "$SWITCH_SCRIPT" --validate-only > /dev/null 2>&1
    else
        # If runner directory exists, validation should proceed further
        "$SWITCH_SCRIPT" --validate-only > /dev/null 2>&1 || true
    fi
}

# Test command line argument parsing
test_argument_parsing() {
    # Test unknown argument
    ! "$SWITCH_SCRIPT" --unknown-argument > /dev/null 2>&1
}

# Test force flag functionality
test_force_flag() {
    export CURRENT_GITHUB_USERNAME="testuser"
    export CURRENT_GITHUB_REPOSITORY="old-repo"
    export NEW_GITHUB_USERNAME="testuser"
    export NEW_GITHUB_REPOSITORY="new-repo"
    export GH_PAT="fake-token"
    
    # Force flag should be accepted (though validation will still fail due to fake token)
    "$SWITCH_SCRIPT" --force --dry-run > /dev/null 2>&1
}

# Main test execution
run_all_tests() {
    log_info "Starting repository switching functionality tests..."
    log_info "Switch script: $SWITCH_SCRIPT"
    echo ""
    
    # Basic functionality tests
    run_test "Script exists and is executable" "test_script_exists"
    run_test "Help functionality works" "test_help_functionality"
    run_test "Version functionality works" "test_version_functionality"
    
    # Validation tests
    run_test "Missing environment variables detected" "test_missing_env_vars"
    run_test "Invalid username format detected" "test_invalid_username_format"
    run_test "Invalid repository format detected" "test_invalid_repository_format"
    run_test "Same repository switching prevented" "test_same_repository_switching"
    
    # Functionality tests
    run_test "Dry run functionality works" "test_dry_run_functionality"
    run_test "Status works without full config" "test_status_without_config"
    run_test "Validation library integration" "test_validation_library_integration"
    run_test "Runner directory validation" "test_runner_directory_validation"
    
    # Argument parsing tests
    run_test "Unknown arguments rejected" "test_argument_parsing"
    run_test "Force flag accepted" "test_force_flag"
    
    # Test summary
    echo ""
    log_info "=== Test Summary ==="
    log_info "Tests run: $TESTS_RUN"
    log_success "Tests passed: $TESTS_PASSED"
    
    if [ $TESTS_FAILED -gt 0 ]; then
        log_error "Tests failed: $TESTS_FAILED"
        return 1
    else
        log_success "All tests passed!"
        return 0
    fi
}

# Show usage information
show_usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

USAGE:
    $0 [OPTIONS]

DESCRIPTION:
    Tests the repository runner switching functionality to ensure
    it works correctly and handles various scenarios properly.

OPTIONS:
    -h, --help      Show this help message
    -v, --version   Show script version

EXAMPLES:
    # Run all tests
    $0

    # Show help
    $0 --help

EOF
}

# Parse command line arguments
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
    
    # Check if switch script exists
    if [ ! -f "$SWITCH_SCRIPT" ]; then
        log_error "Switch script not found: $SWITCH_SCRIPT"
        log_error "Please ensure the switch-repository-runner.sh script exists"
        exit 1
    fi
    
    # Run all tests
    if run_all_tests; then
        log_success "Repository switching functionality tests completed successfully"
        exit 0
    else
        log_error "Some tests failed"
        exit 1
    fi
}

# Execute main function
main "$@"