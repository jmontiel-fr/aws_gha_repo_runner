#!/bin/bash

# Comprehensive Test Suite Runner
# This script orchestrates all testing and validation scripts for the
# repository-level GitHub Actions runner setup.

set -e

# Script version and metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="Comprehensive Test Suite Runner"

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
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

log_suite() {
    echo -e "${MAGENTA}>>> $1 <<<${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="/tmp/comprehensive-test-results"
FINAL_REPORT="$RESULTS_DIR/comprehensive-test-report.json"

# Test suite configuration
declare -A TEST_SUITES=(
    ["validation"]="Repository Configuration Validation"
    ["setup"]="Repository Setup Comprehensive Test"
    ["integration"]="Workflow Integration Test"
    ["health"]="Runner Health Check"
)

declare -A TEST_SCRIPTS=(
    ["validation"]="validate-repository-configuration.sh"
    ["setup"]="test-repository-setup.sh"
    ["integration"]="test-workflow-integration.sh"
    ["health"]="health-check-runner.sh"
)

# Test execution tracking
declare -A SUITE_RESULTS=()
declare -A SUITE_DURATIONS=()
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

# =============================================================================
# Test Suite Framework Functions
# =============================================================================

# Initialize test environment
init_test_environment() {
    log_info "Initializing comprehensive test environment"
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    
    # Initialize final report
    cat > "$FINAL_REPORT" << EOF
{
    "comprehensive_test_run": {
        "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
        "script_version": "$SCRIPT_VERSION",
        "repository": "${GITHUB_USERNAME}/${GITHUB_REPOSITORY}",
        "environment": {
            "os": "$(uname -s)",
            "shell": "$SHELL",
            "user": "$USER",
            "pwd": "$(pwd)"
        }
    },
    "test_suites": {},
    "summary": {}
}
EOF
    
    log_success "Test environment initialized"
    log_info "Results directory: $RESULTS_DIR"
}

# Run a test suite
run_test_suite() {
    local suite_key="$1"
    local suite_name="${TEST_SUITES[$suite_key]}"
    local script_name="${TEST_SCRIPTS[$suite_key]}"
    local script_path="$SCRIPT_DIR/$script_name"
    
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    
    log_suite "Running Test Suite: $suite_name"
    
    if [ ! -f "$script_path" ]; then
        log_error "Test script not found: $script_path"
        SUITE_RESULTS[$suite_key]="ERROR"
        FAILED_SUITES=$((FAILED_SUITES + 1))
        return 1
    fi
    
    if [ ! -x "$script_path" ]; then
        log_error "Test script not executable: $script_path"
        SUITE_RESULTS[$suite_key]="ERROR"
        FAILED_SUITES=$((FAILED_SUITES + 1))
        return 1
    fi
    
    local start_time=$(date +%s)
    local suite_result="FAILED"
    local suite_output=""
    local suite_exit_code=0
    
    # Run the test suite and capture output
    log_info "Executing: $script_name"
    if suite_output=$("$script_path" 2>&1); then
        suite_result="PASSED"
        PASSED_SUITES=$((PASSED_SUITES + 1))
        log_success "Test suite PASSED: $suite_name"
    else
        suite_exit_code=$?
        suite_result="FAILED"
        FAILED_SUITES=$((FAILED_SUITES + 1))
        log_error "Test suite FAILED: $suite_name (exit code: $suite_exit_code)"
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    SUITE_RESULTS[$suite_key]="$suite_result"
    SUITE_DURATIONS[$suite_key]="$duration"
    
    log_info "Duration: ${duration}s"
    
    # Save suite output to file
    local suite_output_file="$RESULTS_DIR/${suite_key}-output.log"
    echo "$suite_output" > "$suite_output_file"
    log_info "Suite output saved: $suite_output_file"
    
    # Update final report with suite results
    local suite_json=$(cat << EOF
{
    "name": "$suite_name",
    "script": "$script_name",
    "result": "$suite_result",
    "exit_code": $suite_exit_code,
    "duration": $duration,
    "output_file": "$suite_output_file",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)
    
    jq ".test_suites[\"$suite_key\"] = $suite_json" "$FINAL_REPORT" > "${FINAL_REPORT}.tmp" && mv "${FINAL_REPORT}.tmp" "$FINAL_REPORT"
    
    echo ""
    return $suite_exit_code
}

# =============================================================================
# Test Suite Execution Functions
# =============================================================================

# Run validation suite
run_validation_suite() {
    log_header "REPOSITORY CONFIGURATION VALIDATION SUITE"
    echo "This suite validates all repository configuration requirements"
    echo "and ensures the system meets security and optimization criteria."
    echo ""
    
    run_test_suite "validation"
}

# Run setup test suite
run_setup_test_suite() {
    log_header "REPOSITORY SETUP COMPREHENSIVE TEST SUITE"
    echo "This suite tests the complete repository-level setup process"
    echo "including prerequisites, configuration, and permissions."
    echo ""
    
    run_test_suite "setup"
}

# Run integration test suite
run_integration_test_suite() {
    log_header "WORKFLOW INTEGRATION TEST SUITE"
    echo "This suite tests GitHub Actions workflow integration and"
    echo "validates end-to-end functionality with AWS services."
    echo ""
    
    run_test_suite "integration"
}

# Run health check suite
run_health_check_suite() {
    log_header "RUNNER HEALTH CHECK SUITE"
    echo "This suite performs comprehensive health monitoring and"
    echo "status checking for the repository runner system."
    echo ""
    
    run_test_suite "health"
}

# =============================================================================
# Report Generation Functions
# =============================================================================

# Generate comprehensive summary report
generate_summary_report() {
    log_header "Comprehensive Test Summary"
    
    # Calculate overall statistics
    local total_duration=0
    for suite in "${!SUITE_DURATIONS[@]}"; do
        total_duration=$((total_duration + SUITE_DURATIONS[$suite]))
    done
    
    local success_rate=0
    if [ $TOTAL_SUITES -gt 0 ]; then
        success_rate=$(echo "scale=1; $PASSED_SUITES * 100 / $TOTAL_SUITES" | bc -l 2>/dev/null || echo "0")
    fi
    
    # Update final report summary
    local summary_json=$(cat << EOF
{
    "total_suites": $TOTAL_SUITES,
    "passed_suites": $PASSED_SUITES,
    "failed_suites": $FAILED_SUITES,
    "success_rate": $success_rate,
    "total_duration": $total_duration,
    "suite_results": $(for suite in "${!SUITE_RESULTS[@]}"; do echo "\"$suite\": \"${SUITE_RESULTS[$suite]}\""; done | paste -sd ',' | sed 's/^/{/' | sed 's/$/}/')
}
EOF
)
    
    jq ".summary = $summary_json" "$FINAL_REPORT" > "${FINAL_REPORT}.tmp" && mv "${FINAL_REPORT}.tmp" "$FINAL_REPORT"
    
    # Display summary
    echo ""
    echo "=== COMPREHENSIVE TEST RESULTS ==="
    echo "Total Test Suites: $TOTAL_SUITES"
    echo "Passed: $PASSED_SUITES"
    echo "Failed: $FAILED_SUITES"
    echo "Success Rate: ${success_rate}%"
    echo "Total Duration: ${total_duration}s"
    echo ""
    
    # Display individual suite results
    echo "Suite Results:"
    for suite in "${!SUITE_RESULTS[@]}"; do
        local suite_name="${TEST_SUITES[$suite]}"
        local result="${SUITE_RESULTS[$suite]}"
        local duration="${SUITE_DURATIONS[$suite]}"
        
        case $result in
            "PASSED")
                echo -e "  ${GREEN}✓${NC} $suite_name (${duration}s)"
                ;;
            "FAILED")
                echo -e "  ${RED}✗${NC} $suite_name (${duration}s)"
                ;;
            "ERROR")
                echo -e "  ${RED}!${NC} $suite_name (error)"
                ;;
        esac
    done
    
    echo ""
    echo "Detailed Results:"
    echo "  Final Report: $FINAL_REPORT"
    echo "  Results Directory: $RESULTS_DIR"
    
    # Provide recommendations
    if [ $FAILED_SUITES -gt 0 ]; then
        echo ""
        log_error "Some test suites failed"
        log_error "Review the individual suite outputs for detailed error information"
        log_error "Address the issues before proceeding with runner deployment"
        return 1
    else
        echo ""
        log_success "All test suites passed successfully"
        log_success "Repository-level runner system is ready for deployment"
        return 0
    fi
}

# Generate detailed HTML report (optional)
generate_html_report() {
    local html_report="$RESULTS_DIR/comprehensive-test-report.html"
    
    log_info "Generating HTML report: $html_report"
    
    cat > "$html_report" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Comprehensive Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .suite { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
        .passed { border-left: 5px solid #28a745; }
        .failed { border-left: 5px solid #dc3545; }
        .error { border-left: 5px solid #ffc107; }
        .summary { background-color: #e9ecef; padding: 15px; border-radius: 5px; }
        pre { background-color: #f8f9fa; padding: 10px; border-radius: 3px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Comprehensive Test Report</h1>
        <p><strong>Generated:</strong> $(date)</p>
        <p><strong>Repository:</strong> ${GITHUB_USERNAME}/${GITHUB_REPOSITORY}</p>
        <p><strong>Script Version:</strong> $SCRIPT_VERSION</p>
    </div>
    
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Total Suites:</strong> $TOTAL_SUITES</p>
        <p><strong>Passed:</strong> $PASSED_SUITES</p>
        <p><strong>Failed:</strong> $FAILED_SUITES</p>
        <p><strong>Success Rate:</strong> $(echo "scale=1; $PASSED_SUITES * 100 / $TOTAL_SUITES" | bc -l 2>/dev/null || echo "0")%</p>
    </div>
EOF
    
    # Add suite details
    for suite in "${!SUITE_RESULTS[@]}"; do
        local suite_name="${TEST_SUITES[$suite]}"
        local result="${SUITE_RESULTS[$suite]}"
        local duration="${SUITE_DURATIONS[$suite]}"
        local output_file="$RESULTS_DIR/${suite}-output.log"
        
        local css_class="passed"
        case $result in
            "FAILED") css_class="failed" ;;
            "ERROR") css_class="error" ;;
        esac
        
        cat >> "$html_report" << EOF
    
    <div class="suite $css_class">
        <h3>$suite_name</h3>
        <p><strong>Result:</strong> $result</p>
        <p><strong>Duration:</strong> ${duration}s</p>
        <details>
            <summary>View Output</summary>
            <pre>$(cat "$output_file" 2>/dev/null || echo "Output not available")</pre>
        </details>
    </div>
EOF
    done
    
    cat >> "$html_report" << EOF
</body>
</html>
EOF
    
    log_success "HTML report generated: $html_report"
}

# =============================================================================
# Main Execution Functions
# =============================================================================

# Run all test suites
run_all_test_suites() {
    log_info "Starting comprehensive test suite execution"
    
    # Initialize test environment
    init_test_environment
    
    # Run test suites in logical order
    run_validation_suite
    run_setup_test_suite
    run_integration_test_suite
    run_health_check_suite
    
    # Generate reports
    generate_summary_report
    local summary_result=$?
    
    # Generate HTML report if requested
    if [ "$GENERATE_HTML" = true ]; then
        generate_html_report
    fi
    
    return $summary_result
}

# Run specific test suite
run_specific_suite() {
    local suite_key="$1"
    
    if [ -z "${TEST_SUITES[$suite_key]}" ]; then
        log_error "Unknown test suite: $suite_key"
        log_error "Available suites: ${!TEST_SUITES[*]}"
        return 1
    fi
    
    log_info "Running specific test suite: ${TEST_SUITES[$suite_key]}"
    
    # Initialize test environment
    init_test_environment
    
    # Run the specific suite
    case $suite_key in
        "validation") run_validation_suite ;;
        "setup") run_setup_test_suite ;;
        "integration") run_integration_test_suite ;;
        "health") run_health_check_suite ;;
    esac
    
    local suite_result=$?
    
    # Generate summary for single suite
    generate_summary_report
    
    return $suite_result
}

# Show usage information
show_usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

USAGE:
    $0 [OPTIONS] [SUITE]

DESCRIPTION:
    Orchestrates all testing and validation scripts for the repository-level
    GitHub Actions runner setup. Runs comprehensive tests and generates
    detailed reports.

ARGUMENTS:
    SUITE           Run specific test suite (optional)
                    Options: validation, setup, integration, health

REQUIRED ENVIRONMENT VARIABLES:
    GITHUB_USERNAME     GitHub username
    GITHUB_REPOSITORY   Repository name
    GH_PAT             GitHub Personal Access Token

OPTIONAL ENVIRONMENT VARIABLES:
    AWS_ACCESS_KEY_ID       AWS access key
    AWS_SECRET_ACCESS_KEY   AWS secret access key
    AWS_REGION             AWS region
    EC2_INSTANCE_ID        EC2 instance ID

OPTIONS:
    -h, --help      Show this help message
    -v, --version   Show script version
    --html          Generate HTML report in addition to JSON
    --results-dir   Specify custom results directory

TEST SUITES:
    validation      Repository Configuration Validation
    setup          Repository Setup Comprehensive Test
    integration    Workflow Integration Test
    health         Runner Health Check

EXAMPLES:
    # Run all test suites
    export GITHUB_USERNAME="myusername"
    export GITHUB_REPOSITORY="my-repo"
    export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
    $0

    # Run specific test suite
    $0 validation

    # Run with HTML report generation
    $0 --html

    # Run with custom results directory
    $0 --results-dir /custom/path

OUTPUT:
    $RESULTS_DIR/     Test results directory
    comprehensive-test-report.json    Final JSON report
    comprehensive-test-report.html    HTML report (if --html)
    *-output.log                     Individual suite outputs

EOF
}

# Parse command line arguments
GENERATE_HTML=false
CUSTOM_RESULTS_DIR=""
SPECIFIC_SUITE=""

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
        --html)
            GENERATE_HTML=true
            shift
            ;;
        --results-dir)
            CUSTOM_RESULTS_DIR="$2"
            shift 2
            ;;
        validation|setup|integration|health)
            SPECIFIC_SUITE="$1"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Update results directory if custom path provided
if [ -n "$CUSTOM_RESULTS_DIR" ]; then
    RESULTS_DIR="$CUSTOM_RESULTS_DIR"
    FINAL_REPORT="$RESULTS_DIR/comprehensive-test-report.json"
fi

# Main execution
main() {
    echo "=== $SCRIPT_NAME v$SCRIPT_VERSION ==="
    echo ""
    
    # Check for required environment variables
    if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPOSITORY" ] || [ -z "$GH_PAT" ]; then
        log_error "Required environment variables not set"
        log_error "Please set GITHUB_USERNAME, GITHUB_REPOSITORY, and GH_PAT"
        exit 1
    fi
    
    log_info "Repository: $GITHUB_USERNAME/$GITHUB_REPOSITORY"
    log_info "Results will be saved to: $RESULTS_DIR"
    echo ""
    
    # Run tests
    if [ -n "$SPECIFIC_SUITE" ]; then
        if run_specific_suite "$SPECIFIC_SUITE"; then
            log_success "Test suite completed successfully"
            exit 0
        else
            log_error "Test suite failed"
            exit 1
        fi
    else
        if run_all_test_suites; then
            log_success "All test suites completed successfully"
            exit 0
        else
            log_error "Some test suites failed"
            exit 1
        fi
    fi
}

# Execute main function
main "$@"