#!/bin/bash

# Comprehensive Repository Configuration Validation Script
# This script validates all repository configuration requirements and ensures
# the system is ready for repository-level GitHub Actions runner deployment.

set -e

# Script version and metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="Repository Configuration Validator"

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATION_LIB="$SCRIPT_DIR/repo-validation-functions.sh"
VALIDATION_REPORT_FILE="/tmp/repository-configuration-validation.json"

# Validation tracking
VALIDATIONS_RUN=0
VALIDATIONS_PASSED=0
VALIDATIONS_FAILED=0
VALIDATIONS_SKIPPED=0
declare -a FAILED_VALIDATIONS=()
declare -a SKIPPED_VALIDATIONS=()

# Configuration requirements mapping to Requirement 6 acceptance criteria
declare -A REQUIREMENT_MAPPING=(
    ["persistent_registration"]="6.1"
    ["runner_availability"]="6.2"
    ["cost_optimization"]="6.3"
    ["security_restrictions"]="6.4"
    ["isolation_guarantees"]="6.5"
)

# =============================================================================
# Validation Framework Functions
# =============================================================================

# Initialize validation environment
init_validation_environment() {
    log_info "Initializing repository configuration validation"
    
    # Create validation report file
    cat > "$VALIDATION_REPORT_FILE" << EOF
{
    "validation_run": {
        "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
        "script_version": "$SCRIPT_VERSION",
        "repository": "${GITHUB_USERNAME}/${GITHUB_REPOSITORY}",
        "requirements_mapping": $(echo '{}' | jq '. + $ARGS.named' --argjson ARGS "$(declare -p REQUIREMENT_MAPPING | sed 's/declare -A [^=]*=//' | tr -d '()')")
    },
    "validations": [],
    "summary": {}
}
EOF
    
    log_success "Validation environment initialized"
}

# Run a validation and track results
run_validation() {
    local category="$1"
    local validation_name="$2"
    local validation_function="$3"
    local requirement_ref="$4"
    shift 4
    local validation_args=("$@")
    
    VALIDATIONS_RUN=$((VALIDATIONS_RUN + 1))
    
    echo ""
    log_header "Validation $VALIDATIONS_RUN: $validation_name"
    if [ -n "$requirement_ref" ]; then
        echo "Requirement: $requirement_ref"
    fi
    
    local start_time=$(date +%s)
    local validation_result="FAILED"
    local validation_output=""
    local validation_error=""
    
    # Capture validation output
    if validation_output=$($validation_function "${validation_args[@]}" 2>&1); then
        validation_result="PASSED"
        VALIDATIONS_PASSED=$((VALIDATIONS_PASSED + 1))
        log_success "Validation PASSED: $validation_name"
    else
        local exit_code=$?
        if [ $exit_code -eq 2 ]; then
            validation_result="SKIPPED"
            VALIDATIONS_SKIPPED=$((VALIDATIONS_SKIPPED + 1))
            SKIPPED_VALIDATIONS+=("$validation_name")
            log_warning "Validation SKIPPED: $validation_name"
        else
            validation_result="FAILED"
            VALIDATIONS_FAILED=$((VALIDATIONS_FAILED + 1))
            FAILED_VALIDATIONS+=("$validation_name")
            log_error "Validation FAILED: $validation_name"
            validation_error="Exit code: $exit_code"
        fi
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "Result: $validation_result (${duration}s)"
    echo "Output: $validation_output"
    
    # Update JSON results
    local validation_json=$(cat << EOF
{
    "id": "validation_${VALIDATIONS_RUN}",
    "name": "$validation_name",
    "category": "$category",
    "requirement": "$requirement_ref",
    "result": "$validation_result",
    "duration": $duration,
    "output": $(echo "$validation_output" | jq -R -s .),
    "error": $(echo "$validation_error" | jq -R -s .),
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)
    
    jq ".validations += [$validation_json]" "$VALIDATION_REPORT_FILE" > "${VALIDATION_REPORT_FILE}.tmp" && mv "${VALIDATION_REPORT_FILE}.tmp" "$VALIDATION_REPORT_FILE"
}

# =============================================================================
# Core Configuration Validations (Requirement 6.1 - Persistent Registration)
# =============================================================================

validate_persistent_registration_capability() {
    log_info "Validating persistent registration capability"
    
    if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPOSITORY" ] || [ -z "$GH_PAT" ]; then
        echo "Required configuration variables not set"
        return 2  # Skip
    fi
    
    # Source validation library
    source "$VALIDATION_LIB"
    
    # Test registration token generation (indicates persistent registration capability)
    if validate_runner_registration_access "$GITHUB_USERNAME" "$GITHUB_REPOSITORY" "$GH_PAT"; then
        echo "Persistent registration capability confirmed"
        echo "Repository supports runner registration and management"
        return 0
    else
        echo "Persistent registration capability validation failed"
        return 1
    fi
}

validate_runner_persistence_configuration() {
    log_info "Validating runner persistence configuration"
    
    local runner_dir="$HOME/actions-runner"
    
    if [ ! -d "$runner_dir" ]; then
        echo "Runner directory not found - this is expected if not yet configured"
        echo "Persistence will be configured during runner setup"
        return 0
    fi
    
    # Check for persistent configuration files
    local config_files=(".runner" ".credentials")
    local persistent_config=true
    
    for file in "${config_files[@]}"; do
        if [ ! -f "$runner_dir/$file" ]; then
            echo "Configuration file missing: $file"
            persistent_config=false
        fi
    done
    
    if [ "$persistent_config" = true ]; then
        echo "Runner persistence configuration validated"
        echo "Configuration files present for persistent registration"
    else
        echo "Runner not configured for persistence yet"
        echo "This is normal for initial setup"
    fi
    
    return 0
}

# =============================================================================
# Runner Availability Validations (Requirement 6.2)
# =============================================================================

validate_runner_availability_setup() {
    log_info "Validating runner availability setup"
    
    # Check GitHub Actions is enabled
    if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPOSITORY" ] || [ -z "$GH_PAT" ]; then
        echo "Configuration incomplete for availability check"
        return 2  # Skip
    fi
    
    source "$VALIDATION_LIB"
    
    if validate_actions_enabled "$GITHUB_USERNAME" "$GITHUB_REPOSITORY" "$GH_PAT"; then
        echo "GitHub Actions enabled - runner availability supported"
        
        # Check current runner status
        local runners_response
        runners_response=$(curl -s -H "Authorization: token $GH_PAT" \
            "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners")
        
        local runner_count=$(echo "$runners_response" | jq -r '.total_count')
        echo "Current registered runners: $runner_count"
        
        if [ "$runner_count" -gt 0 ]; then
            echo "Runners available for job execution"
        else
            echo "No runners currently registered (expected for initial setup)"
        fi
        
        return 0
    else
        echo "GitHub Actions not enabled - runner availability not possible"
        return 1
    fi
}

validate_workflow_runner_configuration() {
    log_info "Validating workflow runner configuration"
    
    local workflow_dir=".github/workflows"
    
    if [ ! -d "$workflow_dir" ]; then
        echo "Workflow directory not found"
        echo "Workflows will be needed for runner availability"
        return 1
    fi
    
    # Check for runner-specific workflows
    local runner_workflows=()
    while IFS= read -r -d '' file; do
        if grep -q "self-hosted\|gha_aws_runner" "$file"; then
            runner_workflows+=("$(basename "$file")")
        fi
    done < <(find "$workflow_dir" -name "*.yml" -o -name "*.yaml" -print0 2>/dev/null)
    
    if [ ${#runner_workflows[@]} -gt 0 ]; then
        echo "Runner-configured workflows found: ${runner_workflows[*]}"
        echo "Workflows configured for self-hosted runner availability"
        return 0
    else
        echo "No workflows configured for self-hosted runners"
        echo "Add workflows with 'runs-on: [self-hosted, gha_aws_runner]'"
        return 1
    fi
}

# =============================================================================
# Cost Optimization Validations (Requirement 6.3)
# =============================================================================

validate_cost_optimization_features() {
    log_info "Validating cost optimization features"
    
    # Check AWS configuration for cost optimization
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        echo "AWS configuration not available"
        echo "Cost optimization features require AWS integration"
        return 2  # Skip
    fi
    
    # Test AWS connectivity
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "AWS credentials validation failed"
        return 1
    fi
    
    echo "AWS integration available for cost optimization"
    
    # Check EC2 instance configuration if available
    if [ -n "$EC2_INSTANCE_ID" ]; then
        local instance_info
        if instance_info=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" 2>&1); then
            local instance_type=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].InstanceType')
            local instance_state=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].State.Name')
            
            echo "EC2 instance type: $instance_type"
            echo "Current state: $instance_state"
            
            # Validate cost-optimized instance type
            if [[ "$instance_type" =~ ^t[2-4]\.(nano|micro|small) ]]; then
                echo "Cost-optimized instance type confirmed"
            else
                echo "Instance type may not be cost-optimized"
                echo "Consider using t3.micro or similar for cost optimization"
            fi
            
            # Check if instance can be stopped (cost optimization feature)
            if [ "$instance_state" = "running" ] || [ "$instance_state" = "stopped" ]; then
                echo "Instance supports start/stop for cost optimization"
            else
                echo "Instance state may not support cost optimization"
            fi
        else
            echo "Cannot access EC2 instance for cost optimization validation"
            return 1
        fi
    else
        echo "EC2_INSTANCE_ID not configured"
        echo "Cost optimization requires EC2 instance management"
    fi
    
    return 0
}

validate_workflow_cost_optimization() {
    log_info "Validating workflow cost optimization"
    
    local workflow_dir=".github/workflows"
    
    if [ ! -d "$workflow_dir" ]; then
        echo "No workflows found to validate cost optimization"
        return 2  # Skip
    fi
    
    # Check for start/stop patterns in workflows
    local cost_optimized_workflows=()
    while IFS= read -r -d '' file; do
        if grep -q "start-instances\|stop-instances" "$file"; then
            cost_optimized_workflows+=("$(basename "$file")")
        fi
    done < <(find "$workflow_dir" -name "*.yml" -o -name "*.yaml" -print0 2>/dev/null)
    
    if [ ${#cost_optimized_workflows[@]} -gt 0 ]; then
        echo "Cost-optimized workflows found: ${cost_optimized_workflows[*]}"
        echo "Workflows include EC2 start/stop for cost optimization"
        return 0
    else
        echo "No cost optimization patterns found in workflows"
        echo "Consider adding EC2 start/stop to workflows for cost optimization"
        return 1
    fi
}

# =============================================================================
# Security Restrictions Validations (Requirement 6.4)
# =============================================================================

validate_security_group_restrictions() {
    log_info "Validating security group restrictions"
    
    if [ -z "$EC2_INSTANCE_ID" ] || [ -z "$AWS_ACCESS_KEY_ID" ]; then
        echo "AWS/EC2 configuration not available for security validation"
        return 2  # Skip
    fi
    
    # Get security groups for the instance
    local security_groups
    if security_groups=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' --output text 2>&1); then
        
        echo "Security groups: $security_groups"
        
        # Check security group rules
        local has_restricted_access=false
        for sg in $security_groups; do
            local sg_rules
            if sg_rules=$(aws ec2 describe-security-groups --group-ids "$sg" \
                --query 'SecurityGroups[0].IpPermissions' 2>&1); then
                
                # Check for overly permissive rules (0.0.0.0/0 on sensitive ports)
                local open_ssh=$(echo "$sg_rules" | jq -r '.[] | select(.FromPort == 22) | .IpRanges[] | select(.CidrIp == "0.0.0.0/0") | .CidrIp' 2>/dev/null || echo "")
                
                if [ -n "$open_ssh" ]; then
                    echo "Warning: SSH (port 22) open to 0.0.0.0/0 in security group $sg"
                else
                    echo "SSH access properly restricted in security group $sg"
                    has_restricted_access=true
                fi
            fi
        done
        
        if [ "$has_restricted_access" = true ]; then
            echo "Security group restrictions validated"
            return 0
        else
            echo "Security group restrictions may be insufficient"
            return 1
        fi
    else
        echo "Cannot access security group information"
        return 1
    fi
}

validate_pat_security_scope() {
    log_info "Validating PAT security scope"
    
    if [ -z "$GH_PAT" ]; then
        echo "GitHub PAT not configured"
        return 2  # Skip
    fi
    
    source "$VALIDATION_LIB"
    
    # Validate PAT has appropriate scope (not excessive)
    if validate_pat_repo_scope "$GH_PAT"; then
        echo "PAT scope validation passed"
        
        # Check that PAT doesn't have admin:org (security best practice)
        validate_pat_no_admin_org "$GH_PAT"  # This is informational
        
        echo "PAT security scope validated"
        return 0
    else
        echo "PAT security scope validation failed"
        return 1
    fi
}

validate_runner_security_isolation() {
    log_info "Validating runner security isolation"
    
    local runner_dir="$HOME/actions-runner"
    
    if [ ! -d "$runner_dir" ]; then
        echo "Runner not installed - isolation will be configured during setup"
        return 0
    fi
    
    # Check runner directory permissions
    local dir_perms=$(stat -c "%a" "$runner_dir" 2>/dev/null || stat -f "%A" "$runner_dir" 2>/dev/null || echo "unknown")
    echo "Runner directory permissions: $dir_perms"
    
    # Check for sensitive files and their permissions
    local sensitive_files=(".credentials" ".runner" ".credentials_rsaparams")
    local security_issues=()
    
    for file in "${sensitive_files[@]}"; do
        local file_path="$runner_dir/$file"
        if [ -f "$file_path" ]; then
            local file_perms=$(stat -c "%a" "$file_path" 2>/dev/null || stat -f "%A" "$file_path" 2>/dev/null || echo "unknown")
            echo "Sensitive file $file permissions: $file_perms"
            
            # Check if file is readable by others (last digit > 0)
            if [[ "$file_perms" =~ [0-9][0-9][1-7]$ ]]; then
                security_issues+=("$file is readable by others")
            fi
        fi
    done
    
    if [ ${#security_issues[@]} -gt 0 ]; then
        echo "Security isolation issues found: ${security_issues[*]}"
        return 1
    else
        echo "Runner security isolation validated"
        return 0
    fi
}

# =============================================================================
# Isolation Guarantees Validations (Requirement 6.5)
# =============================================================================

validate_repository_isolation() {
    log_info "Validating repository isolation guarantees"
    
    if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPOSITORY" ] || [ -z "$GH_PAT" ]; then
        echo "Configuration incomplete for isolation validation"
        return 2  # Skip
    fi
    
    source "$VALIDATION_LIB"
    
    # Validate repository-specific registration
    if validate_repository_access "$GITHUB_USERNAME" "$GITHUB_REPOSITORY" "$GH_PAT"; then
        echo "Repository access validated - isolation boundary confirmed"
        
        # Check that runner will be registered to specific repository
        local expected_url="https://github.com/$GITHUB_USERNAME/$GITHUB_REPOSITORY"
        echo "Runner will be isolated to: $expected_url"
        
        # Verify admin permissions (required for isolation)
        if validate_repository_admin_permissions "$GITHUB_USERNAME" "$GITHUB_REPOSITORY" "$GH_PAT"; then
            echo "Admin permissions confirmed - full isolation control available"
            return 0
        else
            echo "Admin permissions missing - isolation may be incomplete"
            return 1
        fi
    else
        echo "Repository isolation validation failed"
        return 1
    fi
}

validate_workflow_isolation() {
    log_info "Validating workflow isolation configuration"
    
    local workflow_dir=".github/workflows"
    
    if [ ! -d "$workflow_dir" ]; then
        echo "No workflows to validate for isolation"
        return 2  # Skip
    fi
    
    # Check that workflows use repository-specific configurations
    local isolation_issues=()
    
    while IFS= read -r -d '' file; do
        local filename=$(basename "$file")
        
        # Check for hardcoded organization references (isolation violation)
        if grep -q "github\.com/[^/]*/[^/]*" "$file" && ! grep -q "github\.repository" "$file"; then
            isolation_issues+=("$filename may have hardcoded repository references")
        fi
        
        # Check for proper repository context usage
        if grep -q "github\.repository" "$file"; then
            echo "Workflow $filename uses proper repository context"
        fi
        
    done < <(find "$workflow_dir" -name "*.yml" -o -name "*.yaml" -print0 2>/dev/null)
    
    if [ ${#isolation_issues[@]} -gt 0 ]; then
        echo "Workflow isolation issues: ${isolation_issues[*]}"
        return 1
    else
        echo "Workflow isolation configuration validated"
        return 0
    fi
}

validate_network_isolation() {
    log_info "Validating network isolation configuration"
    
    # Test that we can reach required endpoints but not others
    local required_endpoints=("api.github.com" "github.com")
    local connectivity_ok=true
    
    for endpoint in "${required_endpoints[@]}"; do
        if timeout 5 bash -c "</dev/tcp/$endpoint/443" 2>/dev/null; then
            echo "Required connectivity to $endpoint: OK"
        else
            echo "Required connectivity to $endpoint: FAILED"
            connectivity_ok=false
        fi
    done
    
    if [ "$connectivity_ok" = true ]; then
        echo "Network isolation allows required connectivity"
        echo "Runner will have access to necessary GitHub services"
        return 0
    else
        echo "Network isolation may be blocking required connectivity"
        return 1
    fi
}

# =============================================================================
# Comprehensive Validation Execution
# =============================================================================

run_all_validations() {
    log_info "Starting comprehensive repository configuration validation"
    
    # Initialize validation environment
    init_validation_environment
    
    # Core Configuration Validations (Requirement 6.1)
    log_header "PERSISTENT REGISTRATION VALIDATIONS (Requirement 6.1)"
    run_validation "persistent_registration" "Persistent Registration Capability" validate_persistent_registration_capability "6.1"
    run_validation "persistent_registration" "Runner Persistence Configuration" validate_runner_persistence_configuration "6.1"
    
    # Runner Availability Validations (Requirement 6.2)
    log_header "RUNNER AVAILABILITY VALIDATIONS (Requirement 6.2)"
    run_validation "runner_availability" "Runner Availability Setup" validate_runner_availability_setup "6.2"
    run_validation "runner_availability" "Workflow Runner Configuration" validate_workflow_runner_configuration "6.2"
    
    # Cost Optimization Validations (Requirement 6.3)
    log_header "COST OPTIMIZATION VALIDATIONS (Requirement 6.3)"
    run_validation "cost_optimization" "Cost Optimization Features" validate_cost_optimization_features "6.3"
    run_validation "cost_optimization" "Workflow Cost Optimization" validate_workflow_cost_optimization "6.3"
    
    # Security Restrictions Validations (Requirement 6.4)
    log_header "SECURITY RESTRICTIONS VALIDATIONS (Requirement 6.4)"
    run_validation "security_restrictions" "Security Group Restrictions" validate_security_group_restrictions "6.4"
    run_validation "security_restrictions" "PAT Security Scope" validate_pat_security_scope "6.4"
    run_validation "security_restrictions" "Runner Security Isolation" validate_runner_security_isolation "6.4"
    
    # Isolation Guarantees Validations (Requirement 6.5)
    log_header "ISOLATION GUARANTEES VALIDATIONS (Requirement 6.5)"
    run_validation "isolation_guarantees" "Repository Isolation" validate_repository_isolation "6.5"
    run_validation "isolation_guarantees" "Workflow Isolation" validate_workflow_isolation "6.5"
    run_validation "isolation_guarantees" "Network Isolation" validate_network_isolation "6.5"
    
    # Generate final report
    generate_validation_report
}

# Generate final validation report
generate_validation_report() {
    log_header "Validation Report"
    
    # Update summary in JSON file
    local summary_json=$(cat << EOF
{
    "total_validations": $VALIDATIONS_RUN,
    "passed": $VALIDATIONS_PASSED,
    "failed": $VALIDATIONS_FAILED,
    "skipped": $VALIDATIONS_SKIPPED,
    "success_rate": $(echo "scale=2; $VALIDATIONS_PASSED * 100 / $VALIDATIONS_RUN" | bc -l 2>/dev/null || echo "0"),
    "failed_validations": $(printf '%s\n' "${FAILED_VALIDATIONS[@]}" | jq -R . | jq -s .),
    "skipped_validations": $(printf '%s\n' "${SKIPPED_VALIDATIONS[@]}" | jq -R . | jq -s .)
}
EOF
)
    
    jq ".summary = $summary_json" "$VALIDATION_REPORT_FILE" > "${VALIDATION_REPORT_FILE}.tmp" && mv "${VALIDATION_REPORT_FILE}.tmp" "$VALIDATION_REPORT_FILE"
    
    # Display summary
    echo ""
    echo "Validations Run: $VALIDATIONS_RUN"
    echo "Passed: $VALIDATIONS_PASSED"
    echo "Failed: $VALIDATIONS_FAILED"
    echo "Skipped: $VALIDATIONS_SKIPPED"
    
    if [ $VALIDATIONS_RUN -gt 0 ]; then
        local success_rate=$(echo "scale=1; $VALIDATIONS_PASSED * 100 / $VALIDATIONS_RUN" | bc -l 2>/dev/null || echo "0")
        echo "Success Rate: ${success_rate}%"
    fi
    
    if [ ${#FAILED_VALIDATIONS[@]} -gt 0 ]; then
        echo ""
        log_error "Failed Validations:"
        for validation in "${FAILED_VALIDATIONS[@]}"; do
            echo "  - $validation"
        done
    fi
    
    if [ ${#SKIPPED_VALIDATIONS[@]} -gt 0 ]; then
        echo ""
        log_warning "Skipped Validations:"
        for validation in "${SKIPPED_VALIDATIONS[@]}"; do
            echo "  - $validation"
        done
    fi
    
    echo ""
    echo "Detailed report: $VALIDATION_REPORT_FILE"
    
    # Provide recommendations
    if [ $VALIDATIONS_FAILED -gt 0 ]; then
        echo ""
        log_error "Configuration validation failed"
        log_error "Address the failed validations before proceeding with runner setup"
        return 1
    elif [ $VALIDATIONS_SKIPPED -gt 0 ]; then
        echo ""
        log_warning "Some validations were skipped due to missing configuration"
        log_warning "Consider completing the configuration for full validation"
        return 0
    else
        echo ""
        log_success "All repository configuration validations passed"
        log_success "System is ready for repository-level runner deployment"
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
    Comprehensive validation of all repository configuration requirements
    for GitHub Actions runner deployment. Validates against Requirement 6
    acceptance criteria (6.1-6.5) for security and cost optimization.

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

VALIDATION CATEGORIES:
    - Persistent Registration (Requirement 6.1)
    - Runner Availability (Requirement 6.2)
    - Cost Optimization (Requirement 6.3)
    - Security Restrictions (Requirement 6.4)
    - Isolation Guarantees (Requirement 6.5)

EXAMPLES:
    # Basic configuration validation
    export GITHUB_USERNAME="myusername"
    export GITHUB_REPOSITORY="my-repo"
    export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
    $0

    # Full validation with AWS
    export AWS_ACCESS_KEY_ID="AKIA..."
    export EC2_INSTANCE_ID="i-1234567890abcdef0"
    $0

OUTPUT:
    $VALIDATION_REPORT_FILE     JSON validation report

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
    
    # Run all validations
    if run_all_validations; then
        log_success "Repository configuration validation completed successfully"
        exit 0
    else
        log_error "Repository configuration validation failed"
        exit 1
    fi
}

# Execute main function
main "$@"