#!/bin/bash

# Repository Runner Health Check Script
# This script provides comprehensive health monitoring and status checking
# for repository-level GitHub Actions runners.

set -e

# Script version and metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="Repository Runner Health Check"

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
HEALTH_REPORT_FILE="/tmp/runner-health-report.json"

# Health check configuration
RUNNER_DIR="$HOME/actions-runner"
DEFAULT_RUNNER_NAME="gha_aws_runner"

# Health status tracking
OVERALL_HEALTH="HEALTHY"
declare -a HEALTH_ISSUES=()
declare -a HEALTH_WARNINGS=()

# =============================================================================
# Health Check Framework Functions
# =============================================================================

# Initialize health check environment
init_health_check() {
    log_info "Initializing runner health check"
    
    # Create health report file
    cat > "$HEALTH_REPORT_FILE" << EOF
{
    "health_check": {
        "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
        "script_version": "$SCRIPT_VERSION",
        "repository": "${GITHUB_USERNAME}/${GITHUB_REPOSITORY}",
        "runner_name": "${RUNNER_NAME:-$DEFAULT_RUNNER_NAME}"
    },
    "checks": {},
    "summary": {}
}
EOF
    
    log_success "Health check environment initialized"
}

# Record health check result
record_health_check() {
    local check_name="$1"
    local status="$2"
    local message="$3"
    local details="$4"
    
    # Update overall health status
    case $status in
        "ERROR"|"CRITICAL")
            OVERALL_HEALTH="UNHEALTHY"
            HEALTH_ISSUES+=("$check_name: $message")
            ;;
        "WARNING")
            if [ "$OVERALL_HEALTH" = "HEALTHY" ]; then
                OVERALL_HEALTH="DEGRADED"
            fi
            HEALTH_WARNINGS+=("$check_name: $message")
            ;;
    esac
    
    # Create JSON for this check
    local check_json=$(cat << EOF
{
    "status": "$status",
    "message": "$message",
    "details": $(echo "$details" | jq -R -s .),
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)
    
    # Update health report file
    jq ".checks[\"$check_name\"] = $check_json" "$HEALTH_REPORT_FILE" > "${HEALTH_REPORT_FILE}.tmp" && mv "${HEALTH_REPORT_FILE}.tmp" "$HEALTH_REPORT_FILE"
}

# =============================================================================
# GitHub Repository Health Checks
# =============================================================================

check_github_connectivity() {
    log_header "GitHub Connectivity Check"
    
    local status="OK"
    local message="GitHub API accessible"
    local details=""
    
    if [ -z "$GH_PAT" ]; then
        status="ERROR"
        message="GitHub PAT not configured"
        details="Set GH_PAT environment variable"
    else
        # Test GitHub API connectivity
        local api_response
        api_response=$(curl -s -w "%{http_code}" --max-time 10 \
            -H "Authorization: token $GH_PAT" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/user" 2>&1)
        
        local http_code="${api_response: -3}"
        
        case $http_code in
            200)
                local user_info="${api_response%???}"
                local username=$(echo "$user_info" | jq -r '.login')
                message="GitHub API accessible (user: $username)"
                details="API response time: $(curl -s -w "%{time_total}" -o /dev/null -H "Authorization: token $GH_PAT" "https://api.github.com/user")s"
                ;;
            401)
                status="ERROR"
                message="GitHub authentication failed"
                details="PAT is invalid or expired"
                ;;
            403)
                status="ERROR"
                message="GitHub API access forbidden"
                details="PAT may lack required permissions or rate limit exceeded"
                ;;
            *)
                status="ERROR"
                message="GitHub API connectivity failed"
                details="HTTP $http_code"
                ;;
        esac
    fi
    
    echo "Status: $status"
    echo "Message: $message"
    if [ -n "$details" ]; then
        echo "Details: $details"
    fi
    
    record_health_check "github_connectivity" "$status" "$message" "$details"
}

check_repository_access() {
    log_header "Repository Access Check"
    
    local status="OK"
    local message="Repository accessible"
    local details=""
    
    if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPOSITORY" ] || [ -z "$GH_PAT" ]; then
        status="ERROR"
        message="Repository configuration incomplete"
        details="Set GITHUB_USERNAME, GITHUB_REPOSITORY, and GH_PAT"
    else
        # Test repository access
        local repo_response
        repo_response=$(curl -s -w "%{http_code}" --max-time 10 \
            -H "Authorization: token $GH_PAT" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY" 2>&1)
        
        local http_code="${repo_response: -3}"
        local repo_body="${repo_response%???}"
        
        case $http_code in
            200)
                local repo_name=$(echo "$repo_body" | jq -r '.name')
                local repo_private=$(echo "$repo_body" | jq -r '.private')
                local admin_permission=$(echo "$repo_body" | jq -r '.permissions.admin // false')
                
                message="Repository accessible: $repo_name"
                details="Private: $repo_private, Admin access: $admin_permission"
                
                if [ "$admin_permission" != "true" ]; then
                    status="WARNING"
                    message="Repository accessible but no admin permissions"
                    details="$details - Admin permissions required for runner management"
                fi
                ;;
            404)
                status="ERROR"
                message="Repository not found or not accessible"
                details="Check repository name and PAT permissions"
                ;;
            403)
                status="ERROR"
                message="Repository access forbidden"
                details="PAT may lack repository access permissions"
                ;;
            *)
                status="ERROR"
                message="Repository access check failed"
                details="HTTP $http_code"
                ;;
        esac
    fi
    
    echo "Status: $status"
    echo "Message: $message"
    if [ -n "$details" ]; then
        echo "Details: $details"
    fi
    
    record_health_check "repository_access" "$status" "$message" "$details"
}

check_actions_enabled() {
    log_header "GitHub Actions Status Check"
    
    local status="OK"
    local message="GitHub Actions enabled"
    local details=""
    
    if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPOSITORY" ] || [ -z "$GH_PAT" ]; then
        status="ERROR"
        message="Configuration incomplete for Actions check"
        details="Repository configuration required"
    else
        # Test Actions API access
        local actions_response
        actions_response=$(curl -s -w "%{http_code}" --max-time 10 \
            -H "Authorization: token $GH_PAT" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners" 2>&1)
        
        local http_code="${actions_response: -3}"
        local actions_body="${actions_response%???}"
        
        case $http_code in
            200)
                local runner_count=$(echo "$actions_body" | jq -r '.total_count')
                message="GitHub Actions enabled"
                details="Registered runners: $runner_count"
                ;;
            404)
                status="ERROR"
                message="GitHub Actions not enabled"
                details="Enable Actions in repository Settings → Actions → General"
                ;;
            403)
                status="ERROR"
                message="Actions API access forbidden"
                details="Insufficient permissions or Actions disabled"
                ;;
            *)
                status="ERROR"
                message="Actions status check failed"
                details="HTTP $http_code"
                ;;
        esac
    fi
    
    echo "Status: $status"
    echo "Message: $message"
    if [ -n "$details" ]; then
        echo "Details: $details"
    fi
    
    record_health_check "actions_enabled" "$status" "$message" "$details"
}

# =============================================================================
# Runner Registration Health Checks
# =============================================================================

check_runner_registration() {
    log_header "Runner Registration Check"
    
    local status="OK"
    local message="Runner registration healthy"
    local details=""
    local runner_name="${RUNNER_NAME:-$DEFAULT_RUNNER_NAME}"
    
    if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPOSITORY" ] || [ -z "$GH_PAT" ]; then
        status="ERROR"
        message="Configuration incomplete for runner check"
        details="Repository configuration required"
    else
        # Get registered runners
        local runners_response
        runners_response=$(curl -s -w "%{http_code}" --max-time 10 \
            -H "Authorization: token $GH_PAT" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners" 2>&1)
        
        local http_code="${runners_response: -3}"
        local runners_body="${runners_response%???}"
        
        if [ "$http_code" = "200" ]; then
            local total_runners=$(echo "$runners_body" | jq -r '.total_count')
            
            if [ "$total_runners" -eq 0 ]; then
                status="WARNING"
                message="No runners registered"
                details="Repository has no self-hosted runners registered"
            else
                # Check for our specific runner
                local our_runner
                our_runner=$(echo "$runners_body" | jq -r ".runners[] | select(.name == \"$runner_name\")")
                
                if [ -n "$our_runner" ] && [ "$our_runner" != "null" ]; then
                    local runner_status=$(echo "$our_runner" | jq -r '.status')
                    local runner_busy=$(echo "$our_runner" | jq -r '.busy')
                    local runner_labels=$(echo "$our_runner" | jq -r '.labels[].name' | tr '\n' ',' | sed 's/,$//')
                    
                    message="Runner '$runner_name' registered"
                    details="Status: $runner_status, Busy: $runner_busy, Labels: $runner_labels"
                    
                    if [ "$runner_status" != "online" ]; then
                        status="WARNING"
                        message="Runner '$runner_name' not online"
                        details="$details - Runner may be offline or disconnected"
                    fi
                else
                    status="WARNING"
                    message="Expected runner '$runner_name' not found"
                    details="Found $total_runners other runners"
                fi
            fi
        else
            status="ERROR"
            message="Failed to check runner registration"
            details="HTTP $http_code"
        fi
    fi
    
    echo "Status: $status"
    echo "Message: $message"
    if [ -n "$details" ]; then
        echo "Details: $details"
    fi
    
    record_health_check "runner_registration" "$status" "$message" "$details"
}

check_runner_token_generation() {
    log_header "Runner Token Generation Check"
    
    local status="OK"
    local message="Registration token generation working"
    local details=""
    
    if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPOSITORY" ] || [ -z "$GH_PAT" ]; then
        status="ERROR"
        message="Configuration incomplete for token check"
        details="Repository configuration required"
    else
        # Test registration token generation
        local token_response
        token_response=$(curl -s -w "%{http_code}" --max-time 10 -X POST \
            -H "Authorization: token $GH_PAT" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners/registration-token" 2>&1)
        
        local http_code="${token_response: -3}"
        local token_body="${token_response%???}"
        
        case $http_code in
            201)
                local token=$(echo "$token_body" | jq -r '.token')
                local expires_at=$(echo "$token_body" | jq -r '.expires_at')
                
                if [ "$token" != "null" ] && [ -n "$token" ]; then
                    message="Registration token generated successfully"
                    details="Token expires: $expires_at"
                else
                    status="ERROR"
                    message="Invalid registration token received"
                    details="Token generation returned null or empty token"
                fi
                ;;
            403)
                status="ERROR"
                message="Insufficient permissions for token generation"
                details="Admin permissions required on repository"
                ;;
            404)
                status="ERROR"
                message="Token generation endpoint not found"
                details="Repository may not exist or Actions not enabled"
                ;;
            *)
                status="ERROR"
                message="Token generation failed"
                details="HTTP $http_code"
                ;;
        esac
    fi
    
    echo "Status: $status"
    echo "Message: $message"
    if [ -n "$details" ]; then
        echo "Details: $details"
    fi
    
    record_health_check "token_generation" "$status" "$message" "$details"
}

# =============================================================================
# Local Runner Health Checks
# =============================================================================

check_runner_installation() {
    log_header "Runner Installation Check"
    
    local status="OK"
    local message="Runner installation healthy"
    local details=""
    
    if [ ! -d "$RUNNER_DIR" ]; then
        status="WARNING"
        message="Runner directory not found"
        details="Runner not installed at $RUNNER_DIR"
    else
        echo "Runner directory: $RUNNER_DIR"
        
        # Check for required files
        local required_files=("config.sh" "run.sh" "svc.sh")
        local missing_files=()
        
        for file in "${required_files[@]}"; do
            if [ ! -f "$RUNNER_DIR/$file" ]; then
                missing_files+=("$file")
            fi
        done
        
        if [ ${#missing_files[@]} -gt 0 ]; then
            status="ERROR"
            message="Runner installation incomplete"
            details="Missing files: ${missing_files[*]}"
        else
            # Check runner configuration
            if [ -f "$RUNNER_DIR/.runner" ]; then
                local runner_config=$(cat "$RUNNER_DIR/.runner" 2>/dev/null || echo "{}")
                local configured_url=$(echo "$runner_config" | jq -r '.gitHubUrl // "not configured"')
                local configured_name=$(echo "$runner_config" | jq -r '.agentName // "not configured"')
                
                message="Runner installation complete"
                details="Configured for: $configured_url, Name: $configured_name"
                
                # Verify configuration matches current settings
                local expected_url="https://github.com/$GITHUB_USERNAME/$GITHUB_REPOSITORY"
                if [ -n "$GITHUB_USERNAME" ] && [ -n "$GITHUB_REPOSITORY" ] && [ "$configured_url" != "$expected_url" ]; then
                    status="WARNING"
                    message="Runner configured for different repository"
                    details="$details - Expected: $expected_url"
                fi
            else
                status="WARNING"
                message="Runner installed but not configured"
                details="Run configuration to register with repository"
            fi
        fi
    fi
    
    echo "Status: $status"
    echo "Message: $message"
    if [ -n "$details" ]; then
        echo "Details: $details"
    fi
    
    record_health_check "runner_installation" "$status" "$message" "$details"
}

check_runner_service() {
    log_header "Runner Service Check"
    
    local status="OK"
    local message="Runner service healthy"
    local details=""
    
    if [ ! -d "$RUNNER_DIR" ]; then
        status="WARNING"
        message="Runner not installed"
        details="Cannot check service status without installation"
    else
        # Check if service script exists
        if [ ! -f "$RUNNER_DIR/svc.sh" ]; then
            status="ERROR"
            message="Runner service script not found"
            details="svc.sh missing from runner installation"
        else
            # Check service status
            cd "$RUNNER_DIR"
            local service_status
            if service_status=$(sudo ./svc.sh status 2>&1); then
                if echo "$service_status" | grep -q "active (running)"; then
                    message="Runner service running"
                    details="Service is active and running"
                elif echo "$service_status" | grep -q "inactive"; then
                    status="WARNING"
                    message="Runner service not running"
                    details="Service is installed but not active"
                else
                    status="WARNING"
                    message="Runner service status unclear"
                    details="$service_status"
                fi
            else
                status="WARNING"
                message="Runner service not installed"
                details="Service not configured as system service"
            fi
            cd - > /dev/null
        fi
    fi
    
    echo "Status: $status"
    echo "Message: $message"
    if [ -n "$details" ]; then
        echo "Details: $details"
    fi
    
    record_health_check "runner_service" "$status" "$message" "$details"
}

check_runner_logs() {
    log_header "Runner Logs Check"
    
    local status="OK"
    local message="Runner logs healthy"
    local details=""
    
    if [ ! -d "$RUNNER_DIR" ]; then
        status="WARNING"
        message="Runner not installed"
        details="Cannot check logs without installation"
    else
        local log_dir="$RUNNER_DIR/_diag"
        
        if [ ! -d "$log_dir" ]; then
            status="WARNING"
            message="Runner log directory not found"
            details="No diagnostic logs available"
        else
            # Check for recent log files
            local recent_logs
            recent_logs=$(find "$log_dir" -name "*.log" -mtime -1 2>/dev/null | wc -l)
            
            if [ "$recent_logs" -gt 0 ]; then
                message="Runner logs available"
                details="Found $recent_logs recent log files"
                
                # Check for error patterns in recent logs
                local error_count=0
                if command -v grep &> /dev/null; then
                    error_count=$(find "$log_dir" -name "*.log" -mtime -1 -exec grep -l -i "error\|exception\|failed" {} \; 2>/dev/null | wc -l)
                fi
                
                if [ "$error_count" -gt 0 ]; then
                    status="WARNING"
                    message="Errors found in runner logs"
                    details="$details - $error_count log files contain errors"
                fi
            else
                status="WARNING"
                message="No recent runner logs"
                details="No log files from last 24 hours"
            fi
        fi
    fi
    
    echo "Status: $status"
    echo "Message: $message"
    if [ -n "$details" ]; then
        echo "Details: $details"
    fi
    
    record_health_check "runner_logs" "$status" "$message" "$details"
}

# =============================================================================
# AWS Infrastructure Health Checks
# =============================================================================

check_aws_connectivity() {
    log_header "AWS Connectivity Check"
    
    local status="OK"
    local message="AWS connectivity healthy"
    local details=""
    
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        status="WARNING"
        message="AWS credentials not configured"
        details="AWS integration not available"
    else
        # Test AWS credentials
        local aws_identity
        if aws_identity=$(aws sts get-caller-identity 2>&1); then
            local aws_user=$(echo "$aws_identity" | jq -r '.Arn')
            message="AWS connectivity healthy"
            details="Identity: $aws_user"
        else
            status="ERROR"
            message="AWS authentication failed"
            details="$aws_identity"
        fi
    fi
    
    echo "Status: $status"
    echo "Message: $message"
    if [ -n "$details" ]; then
        echo "Details: $details"
    fi
    
    record_health_check "aws_connectivity" "$status" "$message" "$details"
}

check_ec2_instance() {
    log_header "EC2 Instance Check"
    
    local status="OK"
    local message="EC2 instance healthy"
    local details=""
    
    if [ -z "$EC2_INSTANCE_ID" ]; then
        status="WARNING"
        message="EC2 instance not configured"
        details="EC2_INSTANCE_ID not set"
    elif [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        status="WARNING"
        message="Cannot check EC2 instance"
        details="AWS credentials not configured"
    else
        # Check EC2 instance status
        local instance_info
        if instance_info=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" 2>&1); then
            local instance_state=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].State.Name')
            local instance_type=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].InstanceType')
            local public_ip=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].PublicIpAddress // "none"')
            
            message="EC2 instance accessible"
            details="State: $instance_state, Type: $instance_type, IP: $public_ip"
            
            case $instance_state in
                "running")
                    status="OK"
                    ;;
                "stopped")
                    status="WARNING"
                    message="EC2 instance stopped"
                    ;;
                "stopping"|"pending"|"shutting-down")
                    status="WARNING"
                    message="EC2 instance in transition"
                    ;;
                "terminated")
                    status="ERROR"
                    message="EC2 instance terminated"
                    ;;
                *)
                    status="WARNING"
                    message="EC2 instance in unknown state"
                    ;;
            esac
        else
            status="ERROR"
            message="EC2 instance check failed"
            details="$instance_info"
        fi
    fi
    
    echo "Status: $status"
    echo "Message: $message"
    if [ -n "$details" ]; then
        echo "Details: $details"
    fi
    
    record_health_check "ec2_instance" "$status" "$message" "$details"
}

# =============================================================================
# Workflow Health Checks
# =============================================================================

check_workflow_files() {
    log_header "Workflow Files Check"
    
    local status="OK"
    local message="Workflow files healthy"
    local details=""
    
    local workflow_dir=".github/workflows"
    
    if [ ! -d "$workflow_dir" ]; then
        status="WARNING"
        message="Workflow directory not found"
        details="No GitHub Actions workflows configured"
    else
        local workflow_count=$(find "$workflow_dir" -name "*.yml" -o -name "*.yaml" | wc -l)
        
        if [ "$workflow_count" -eq 0 ]; then
            status="WARNING"
            message="No workflow files found"
            details="No YAML files in $workflow_dir"
        else
            message="Workflow files found"
            details="Found $workflow_count workflow files"
            
            # Check for runner-specific workflows
            local runner_workflows=0
            if ls "$workflow_dir"/*runner*.yml "$workflow_dir"/*runner*.yaml 2>/dev/null | grep -q .; then
                runner_workflows=$(ls "$workflow_dir"/*runner*.yml "$workflow_dir"/*runner*.yaml 2>/dev/null | wc -l)
            fi
            
            if [ "$runner_workflows" -gt 0 ]; then
                details="$details, Runner workflows: $runner_workflows"
            else
                status="WARNING"
                message="No runner-specific workflows found"
                details="$details - Consider adding runner management workflows"
            fi
        fi
    fi
    
    echo "Status: $status"
    echo "Message: $message"
    if [ -n "$details" ]; then
        echo "Details: $details"
    fi
    
    record_health_check "workflow_files" "$status" "$message" "$details"
}

check_recent_workflow_runs() {
    log_header "Recent Workflow Runs Check"
    
    local status="OK"
    local message="Workflow runs healthy"
    local details=""
    
    if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPOSITORY" ] || [ -z "$GH_PAT" ]; then
        status="WARNING"
        message="Cannot check workflow runs"
        details="Repository configuration incomplete"
    else
        # Get recent workflow runs
        local runs_response
        runs_response=$(curl -s -w "%{http_code}" --max-time 10 \
            -H "Authorization: token $GH_PAT" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runs?per_page=10" 2>&1)
        
        local http_code="${runs_response: -3}"
        local runs_body="${runs_response%???}"
        
        if [ "$http_code" = "200" ]; then
            local total_runs=$(echo "$runs_body" | jq -r '.total_count')
            local recent_runs=$(echo "$runs_body" | jq -r '.workflow_runs | length')
            
            message="Workflow runs accessible"
            details="Total runs: $total_runs, Recent: $recent_runs"
            
            if [ "$recent_runs" -gt 0 ]; then
                # Check for failed runs
                local failed_runs=$(echo "$runs_body" | jq -r '.workflow_runs[] | select(.status == "completed" and .conclusion == "failure") | .id' | wc -l)
                local success_runs=$(echo "$runs_body" | jq -r '.workflow_runs[] | select(.status == "completed" and .conclusion == "success") | .id' | wc -l)
                
                details="$details, Failed: $failed_runs, Success: $success_runs"
                
                if [ "$failed_runs" -gt "$success_runs" ] && [ "$failed_runs" -gt 0 ]; then
                    status="WARNING"
                    message="High failure rate in recent runs"
                fi
            fi
        else
            status="WARNING"
            message="Cannot access workflow runs"
            details="HTTP $http_code"
        fi
    fi
    
    echo "Status: $status"
    echo "Message: $message"
    if [ -n "$details" ]; then
        echo "Details: $details"
    fi
    
    record_health_check "workflow_runs" "$status" "$message" "$details"
}

# =============================================================================
# Health Report Generation
# =============================================================================

generate_health_summary() {
    log_header "Health Check Summary"
    
    # Update summary in JSON file
    local summary_json=$(cat << EOF
{
    "overall_health": "$OVERALL_HEALTH",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "issues_count": ${#HEALTH_ISSUES[@]},
    "warnings_count": ${#HEALTH_WARNINGS[@]},
    "issues": $(printf '%s\n' "${HEALTH_ISSUES[@]}" | jq -R . | jq -s .),
    "warnings": $(printf '%s\n' "${HEALTH_WARNINGS[@]}" | jq -R . | jq -s .)
}
EOF
)
    
    jq ".summary = $summary_json" "$HEALTH_REPORT_FILE" > "${HEALTH_REPORT_FILE}.tmp" && mv "${HEALTH_REPORT_FILE}.tmp" "$HEALTH_REPORT_FILE"
    
    # Display summary
    echo ""
    case $OVERALL_HEALTH in
        "HEALTHY")
            log_success "Overall Health: $OVERALL_HEALTH"
            ;;
        "DEGRADED")
            log_warning "Overall Health: $OVERALL_HEALTH"
            ;;
        "UNHEALTHY")
            log_error "Overall Health: $OVERALL_HEALTH"
            ;;
    esac
    
    echo "Issues: ${#HEALTH_ISSUES[@]}"
    echo "Warnings: ${#HEALTH_WARNINGS[@]}"
    
    if [ ${#HEALTH_ISSUES[@]} -gt 0 ]; then
        echo ""
        log_error "Critical Issues:"
        for issue in "${HEALTH_ISSUES[@]}"; do
            echo "  - $issue"
        done
    fi
    
    if [ ${#HEALTH_WARNINGS[@]} -gt 0 ]; then
        echo ""
        log_warning "Warnings:"
        for warning in "${HEALTH_WARNINGS[@]}"; do
            echo "  - $warning"
        done
    fi
    
    echo ""
    echo "Detailed report: $HEALTH_REPORT_FILE"
    
    # Return appropriate exit code
    case $OVERALL_HEALTH in
        "HEALTHY") return 0 ;;
        "DEGRADED") return 1 ;;
        "UNHEALTHY") return 2 ;;
    esac
}

# =============================================================================
# Main Health Check Execution
# =============================================================================

run_all_health_checks() {
    log_info "Starting comprehensive runner health check"
    
    # Initialize health check environment
    init_health_check
    
    # GitHub Repository Health Checks
    check_github_connectivity
    check_repository_access
    check_actions_enabled
    
    # Runner Registration Health Checks
    check_runner_registration
    check_runner_token_generation
    
    # Local Runner Health Checks
    check_runner_installation
    check_runner_service
    check_runner_logs
    
    # AWS Infrastructure Health Checks
    check_aws_connectivity
    check_ec2_instance
    
    # Workflow Health Checks
    check_workflow_files
    check_recent_workflow_runs
    
    # Generate final summary
    generate_health_summary
}

# Show usage information
show_usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

USAGE:
    $0 [OPTIONS]

DESCRIPTION:
    Comprehensive health monitoring and status checking for repository-level
    GitHub Actions runners. Checks GitHub connectivity, runner registration,
    local installation, AWS infrastructure, and workflow status.

ENVIRONMENT VARIABLES:
    GITHUB_USERNAME     GitHub username
    GITHUB_REPOSITORY   Repository name
    GH_PAT             GitHub Personal Access Token
    RUNNER_NAME        Runner name (default: $DEFAULT_RUNNER_NAME)
    AWS_ACCESS_KEY_ID   AWS access key (optional)
    AWS_SECRET_ACCESS_KEY AWS secret key (optional)
    AWS_REGION         AWS region (optional)
    EC2_INSTANCE_ID    EC2 instance ID (optional)

OPTIONS:
    -h, --help      Show this help message
    -v, --version   Show script version
    --json-only     Output only JSON report

EXAMPLES:
    # Basic health check
    export GITHUB_USERNAME="myusername"
    export GITHUB_REPOSITORY="my-repo"
    export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
    $0

    # Full health check with AWS
    export AWS_ACCESS_KEY_ID="AKIA..."
    export EC2_INSTANCE_ID="i-1234567890abcdef0"
    $0

EXIT CODES:
    0 - Healthy (all checks passed)
    1 - Degraded (warnings present)
    2 - Unhealthy (critical issues found)

OUTPUT:
    $HEALTH_REPORT_FILE     JSON health report

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
    
    # Run all health checks
    exit_code=0
    if ! run_all_health_checks; then
        exit_code=$?
    fi
    
    if [ "$JSON_ONLY" = true ]; then
        cat "$HEALTH_REPORT_FILE"
    fi
    
    exit $exit_code
}

# Execute main function
main "$@"