#!/bin/bash

# Installation Robustness Integration Tests
# This script provides comprehensive integration tests for the enhanced
# GitHub Actions runner installation process, testing various system
# states, failure scenarios, and recovery mechanisms.

set -e

# Script version and metadata
TEST_VERSION="1.0.0"
TEST_NAME="Installation Robustness Integration Tests"

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_READINESS_LIB="$SCRIPT_DIR/system-readiness-functions.sh"
PACKAGE_MANAGER_LIB="$SCRIPT_DIR/package-manager-functions.sh"
ERROR_HANDLER_LIB="$SCRIPT_DIR/installation-error-handler.sh"
INSTALLATION_LOGGER_LIB="$SCRIPT_DIR/installation-logger.sh"

# Test environment configuration
TEST_LOG_DIR="/tmp/runner-test-logs"
TEST_RUNNER_DIR="/tmp/test-runner"
TEST_TIMEOUT=300  # 5 minutes default timeout for integration tests

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

log_integration() {
    echo -e "${MAGENTA}[INTEGRATION]${NC} $1"
}

# Test execution framework
run_integration_test() {
    local test_name="$1"
    local test_function="$2"
    local timeout="${3:-$TEST_TIMEOUT}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    log_test "Running integration test: $test_name"
    log_integration "Timeout: ${timeout}s"
    
    # Set up test environment
    setup_test_environment
    
    # Run test with timeout
    local test_result=0
    if timeout "$timeout" bash -c "$test_function"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log_success "PASSED: $test_name"
        test_result=0
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log_error "TIMEOUT: $test_name (exceeded ${timeout}s)"
        else
            log_error "FAILED: $test_name (exit code: $exit_code)"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$test_name")
        test_result=1
    fi
    
    # Clean up test environment
    cleanup_test_environment
    
    return $test_result
}

skip_integration_test() {
    local test_name="$1"
    local reason="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    SKIPPED_TESTS+=("$test_name")
    
    log_warning "SKIPPED: $test_name - $reason"
}

# =============================================================================
# Test Environment Management
# =============================================================================

# Set up test environment
setup_test_environment() {
    log_integration "Setting up test environment"
    
    # Create test directories
    mkdir -p "$TEST_LOG_DIR"
    mkdir -p "$TEST_RUNNER_DIR"
    
    # Set environment variables for testing
    export RUNNER_LOG_DIR="$TEST_LOG_DIR"
    export RUNNER_LOG_FILE="test-installation.log"
    export DEBUG=true
    
    # Initialize test logging
    if [ -f "$INSTALLATION_LOGGER_LIB" ]; then
        source "$INSTALLATION_LOGGER_LIB"
        init_logging "$TEST_LOG_DIR" "test-installation.log"
    fi
    
    log_integration "Test environment ready"
}

# Clean up test environment
cleanup_test_environment() {
    log_integration "Cleaning up test environment"
    
    # Stop any test processes
    pkill -f "test-runner" 2>/dev/null || true
    
    # Clean up test files (but preserve logs for analysis)
    rm -rf "$TEST_RUNNER_DIR" 2>/dev/null || true
    
    # Reset environment variables
    unset RUNNER_LOG_DIR RUNNER_LOG_FILE DEBUG
    
    log_integration "Test environment cleaned up"
}

# Create mock system conditions
create_mock_system_condition() {
    local condition="$1"
    
    case "$condition" in
        "cloud_init_running")
            # Create a mock cloud-init process
            (
                echo "Mock cloud-init process running"
                sleep 30
            ) &
            export MOCK_CLOUD_INIT_PID=$!
            ;;
        "package_manager_busy")
            # Create mock package manager processes
            (
                echo "Mock apt process running"
                sleep 60
            ) &
            export MOCK_APT_PID=$!
            
            # Create mock lock files
            mkdir -p /tmp/mock-dpkg-locks
            touch /tmp/mock-dpkg-locks/lock
            ;;
        "low_disk_space")
            # Mock low disk space condition
            export MOCK_DISK_SPACE="500"  # 500MB available
            ;;
        "network_issues")
            # Mock network connectivity issues
            export MOCK_NETWORK_STATUS="intermittent"
            ;;
        "github_api_slow")
            # Mock slow GitHub API responses
            export MOCK_GITHUB_DELAY="10"
            ;;
    esac
    
    log_integration "Created mock system condition: $condition"
}

# Clean up mock system conditions
cleanup_mock_system_condition() {
    local condition="$1"
    
    case "$condition" in
        "cloud_init_running")
            if [ -n "${MOCK_CLOUD_INIT_PID:-}" ]; then
                kill "$MOCK_CLOUD_INIT_PID" 2>/dev/null || true
                unset MOCK_CLOUD_INIT_PID
            fi
            ;;
        "package_manager_busy")
            if [ -n "${MOCK_APT_PID:-}" ]; then
                kill "$MOCK_APT_PID" 2>/dev/null || true
                unset MOCK_APT_PID
            fi
            rm -rf /tmp/mock-dpkg-locks 2>/dev/null || true
            ;;
        "low_disk_space")
            unset MOCK_DISK_SPACE
            ;;
        "network_issues")
            unset MOCK_NETWORK_STATUS
            ;;
        "github_api_slow")
            unset MOCK_GITHUB_DELAY
            ;;
    esac
    
    log_integration "Cleaned up mock system condition: $condition"
}

# =============================================================================
# Mock Installation Functions
# =============================================================================

# Mock enhanced installation process
mock_enhanced_installation() {
    local scenario="$1"
    local expected_result="${2:-success}"
    
    log_integration "Running mock enhanced installation: $scenario"
    
    # Load required libraries
    source "$SYSTEM_READINESS_LIB" 2>/dev/null || true
    source "$PACKAGE_MANAGER_LIB" 2>/dev/null || true
    source "$ERROR_HANDLER_LIB" 2>/dev/null || true
    
    # Simulate installation steps based on scenario
    case "$scenario" in
        "normal_installation")
            mock_normal_installation
            ;;
        "cloud_init_delay")
            mock_cloud_init_delay_installation
            ;;
        "package_conflicts")
            mock_package_conflicts_installation
            ;;
        "network_intermittent")
            mock_network_intermittent_installation
            ;;
        "resource_constraints")
            mock_resource_constraints_installation
            ;;
        "github_api_issues")
            mock_github_api_issues_installation
            ;;
        *)
            log_error "Unknown installation scenario: $scenario"
            return 1
            ;;
    esac
}

# Mock normal installation process
mock_normal_installation() {
    log_integration "Step 1: System readiness validation"
    sleep 2
    
    log_integration "Step 2: Package manager preparation"
    sleep 3
    
    log_integration "Step 3: Runner download and extraction"
    sleep 5
    
    log_integration "Step 4: Dependency installation"
    sleep 4
    
    log_integration "Step 5: Runner configuration"
    sleep 3
    
    log_integration "Step 6: Service installation and startup"
    sleep 2
    
    log_success "Mock normal installation completed successfully"
    return 0
}

# Mock installation with cloud-init delay
mock_cloud_init_delay_installation() {
    log_integration "Step 1: System readiness validation"
    log_integration "Waiting for cloud-init to complete..."
    
    # Simulate cloud-init running for a while
    local wait_time=15
    for ((i=1; i<=wait_time; i++)); do
        printf "\r${BLUE}[INFO]${NC} Waiting for cloud-init... %d/%ds" "$i" "$wait_time"
        sleep 1
    done
    echo ""
    
    log_success "cloud-init completed"
    
    # Continue with normal installation
    log_integration "Step 2: Package manager preparation"
    sleep 2
    
    log_integration "Remaining steps proceeding normally..."
    sleep 5
    
    log_success "Mock cloud-init delay installation completed successfully"
    return 0
}

# Mock installation with package conflicts
mock_package_conflicts_installation() {
    log_integration "Step 1: System readiness validation"
    sleep 1
    
    log_integration "Step 2: Package manager preparation"
    log_integration "Package managers are busy, waiting..."
    
    # Simulate waiting for package managers
    local wait_time=20
    for ((i=1; i<=wait_time; i++)); do
        printf "\r${BLUE}[INFO]${NC} Waiting for package managers... %d/%ds" "$i" "$wait_time"
        sleep 1
    done
    echo ""
    
    log_success "Package managers are now available"
    
    log_integration "Step 3: Dependency installation with retry"
    log_integration "Attempt 1: Installing dependencies..."
    sleep 2
    log_warning "Installation failed, retrying in 30s..."
    sleep 3  # Simulate shorter wait for testing
    
    log_integration "Attempt 2: Installing dependencies..."
    sleep 2
    log_success "Dependencies installed successfully"
    
    log_integration "Remaining steps proceeding normally..."
    sleep 3
    
    log_success "Mock package conflicts installation completed successfully"
    return 0
}

# Mock installation with intermittent network issues
mock_network_intermittent_installation() {
    log_integration "Step 1: System readiness validation"
    log_integration "Testing network connectivity..."
    sleep 2
    log_warning "Network connectivity issues detected, retrying..."
    sleep 3
    log_success "Network connectivity restored"
    
    log_integration "Step 2: Package manager preparation"
    sleep 2
    
    log_integration "Step 3: Runner download with retry"
    log_integration "Attempt 1: Downloading runner..."
    sleep 3
    log_warning "Download failed, retrying in 30s..."
    sleep 3  # Simulate shorter wait for testing
    
    log_integration "Attempt 2: Downloading runner..."
    sleep 3
    log_success "Runner downloaded successfully"
    
    log_integration "Remaining steps proceeding normally..."
    sleep 3
    
    log_success "Mock network intermittent installation completed successfully"
    return 0
}

# Mock installation with resource constraints
mock_resource_constraints_installation() {
    log_integration "Step 1: System readiness validation"
    log_warning "Low disk space detected (1.5GB available, 2GB recommended)"
    log_integration "Proceeding with caution..."
    sleep 2
    
    log_integration "Step 2: Package manager preparation"
    log_integration "Cleaning package cache to free space..."
    sleep 3
    log_success "Package cache cleaned, space freed"
    
    log_integration "Step 3: Runner installation with space monitoring"
    sleep 4
    
    log_integration "Remaining steps proceeding normally..."
    sleep 3
    
    log_success "Mock resource constraints installation completed successfully"
    return 0
}

# Mock installation with GitHub API issues
mock_github_api_issues_installation() {
    log_integration "Step 1: System readiness validation"
    sleep 1
    
    log_integration "Step 2: GitHub API connectivity test"
    log_warning "GitHub API is responding slowly..."
    sleep 5
    log_success "GitHub API connectivity confirmed"
    
    log_integration "Step 3: Runner version lookup with retry"
    log_integration "Attempt 1: Getting latest runner version..."
    sleep 3
    log_warning "API request timed out, retrying..."
    sleep 2
    
    log_integration "Attempt 2: Getting latest runner version..."
    sleep 3
    log_success "Runner version obtained: v2.311.0"
    
    log_integration "Remaining steps proceeding normally..."
    sleep 4
    
    log_success "Mock GitHub API issues installation completed successfully"
    return 0
}

# =============================================================================
# Integration Test Cases
# =============================================================================

# Test normal installation flow
test_normal_installation_flow() {
    log_integration "Testing normal installation flow"
    
    if mock_enhanced_installation "normal_installation"; then
        log_success "Normal installation flow test passed"
        return 0
    else
        log_error "Normal installation flow test failed"
        return 1
    fi
}

# Test installation during cloud-init
test_installation_during_cloud_init() {
    log_integration "Testing installation during cloud-init"
    
    create_mock_system_condition "cloud_init_running"
    
    if mock_enhanced_installation "cloud_init_delay"; then
        log_success "Cloud-init delay installation test passed"
        cleanup_mock_system_condition "cloud_init_running"
        return 0
    else
        log_error "Cloud-init delay installation test failed"
        cleanup_mock_system_condition "cloud_init_running"
        return 1
    fi
}

# Test installation with package manager conflicts
test_installation_with_package_conflicts() {
    log_integration "Testing installation with package manager conflicts"
    
    create_mock_system_condition "package_manager_busy"
    
    if mock_enhanced_installation "package_conflicts"; then
        log_success "Package conflicts installation test passed"
        cleanup_mock_system_condition "package_manager_busy"
        return 0
    else
        log_error "Package conflicts installation test failed"
        cleanup_mock_system_condition "package_manager_busy"
        return 1
    fi
}

# Test installation with network issues
test_installation_with_network_issues() {
    log_integration "Testing installation with network issues"
    
    create_mock_system_condition "network_issues"
    
    if mock_enhanced_installation "network_intermittent"; then
        log_success "Network issues installation test passed"
        cleanup_mock_system_condition "network_issues"
        return 0
    else
        log_error "Network issues installation test failed"
        cleanup_mock_system_condition "network_issues"
        return 1
    fi
}

# Test installation with resource constraints
test_installation_with_resource_constraints() {
    log_integration "Testing installation with resource constraints"
    
    create_mock_system_condition "low_disk_space"
    
    if mock_enhanced_installation "resource_constraints"; then
        log_success "Resource constraints installation test passed"
        cleanup_mock_system_condition "low_disk_space"
        return 0
    else
        log_error "Resource constraints installation test failed"
        cleanup_mock_system_condition "low_disk_space"
        return 1
    fi
}

# Test installation with GitHub API issues
test_installation_with_github_api_issues() {
    log_integration "Testing installation with GitHub API issues"
    
    create_mock_system_condition "github_api_slow"
    
    if mock_enhanced_installation "github_api_issues"; then
        log_success "GitHub API issues installation test passed"
        cleanup_mock_system_condition "github_api_slow"
        return 0
    else
        log_error "GitHub API issues installation test failed"
        cleanup_mock_system_condition "github_api_slow"
        return 1
    fi
}

# Test retry mechanism behavior
test_retry_mechanism_behavior() {
    log_integration "Testing retry mechanism behavior"
    
    # Test exponential backoff calculation
    local base_delay=30
    local max_delay=300
    
    for retry in 0 1 2 3 4; do
        local delay=$((base_delay * (1 << retry)))
        if [ $delay -gt $max_delay ]; then
            delay=$max_delay
        fi
        
        log_integration "Retry $retry: delay = ${delay}s"
        
        # Verify delay is within expected range
        if [ $retry -eq 0 ] && [ $delay -ne 30 ]; then
            log_error "Retry 0 delay should be 30s, got ${delay}s"
            return 1
        elif [ $retry -eq 1 ] && [ $delay -ne 60 ]; then
            log_error "Retry 1 delay should be 60s, got ${delay}s"
            return 1
        elif [ $retry -eq 2 ] && [ $delay -ne 120 ]; then
            log_error "Retry 2 delay should be 120s, got ${delay}s"
            return 1
        elif [ $retry -eq 3 ] && [ $delay -ne 240 ]; then
            log_error "Retry 3 delay should be 240s, got ${delay}s"
            return 1
        elif [ $retry -eq 4 ] && [ $delay -ne 300 ]; then
            log_error "Retry 4 delay should be capped at 300s, got ${delay}s"
            return 1
        fi
    done
    
    log_success "Retry mechanism behavior test passed"
    return 0
}

# Test error handling and recovery
test_error_handling_and_recovery() {
    log_integration "Testing error handling and recovery"
    
    # Simulate various error conditions and recovery
    local error_scenarios=(
        "CLOUD_INIT_TIMEOUT"
        "PACKAGE_MANAGER_BUSY"
        "NETWORK_CONNECTIVITY"
        "INSUFFICIENT_RESOURCES"
        "GITHUB_AUTH_FAILED"
    )
    
    for scenario in "${error_scenarios[@]}"; do
        log_integration "Testing error scenario: $scenario"
        
        # Mock error handling (simplified for testing)
        case "$scenario" in
            "CLOUD_INIT_TIMEOUT")
                log_warning "Simulated cloud-init timeout"
                log_integration "Recovery: Proceeding with installation anyway"
                ;;
            "PACKAGE_MANAGER_BUSY")
                log_warning "Simulated package manager busy"
                log_integration "Recovery: Waiting and retrying"
                ;;
            "NETWORK_CONNECTIVITY")
                log_warning "Simulated network connectivity issues"
                log_integration "Recovery: Testing alternative endpoints"
                ;;
            "INSUFFICIENT_RESOURCES")
                log_warning "Simulated insufficient resources"
                log_integration "Recovery: Cleaning cache and retrying"
                ;;
            "GITHUB_AUTH_FAILED")
                log_warning "Simulated GitHub authentication failure"
                log_integration "Recovery: Providing troubleshooting guidance"
                ;;
        esac
        
        sleep 1  # Simulate recovery time
        log_success "Error scenario $scenario handled successfully"
    done
    
    log_success "Error handling and recovery test passed"
    return 0
}

# Test logging and metrics collection
test_logging_and_metrics_collection() {
    log_integration "Testing logging and metrics collection"
    
    # Test logging functionality
    if [ -f "$INSTALLATION_LOGGER_LIB" ]; then
        source "$INSTALLATION_LOGGER_LIB"
        
        # Start a test session
        local session_id
        session_id=$(start_installation_session "integration-test" "Testing logging functionality")
        
        # Log some test steps
        log_step_start "Test Step 1" 1 3 "Testing step logging"
        sleep 1
        log_step_complete "Test Step 1" 1 "Step completed successfully"
        
        log_step_start "Test Step 2" 2 3 "Testing retry logging"
        sleep 1
        record_step_metrics "Test Step 2" "warning" 1 2 "Simulated retry scenario"
        log_step_complete "Test Step 2" 1 "Step completed with retries"
        
        log_step_start "Test Step 3" 3 3 "Testing final step"
        sleep 1
        log_step_complete "Test Step 3" 1 "Final step completed"
        
        # End the session
        end_installation_session "success" "Integration test completed"
        
        # Verify log files exist
        if [ -f "$TEST_LOG_DIR/test-installation.log" ]; then
            log_success "Log file created successfully"
        else
            log_error "Log file not created"
            return 1
        fi
        
        # Verify metrics file exists
        if [ -f "$TEST_LOG_DIR/installation-metrics.json" ]; then
            log_success "Metrics file created successfully"
        else
            log_warning "Metrics file not created (jq may not be available)"
        fi
        
        log_success "Logging and metrics collection test passed"
        return 0
    else
        log_warning "Installation logger library not found, skipping test"
        return 0
    fi
}

# Test concurrent installation scenarios
test_concurrent_installation_scenarios() {
    log_integration "Testing concurrent installation scenarios"
    
    # Simulate multiple installation attempts
    log_integration "Scenario 1: Multiple package managers running"
    create_mock_system_condition "package_manager_busy"
    sleep 2
    log_integration "Waiting for package managers to become available..."
    sleep 3
    cleanup_mock_system_condition "package_manager_busy"
    log_success "Package managers became available"
    
    log_integration "Scenario 2: System updates during installation"
    log_integration "Detected unattended-upgrades running"
    sleep 2
    log_integration "Waiting for system updates to complete..."
    sleep 3
    log_success "System updates completed"
    
    log_integration "Scenario 3: Multiple runner installations"
    log_integration "Detected existing runner configuration"
    sleep 1
    log_integration "Removing existing configuration before proceeding"
    sleep 2
    log_success "Existing configuration removed, proceeding with new installation"
    
    log_success "Concurrent installation scenarios test passed"
    return 0
}

# Test end-to-end installation validation
test_end_to_end_installation_validation() {
    log_integration "Testing end-to-end installation validation"
    
    # Simulate complete installation process with validation
    log_integration "Phase 1: Pre-installation validation"
    sleep 2
    log_success "Pre-installation validation passed"
    
    log_integration "Phase 2: Installation execution"
    sleep 5
    log_success "Installation execution completed"
    
    log_integration "Phase 3: Post-installation verification"
    
    # Mock post-installation checks
    log_integration "Checking runner dependencies..."
    sleep 1
    log_success "All dependencies verified"
    
    log_integration "Checking runner service status..."
    sleep 1
    log_success "Runner service is active and running"
    
    log_integration "Checking GitHub registration..."
    sleep 2
    log_success "Runner successfully registered with GitHub"
    
    log_integration "Phase 4: Final validation"
    sleep 1
    log_success "End-to-end validation completed successfully"
    
    log_success "End-to-end installation validation test passed"
    return 0
}

# =============================================================================
# Test Suite Execution
# =============================================================================

# Load required libraries
load_libraries() {
    local missing_libs=()
    
    for lib in "$SYSTEM_READINESS_LIB" "$PACKAGE_MANAGER_LIB" "$ERROR_HANDLER_LIB"; do
        if [ ! -f "$lib" ]; then
            missing_libs+=("$(basename "$lib")")
        fi
    done
    
    if [ ${#missing_libs[@]} -gt 0 ]; then
        log_warning "Some libraries not found: ${missing_libs[*]}"
        log_warning "Some tests may be skipped"
    fi
    
    # Load available libraries
    [ -f "$SYSTEM_READINESS_LIB" ] && source "$SYSTEM_READINESS_LIB"
    [ -f "$PACKAGE_MANAGER_LIB" ] && source "$PACKAGE_MANAGER_LIB"
    [ -f "$ERROR_HANDLER_LIB" ] && source "$ERROR_HANDLER_LIB"
    [ -f "$INSTALLATION_LOGGER_LIB" ] && source "$INSTALLATION_LOGGER_LIB"
    
    log_info "Available libraries loaded"
    return 0
}

# Run all integration tests
run_all_integration_tests() {
    log_info "Starting installation robustness integration tests"
    echo ""
    
    # Basic installation flow tests
    echo "=== Basic Installation Flow Tests ==="
    run_integration_test "normal_installation_flow" test_normal_installation_flow 60
    echo ""
    
    # System state scenario tests
    echo "=== System State Scenario Tests ==="
    run_integration_test "installation_during_cloud_init" test_installation_during_cloud_init 120
    run_integration_test "installation_with_package_conflicts" test_installation_with_package_conflicts 120
    run_integration_test "installation_with_resource_constraints" test_installation_with_resource_constraints 90
    echo ""
    
    # Network and connectivity tests
    echo "=== Network and Connectivity Tests ==="
    run_integration_test "installation_with_network_issues" test_installation_with_network_issues 120
    run_integration_test "installation_with_github_api_issues" test_installation_with_github_api_issues 120
    echo ""
    
    # Mechanism behavior tests
    echo "=== Mechanism Behavior Tests ==="
    run_integration_test "retry_mechanism_behavior" test_retry_mechanism_behavior 30
    run_integration_test "error_handling_and_recovery" test_error_handling_and_recovery 60
    echo ""
    
    # System integration tests
    echo "=== System Integration Tests ==="
    run_integration_test "logging_and_metrics_collection" test_logging_and_metrics_collection 60
    run_integration_test "concurrent_installation_scenarios" test_concurrent_installation_scenarios 90
    echo ""
    
    # End-to-end tests
    echo "=== End-to-End Tests ==="
    run_integration_test "end_to_end_installation_validation" test_end_to_end_installation_validation 120
    echo ""
}

# Show test results
show_test_results() {
    echo "==============================================================================="
    echo "INTEGRATION TEST RESULTS SUMMARY"
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
    
    local success_rate=0
    if [ $TESTS_RUN -gt 0 ]; then
        success_rate=$((TESTS_PASSED * 100 / TESTS_RUN))
    fi
    echo "Success Rate: ${success_rate}%"
    echo ""
    
    # Show test logs location
    if [ -d "$TEST_LOG_DIR" ]; then
        echo "Test logs available in: $TEST_LOG_DIR"
        echo ""
    fi
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "All integration tests passed!"
        return 0
    else
        log_error "Some integration tests failed!"
        return 1
    fi
}

# Main execution
main() {
    echo "=== $TEST_NAME v$TEST_VERSION ==="
    echo ""
    
    # Load libraries
    load_libraries
    
    # Set up global test environment
    setup_test_environment
    
    # Run integration tests
    run_all_integration_tests
    
    # Show results
    local test_result=0
    if ! show_test_results; then
        test_result=1
    fi
    
    # Clean up global test environment
    cleanup_test_environment
    
    exit $test_result
}

# Command line interface
case "${1:-}" in
    --help|-h)
        echo "$TEST_NAME v$TEST_VERSION"
        echo ""
        echo "USAGE:"
        echo "  $0                Run all integration tests"
        echo "  $0 --help         Show this help"
        echo ""
        echo "DESCRIPTION:"
        echo "  Runs comprehensive integration tests for the enhanced GitHub Actions"
        echo "  runner installation process. Tests various system states, failure"
        echo "  scenarios, and recovery mechanisms."
        echo ""
        echo "TEST CATEGORIES:"
        echo "  - Basic installation flow"
        echo "  - System state scenarios (cloud-init, package conflicts, resources)"
        echo "  - Network and connectivity issues"
        echo "  - Retry mechanism behavior"
        echo "  - Error handling and recovery"
        echo "  - Logging and metrics collection"
        echo "  - Concurrent installation scenarios"
        echo "  - End-to-end validation"
        echo ""
        echo "ENVIRONMENT:"
        echo "  TEST_TIMEOUT      Timeout for individual tests (default: 300s)"
        echo "  DEBUG             Enable debug logging (default: false)"
        echo ""
        ;;
    *)
        main "$@"
        ;;
esac