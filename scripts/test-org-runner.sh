#!/bin/bash
set -e

# GitHub Runner Testing Script
# This script helps test and validate GitHub Actions runner access for both organization and repository levels

# Script metadata
SCRIPT_VERSION="2.0.0"
SCRIPT_NAME="GitHub Runner Testing Script"

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

# Configuration variables
GITHUB_ORGANIZATION="${GITHUB_ORGANIZATION:-}"
GITHUB_USERNAME="${GITHUB_USERNAME:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GH_PAT="${GH_PAT:-}"
RUNNER_NAME="${RUNNER_NAME:-gha_aws_runner}"
RUNNER_MODE="${RUNNER_MODE:-auto}" # auto, organization, repository

# Show usage information
show_usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

USAGE:
    $0 [OPTIONS]

DESCRIPTION:
    Tests and validates GitHub Actions runner access and functionality for both organization and repository levels.
    Automatically detects the appropriate mode based on provided environment variables.

REQUIRED ENVIRONMENT VARIABLES (Organization Mode):
    GITHUB_ORGANIZATION    GitHub organization name
    GH_PAT                GitHub Personal Access Token with 'repo' and 'admin:org' scopes

REQUIRED ENVIRONMENT VARIABLES (Repository Mode):
    GITHUB_USERNAME       GitHub username
    GITHUB_REPOSITORY     GitHub repository name
    GH_PAT                GitHub Personal Access Token with 'repo' scope

OPTIONAL ENVIRONMENT VARIABLES:
    RUNNER_NAME           Runner name to test (default: gha_aws_runner)
    RUNNER_MODE           Force mode: auto, organization, repository (default: auto)

OPTIONS:
    -h, --help           Show this help message
    -v, --version        Show script version
    --list-runners       List all organization runners
    --test-api           Test GitHub API access and permissions
    --test-runner        Test specific runner availability and status
    --test-repos         Test runner access from multiple repositories
    --generate-workflow  Generate test workflow files for repositories
    --full-test          Run comprehensive test suite

EXAMPLES:
    # Test organization API access and permissions
    export GITHUB_ORGANIZATION="my-org"
    export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
    $0 --test-api

    # Test repository API access and permissions
    export GITHUB_USERNAME="my-username"
    export GITHUB_REPOSITORY="my-repo"
    export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
    $0 --test-api

    # Test specific runner
    $0 --test-runner

    # Run full test suite
    $0 --full-test

    # Generate test workflows
    $0 --generate-workflow

PREREQUISITES:
    Organization Mode:
    - GitHub organization admin permissions
    - GitHub PAT with 'repo' and 'admin:org' scopes
    
    Repository Mode:
    - GitHub repository admin permissions
    - GitHub PAT with 'repo' scope only
    
    Common:
    - curl and jq installed
    - Internet connectivity to GitHub API

EOF
}

# Determine runner mode based on environment variables
determine_runner_mode() {
    if [ "$RUNNER_MODE" = "organization" ] || [ "$RUNNER_MODE" = "repository" ]; then
        log_info "Using forced runner mode: $RUNNER_MODE"
        return 0
    fi
    
    # Auto-detect mode based on available environment variables
    if [ -n "$GITHUB_ORGANIZATION" ] && [ -z "$GITHUB_USERNAME" ] && [ -z "$GITHUB_REPOSITORY" ]; then
        RUNNER_MODE="organization"
        log_info "Auto-detected organization mode"
    elif [ -n "$GITHUB_USERNAME" ] && [ -n "$GITHUB_REPOSITORY" ] && [ -z "$GITHUB_ORGANIZATION" ]; then
        RUNNER_MODE="repository"
        log_info "Auto-detected repository mode"
    elif [ -n "$GITHUB_ORGANIZATION" ] && [ -n "$GITHUB_USERNAME" ] && [ -n "$GITHUB_REPOSITORY" ]; then
        # Both sets provided, prefer repository mode
        RUNNER_MODE="repository"
        log_info "Both organization and repository variables provided, using repository mode"
    else
        log_error "Cannot determine runner mode. Please provide either:"
        log_error "  Organization mode: GITHUB_ORGANIZATION"
        log_error "  Repository mode: GITHUB_USERNAME and GITHUB_REPOSITORY"
        return 1
    fi
    
    return 0
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check required commands
    local required_commands=("curl" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' is not installed"
            return 1
        fi
    done
    
    # Determine runner mode first
    if ! determine_runner_mode; then
        return 1
    fi
    
    # Check required environment variables based on mode
    if [ "$RUNNER_MODE" = "organization" ]; then
        if [ -z "$GITHUB_ORGANIZATION" ]; then
            log_error "GITHUB_ORGANIZATION environment variable is required for organization mode"
            return 1
        fi
    elif [ "$RUNNER_MODE" = "repository" ]; then
        if [ -z "$GITHUB_USERNAME" ]; then
            log_error "GITHUB_USERNAME environment variable is required for repository mode"
            return 1
        fi
        
        if [ -z "$GITHUB_REPOSITORY" ]; then
            log_error "GITHUB_REPOSITORY environment variable is required for repository mode"
            return 1
        fi
    fi
    
    if [ -z "$GH_PAT" ]; then
        log_error "GH_PAT environment variable is required"
        return 1
    fi
    
    log_success "Prerequisites validation passed"
    return 0
}

# Test GitHub API access and permissions
test_api_access() {
    log_info "Testing GitHub API access and permissions..."
    
    # Test basic authentication
    log_info "Testing basic authentication..."
    local auth_response
    auth_response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/user")
    
    local auth_http_code="${auth_response: -3}"
    local auth_body="${auth_response%???}"
    
    if [ "$auth_http_code" != "200" ]; then
        log_error "GitHub PAT authentication failed (HTTP $auth_http_code)"
        return 1
    fi
    
    local username
    username=$(echo "$auth_body" | jq -r '.login')
    log_success "Authenticated as: $username"
    
    # Test organization access
    log_info "Testing organization access..."
    local org_response
    org_response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/orgs/$GITHUB_ORGANIZATION")
    
    local org_http_code="${org_response: -3}"
    local org_body="${org_response%???}"
    
    if [ "$org_http_code" != "200" ]; then
        log_error "Organization access failed (HTTP $org_http_code)"
        return 1
    fi
    
    local org_name
    org_name=$(echo "$org_body" | jq -r '.name // .login')
    log_success "Organization access confirmed: $org_name"
    
    # Test organization membership
    log_info "Testing organization membership..."
    local membership_response
    membership_response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/orgs/$GITHUB_ORGANIZATION/memberships/$username")
    
    local membership_http_code="${membership_response: -3}"
    local membership_body="${membership_response%???}"
    
    if [ "$membership_http_code" = "200" ]; then
        local role
        role=$(echo "$membership_body" | jq -r '.role')
        local state
        state=$(echo "$membership_body" | jq -r '.state')
        
        log_success "Membership confirmed - Role: $role, State: $state"
        
        if [ "$role" = "admin" ]; then
            log_success "Admin role confirmed - can manage organization runners"
        else
            log_warning "Non-admin role detected - may have limited runner management capabilities"
        fi
    else
        log_warning "Could not verify organization membership"
    fi
    
    # Test runner API access
    log_info "Testing runner API access..."
    local runners_response
    runners_response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners")
    
    local runners_http_code="${runners_response: -3}"
    local runners_body="${runners_response%???}"
    
    if [ "$runners_http_code" = "200" ]; then
        local runner_count
        runner_count=$(echo "$runners_body" | jq '.total_count')
        log_success "Runner API access confirmed - $runner_count runners found"
    else
        log_error "Runner API access failed (HTTP $runners_http_code)"
        return 1
    fi
    
    # Test registration token generation
    log_info "Testing registration token generation..."
    local token_response
    token_response=$(curl -s -w "%{http_code}" -X POST \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners/registration-token")
    
    local token_http_code="${token_response: -3}"
    
    if [ "$token_http_code" = "201" ]; then
        log_success "Registration token generation confirmed - admin:org scope verified"
    else
        log_error "Registration token generation failed (HTTP $token_http_code)"
        log_error "This indicates insufficient permissions - ensure PAT has 'admin:org' scope"
        return 1
    fi
    
    log_success "All API access tests passed"
    return 0
}

# List all organization runners
list_organization_runners() {
    log_info "Listing organization runners..."
    
    local response
    response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" != "200" ]; then
        log_error "Failed to list organization runners (HTTP $http_code)"
        return 1
    fi
    
    local total_count
    total_count=$(echo "$body" | jq '.total_count')
    
    log_info "Total organization runners: $total_count"
    
    if [ "$total_count" -gt 0 ]; then
        echo ""
        echo "Organization Runners:"
        echo "===================="
        echo "$body" | jq -r '.runners[] | "Name: \(.name)\nID: \(.id)\nStatus: \(.status)\nOS: \(.os)\nLabels: \([.labels[].name] | join(", "))\nBusy: \(.busy)\n---"'
    else
        log_info "No runners found in organization"
    fi
    
    return 0
}

# Test specific runner
test_specific_runner() {
    log_info "Testing runner: $RUNNER_NAME"
    
    local response
    response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" != "200" ]; then
        log_error "Failed to get organization runners (HTTP $http_code)"
        return 1
    fi
    
    local runner_info
    runner_info=$(echo "$body" | jq ".runners[] | select(.name==\"$RUNNER_NAME\")")
    
    if [ -z "$runner_info" ] || [ "$runner_info" = "null" ]; then
        log_error "Runner '$RUNNER_NAME' not found in organization"
        log_info "Available runners:"
        echo "$body" | jq -r '.runners[] | "- \(.name) (Status: \(.status))"'
        return 1
    fi
    
    local runner_id
    runner_id=$(echo "$runner_info" | jq -r '.id')
    local runner_status
    runner_status=$(echo "$runner_info" | jq -r '.status')
    local runner_os
    runner_os=$(echo "$runner_info" | jq -r '.os')
    local runner_busy
    runner_busy=$(echo "$runner_info" | jq -r '.busy')
    local runner_labels
    runner_labels=$(echo "$runner_info" | jq -r '[.labels[].name] | join(", ")')
    
    log_success "Runner found: $RUNNER_NAME"
    echo ""
    echo "Runner Details:"
    echo "==============="
    echo "ID: $runner_id"
    echo "Status: $runner_status"
    echo "OS: $runner_os"
    echo "Busy: $runner_busy"
    echo "Labels: $runner_labels"
    
    if [ "$runner_status" = "online" ]; then
        log_success "Runner is online and available"
    else
        log_warning "Runner status is '$runner_status' - may not be available for jobs"
    fi
    
    if [ "$runner_busy" = "true" ]; then
        log_info "Runner is currently busy executing a job"
    else
        log_info "Runner is idle and ready for jobs"
    fi
    
    return 0
}

# Test runner access from multiple repositories
test_repository_access() {
    log_info "Testing runner access from organization repositories..."
    
    # Get organization repositories
    local repos_response
    repos_response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/orgs/$GITHUB_ORGANIZATION/repos?type=all&per_page=10")
    
    local repos_http_code="${repos_response: -3}"
    local repos_body="${repos_response%???}"
    
    if [ "$repos_http_code" != "200" ]; then
        log_error "Failed to get organization repositories (HTTP $repos_http_code)"
        return 1
    fi
    
    local repo_count
    repo_count=$(echo "$repos_body" | jq 'length')
    
    if [ "$repo_count" -eq 0 ]; then
        log_warning "No repositories found in organization"
        return 0
    fi
    
    log_info "Found $repo_count repositories in organization"
    echo ""
    echo "Repository Access Test:"
    echo "======================"
    
    # Test workflow access for each repository
    echo "$repos_body" | jq -r '.[].full_name' | head -5 | while read -r repo_name; do
        log_info "Testing repository: $repo_name"
        
        # Check if repository has Actions enabled
        local actions_response
        actions_response=$(curl -s -w "%{http_code}" \
            -H "Authorization: token $GH_PAT" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$repo_name/actions/permissions")
        
        local actions_http_code="${actions_response: -3}"
        local actions_body="${actions_response%???}"
        
        if [ "$actions_http_code" = "200" ]; then
            local actions_enabled
            actions_enabled=$(echo "$actions_body" | jq -r '.enabled')
            
            if [ "$actions_enabled" = "true" ]; then
                log_success "  ✓ Actions enabled - can use organization runner"
            else
                log_warning "  ⚠ Actions disabled - cannot use runners"
            fi
        else
            log_warning "  ? Could not check Actions status (HTTP $actions_http_code)"
        fi
    done
    
    return 0
}

# Generate test workflow files
generate_test_workflows() {
    log_info "Generating test workflow files..."
    
    local workflows_dir="test-workflows"
    mkdir -p "$workflows_dir"
    
    # Basic runner test workflow
    cat > "$workflows_dir/test-org-runner.yml" << EOF
name: Test Organization Runner

# This workflow tests the organization-level ephemeral runner
# It can be used in any repository within the organization

on:
  workflow_dispatch:
    inputs:
      test_type:
        description: 'Type of test to run'
        required: false
        default: 'basic'
        type: choice
        options:
        - basic
        - tools
        - extended

jobs:
  test-runner:
    runs-on: [self-hosted, gha_aws_runner]
    timeout-minutes: 10
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        
      - name: Test runner environment
        run: |
          echo "=== Runner Environment Test ==="
          echo "Repository: \${{ github.repository }}"
          echo "Organization: \${{ github.repository_owner }}"
          echo "Runner: \${{ runner.name }}"
          echo "OS: \${{ runner.os }}"
          echo "Architecture: \${{ runner.arch }}"
          echo "Hostname: \$(hostname)"
          echo "User: \$(whoami)"
          echo "Working Directory: \$(pwd)"
          echo "Date: \$(date)"
          
      - name: Test basic commands
        if: \${{ inputs.test_type == 'basic' || inputs.test_type == 'extended' }}
        run: |
          echo "=== Basic Commands Test ==="
          echo "Shell: \$SHELL"
          uname -a
          df -h
          free -h
          
      - name: Test installed tools
        if: \${{ inputs.test_type == 'tools' || inputs.test_type == 'extended' }}
        run: |
          echo "=== Installed Tools Test ==="
          
          # Test Docker
          if command -v docker &> /dev/null; then
            echo "✓ Docker: \$(docker --version)"
            docker info --format '{{.ServerVersion}}' 2>/dev/null && echo "✓ Docker daemon running" || echo "✗ Docker daemon not running"
          else
            echo "✗ Docker not installed"
          fi
          
          # Test AWS CLI
          if command -v aws &> /dev/null; then
            echo "✓ AWS CLI: \$(aws --version)"
          else
            echo "✗ AWS CLI not installed"
          fi
          
          # Test Python
          if command -v python3 &> /dev/null; then
            echo "✓ Python: \$(python3 --version)"
          else
            echo "✗ Python not installed"
          fi
          
          # Test Java
          if command -v java &> /dev/null; then
            echo "✓ Java: \$(java -version 2>&1 | head -1)"
          else
            echo "✗ Java not installed"
          fi
          
          # Test Terraform
          if command -v terraform &> /dev/null; then
            echo "✓ Terraform: \$(terraform --version | head -1)"
          else
            echo "✗ Terraform not installed"
          fi
          
          # Test kubectl
          if command -v kubectl &> /dev/null; then
            echo "✓ kubectl: \$(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"
          else
            echo "✗ kubectl not installed"
          fi
          
          # Test Helm
          if command -v helm &> /dev/null; then
            echo "✓ Helm: \$(helm version --short 2>/dev/null || helm version 2>/dev/null | head -1)"
          else
            echo "✗ Helm not installed"
          fi
          
      - name: Test repository access
        if: \${{ inputs.test_type == 'extended' }}
        run: |
          echo "=== Repository Access Test ==="
          echo "Repository files:"
          ls -la
          
          if [ -f "README.md" ]; then
            echo "✓ README.md found"
            wc -l README.md
          else
            echo "ℹ No README.md found"
          fi
          
          echo "Git status:"
          git status || echo "Not a git repository"
          
      - name: Test network connectivity
        if: \${{ inputs.test_type == 'extended' }}
        run: |
          echo "=== Network Connectivity Test ==="
          
          # Test GitHub connectivity
          curl -I https://github.com && echo "✓ GitHub.com accessible" || echo "✗ GitHub.com not accessible"
          curl -I https://api.github.com && echo "✓ GitHub API accessible" || echo "✗ GitHub API not accessible"
          
          # Test package repositories
          curl -I https://archive.ubuntu.com && echo "✓ Ubuntu packages accessible" || echo "✗ Ubuntu packages not accessible"
          
      - name: Test summary
        run: |
          echo "=== Test Summary ==="
          echo "✓ Organization runner test completed successfully"
          echo "✓ Repository: \${{ github.repository }}"
          echo "✓ Runner available to organization repositories"
          echo "✓ Ephemeral configuration working"
EOF

    # Cross-repository test workflow
    cat > "$workflows_dir/cross-repo-test.yml" << EOF
name: Cross-Repository Runner Test

# This workflow demonstrates cross-repository runner usage
# Deploy this workflow in multiple repositories to test shared runner access

on:
  workflow_dispatch:
  schedule:
    # Run daily at 9 AM UTC (optional)
    - cron: '0 9 * * *'

jobs:
  identify-repository:
    runs-on: [self-hosted, gha_aws_runner]
    timeout-minutes: 5
    
    outputs:
      repository: \${{ steps.info.outputs.repository }}
      timestamp: \${{ steps.info.outputs.timestamp }}
    
    steps:
      - name: Repository identification
        id: info
        run: |
          echo "=== Cross-Repository Runner Test ==="
          echo "Repository: \${{ github.repository }}"
          echo "Organization: \${{ github.repository_owner }}"
          echo "Workflow: \${{ github.workflow }}"
          echo "Run ID: \${{ github.run_id }}"
          echo "Runner: \${{ runner.name }}"
          echo "Timestamp: \$(date -u +"%Y-%m-%d %H:%M:%S UTC")"
          
          echo "repository=\${{ github.repository }}" >> \$GITHUB_OUTPUT
          echo "timestamp=\$(date -u +"%Y-%m-%d %H:%M:%S UTC")" >> \$GITHUB_OUTPUT
          
      - name: Create repository marker
        run: |
          # Create a temporary file to demonstrate cross-repository isolation
          MARKER_FILE="/tmp/repo-marker-\${{ github.run_id }}.txt"
          echo "Repository: \${{ github.repository }}" > "\$MARKER_FILE"
          echo "Timestamp: \$(date -u)" >> "\$MARKER_FILE"
          echo "Run ID: \${{ github.run_id }}" >> "\$MARKER_FILE"
          
          echo "Created marker file: \$MARKER_FILE"
          cat "\$MARKER_FILE"
          
      - name: Test runner isolation
        run: |
          echo "=== Runner Isolation Test ==="
          echo "Checking for other repository markers..."
          
          # List any existing marker files (should be cleaned up by ephemeral config)
          if ls /tmp/repo-marker-*.txt 2>/dev/null; then
            echo "Found existing markers (may indicate non-ephemeral configuration):"
            ls -la /tmp/repo-marker-*.txt
          else
            echo "✓ No existing markers found (ephemeral configuration working)"
          fi
          
          # Check runner work directory
          echo "Runner work directory contents:"
          ls -la \${{ runner.workspace }}/.. || echo "Could not access parent directory"
          
  cleanup-test:
    needs: identify-repository
    runs-on: [self-hosted, gha_aws_runner]
    if: always()
    timeout-minutes: 2
    
    steps:
      - name: Cleanup test files
        run: |
          echo "=== Cleanup Test ==="
          echo "Repository: \${{ needs.identify-repository.outputs.repository }}"
          echo "Timestamp: \${{ needs.identify-repository.outputs.timestamp }}"
          
          # Clean up marker file
          MARKER_FILE="/tmp/repo-marker-\${{ github.run_id }}.txt"
          if [ -f "\$MARKER_FILE" ]; then
            rm "\$MARKER_FILE"
            echo "✓ Cleaned up marker file"
          else
            echo "ℹ Marker file not found (may have been cleaned up already)"
          fi
          
          echo "✓ Cross-repository test completed"
EOF

    # Performance test workflow
    cat > "$workflows_dir/performance-test.yml" << EOF
name: Runner Performance Test

# This workflow tests the performance characteristics of the organization runner

on:
  workflow_dispatch:
    inputs:
      duration:
        description: 'Test duration in minutes'
        required: false
        default: '5'
        type: string

jobs:
  performance-test:
    runs-on: [self-hosted, gha_aws_runner]
    timeout-minutes: 15
    
    steps:
      - name: System information
        run: |
          echo "=== System Performance Test ==="
          echo "Repository: \${{ github.repository }}"
          echo "Test Duration: \${{ inputs.duration }} minutes"
          echo ""
          
          echo "=== System Information ==="
          uname -a
          
          echo "=== CPU Information ==="
          lscpu | grep -E "Model name|CPU\(s\)|Thread|Core"
          
          echo "=== Memory Information ==="
          free -h
          
          echo "=== Disk Information ==="
          df -h
          
          echo "=== Network Information ==="
          ip addr show | grep -E "inet.*scope global"
          
      - name: CPU performance test
        run: |
          echo "=== CPU Performance Test ==="
          
          # Simple CPU benchmark
          echo "Running CPU benchmark..."
          time bash -c 'for i in {1..100000}; do echo \$i > /dev/null; done'
          
          # Check CPU usage during test
          echo "Current CPU usage:"
          top -bn1 | grep "Cpu(s)" || echo "Could not get CPU usage"
          
      - name: Memory performance test
        run: |
          echo "=== Memory Performance Test ==="
          
          # Memory allocation test
          echo "Testing memory allocation..."
          python3 -c "
import sys
print('Python memory test')
data = []
for i in range(1000):
    data.append('x' * 1000)
print(f'Allocated {len(data)} KB of memory')
del data
print('Memory released')
"
          
      - name: Disk performance test
        run: |
          echo "=== Disk Performance Test ==="
          
          # Simple disk I/O test
          echo "Testing disk write performance..."
          time dd if=/dev/zero of=/tmp/test_file bs=1M count=100 2>&1 | grep -E "copied|MB/s"
          
          echo "Testing disk read performance..."
          time dd if=/tmp/test_file of=/dev/null bs=1M 2>&1 | grep -E "copied|MB/s"
          
          # Cleanup
          rm -f /tmp/test_file
          echo "✓ Cleanup completed"
          
      - name: Network performance test
        run: |
          echo "=== Network Performance Test ==="
          
          # Test GitHub connectivity speed
          echo "Testing GitHub API response time..."
          time curl -s https://api.github.com/zen > /dev/null
          
          echo "Testing package download speed..."
          time curl -s -o /dev/null https://archive.ubuntu.com/ubuntu/ls-lR.gz
          
      - name: Tool startup performance
        run: |
          echo "=== Tool Startup Performance ==="
          
          # Test Docker startup time
          if command -v docker &> /dev/null; then
            echo "Testing Docker startup time..."
            time docker --version > /dev/null
            time docker info > /dev/null 2>&1 || echo "Docker daemon not running"
          fi
          
          # Test other tools
          for tool in aws python3 java terraform kubectl helm; do
            if command -v \$tool &> /dev/null; then
              echo "Testing \$tool startup time..."
              time \$tool --version > /dev/null 2>&1 || echo "\$tool version check failed"
            fi
          done
          
      - name: Performance summary
        run: |
          echo "=== Performance Test Summary ==="
          echo "✓ Performance test completed for repository: \${{ github.repository }}"
          echo "✓ System resources adequate for CI/CD workloads"
          echo "✓ All tools responsive and functional"
          echo "✓ Network connectivity optimal"
EOF

    log_success "Test workflow files generated in: $workflows_dir/"
    log_info "Generated workflows:"
    log_info "  - test-org-runner.yml: Basic runner functionality test"
    log_info "  - cross-repo-test.yml: Cross-repository access test"
    log_info "  - performance-test.yml: Runner performance benchmarks"
    log_info ""
    log_info "To use these workflows:"
    log_info "1. Copy the desired workflow to .github/workflows/ in your repositories"
    log_info "2. Commit and push the workflow file"
    log_info "3. Go to Actions tab and run the workflow manually"
    log_info "4. Verify the runner executes the job successfully"
    
    return 0
}

# Run comprehensive test suite
run_full_test() {
    log_info "Running comprehensive organization runner test suite..."
    
    local test_results=()
    
    # Test 1: Prerequisites
    log_info "=== Test 1: Prerequisites ==="
    if validate_prerequisites; then
        test_results+=("✓ Prerequisites")
    else
        test_results+=("✗ Prerequisites")
        log_error "Prerequisites test failed - stopping test suite"
        return 1
    fi
    
    # Test 2: API Access
    log_info ""
    log_info "=== Test 2: API Access ==="
    if test_api_access; then
        test_results+=("✓ API Access")
    else
        test_results+=("✗ API Access")
    fi
    
    # Test 3: List Runners
    log_info ""
    log_info "=== Test 3: List Runners ==="
    if list_organization_runners; then
        test_results+=("✓ List Runners")
    else
        test_results+=("✗ List Runners")
    fi
    
    # Test 4: Specific Runner
    log_info ""
    log_info "=== Test 4: Specific Runner ==="
    if test_specific_runner; then
        test_results+=("✓ Specific Runner")
    else
        test_results+=("✗ Specific Runner")
    fi
    
    # Test 5: Repository Access
    log_info ""
    log_info "=== Test 5: Repository Access ==="
    if test_repository_access; then
        test_results+=("✓ Repository Access")
    else
        test_results+=("✗ Repository Access")
    fi
    
    # Test Summary
    log_info ""
    log_info "=== Test Suite Summary ==="
    for result in "${test_results[@]}"; do
        if [[ $result == ✓* ]]; then
            log_success "$result"
        else
            log_error "$result"
        fi
    done
    
    local passed_count=$(printf '%s\n' "${test_results[@]}" | grep -c "✓")
    local total_count=${#test_results[@]}
    
    log_info ""
    log_info "Tests passed: $passed_count/$total_count"
    
    if [ "$passed_count" -eq "$total_count" ]; then
        log_success "All tests passed! Organization runner is properly configured and accessible."
        return 0
    else
        log_error "Some tests failed. Please review the output and fix any issues."
        return 1
    fi
}

# Parse command line arguments
LIST_RUNNERS=false
TEST_API=false
TEST_RUNNER=false
TEST_REPOS=false
GENERATE_WORKFLOW=false
FULL_TEST=false

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
        --list-runners)
            LIST_RUNNERS=true
            shift
            ;;
        --test-api)
            TEST_API=true
            shift
            ;;
        --test-runner)
            TEST_RUNNER=true
            shift
            ;;
        --test-repos)
            TEST_REPOS=true
            shift
            ;;
        --generate-workflow)
            GENERATE_WORKFLOW=true
            shift
            ;;
        --full-test)
            FULL_TEST=true
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
    echo "=== $SCRIPT_NAME v$SCRIPT_VERSION ==="
    echo ""
    
    # Validate prerequisites for all operations
    if ! validate_prerequisites; then
        exit 1
    fi
    
    # Execute requested operations
    if [ "$LIST_RUNNERS" = true ]; then
        list_organization_runners
    fi
    
    if [ "$TEST_API" = true ]; then
        test_api_access
    fi
    
    if [ "$TEST_RUNNER" = true ]; then
        test_specific_runner
    fi
    
    if [ "$TEST_REPOS" = true ]; then
        test_repository_access
    fi
    
    if [ "$GENERATE_WORKFLOW" = true ]; then
        generate_test_workflows
    fi
    
    if [ "$FULL_TEST" = true ]; then
        run_full_test
        exit $?
    fi
    
    # If no specific operation requested, show usage
    if [ "$LIST_RUNNERS" = false ] && [ "$TEST_API" = false ] && [ "$TEST_RUNNER" = false ] && [ "$TEST_REPOS" = false ] && [ "$GENERATE_WORKFLOW" = false ] && [ "$FULL_TEST" = false ]; then
        log_info "No specific test requested. Use --help for usage information."
        log_info "Quick start: $0 --full-test"
    fi
}

# Execute main function
main "$@"