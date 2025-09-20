#!/bin/bash

# Comprehensive Repository-Level Setup Test Script
# This script validates the complete repository-level GitHub Actions runner setup
# and ensures all components work correctly together.

set -e

# Script version and metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="Repository Setup Comprehensive Test"

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

# Script directory and dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATION_LIB="$SCRIPT_DIR/repo-validation-functions.sh"
REPO_SETUP_SCRIPT="$SCRIPT_DIR/repo-runner-setup.sh"

# Test configuration
TEST_RESULTS_FILE="/tmp/repository-setup-test-results.json"
DETAILED_LOG_FILE="/tmp/repository-setup-test-detailed.log"

# Test counters and tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
declare -a FAILED_TESTS=()
declare -a SKIPPED_TESTS=()

# Test categories
declare -A TEST_CATEGORIES=(
    ["prerequisites"]="Prerequisites and Dependencies"
    ["configuration"]="Configuration Validation"
    ["permissions"]="Permission and Access Tests"
    ["integration"]="Integration and Workflow Tests"
    ["security"]="Security and Best Practices"
    ["performance"]="Performance and Optimization"
)

# =============================================================================
# Test Framework Functions
# =============================================================================

# Initialize test environment
init_test_environment() {
    log_info "Initializing test environment"
    
    # Create test results file
    cat > "$TEST_RESULTS_FILE" << EOF
{
    "test_run": {
        "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
        "script_version": "$SCRIPT_VERSION",
        "environment": {
            "os": "$(uname -s)",
            "shell": "$SHELL",
            "user": "$USER"
        }
    },
    "test_results": [],
    "summary": {}
}
EOF
    
    # Initialize detailed log
    echo "=== Repository Setup Comprehensive Test Log ===" > "$DETAILED_LOG_FILE"
    echo "Started at: $(date)" >> "$DETAILED_LOG_FILE"
    echo "" >> "$DETAILED_LOG_FILE"
    
    log_success "Test environment initialized"
}

# Run a test and track results
run_test() {
    local category="$1"
    local test_name="$2"
    local test_function="$3"
    shift 3
    local test_args=("$@")
    
    TESTS_RUN=$((TESTS_RUN + 1))
    local test_id="test_${TESTS_RUN}"
    
    echo "" | tee -a "$DETAILED_LOG_FILE"
    echo "=== Test $TESTS_RUN: $test_name ===" | tee -a "$DETAILED_LOG_FILE"
    echo "Category: ${TEST_CATEGORIES[$category]}" | tee -a "$DETAILED_LOG_FILE"
    echo "Started at: $(date)" | tee -a "$DETAILED_LOG_FILE"
    
    local start_time=$(date +%s)
    local test_result="FAILED"
    local test_output=""
    local test_error=""
    
    # Capture test output
    if test_output=$($test_function "${test_args[@]}" 2>&1); then
        test_result="PASSED"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log_success "Test PASSED: $test_name"
    else
        local exit_code=$?
        if [ $exit_code -eq 2 ]; then
            test_result="SKIPPED"
            TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
            SKIPPED_TESTS+=("$test_name")
            log_warning "Test SKIPPED: $test_name"
        else
            test_result="FAILED"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            FAILED_TESTS+=("$test_name")
            log_error "Test FAILED: $test_name"
            test_error="Exit code: $exit_code"
        fi
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Log detailed results
    echo "Result: $test_result" | tee -a "$DETAILED_LOG_FILE"
    echo "Duration: ${duration}s" | tee -a "$DETAILED_LOG_FILE"
    echo "Output:" | tee -a "$DETAILED_LOG_FILE"
    echo "$test_output" | tee -a "$DETAILED_LOG_FILE"
    if [ -n "$test_error" ]; then
        echo "Error: $test_error" | tee -a "$DETAILED_LOG_FILE"
    fi
    
    # Update JSON results
    local test_json=$(cat << EOF
{
    "id": "$test_id",
    "name": "$test_name",
    "category": "$category",
    "result": "$test_result",
    "duration": $duration,
    "output": $(echo "$test_output" | jq -R -s .),
    "error": $(echo "$test_error" | jq -R -s .)
}
EOF
)
    
    # Add to results file (using jq to properly append)
    jq ".test_results += [$test_json]" "$TEST_RESULTS_FILE" > "${TEST_RESULTS_FILE}.tmp" && mv "${TEST_RESULTS_FILE}.tmp" "$TEST_RESULTS_FILE"
}

# Skip a test with reason
skip_test() {
    local category="$1"
    local test_name="$2"
    local reason="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    SKIPPED_TESTS+=("$test_name")
    
    log_warning "Test SKIPPED: $test_name - $reason"
    
    # Log to detailed file
    echo "" >> "$DETAILED_LOG_FILE"
    echo "=== Test $TESTS_RUN: $test_name (SKIPPED) ===" >> "$DETAILED_LOG_FILE"
    echo "Reason: $reason" >> "$DETAILED_LOG_FILE"
}

# =============================================================================
# Prerequisites and Dependencies Tests
# =============================================================================

test_required_tools() {
    log_info "Testing required tools availability"
    
    local required_tools=("curl" "jq" "aws" "ssh" "git")
    local missing_tools=()
    local tool_versions=""
    
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            local version=""
            case $tool in
                "curl") version=$(curl --version | head -n1) ;;
                "jq") version=$(jq --version) ;;
                "aws") version=$(aws --version 2>&1 | head -n1) ;;
                "ssh") version=$(ssh -V 2>&1) ;;
                "git") version=$(git --version) ;;
            esac
            tool_versions+="$tool: $version\n"
        else
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo "Missing required tools: ${missing_tools[*]}"
        return 1
    fi
    
    echo -e "All required tools available:\n$tool_versions"
    return 0
}

test_validation_library() {
    log_info "Testing validation library availability"
    
    if [ ! -f "$VALIDATION_LIB" ]; then
        echo "Validation library not found: $VALIDATION_LIB"
        return 1
    fi
    
    if [ ! -r "$VALIDATION_LIB" ]; then
        echo "Validation library not readable: $VALIDATION_LIB"
        return 1
    fi
    
    # Source the library and test a function
    source "$VALIDATION_LIB"
    
    if ! command -v validate_required_tools &> /dev/null; then
        echo "Validation library functions not available after sourcing"
        return 1
    fi
    
    echo "Validation library loaded successfully"
    echo "Available functions: $(declare -F | grep validate_ | wc -l) validation functions"
    return 0
}

test_setup_script_availability() {
    log_info "Testing repository setup script availability"
    
    if [ ! -f "$REPO_SETUP_SCRIPT" ]; then
        echo "Repository setup script not found: $REPO_SETUP_SCRIPT"
        return 1
    fi
    
    if [ ! -x "$REPO_SETUP_SCRIPT" ]; then
        echo "Repository setup script not executable: $REPO_SETUP_SCRIPT"
        return 1
    fi
    
    # Test help functionality
    if ! "$REPO_SETUP_SCRIPT" --help &> /dev/null; then
        echo "Repository setup script help functionality not working"
        return 1
    fi
    
    echo "Repository setup script available and functional"
    return 0
}

# =============================================================================
# Configuration Validation Tests
# =============================================================================

test_environment_variables() {
    log_info "Testing environment variable configuration"
    
    local required_vars=("GITHUB_USERNAME" "GITHUB_REPOSITORY" "GH_PAT")
    local optional_vars=("AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_REGION" "EC2_INSTANCE_ID")
    local missing_required=()
    local missing_optional=()
    
    # Check required variables
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_required+=("$var")
        else
            echo "$var: configured (${#!var} characters)"
        fi
    done
    
    # Check optional variables
    for var in "${optional_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_optional+=("$var")
        else
            echo "$var: configured"
        fi
    done
    
    if [ ${#missing_required[@]} -gt 0 ]; then
        echo "Missing required environment variables: ${missing_required[*]}"
        echo "Set these variables before running repository setup"
        return 1
    fi
    
    if [ ${#missing_optional[@]} -gt 0 ]; then
        echo "Missing optional environment variables: ${missing_optional[*]}"
        echo "These may be needed for full AWS integration"
    fi
    
    echo "Environment variable configuration validated"
    return 0
}

test_github_configuration_format() {
    log_info "Testing GitHub configuration format validation"
    
    # Source validation library
    source "$VALIDATION_LIB"
    
    if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPOSITORY" ]; then
        echo "GITHUB_USERNAME and GITHUB_REPOSITORY must be set for this test"
        return 2  # Skip test
    fi
    
    # Test username format
    if ! validate_username_format "$GITHUB_USERNAME"; then
        echo "Invalid GitHub username format: $GITHUB_USERNAME"
        return 1
    fi
    
    # Test repository format
    if ! validate_repository_format "$GITHUB_REPOSITORY"; then
        echo "Invalid GitHub repository format: $GITHUB_REPOSITORY"
        return 1
    fi
    
    echo "GitHub configuration format validation passed"
    echo "Username: $GITHUB_USERNAME"
    echo "Repository: $GITHUB_REPOSITORY"
    return 0
}

test_aws_configuration() {
    log_info "Testing AWS configuration"
    
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_REGION" ]; then
        echo "AWS configuration not complete - skipping AWS tests"
        return 2  # Skip test
    fi
    
    # Test AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "AWS credentials validation failed"
        echo "Check AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
        return 1
    fi
    
    local aws_identity=$(aws sts get-caller-identity)
    local aws_user=$(echo "$aws_identity" | jq -r '.Arn')
    
    echo "AWS credentials validated"
    echo "Identity: $aws_user"
    echo "Region: $AWS_REGION"
    
    # Test EC2 instance if specified
    if [ -n "$EC2_INSTANCE_ID" ]; then
        if aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" &> /dev/null; then
            local instance_state=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" --query 'Reservations[0].Instances[0].State.Name' --output text)
            echo "EC2 instance $EC2_INSTANCE_ID state: $instance_state"
        else
            echo "EC2 instance $EC2_INSTANCE_ID not accessible or doesn't exist"
            return 1
        fi
    fi
    
    return 0
}

# =============================================================================
# Permission and Access Tests
# =============================================================================

test_github_authentication() {
    log_info "Testing GitHub authentication"
    
    if [ -z "$GH_PAT" ]; then
        echo "GH_PAT environment variable not set"
        return 2  # Skip test
    fi
    
    # Source validation library
    source "$VALIDATION_LIB"
    
    local authenticated_user
    if authenticated_user=$(validate_user_authentication "$GH_PAT"); then
        echo "GitHub authentication successful"
        echo "Authenticated user: $authenticated_user"
        
        # Verify authenticated user matches GITHUB_USERNAME if set
        if [ -n "$GITHUB_USERNAME" ] && [ "$authenticated_user" != "$GITHUB_USERNAME" ]; then
            echo "Warning: Authenticated user ($authenticated_user) differs from GITHUB_USERNAME ($GITHUB_USERNAME)"
        fi
        
        return 0
    else
        echo "GitHub authentication failed"
        return 1
    fi
}

test_repository_access() {
    log_info "Testing repository access and permissions"
    
    if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPOSITORY" ] || [ -z "$GH_PAT" ]; then
        echo "GITHUB_USERNAME, GITHUB_REPOSITORY, and GH_PAT must be set"
        return 2  # Skip test
    fi
    
    # Source validation library
    source "$VALIDATION_LIB"
    
    if validate_repository_configuration "$GITHUB_USERNAME" "$GITHUB_REPOSITORY" "$GH_PAT"; then
        echo "Repository access and permissions validated successfully"
        return 0
    else
        echo "Repository access validation failed"
        return 1
    fi
}

test_runner_registration_capability() {
    log_info "Testing runner registration capability"
    
    if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPOSITORY" ] || [ -z "$GH_PAT" ]; then
        echo "Required environment variables not set"
        return 2  # Skip test
    fi
    
    # Source validation library
    source "$VALIDATION_LIB"
    
    if validate_runner_registration_access "$GITHUB_USERNAME" "$GITHUB_REPOSITORY" "$GH_PAT"; then
        echo "Runner registration capability confirmed"
        return 0
    else
        echo "Runner registration capability test failed"
        return 1
    fi
}

# =============================================================================
# Integration and Workflow Tests
# =============================================================================

test_workflow_files_exist() {
    log_info "Testing GitHub Actions workflow files"
    
    local workflow_dir=".github/workflows"
    local expected_workflows=("runner-demo.yml" "configure-runner.yml")
    local missing_workflows=()
    
    if [ ! -d "$workflow_dir" ]; then
        echo "GitHub Actions workflow directory not found: $workflow_dir"
        return 1
    fi
    
    for workflow in "${expected_workflows[@]}"; do
        local workflow_path="$workflow_dir/$workflow"
        if [ -f "$workflow_path" ]; then
            echo "Workflow found: $workflow"
            
            # Basic YAML syntax check
            if command -v python3 &> /dev/null; then
                if python3 -c "import yaml; yaml.safe_load(open('$workflow_path'))" 2>/dev/null; then
                    echo "  YAML syntax: valid"
                else
                    echo "  YAML syntax: invalid"
                    return 1
                fi
            fi
        else
            missing_workflows+=("$workflow")
        fi
    done
    
    if [ ${#missing_workflows[@]} -gt 0 ]; then
        echo "Missing workflow files: ${missing_workflows[*]}"
        return 1
    fi
    
    echo "All expected workflow files found and validated"
    return 0
}

test_repository_secrets_documentation() {
    log_info "Testing repository secrets documentation"
    
    local required_secrets=("AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_REGION" "GH_PAT" "EC2_INSTANCE_ID" "RUNNER_NAME")
    
    # Check if documentation mentions required secrets
    local docs_found=false
    local docs_files=("README.md" "docs/repository-runner-setup.md" ".kiro/specs/personal-repository-runner/design.md")
    
    for doc_file in "${docs_files[@]}"; do
        if [ -f "$doc_file" ]; then
            docs_found=true
            echo "Checking documentation: $doc_file"
            
            local missing_secrets=()
            for secret in "${required_secrets[@]}"; do
                if ! grep -q "$secret" "$doc_file"; then
                    missing_secrets+=("$secret")
                fi
            done
            
            if [ ${#missing_secrets[@]} -eq 0 ]; then
                echo "  All required secrets documented"
            else
                echo "  Missing secret documentation: ${missing_secrets[*]}"
            fi
        fi
    done
    
    if [ "$docs_found" = false ]; then
        echo "No documentation files found to check"
        return 1
    fi
    
    echo "Repository secrets documentation check completed"
    return 0
}

test_terraform_configuration() {
    log_info "Testing Terraform configuration compatibility"
    
    local terraform_dir="terraform"
    
    if [ ! -d "$terraform_dir" ]; then
        echo "Terraform directory not found: $terraform_dir"
        return 2  # Skip test
    fi
    
    # Check for required Terraform files
    local required_files=("main.tf" "variables.tf" "outputs.tf")
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$terraform_dir/$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        echo "Missing Terraform files: ${missing_files[*]}"
        return 1
    fi
    
    # Test Terraform syntax if terraform is available
    if command -v terraform &> /dev/null; then
        cd "$terraform_dir"
        if terraform validate &> /dev/null; then
            echo "Terraform configuration syntax valid"
        else
            echo "Terraform configuration syntax errors found"
            cd - > /dev/null
            return 1
        fi
        cd - > /dev/null
    else
        echo "Terraform not available - skipping syntax validation"
    fi
    
    echo "Terraform configuration compatibility check passed"
    return 0
}

# =============================================================================
# Security and Best Practices Tests
# =============================================================================

test_pat_scope_security() {
    log_info "Testing PAT scope security best practices"
    
    if [ -z "$GH_PAT" ]; then
        echo "GH_PAT not set"
        return 2  # Skip test
    fi
    
    # Source validation library
    source "$VALIDATION_LIB"
    
    # Test PAT has appropriate scope
    if ! validate_pat_repo_scope "$GH_PAT"; then
        echo "PAT scope validation failed"
        return 1
    fi
    
    # Test PAT doesn't have excessive permissions
    validate_pat_no_admin_org "$GH_PAT"  # This is a warning, not a failure
    
    echo "PAT scope security validation completed"
    return 0
}

test_runner_security_configuration() {
    log_info "Testing runner security configuration"
    
    # Check if runner directory has appropriate permissions
    local runner_dir="$HOME/actions-runner"
    
    if [ -d "$runner_dir" ]; then
        local dir_perms=$(stat -c "%a" "$runner_dir" 2>/dev/null || stat -f "%A" "$runner_dir" 2>/dev/null)
        echo "Runner directory permissions: $dir_perms"
        
        # Check for sensitive files
        local sensitive_files=(".credentials" ".runner" ".credentials_rsaparams")
        for file in "${sensitive_files[@]}"; do
            local file_path="$runner_dir/$file"
            if [ -f "$file_path" ]; then
                local file_perms=$(stat -c "%a" "$file_path" 2>/dev/null || stat -f "%A" "$file_path" 2>/dev/null)
                echo "Sensitive file $file permissions: $file_perms"
                
                # Check if file is readable by others
                if [[ "$file_perms" =~ [0-9][0-9][1-7] ]]; then
                    echo "Warning: Sensitive file $file is readable by others"
                fi
            fi
        done
    else
        echo "Runner directory not found - this is expected if runner not yet configured"
    fi
    
    echo "Runner security configuration check completed"
    return 0
}

# =============================================================================
# Performance and Optimization Tests
# =============================================================================

test_network_connectivity() {
    log_info "Testing network connectivity to required services"
    
    local endpoints=(
        "api.github.com:443"
        "github.com:443"
    )
    
    if [ -n "$AWS_REGION" ]; then
        endpoints+=("ec2.$AWS_REGION.amazonaws.com:443")
    fi
    
    local failed_endpoints=()
    
    for endpoint in "${endpoints[@]}"; do
        local host=$(echo "$endpoint" | cut -d: -f1)
        local port=$(echo "$endpoint" | cut -d: -f2)
        
        if timeout 10 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
            echo "Connectivity to $endpoint: OK"
        else
            echo "Connectivity to $endpoint: FAILED"
            failed_endpoints+=("$endpoint")
        fi
    done
    
    if [ ${#failed_endpoints[@]} -gt 0 ]; then
        echo "Failed to connect to: ${failed_endpoints[*]}"
        return 1
    fi
    
    echo "All network connectivity tests passed"
    return 0
}

test_api_rate_limits() {
    log_info "Testing GitHub API rate limits"
    
    if [ -z "$GH_PAT" ]; then
        echo "GH_PAT not set"
        return 2  # Skip test
    fi
    
    local rate_limit_response
    rate_limit_response=$(curl -s -H "Authorization: token $GH_PAT" "https://api.github.com/rate_limit")
    
    if [ $? -ne 0 ]; then
        echo "Failed to check rate limits"
        return 1
    fi
    
    local core_limit=$(echo "$rate_limit_response" | jq -r '.resources.core.limit')
    local core_remaining=$(echo "$rate_limit_response" | jq -r '.resources.core.remaining')
    local core_reset=$(echo "$rate_limit_response" | jq -r '.resources.core.reset')
    
    echo "GitHub API rate limits:"
    echo "  Core limit: $core_limit"
    echo "  Remaining: $core_remaining"
    echo "  Reset time: $(date -d @$core_reset 2>/dev/null || date -r $core_reset 2>/dev/null || echo $core_reset)"
    
    if [ "$core_remaining" -lt 100 ]; then
        echo "Warning: Low API rate limit remaining ($core_remaining)"
    fi
    
    return 0
}

# =============================================================================
# Test Execution and Reporting
# =============================================================================

# Generate final test report
generate_test_report() {
    log_info "Generating comprehensive test report"
    
    # Update summary in JSON file
    local summary_json=$(cat << EOF
{
    "total_tests": $TESTS_RUN,
    "passed": $TESTS_PASSED,
    "failed": $TESTS_FAILED,
    "skipped": $TESTS_SKIPPED,
    "success_rate": $(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_RUN" | bc -l 2>/dev/null || echo "0"),
    "failed_tests": $(printf '%s\n' "${FAILED_TESTS[@]}" | jq -R . | jq -s .),
    "skipped_tests": $(printf '%s\n' "${SKIPPED_TESTS[@]}" | jq -R . | jq -s .)
}
EOF
)
    
    jq ".summary = $summary_json" "$TEST_RESULTS_FILE" > "${TEST_RESULTS_FILE}.tmp" && mv "${TEST_RESULTS_FILE}.tmp" "$TEST_RESULTS_FILE"
    
    # Display summary
    echo ""
    echo "=== COMPREHENSIVE TEST REPORT ==="
    echo "Tests Run: $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo "Skipped: $TESTS_SKIPPED"
    
    if [ $TESTS_RUN -gt 0 ]; then
        local success_rate=$(echo "scale=1; $TESTS_PASSED * 100 / $TESTS_RUN" | bc -l 2>/dev/null || echo "0")
        echo "Success Rate: ${success_rate}%"
    fi
    
    if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
        echo ""
        echo "Failed Tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
    fi
    
    if [ ${#SKIPPED_TESTS[@]} -gt 0 ]; then
        echo ""
        echo "Skipped Tests:"
        for test in "${SKIPPED_TESTS[@]}"; do
            echo "  - $test"
        done
    fi
    
    echo ""
    echo "Detailed results: $TEST_RESULTS_FILE"
    echo "Detailed log: $DETAILED_LOG_FILE"
    
    # Return appropriate exit code
    if [ $TESTS_FAILED -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# Main test execution function
run_all_tests() {
    log_info "Starting comprehensive repository setup validation"
    
    # Initialize test environment
    init_test_environment
    
    # Prerequisites and Dependencies Tests
    log_info "=== PREREQUISITES AND DEPENDENCIES ==="
    run_test "prerequisites" "Required Tools Available" test_required_tools
    run_test "prerequisites" "Validation Library Available" test_validation_library
    run_test "prerequisites" "Setup Script Available" test_setup_script_availability
    
    # Configuration Validation Tests
    log_info "=== CONFIGURATION VALIDATION ==="
    run_test "configuration" "Environment Variables" test_environment_variables
    run_test "configuration" "GitHub Configuration Format" test_github_configuration_format
    run_test "configuration" "AWS Configuration" test_aws_configuration
    
    # Permission and Access Tests
    log_info "=== PERMISSIONS AND ACCESS ==="
    run_test "permissions" "GitHub Authentication" test_github_authentication
    run_test "permissions" "Repository Access" test_repository_access
    run_test "permissions" "Runner Registration Capability" test_runner_registration_capability
    
    # Integration and Workflow Tests
    log_info "=== INTEGRATION AND WORKFLOWS ==="
    run_test "integration" "Workflow Files Exist" test_workflow_files_exist
    run_test "integration" "Repository Secrets Documentation" test_repository_secrets_documentation
    run_test "integration" "Terraform Configuration" test_terraform_configuration
    
    # Security and Best Practices Tests
    log_info "=== SECURITY AND BEST PRACTICES ==="
    run_test "security" "PAT Scope Security" test_pat_scope_security
    run_test "security" "Runner Security Configuration" test_runner_security_configuration
    
    # Performance and Optimization Tests
    log_info "=== PERFORMANCE AND OPTIMIZATION ==="
    run_test "performance" "Network Connectivity" test_network_connectivity
    run_test "performance" "API Rate Limits" test_api_rate_limits
    
    # Generate final report
    generate_test_report
}

# Show usage information
show_usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

USAGE:
    $0 [OPTIONS]

DESCRIPTION:
    Comprehensive validation of repository-level GitHub Actions runner setup.
    Tests all components including configuration, permissions, workflows, and security.

REQUIRED ENVIRONMENT VARIABLES:
    GITHUB_USERNAME     GitHub username
    GITHUB_REPOSITORY   Repository name
    GH_PAT             GitHub Personal Access Token (repo scope)

OPTIONAL ENVIRONMENT VARIABLES:
    AWS_ACCESS_KEY_ID       AWS access key for EC2 management
    AWS_SECRET_ACCESS_KEY   AWS secret access key
    AWS_REGION             AWS region
    EC2_INSTANCE_ID        EC2 instance ID

OPTIONS:
    -h, --help      Show this help message
    -v, --version   Show script version
    --json-only     Output only JSON results (no console output)

EXAMPLES:
    # Run all tests with environment variables
    export GITHUB_USERNAME="myusername"
    export GITHUB_REPOSITORY="my-repo"
    export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
    $0

    # Run with AWS configuration
    export AWS_ACCESS_KEY_ID="AKIA..."
    export AWS_SECRET_ACCESS_KEY="..."
    export AWS_REGION="us-east-1"
    export EC2_INSTANCE_ID="i-1234567890abcdef0"
    $0

OUTPUT FILES:
    $TEST_RESULTS_FILE     JSON test results
    $DETAILED_LOG_FILE     Detailed test log

EOF
}

# Parse command line arguments
JSON_ONLY=false

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
        --json-only)
            JSON_ONLY=true
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
    if [ "$JSON_ONLY" = false ]; then
        echo "=== $SCRIPT_NAME v$SCRIPT_VERSION ==="
        echo ""
    fi
    
    # Run all tests
    if run_all_tests; then
        if [ "$JSON_ONLY" = false ]; then
            log_success "Repository setup validation completed successfully"
        fi
        exit 0
    else
        if [ "$JSON_ONLY" = false ]; then
            log_error "Repository setup validation failed"
        fi
        exit 1
    fi
}

# Execute main function
main "$@"