#!/bin/bash

# System Readiness Validation Tests
# This script provides comprehensive unit tests for the system readiness
# validation functions, including cloud-init status checking, resource
# validation, and network connectivity testing.

set -e

# Script version and metadata
TEST_VERSION="1.0.0"
TEST_NAME="System Readiness Validation Tests"

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_READINESS_LIB="$SCRIPT_DIR/system-readiness-functions.sh"
PACKAGE_MANAGER_LIB="$SCRIPT_DIR/package-manager-functions.sh"
ERROR_HANDLER_LIB="$SCRIPT_DIR/installation-error-handler.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test results
declare -a FAILED_TESTS=()
declare -a SKIPPED_TESTS=()

# =============================================================================
# Test Framework Functions
# =============================================================================

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

log_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    if [ "$expected" = "$actual" ]; then
        return 0
    else
        log_error "$message: expected '$expected', got '$actual'"
        return 1
    fi
}

assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    if [ "$not_expected" != "$actual" ]; then
        return 0
    else
        log_error "$message: expected not '$not_expected', but got '$actual'"
        return 1
    fi
}

assert_true() {
    local condition="$1"
    local message="${2:-Assertion failed}"
    
    if [ "$condition" = "true" ] || [ "$condition" = "0" ]; then
        return 0
    else
        log_error "$message: expected true, got '$condition'"
        return 1
    fi
}

assert_false() {
    local condition="$1"
    local message="${2:-Assertion failed}"
    
    if [ "$condition" = "false" ] || [ "$condition" = "1" ]; then
        return 0
    else
        log_error "$message: expected false, got '$condition'"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-Assertion failed}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        log_error "$message: '$haystack' does not contain '$needle'"
        return 1
    fi
}

# Test execution framework
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    log_test "Running test: $test_name"
    
    if $test_function; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log_success "PASSED: $test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$test_name")
        log_error "FAILED: $test_name"
        return 1
    fi
}

skip_test() {
    local test_name="$1"
    local reason="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    SKIPPED_TESTS+=("$test_name")
    
    log_warning "SKIPPED: $test_name - $reason"
}

# =============================================================================
# Mock Functions for Testing
# =============================================================================

# Mock cloud-init command for testing
mock_cloud_init() {
    local status="${MOCK_CLOUD_INIT_STATUS:-done}"
    
    case "$status" in
        "done")
            echo "status: done"
            return 0
            ;;
        "running")
            echo "status: running"
            return 0
            ;;
        "error")
            echo "status: error"
            return 0
            ;;
        "not_found")
            return 127  # Command not found
            ;;
        *)
            echo "status: $status"
            return 0
            ;;
    esac
}

# Mock pgrep for testing
mock_pgrep() {
    local pattern="$1"
    
    case "$MOCK_PGREP_RESULT" in
        "found")
            echo "1234"
            return 0
            ;;
        "not_found")
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Mock df command for testing
mock_df() {
    local path="$1"
    local available_mb="${MOCK_DISK_SPACE:-5000}"
    
    echo "Filesystem     1M-blocks  Used Available Use% Mounted on"
    echo "/dev/sda1          10000  4000    $available_mb  40% /"
}

# Mock free command for testing
mock_free() {
    local available_mb="${MOCK_MEMORY_AVAILABLE:-2000}"
    
    echo "              total        used        free      shared  buff/cache   available"
    echo "Mem:           4000        1500         500           0        2000        $available_mb"
}

# Mock ping command for testing
mock_ping() {
    local host="$1"
    
    case "$MOCK_NETWORK_STATUS" in
        "connected")
            echo "PING $host: 56 data bytes"
            echo "64 bytes from $host: icmp_seq=0 ttl=64 time=1.234 ms"
            return 0
            ;;
        "disconnected")
            echo "ping: cannot resolve $host: Unknown host"
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Mock curl command for testing
mock_curl() {
    local url="$1"
    
    case "$MOCK_CURL_STATUS" in
        "success")
            if [[ "$url" == *"api.github.com/zen"* ]]; then
                echo "Keep it logically awesome."
            elif [[ "$url" == *"api.github.com/user"* ]]; then
                echo '{"login":"testuser","id":12345}'
            fi
            return 0
            ;;
        "failure")
            echo "curl: (7) Failed to connect"
            return 7
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# Cloud-init Status Tests
# =============================================================================

test_check_cloud_init_status_done() {
    # Mock cloud-init as done
    MOCK_CLOUD_INIT_STATUS="done"
    
    # Override cloud-init command
    cloud-init() { mock_cloud_init "$@"; }
    
    # Test the function
    if check_cloud_init_status; then
        assert_equals "0" "$?" "cloud-init status should return 0 when done"
    else
        return 1
    fi
}

test_check_cloud_init_status_running() {
    # Mock cloud-init as running
    MOCK_CLOUD_INIT_STATUS="running"
    
    # Override cloud-init command
    cloud-init() { mock_cloud_init "$@"; }
    
    # Test the function
    if check_cloud_init_status; then
        return 1  # Should return 1 when running
    else
        assert_equals "1" "$?" "cloud-init status should return 1 when running"
    fi
}

test_check_cloud_init_status_not_installed() {
    # Mock cloud-init as not installed
    MOCK_CLOUD_INIT_STATUS="not_found"
    
    # Override cloud-init command
    cloud-init() { mock_cloud_init "$@"; }
    command() {
        if [ "$1" = "-v" ] && [ "$2" = "cloud-init" ]; then
            return 1  # Not found
        fi
        return 0
    }
    
    # Test the function
    if check_cloud_init_status; then
        assert_equals "0" "$?" "cloud-init status should return 0 when not installed"
    else
        return 1
    fi
}

test_wait_for_cloud_init_already_done() {
    # Mock cloud-init as done
    MOCK_CLOUD_INIT_STATUS="done"
    
    # Override cloud-init command
    cloud-init() { mock_cloud_init "$@"; }
    
    # Test the function with short timeout
    local start_time=$(date +%s)
    if wait_for_cloud_init 10; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        # Should complete quickly since it's already done
        if [ $duration -lt 5 ]; then
            assert_equals "0" "$?" "wait_for_cloud_init should return 0 when already done"
        else
            log_error "wait_for_cloud_init took too long when already done: ${duration}s"
            return 1
        fi
    else
        return 1
    fi
}

test_wait_for_cloud_init_timeout() {
    # Mock cloud-init as always running
    MOCK_CLOUD_INIT_STATUS="running"
    
    # Override cloud-init command
    cloud-init() { mock_cloud_init "$@"; }
    
    # Test the function with very short timeout
    local start_time=$(date +%s)
    if wait_for_cloud_init 2; then
        return 1  # Should timeout and return 1
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        # Should timeout after approximately 2 seconds
        if [ $duration -ge 2 ] && [ $duration -le 5 ]; then
            assert_equals "1" "$?" "wait_for_cloud_init should return 1 on timeout"
        else
            log_error "wait_for_cloud_init timeout duration unexpected: ${duration}s"
            return 1
        fi
    fi
}

# =============================================================================
# System Resource Tests
# =============================================================================

test_check_disk_space_sufficient() {
    # Mock sufficient disk space
    MOCK_DISK_SPACE="5000"
    
    # Override df command
    df() { mock_df "$@"; }
    
    # Test with requirement less than available
    if check_disk_space 2000 "/"; then
        assert_equals "0" "$?" "check_disk_space should return 0 when sufficient"
    else
        return 1
    fi
}

test_check_disk_space_insufficient() {
    # Mock insufficient disk space
    MOCK_DISK_SPACE="500"
    
    # Override df command
    df() { mock_df "$@"; }
    
    # Test with requirement more than available
    if check_disk_space 2000 "/"; then
        return 1  # Should return 1 when insufficient
    else
        assert_equals "1" "$?" "check_disk_space should return 1 when insufficient"
    fi
}

test_check_memory_sufficient() {
    # Mock sufficient memory
    MOCK_MEMORY_AVAILABLE="2000"
    
    # Override free command
    free() { mock_free "$@"; }
    
    # Test with requirement less than available
    if check_memory 1000; then
        assert_equals "0" "$?" "check_memory should return 0 when sufficient"
    else
        return 1
    fi
}

test_check_memory_low() {
    # Mock low memory (but should still pass with warning)
    MOCK_MEMORY_AVAILABLE="200"
    
    # Override free command
    free() { mock_free "$@"; }
    
    # Test with requirement more than available (should warn but not fail)
    if check_memory 1000; then
        assert_equals "0" "$?" "check_memory should return 0 even when low (with warning)"
    else
        return 1
    fi
}

test_validate_system_resources_success() {
    # Mock sufficient resources
    MOCK_DISK_SPACE="5000"
    MOCK_MEMORY_AVAILABLE="2000"
    
    # Override commands
    df() { mock_df "$@"; }
    free() { mock_free "$@"; }
    
    # Test comprehensive validation
    if validate_system_resources; then
        assert_equals "0" "$?" "validate_system_resources should return 0 when all checks pass"
    else
        return 1
    fi
}

test_validate_system_resources_failure() {
    # Mock insufficient disk space
    MOCK_DISK_SPACE="500"
    MOCK_MEMORY_AVAILABLE="2000"
    
    # Override commands
    df() { mock_df "$@"; }
    free() { mock_free "$@"; }
    
    # Test comprehensive validation
    if validate_system_resources; then
        return 1  # Should fail due to insufficient disk space
    else
        assert_equals "1" "$?" "validate_system_resources should return 1 when checks fail"
    fi
}

# =============================================================================
# Network Connectivity Tests
# =============================================================================

test_check_basic_connectivity_success() {
    # Mock successful network connectivity
    MOCK_NETWORK_STATUS="connected"
    
    # Override ping command
    ping() { mock_ping "$@"; }
    
    # Test basic connectivity
    if check_basic_connectivity; then
        assert_equals "0" "$?" "check_basic_connectivity should return 0 when connected"
    else
        return 1
    fi
}

test_check_basic_connectivity_failure() {
    # Mock failed network connectivity
    MOCK_NETWORK_STATUS="disconnected"
    
    # Override ping command
    ping() { mock_ping "$@"; }
    
    # Test basic connectivity
    if check_basic_connectivity; then
        return 1  # Should fail when disconnected
    else
        assert_equals "1" "$?" "check_basic_connectivity should return 1 when disconnected"
    fi
}

test_check_github_connectivity_success() {
    # Mock successful GitHub connectivity
    MOCK_CURL_STATUS="success"
    
    # Override commands
    timeout() { shift 2; "$@"; }  # Skip timeout, just run command
    bash() { return 0; }  # Mock successful TCP connection
    curl() { mock_curl "$@"; }
    
    # Test GitHub connectivity
    if check_github_connectivity; then
        assert_equals "0" "$?" "check_github_connectivity should return 0 when accessible"
    else
        return 1
    fi
}

test_check_github_connectivity_failure() {
    # Mock failed GitHub connectivity
    MOCK_CURL_STATUS="failure"
    
    # Override commands
    timeout() { return 1; }  # Mock timeout failure
    bash() { return 1; }  # Mock failed TCP connection
    curl() { mock_curl "$@"; }
    
    # Test GitHub connectivity
    if check_github_connectivity; then
        return 1  # Should fail when not accessible
    else
        assert_equals "1" "$?" "check_github_connectivity should return 1 when not accessible"
    fi
}

# =============================================================================
# Package Manager Tests
# =============================================================================

test_check_package_managers_free() {
    # Mock no running processes
    MOCK_PGREP_RESULT="not_found"
    
    # Override commands
    pgrep() { mock_pgrep "$@"; }
    flock() { return 0; }  # Mock successful lock acquisition
    
    # Test package manager check
    if check_package_managers; then
        return 1  # Should return 1 when free (0 means busy)
    else
        assert_equals "1" "$?" "check_package_managers should return 1 when free"
    fi
}

test_check_package_managers_busy() {
    # Mock running processes
    MOCK_PGREP_RESULT="found"
    
    # Override commands
    pgrep() { mock_pgrep "$@"; }
    
    # Test package manager check
    if check_package_managers; then
        assert_equals "0" "$?" "check_package_managers should return 0 when busy"
    else
        return 1
    fi
}

# =============================================================================
# Integration Tests
# =============================================================================

test_validate_system_readiness_success() {
    # Mock all systems ready
    MOCK_CLOUD_INIT_STATUS="done"
    MOCK_DISK_SPACE="5000"
    MOCK_MEMORY_AVAILABLE="2000"
    MOCK_NETWORK_STATUS="connected"
    MOCK_CURL_STATUS="success"
    
    # Override commands
    cloud-init() { mock_cloud_init "$@"; }
    df() { mock_df "$@"; }
    free() { mock_free "$@"; }
    ping() { mock_ping "$@"; }
    timeout() { shift 2; "$@"; }
    bash() { return 0; }
    curl() { mock_curl "$@"; }
    
    # Test comprehensive validation
    if validate_system_readiness 10; then
        assert_equals "0" "$?" "validate_system_readiness should return 0 when all checks pass"
    else
        return 1
    fi
}

test_validate_system_readiness_failure() {
    # Mock system not ready (insufficient disk space)
    MOCK_CLOUD_INIT_STATUS="done"
    MOCK_DISK_SPACE="500"  # Insufficient
    MOCK_MEMORY_AVAILABLE="2000"
    MOCK_NETWORK_STATUS="disconnected"  # Also network issues
    
    # Override commands
    cloud-init() { mock_cloud_init "$@"; }
    df() { mock_df "$@"; }
    free() { mock_free "$@"; }
    ping() { mock_ping "$@"; }
    
    # Test comprehensive validation
    if validate_system_readiness 10; then
        return 1  # Should fail due to multiple issues
    else
        assert_equals "1" "$?" "validate_system_readiness should return 1 when checks fail"
    fi
}

# =============================================================================
# Test Suite Execution
# =============================================================================

# Load the system readiness library
load_libraries() {
    if [ ! -f "$SYSTEM_READINESS_LIB" ]; then
        log_error "System readiness library not found: $SYSTEM_READINESS_LIB"
        return 1
    fi
    
    # Source the library
    source "$SYSTEM_READINESS_LIB"
    
    log_info "Libraries loaded successfully"
    return 0
}

# Run all tests
run_all_tests() {
    log_info "Starting system readiness validation tests"
    echo ""
    
    # Cloud-init tests
    echo "=== Cloud-init Status Tests ==="
    run_test "check_cloud_init_status_done" test_check_cloud_init_status_done
    run_test "check_cloud_init_status_running" test_check_cloud_init_status_running
    run_test "check_cloud_init_status_not_installed" test_check_cloud_init_status_not_installed
    run_test "wait_for_cloud_init_already_done" test_wait_for_cloud_init_already_done
    run_test "wait_for_cloud_init_timeout" test_wait_for_cloud_init_timeout
    echo ""
    
    # System resource tests
    echo "=== System Resource Tests ==="
    run_test "check_disk_space_sufficient" test_check_disk_space_sufficient
    run_test "check_disk_space_insufficient" test_check_disk_space_insufficient
    run_test "check_memory_sufficient" test_check_memory_sufficient
    run_test "check_memory_low" test_check_memory_low
    run_test "validate_system_resources_success" test_validate_system_resources_success
    run_test "validate_system_resources_failure" test_validate_system_resources_failure
    echo ""
    
    # Network connectivity tests
    echo "=== Network Connectivity Tests ==="
    run_test "check_basic_connectivity_success" test_check_basic_connectivity_success
    run_test "check_basic_connectivity_failure" test_check_basic_connectivity_failure
    run_test "check_github_connectivity_success" test_check_github_connectivity_success
    run_test "check_github_connectivity_failure" test_check_github_connectivity_failure
    echo ""
    
    # Package manager tests
    echo "=== Package Manager Tests ==="
    run_test "check_package_managers_free" test_check_package_managers_free
    run_test "check_package_managers_busy" test_check_package_managers_busy
    echo ""
    
    # Integration tests
    echo "=== Integration Tests ==="
    run_test "validate_system_readiness_success" test_validate_system_readiness_success
    run_test "validate_system_readiness_failure" test_validate_system_readiness_failure
    echo ""
}

# Show test results
show_test_results() {
    echo "==============================================================================="
    echo "TEST RESULTS SUMMARY"
    echo "==============================================================================="
    echo "Tests Run: $TESTS_RUN"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo "Tests Skipped: $TESTS_SKIPPED"
    echo ""
    
    if [ $TESTS_FAILED -gt 0 ]; then
        echo "FAILED TESTS:"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
        echo ""
    fi
    
    if [ $TESTS_SKIPPED -gt 0 ]; then
        echo "SKIPPED TESTS:"
        for test in "${SKIPPED_TESTS[@]}"; do
            echo "  - $test"
        done
        echo ""
    fi
    
    local success_rate=$((TESTS_PASSED * 100 / TESTS_RUN))
    echo "Success Rate: ${success_rate}%"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "All tests passed!"
        return 0
    else
        log_error "Some tests failed!"
        return 1
    fi
}

# Main execution
main() {
    echo "=== $TEST_NAME v$TEST_VERSION ==="
    echo ""
    
    # Load libraries
    if ! load_libraries; then
        log_error "Failed to load required libraries"
        exit 1
    fi
    
    # Run tests
    run_all_tests
    
    # Show results
    if show_test_results; then
        exit 0
    else
        exit 1
    fi
}

# Command line interface
case "${1:-}" in
    --help|-h)
        echo "$TEST_NAME v$TEST_VERSION"
        echo ""
        echo "USAGE:"
        echo "  $0                Run all tests"
        echo "  $0 --help         Show this help"
        echo ""
        echo "DESCRIPTION:"
        echo "  Runs comprehensive unit tests for system readiness validation functions."
        echo "  Tests cloud-init status checking, resource validation, network connectivity,"
        echo "  and package manager monitoring."
        echo ""
        ;;
    *)
        main "$@"
        ;;
esac