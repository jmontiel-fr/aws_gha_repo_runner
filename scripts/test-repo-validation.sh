#!/bin/bash

# Test script for repository validation functions
# This script tests all validation functions with various scenarios

set -e

# Source the validation functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/repo-validation-functions.sh"

# Test configuration
TEST_SCRIPT_VERSION="1.0.0"
TEST_SCRIPT_NAME="Repository Validation Test Suite"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
declare -a FAILED_TESTS=()

# Test helper functions
run_test() {
    local test_name="$1"
    local test_function="$2"
    shift 2
    local test_args=("$@")
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    echo ""
    echo "=== Test $TESTS_RUN: $test_name ==="
    
    if $test_function "${test_args[@]}"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log_success "Test PASSED: $test_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$test_name")
        log_error "Test FAILED: $test_name"
    fi
}

# Test format validation functions
test_username_format_validation() {
    log_info "Testing username format validation"
    
    # Valid usernames
    if ! validate_username_format "validuser"; then
        return 1
    fi
    
    if ! validate_username_format "user-name"; then
        return 1
    fi
    
    if ! validate_username_format "user123"; then
        return 1
    fi
    
    # Invalid usernames (should fail)
    if validate_username_format "-invaliduser" 2>/dev/null; then
        log_error "Should have failed for username starting with hyphen"
        return 1
    fi
    
    if validate_username_format "invaliduser-" 2>/dev/null; then
        log_error "Should have failed for username ending with hyphen"
        return 1
    fi
    
    if validate_username_format "" 2>/dev/null; then
        log_error "Should have failed for empty username"
        return 1
    fi
    
    log_success "Username format validation tests passed"
    return 0
}

test_repository_format_validation() {
    log_info "Testing repository format validation"
    
    # Valid repository names
    if ! validate_repository_format "valid-repo"; then
        return 1
    fi
    
    if ! validate_repository_format "repo_name"; then
        return 1
    fi
    
    if ! validate_repository_format "repo.name"; then
        return 1
    fi
    
    if ! validate_repository_format "repo123"; then
        return 1
    fi
    
    # Invalid repository names (should fail)
    if validate_repository_format ".invalidrepo" 2>/dev/null; then
        log_error "Should have failed for repository starting with period"
        return 1
    fi
    
    if validate_repository_format "-invalidrepo" 2>/dev/null; then
        log_error "Should have failed for repository starting with hyphen"
        return 1
    fi
    
    if validate_repository_format "" 2>/dev/null; then
        log_error "Should have failed for empty repository name"
        return 1
    fi
    
    log_success "Repository format validation tests passed"
    return 0
}

test_required_tools_validation() {
    log_info "Testing required tools validation"
    
    # This should pass if curl and jq are installed
    if ! validate_required_tools; then
        log_error "Required tools validation failed - ensure curl and jq are installed"
        return 1
    fi
    
    log_success "Required tools validation test passed"
    return 0
}

# Test with mock/invalid credentials (these should fail gracefully)
test_invalid_pat_handling() {
    log_info "Testing invalid PAT handling"
    
    local invalid_pat="invalid_token_12345"
    
    # This should fail gracefully
    if validate_pat_repo_scope "$invalid_pat" 2>/dev/null; then
        log_error "Should have failed for invalid PAT"
        return 1
    fi
    
    log_success "Invalid PAT handling test passed"
    return 0
}

test_missing_parameters() {
    log_info "Testing missing parameter handling"
    
    # Test functions with missing parameters (should fail)
    if validate_repository_exists "" "" "" 2>/dev/null; then
        log_error "Should have failed for missing parameters"
        return 1
    fi
    
    if validate_repository_access "" "" "" 2>/dev/null; then
        log_error "Should have failed for missing parameters"
        return 1
    fi
    
    if validate_pat_repo_scope "" 2>/dev/null; then
        log_error "Should have failed for missing PAT"
        return 1
    fi
    
    log_success "Missing parameter handling tests passed"
    return 0
}

# Test with environment variables if available
test_with_environment_variables() {
    log_info "Testing with environment variables (if available)"
    
    if [ -n "$GITHUB_USERNAME" ] && [ -n "$GITHUB_REPOSITORY" ] && [ -n "$GH_PAT" ]; then
        log_info "Environment variables found - running live tests"
        
        # Test comprehensive validation
        if validate_repository_configuration "$GITHUB_USERNAME" "$GITHUB_REPOSITORY" "$GH_PAT"; then
            log_success "Live repository configuration validation passed"
        else
            log_warning "Live repository configuration validation failed (this may be expected)"
        fi
    else
        log_info "No environment variables found - skipping live tests"
        log_info "To run live tests, set GITHUB_USERNAME, GITHUB_REPOSITORY, and GH_PAT"
    fi
    
    return 0
}

# Function to show test summary
show_test_summary() {
    echo ""
    echo "=== Test Summary ==="
    echo "Tests Run: $TESTS_RUN"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    
    if [ $TESTS_FAILED -gt 0 ]; then
        echo ""
        echo "Failed Tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
        echo ""
        log_error "Some tests failed"
        return 1
    else
        echo ""
        log_success "All tests passed!"
        return 0
    fi
}

# Main test execution
main() {
    echo "=== $TEST_SCRIPT_NAME v$TEST_SCRIPT_VERSION ==="
    echo ""
    
    # Run all tests
    run_test "Username Format Validation" test_username_format_validation
    run_test "Repository Format Validation" test_repository_format_validation
    run_test "Required Tools Validation" test_required_tools_validation
    run_test "Invalid PAT Handling" test_invalid_pat_handling
    run_test "Missing Parameters Handling" test_missing_parameters
    run_test "Environment Variables Test" test_with_environment_variables
    
    # Show summary
    show_test_summary
}

# Show usage if help requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat << EOF
$TEST_SCRIPT_NAME v$TEST_SCRIPT_VERSION

USAGE:
    $0 [OPTIONS]

DESCRIPTION:
    Tests the repository validation functions library.
    Runs unit tests for format validation, error handling, and parameter validation.
    
    For live API tests, set these environment variables:
    - GITHUB_USERNAME: Your GitHub username
    - GITHUB_REPOSITORY: Repository name to test with
    - GH_PAT: GitHub Personal Access Token with repo scope

OPTIONS:
    -h, --help    Show this help message

EXAMPLES:
    # Run basic tests
    $0
    
    # Run with live API testing
    export GITHUB_USERNAME="myusername"
    export GITHUB_REPOSITORY="my-repo"
    export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
    $0

EOF
    exit 0
fi

# Execute main function
main "$@"