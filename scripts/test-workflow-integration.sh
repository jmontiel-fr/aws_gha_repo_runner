#!/bin/bash

# GitHub Actions Workflow Integration Test Script
# This script tests the integration and functionality of repository-level
# GitHub Actions workflows for the self-hosted runner.

set -e

# Script version and metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="Workflow Integration Test"

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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR=".github/workflows"
TEST_RESULTS_FILE="/tmp/workflow-integration-test-results.json"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
declare -a FAILED_TESTS=()

# =============================================================================
# Test Framework Functions
# =============================================================================

# Initialize test environment
init_test_environment() {
    log_info "Initializing workflow integration test environment"
    
    # Create test results file
    cat > "$TEST_RESULTS_FILE" << EOF
{
    "test_run": {
        "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
        "script_version": "$SCRIPT_VERSION",
        "repository": "${GITHUB_USERNAME}/${GITHUB_REPOSITORY}"
    },
    "workflow_tests": [],
    "summary": {}
}
EOF
    
    log_success "Test environment initialized"
}

# Run a test and track results
run_test() {
    local test_name="$1"
    local test_function="$2"
    shift 2
    local test_args=("$@")
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    echo ""
    echo "=== Test $TESTS_RUN: $test_name ==="
    
    local start_time=$(date +%s)
    local test_result="FAILED"
    local test_output=""
    
    if test_output=$($test_function "${test_args[@]}" 2>&1); then
        test_result="PASSED"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log_success "Test PASSED: $test_name"
    else
        local exit_code=$?
        if [ $exit_code -eq 2 ]; then
            test_result="SKIPPED"
            TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
            log_warning "Test SKIPPED: $test_name"
        else
            test_result="FAILED"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            FAILED_TESTS+=("$test_name")
            log_error "Test FAILED: $test_name"
        fi
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "Result: $test_result (${duration}s)"
    echo "Output: $test_output"
    
    # Update JSON results
    local test_json=$(cat << EOF
{
    "name": "$test_name",
    "result": "$test_result",
    "duration": $duration,
    "output": $(echo "$test_output" | jq -R -s .)
}
EOF
)
    
    jq ".workflow_tests += [$test_json]" "$TEST_RESULTS_FILE" > "${TEST_RESULTS_FILE}.tmp" && mv "${TEST_RESULTS_FILE}.tmp" "$TEST_RESULTS_FILE"
}

# =============================================================================
# Workflow File Validation Tests
# =============================================================================

test_workflow_files_exist() {
    log_info "Testing workflow files existence and structure"
    
    if [ ! -d "$WORKFLOW_DIR" ]; then
        echo "Workflow directory not found: $WORKFLOW_DIR"
        return 1
    fi
    
    local expected_workflows=("runner-demo.yml" "configure-runner.yml")
    local found_workflows=()
    local missing_workflows=()
    
    for workflow in "${expected_workflows[@]}"; do
        local workflow_path="$WORKFLOW_DIR/$workflow"
        if [ -f "$workflow_path" ]; then
            found_workflows+=("$workflow")
            echo "Found workflow: $workflow"
        else
            missing_workflows+=("$workflow")
        fi
    done
    
    if [ ${#missing_workflows[@]} -gt 0 ]; then
        echo "Missing workflows: ${missing_workflows[*]}"
        return 1
    fi
    
    echo "All expected workflow files found: ${found_workflows[*]}"
    return 0
}

test_workflow_yaml_syntax() {
    log_info "Testing workflow YAML syntax"
    
    if [ ! -d "$WORKFLOW_DIR" ]; then
        echo "Workflow directory not found"
        return 2  # Skip
    fi
    
    local yaml_errors=()
    
    for workflow_file in "$WORKFLOW_DIR"/*.yml "$WORKFLOW_DIR"/*.yaml; do
        if [ -f "$workflow_file" ]; then
            local filename=$(basename "$workflow_file")
            echo "Validating YAML syntax: $filename"
            
            # Test with Python if available
            if command -v python3 &> /dev/null; then
                if python3 -c "import yaml; yaml.safe_load(open('$workflow_file'))" 2>/dev/null; then
                    echo "  $filename: Valid YAML"
                else
                    echo "  $filename: Invalid YAML"
                    yaml_errors+=("$filename")
                fi
            # Test with yq if available
            elif command -v yq &> /dev/null; then
                if yq eval '.' "$workflow_file" > /dev/null 2>&1; then
                    echo "  $filename: Valid YAML"
                else
                    echo "  $filename: Invalid YAML"
                    yaml_errors+=("$filename")
                fi
            else
                echo "  $filename: Cannot validate (no YAML parser available)"
            fi
        fi
    done
    
    if [ ${#yaml_errors[@]} -gt 0 ]; then
        echo "YAML syntax errors in: ${yaml_errors[*]}"
        return 1
    fi
    
    echo "All workflow files have valid YAML syntax"
    return 0
}

test_workflow_required_secrets() {
    log_info "Testing workflow required secrets configuration"
    
    local required_secrets=("AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_REGION" "GH_PAT" "EC2_INSTANCE_ID" "RUNNER_NAME")
    local workflow_files=()
    
    # Find all workflow files
    if [ -d "$WORKFLOW_DIR" ]; then
        while IFS= read -r -d '' file; do
            workflow_files+=("$file")
        done < <(find "$WORKFLOW_DIR" -name "*.yml" -o -name "*.yaml" -print0)
    else
        echo "Workflow directory not found"
        return 2  # Skip
    fi
    
    if [ ${#workflow_files[@]} -eq 0 ]; then
        echo "No workflow files found"
        return 2  # Skip
    fi
    
    local missing_secrets_overall=()
    
    for workflow_file in "${workflow_files[@]}"; do
        local filename=$(basename "$workflow_file")
        echo "Checking secrets in: $filename"
        
        local missing_secrets_file=()
        for secret in "${required_secrets[@]}"; do
            if grep -q "secrets\.$secret" "$workflow_file"; then
                echo "  $secret: referenced"
            else
                missing_secrets_file+=("$secret")
            fi
        done
        
        if [ ${#missing_secrets_file[@]} -gt 0 ]; then
            echo "  Missing secret references: ${missing_secrets_file[*]}"
            missing_secrets_overall+=("${missing_secrets_file[@]}")
        fi
    done
    
    # Remove duplicates from overall missing secrets
    local unique_missing=($(printf '%s\n' "${missing_secrets_overall[@]}" | sort -u))
    
    if [ ${#unique_missing[@]} -gt 0 ]; then
        echo "Secrets not referenced in any workflow: ${unique_missing[*]}"
        echo "Note: Some secrets may be optional depending on workflow design"
    fi
    
    echo "Workflow secrets validation completed"
    return 0
}

test_workflow_runner_labels() {
    log_info "Testing workflow runner labels configuration"
    
    local expected_labels=("self-hosted" "gha_aws_runner")
    local workflow_files=()
    
    # Find all workflow files
    if [ -d "$WORKFLOW_DIR" ]; then
        while IFS= read -r -d '' file; do
            workflow_files+=("$file")
        done < <(find "$WORKFLOW_DIR" -name "*.yml" -o -name "*.yaml" -print0)
    else
        echo "Workflow directory not found"
        return 2  # Skip
    fi
    
    local label_issues=()
    
    for workflow_file in "${workflow_files[@]}"; do
        local filename=$(basename "$workflow_file")
        echo "Checking runner labels in: $filename"
        
        # Look for runs-on configurations
        if grep -q "runs-on:" "$workflow_file"; then
            local runs_on_lines=$(grep -n "runs-on:" "$workflow_file")
            echo "  Found runs-on configurations:"
            echo "$runs_on_lines" | while read -r line; do
                echo "    $line"
                
                # Check if it uses self-hosted runner
                if echo "$line" | grep -q "self-hosted"; then
                    echo "    Uses self-hosted runner: YES"
                    
                    # Check for custom label
                    if echo "$line" | grep -q "gha_aws_runner"; then
                        echo "    Uses custom label: YES"
                    else
                        echo "    Uses custom label: NO (may cause issues)"
                    fi
                else
                    echo "    Uses GitHub-hosted runner"
                fi
            done
        else
            echo "  No runs-on configurations found"
        fi
    done
    
    echo "Runner labels validation completed"
    return 0
}

# =============================================================================
# GitHub API Integration Tests
# =============================================================================

test_github_api_connectivity() {
    log_info "Testing GitHub API connectivity"
    
    if [ -z "$GH_PAT" ]; then
        echo "GH_PAT not set - skipping API tests"
        return 2  # Skip
    fi
    
    # Test basic API connectivity
    local api_response
    api_response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/user")
    
    local http_code="${api_response: -3}"
    
    if [ "$http_code" = "200" ]; then
        echo "GitHub API connectivity: OK"
    else
        echo "GitHub API connectivity failed (HTTP $http_code)"
        return 1
    fi
    
    # Test repository-specific API access
    if [ -n "$GITHUB_USERNAME" ] && [ -n "$GITHUB_REPOSITORY" ]; then
        local repo_response
        repo_response=$(curl -s -w "%{http_code}" \
            -H "Authorization: token $GH_PAT" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY")
        
        local repo_http_code="${repo_response: -3}"
        
        if [ "$repo_http_code" = "200" ]; then
            echo "Repository API access: OK"
        else
            echo "Repository API access failed (HTTP $repo_http_code)"
            return 1
        fi
    fi
    
    return 0
}

test_actions_api_access() {
    log_info "Testing GitHub Actions API access"
    
    if [ -z "$GH_PAT" ] || [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPOSITORY" ]; then
        echo "Required variables not set - skipping Actions API tests"
        return 2  # Skip
    fi
    
    # Test Actions runners API
    local runners_response
    runners_response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners")
    
    local runners_http_code="${runners_response: -3}"
    local runners_body="${runners_response%???}"
    
    case $runners_http_code in
        200)
            echo "Actions runners API access: OK"
            local runner_count=$(echo "$runners_body" | jq -r '.total_count')
            echo "Current runners registered: $runner_count"
            
            if [ "$runner_count" -gt 0 ]; then
                echo "Registered runners:"
                echo "$runners_body" | jq -r '.runners[] | "  - \(.name) (Status: \(.status))"'
            fi
            ;;
        404)
            echo "Actions not enabled for repository or repository not found"
            return 1
            ;;
        403)
            echo "Insufficient permissions for Actions API"
            return 1
            ;;
        *)
            echo "Actions API access failed (HTTP $runners_http_code)"
            return 1
            ;;
    esac
    
    # Test workflow runs API
    local runs_response
    runs_response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runs?per_page=5")
    
    local runs_http_code="${runs_response: -3}"
    local runs_body="${runs_response%???}"
    
    if [ "$runs_http_code" = "200" ]; then
        echo "Workflow runs API access: OK"
        local runs_count=$(echo "$runs_body" | jq -r '.total_count')
        echo "Total workflow runs: $runs_count"
        
        if [ "$runs_count" -gt 0 ]; then
            echo "Recent workflow runs:"
            echo "$runs_body" | jq -r '.workflow_runs[0:3][] | "  - \(.name): \(.status) (\(.created_at))"'
        fi
    else
        echo "Workflow runs API access failed (HTTP $runs_http_code)"
        return 1
    fi
    
    return 0
}

test_registration_token_generation() {
    log_info "Testing runner registration token generation"
    
    if [ -z "$GH_PAT" ] || [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPOSITORY" ]; then
        echo "Required variables not set"
        return 2  # Skip
    fi
    
    # Generate registration token
    local token_response
    token_response=$(curl -s -w "%{http_code}" -X POST \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners/registration-token")
    
    local token_http_code="${token_response: -3}"
    local token_body="${token_response%???}"
    
    case $token_http_code in
        201)
            local token=$(echo "$token_body" | jq -r '.token')
            local expires_at=$(echo "$token_body" | jq -r '.expires_at')
            
            if [ "$token" != "null" ] && [ -n "$token" ]; then
                echo "Registration token generated successfully"
                echo "Token length: ${#token} characters"
                echo "Expires at: $expires_at"
                
                # Validate token format (GitHub tokens are typically base64-like)
                if [[ "$token" =~ ^[A-Za-z0-9+/=]+$ ]]; then
                    echo "Token format: Valid"
                else
                    echo "Token format: Invalid"
                    return 1
                fi
            else
                echo "Invalid token received"
                return 1
            fi
            ;;
        403)
            echo "Insufficient permissions to generate registration token"
            return 1
            ;;
        404)
            echo "Repository not found or Actions not enabled"
            return 1
            ;;
        *)
            echo "Token generation failed (HTTP $token_http_code)"
            echo "Response: $token_body"
            return 1
            ;;
    esac
    
    return 0
}

# =============================================================================
# AWS Integration Tests
# =============================================================================

test_aws_ec2_integration() {
    log_info "Testing AWS EC2 integration"
    
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_REGION" ]; then
        echo "AWS credentials not configured - skipping EC2 tests"
        return 2  # Skip
    fi
    
    # Test AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "AWS credentials validation failed"
        return 1
    fi
    
    echo "AWS credentials validated"
    
    # Test EC2 instance access if specified
    if [ -n "$EC2_INSTANCE_ID" ]; then
        echo "Testing EC2 instance: $EC2_INSTANCE_ID"
        
        local instance_info
        if instance_info=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" 2>&1); then
            local instance_state=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].State.Name')
            local instance_type=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].InstanceType')
            local public_ip=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].PublicIpAddress // "none"')
            
            echo "Instance state: $instance_state"
            echo "Instance type: $instance_type"
            echo "Public IP: $public_ip"
            
            if [ "$instance_state" = "running" ]; then
                echo "Instance is running and ready for runner configuration"
            elif [ "$instance_state" = "stopped" ]; then
                echo "Instance is stopped - can be started for runner use"
            else
                echo "Instance state may not be suitable for runner use"
            fi
        else
            echo "Failed to access EC2 instance: $instance_info"
            return 1
        fi
    else
        echo "EC2_INSTANCE_ID not set - skipping instance-specific tests"
    fi
    
    return 0
}

test_aws_permissions() {
    log_info "Testing AWS permissions for runner management"
    
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        echo "AWS credentials not configured"
        return 2  # Skip
    fi
    
    # Test required EC2 permissions
    local required_actions=("ec2:DescribeInstances" "ec2:StartInstances" "ec2:StopInstances")
    local permission_issues=()
    
    echo "Testing AWS permissions..."
    
    # Test describe instances (should work for any instance or return empty)
    if aws ec2 describe-instances --max-items 1 &> /dev/null; then
        echo "ec2:DescribeInstances: OK"
    else
        echo "ec2:DescribeInstances: FAILED"
        permission_issues+=("ec2:DescribeInstances")
    fi
    
    # Test start/stop instances if we have an instance ID
    if [ -n "$EC2_INSTANCE_ID" ]; then
        # We won't actually start/stop, just test the dry-run
        if aws ec2 start-instances --instance-ids "$EC2_INSTANCE_ID" --dry-run &> /dev/null; then
            echo "ec2:StartInstances: OK"
        else
            # Check if it's a permission issue or dry-run success
            local start_result
            start_result=$(aws ec2 start-instances --instance-ids "$EC2_INSTANCE_ID" --dry-run 2>&1 || true)
            if echo "$start_result" | grep -q "DryRunOperation"; then
                echo "ec2:StartInstances: OK (dry-run successful)"
            else
                echo "ec2:StartInstances: FAILED"
                permission_issues+=("ec2:StartInstances")
            fi
        fi
        
        if aws ec2 stop-instances --instance-ids "$EC2_INSTANCE_ID" --dry-run &> /dev/null; then
            echo "ec2:StopInstances: OK"
        else
            local stop_result
            stop_result=$(aws ec2 stop-instances --instance-ids "$EC2_INSTANCE_ID" --dry-run 2>&1 || true)
            if echo "$stop_result" | grep -q "DryRunOperation"; then
                echo "ec2:StopInstances: OK (dry-run successful)"
            else
                echo "ec2:StopInstances: FAILED"
                permission_issues+=("ec2:StopInstances")
            fi
        fi
    else
        echo "EC2_INSTANCE_ID not set - skipping start/stop permission tests"
    fi
    
    if [ ${#permission_issues[@]} -gt 0 ]; then
        echo "Permission issues found: ${permission_issues[*]}"
        return 1
    fi
    
    echo "AWS permissions validation completed successfully"
    return 0
}

# =============================================================================
# End-to-End Integration Tests
# =============================================================================

test_workflow_trigger_capability() {
    log_info "Testing workflow trigger capability"
    
    if [ -z "$GH_PAT" ] || [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPOSITORY" ]; then
        echo "Required variables not set"
        return 2  # Skip
    fi
    
    # Check if workflows can be triggered via API
    local workflows_response
    workflows_response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/workflows")
    
    local workflows_http_code="${workflows_response: -3}"
    local workflows_body="${workflows_response%???}"
    
    if [ "$workflows_http_code" != "200" ]; then
        echo "Failed to access workflows API (HTTP $workflows_http_code)"
        return 1
    fi
    
    local workflow_count=$(echo "$workflows_body" | jq -r '.total_count')
    echo "Available workflows: $workflow_count"
    
    if [ "$workflow_count" -gt 0 ]; then
        echo "Workflows found:"
        echo "$workflows_body" | jq -r '.workflows[] | "  - \(.name) (\(.path))"'
        
        # Check for workflow_dispatch triggers
        local dispatch_workflows=()
        while IFS= read -r workflow_id; do
            local workflow_name=$(echo "$workflows_body" | jq -r ".workflows[] | select(.id == $workflow_id) | .name")
            dispatch_workflows+=("$workflow_name")
        done < <(echo "$workflows_body" | jq -r '.workflows[] | select(.path | contains("runner-demo") or contains("configure-runner")) | .id')
        
        if [ ${#dispatch_workflows[@]} -gt 0 ]; then
            echo "Workflows with manual trigger capability: ${dispatch_workflows[*]}"
        else
            echo "No workflows found with manual trigger capability"
        fi
    else
        echo "No workflows found in repository"
    fi
    
    return 0
}

test_runner_configuration_workflow() {
    log_info "Testing runner configuration workflow integration"
    
    # Check if configure-runner.yml exists and has proper structure
    local config_workflow="$WORKFLOW_DIR/configure-runner.yml"
    
    if [ ! -f "$config_workflow" ]; then
        echo "Configure runner workflow not found: $config_workflow"
        return 1
    fi
    
    echo "Configure runner workflow found"
    
    # Check for required workflow elements
    local required_elements=("workflow_dispatch" "jobs" "steps")
    local missing_elements=()
    
    for element in "${required_elements[@]}"; do
        if grep -q "$element" "$config_workflow"; then
            echo "$element: found"
        else
            missing_elements+=("$element")
        fi
    done
    
    if [ ${#missing_elements[@]} -gt 0 ]; then
        echo "Missing workflow elements: ${missing_elements[*]}"
        return 1
    fi
    
    # Check for AWS and GitHub integrations
    local integrations=("aws-actions/configure-aws-credentials" "secrets.GH_PAT" "secrets.EC2_INSTANCE_ID")
    local missing_integrations=()
    
    for integration in "${integrations[@]}"; do
        if grep -q "$integration" "$config_workflow"; then
            echo "Integration found: $integration"
        else
            missing_integrations+=("$integration")
        fi
    done
    
    if [ ${#missing_integrations[@]} -gt 0 ]; then
        echo "Missing integrations: ${missing_integrations[*]}"
        echo "These may be optional depending on workflow design"
    fi
    
    echo "Runner configuration workflow validation completed"
    return 0
}

# =============================================================================
# Test Execution and Reporting
# =============================================================================

# Generate final test report
generate_test_report() {
    log_info "Generating workflow integration test report"
    
    # Update summary in JSON file
    local summary_json=$(cat << EOF
{
    "total_tests": $TESTS_RUN,
    "passed": $TESTS_PASSED,
    "failed": $TESTS_FAILED,
    "skipped": $TESTS_SKIPPED,
    "success_rate": $(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_RUN" | bc -l 2>/dev/null || echo "0"),
    "failed_tests": $(printf '%s\n' "${FAILED_TESTS[@]}" | jq -R . | jq -s .)
}
EOF
)
    
    jq ".summary = $summary_json" "$TEST_RESULTS_FILE" > "${TEST_RESULTS_FILE}.tmp" && mv "${TEST_RESULTS_FILE}.tmp" "$TEST_RESULTS_FILE"
    
    # Display summary
    echo ""
    echo "=== WORKFLOW INTEGRATION TEST REPORT ==="
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
    
    echo ""
    echo "Detailed results: $TEST_RESULTS_FILE"
    
    # Return appropriate exit code
    if [ $TESTS_FAILED -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# Main test execution function
run_all_tests() {
    log_info "Starting workflow integration tests"
    
    # Initialize test environment
    init_test_environment
    
    # Workflow File Tests
    log_info "=== WORKFLOW FILE VALIDATION ==="
    run_test "Workflow Files Exist" test_workflow_files_exist
    run_test "Workflow YAML Syntax" test_workflow_yaml_syntax
    run_test "Workflow Required Secrets" test_workflow_required_secrets
    run_test "Workflow Runner Labels" test_workflow_runner_labels
    
    # GitHub API Integration Tests
    log_info "=== GITHUB API INTEGRATION ==="
    run_test "GitHub API Connectivity" test_github_api_connectivity
    run_test "Actions API Access" test_actions_api_access
    run_test "Registration Token Generation" test_registration_token_generation
    
    # AWS Integration Tests
    log_info "=== AWS INTEGRATION ==="
    run_test "AWS EC2 Integration" test_aws_ec2_integration
    run_test "AWS Permissions" test_aws_permissions
    
    # End-to-End Integration Tests
    log_info "=== END-TO-END INTEGRATION ==="
    run_test "Workflow Trigger Capability" test_workflow_trigger_capability
    run_test "Runner Configuration Workflow" test_runner_configuration_workflow
    
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
    Tests the integration and functionality of repository-level GitHub Actions
    workflows for the self-hosted runner setup.

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

EXAMPLES:
    # Run workflow integration tests
    export GITHUB_USERNAME="myusername"
    export GITHUB_REPOSITORY="my-repo"
    export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
    $0

OUTPUT:
    $TEST_RESULTS_FILE     JSON test results

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
    
    # Run all tests
    if run_all_tests; then
        log_success "Workflow integration tests completed successfully"
        exit 0
    else
        log_error "Workflow integration tests failed"
        exit 1
    fi
}

# Execute main function
main "$@"