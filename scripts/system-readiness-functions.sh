#!/bin/bash

# System Readiness Validation Functions
# This library provides comprehensive system readiness validation for GitHub Actions
# runner installation, including cloud-init status checking, resource validation,
# and network connectivity testing.

# Script version and metadata
SYSTEM_READINESS_VERSION="1.0.0"
SYSTEM_READINESS_NAME="System Readiness Validation Functions"

# Color codes for output formatting (if not already defined)
if [ -z "$RED" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
fi

# Logging functions (if not already defined)
if ! command -v log_info &> /dev/null; then
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
    
    log_debug() {
        if [ "${DEBUG:-false}" = "true" ]; then
            echo -e "${CYAN}[DEBUG]${NC} $1"
        fi
    }
fi

# =============================================================================
# Cloud-init Status Validation Functions
# =============================================================================

# Check if cloud-init has completed
# Usage: check_cloud_init_status
# Returns: 0 if complete, 1 if running, 2 if error
check_cloud_init_status() {
    log_debug "Checking cloud-init status"
    
    # Check if cloud-init is installed
    if ! command -v cloud-init &> /dev/null; then
        log_debug "cloud-init not installed, assuming complete"
        return 0
    fi
    
    # Check cloud-init status using the status command
    local status_output
    if status_output=$(cloud-init status 2>&1); then
        log_debug "cloud-init status output: $status_output"
        
        if echo "$status_output" | grep -q "status: done"; then
            log_debug "cloud-init is complete"
            return 0
        elif echo "$status_output" | grep -q "status: running"; then
            log_debug "cloud-init is still running"
            return 1
        elif echo "$status_output" | grep -q "status: error"; then
            log_warning "cloud-init completed with errors"
            return 0  # Continue anyway, but log the warning
        else
            log_debug "cloud-init status unclear, checking alternative methods"
        fi
    else
        log_debug "cloud-init status command failed, checking alternative methods"
    fi
    
    # Alternative check: look for cloud-init processes
    if pgrep -f "cloud-init" > /dev/null; then
        log_debug "Found running cloud-init processes"
        return 1
    fi
    
    # Alternative check: look for cloud-init lock files
    if [ -f /var/lib/cloud/instance/boot-finished ]; then
        log_debug "Found cloud-init boot-finished marker"
        return 0
    fi
    
    # If we can't determine status, assume it's complete to avoid blocking
    log_debug "Cannot determine cloud-init status, assuming complete"
    return 0
}

# Wait for cloud-init to complete with timeout
# Usage: wait_for_cloud_init [timeout_seconds] [check_interval]
# Returns: 0 if complete, 1 if timeout, 2 if error
wait_for_cloud_init() {
    local timeout=${1:-600}  # 10 minutes default
    local check_interval=${2:-10}  # 10 seconds default
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    log_info "Checking cloud-init status (timeout: ${timeout}s)"
    
    # First check if cloud-init is already complete
    if check_cloud_init_status; then
        log_success "cloud-init is already complete"
        return 0
    fi
    
    log_info "cloud-init is running, waiting for completion..."
    local dots=""
    
    while [ $(date +%s) -lt $end_time ]; do
        if check_cloud_init_status; then
            echo ""  # New line after progress dots
            log_success "cloud-init completed successfully"
            return 0
        fi
        
        # Show progress
        dots="${dots}."
        if [ ${#dots} -gt 3 ]; then
            dots="."
        fi
        printf "\r${BLUE}[INFO]${NC} Waiting for cloud-init to complete${dots}   "
        
        sleep "$check_interval"
    done
    
    echo ""  # New line after progress dots
    log_error "Timeout waiting for cloud-init to complete after ${timeout} seconds"
    
    # Show current cloud-init status for debugging
    log_info "Current cloud-init status:"
    cloud-init status 2>&1 | sed 's/^/  /' || echo "  Unable to get cloud-init status"
    
    return 1
}

# =============================================================================
# System Resource Validation Functions
# =============================================================================

# Validate system has sufficient disk space
# Usage: check_disk_space [required_mb] [path]
# Returns: 0 if sufficient, 1 if insufficient
check_disk_space() {
    local required_mb=${1:-1024}  # 1GB default
    local check_path=${2:-"/"}
    
    log_debug "Checking disk space on $check_path (required: ${required_mb}MB)"
    
    # Get available disk space in MB
    local available_mb
    if available_mb=$(df -m "$check_path" | awk 'NR==2 {print $4}'); then
        log_debug "Available disk space: ${available_mb}MB"
        
        if [ "$available_mb" -ge "$required_mb" ]; then
            log_debug "Sufficient disk space available"
            return 0
        else
            log_error "Insufficient disk space: ${available_mb}MB available, ${required_mb}MB required"
            return 1
        fi
    else
        log_error "Failed to check disk space on $check_path"
        return 1
    fi
}

# Validate system has sufficient memory
# Usage: check_memory [required_mb]
# Returns: 0 if sufficient, 1 if insufficient
check_memory() {
    local required_mb=${1:-512}  # 512MB default
    
    log_debug "Checking available memory (required: ${required_mb}MB)"
    
    # Get available memory in MB
    local available_mb
    if available_mb=$(free -m | awk 'NR==2{print $7}'); then
        log_debug "Available memory: ${available_mb}MB"
        
        if [ "$available_mb" -ge "$required_mb" ]; then
            log_debug "Sufficient memory available"
            return 0
        else
            log_warning "Low memory: ${available_mb}MB available, ${required_mb}MB recommended"
            # Return success but with warning - low memory shouldn't block installation
            return 0
        fi
    else
        log_warning "Failed to check memory usage"
        return 0  # Don't block installation if we can't check
    fi
}

# Comprehensive system resource validation
# Usage: validate_system_resources
# Returns: 0 if all checks pass, 1 if critical issues found
validate_system_resources() {
    log_info "Validating system resources"
    
    local issues=0
    
    # Check disk space (require 2GB for runner installation)
    if ! check_disk_space 2048 "/"; then
        issues=$((issues + 1))
        log_error "Insufficient disk space for runner installation"
    fi
    
    # Check memory (recommend 1GB but don't fail)
    check_memory 1024
    
    # Check if /tmp has sufficient space (require 500MB)
    if ! check_disk_space 500 "/tmp"; then
        issues=$((issues + 1))
        log_error "Insufficient space in /tmp directory"
    fi
    
    # Check if we can write to common directories
    local test_dirs=("/tmp" "/var/tmp" "$HOME")
    for dir in "${test_dirs[@]}"; do
        if [ -d "$dir" ] && [ -w "$dir" ]; then
            log_debug "Write access confirmed for $dir"
        else
            log_warning "No write access to $dir"
        fi
    done
    
    if [ $issues -eq 0 ]; then
        log_success "System resource validation passed"
        return 0
    else
        log_error "System resource validation failed with $issues critical issues"
        return 1
    fi
}

# =============================================================================
# Network Connectivity Validation Functions
# =============================================================================

# Test basic network connectivity
# Usage: check_basic_connectivity
# Returns: 0 if connected, 1 if no connectivity
check_basic_connectivity() {
    log_debug "Testing basic network connectivity"
    
    # Test DNS resolution and basic connectivity
    local test_hosts=("8.8.8.8" "1.1.1.1")
    
    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 5 "$host" &> /dev/null; then
            log_debug "Basic connectivity confirmed via $host"
            return 0
        fi
    done
    
    log_error "No basic network connectivity detected"
    return 1
}

# Test GitHub API connectivity
# Usage: check_github_connectivity
# Returns: 0 if accessible, 1 if not accessible
check_github_connectivity() {
    log_debug "Testing GitHub API connectivity"
    
    # Test GitHub API endpoints
    local github_endpoints=(
        "api.github.com:443"
        "github.com:443"
        "objects.githubusercontent.com:443"
    )
    
    for endpoint in "${github_endpoints[@]}"; do
        local host=$(echo "$endpoint" | cut -d: -f1)
        local port=$(echo "$endpoint" | cut -d: -f2)
        
        if timeout 10 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
            log_debug "GitHub connectivity confirmed via $endpoint"
            
            # Test actual API call
            if curl -s --max-time 10 "https://api.github.com/zen" > /dev/null; then
                log_debug "GitHub API call successful"
                return 0
            fi
        fi
    done
    
    log_error "Cannot connect to GitHub API"
    return 1
}

# Test package repository connectivity
# Usage: check_package_repo_connectivity
# Returns: 0 if accessible, 1 if not accessible
check_package_repo_connectivity() {
    log_debug "Testing package repository connectivity"
    
    # Test Ubuntu package repositories
    local repo_hosts=(
        "archive.ubuntu.com"
        "security.ubuntu.com"
        "download.docker.com"
        "deb.nodesource.com"
    )
    
    local accessible_count=0
    for host in "${repo_hosts[@]}"; do
        if timeout 5 bash -c "</dev/tcp/$host/443" 2>/dev/null || \
           timeout 5 bash -c "</dev/tcp/$host/80" 2>/dev/null; then
            log_debug "Package repository accessible: $host"
            accessible_count=$((accessible_count + 1))
        else
            log_debug "Package repository not accessible: $host"
        fi
    done
    
    if [ $accessible_count -gt 0 ]; then
        log_debug "Package repositories accessible ($accessible_count/${#repo_hosts[@]})"
        return 0
    else
        log_error "No package repositories accessible"
        return 1
    fi
}

# Comprehensive network connectivity check
# Usage: check_network_connectivity
# Returns: 0 if all critical connectivity works, 1 if issues found
check_network_connectivity() {
    log_info "Validating network connectivity"
    
    local issues=0
    
    # Check basic connectivity (critical)
    if ! check_basic_connectivity; then
        issues=$((issues + 1))
        log_error "Basic network connectivity failed"
    fi
    
    # Check GitHub connectivity (critical for runner)
    if ! check_github_connectivity; then
        issues=$((issues + 1))
        log_error "GitHub connectivity failed"
    fi
    
    # Check package repositories (important but not critical)
    if ! check_package_repo_connectivity; then
        log_warning "Some package repositories not accessible"
        # Don't increment issues - this is a warning
    fi
    
    if [ $issues -eq 0 ]; then
        log_success "Network connectivity validation passed"
        return 0
    else
        log_error "Network connectivity validation failed with $issues critical issues"
        return 1
    fi
}

# =============================================================================
# Post-Installation Verification Functions
# =============================================================================

# Verify runner dependencies are installed
# Usage: verify_runner_dependencies
# Returns: 0 if all dependencies present, 1 if missing dependencies
verify_runner_dependencies() {
    log_info "Verifying runner dependencies"
    
    local missing_deps=()
    local required_commands=("curl" "tar" "ps" "id" "systemctl")
    
    # Check required commands
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Check for specific packages that runner needs
    local required_packages=("libc6" "libgcc1" "libgssapi-krb5-2" "libstdc++6" "zlib1g")
    for package in "${required_packages[@]}"; do
        if ! dpkg -l "$package" &> /dev/null; then
            missing_deps+=("$package")
        fi
    done
    
    if [ ${#missing_deps[@]} -eq 0 ]; then
        log_success "All runner dependencies are installed"
        return 0
    else
        log_error "Missing runner dependencies: ${missing_deps[*]}"
        return 1
    fi
}

# Validate runner service status
# Usage: validate_runner_service_status [runner_dir]
# Returns: 0 if service is running, 1 if not running or issues
validate_runner_service_status() {
    local runner_dir=${1:-"$HOME/actions-runner"}
    
    log_info "Validating runner service status"
    
    if [ ! -d "$runner_dir" ]; then
        log_error "Runner directory not found: $runner_dir"
        return 1
    fi
    
    if [ ! -f "$runner_dir/svc.sh" ]; then
        log_error "Runner service script not found: $runner_dir/svc.sh"
        return 1
    fi
    
    cd "$runner_dir"
    
    # Check service status
    local service_status
    if service_status=$(sudo ./svc.sh status 2>&1); then
        if echo "$service_status" | grep -q "active (running)"; then
            log_success "Runner service is active and running"
            return 0
        else
            log_error "Runner service is not running"
            log_error "Service status: $service_status"
            return 1
        fi
    else
        log_error "Failed to check runner service status"
        log_error "Error: $service_status"
        return 1
    fi
}

# Verify GitHub registration
# Usage: verify_github_registration <username> <repository> <pat> <runner_name>
# Returns: 0 if registered, 1 if not registered
verify_github_registration() {
    local username="$1"
    local repository="$2"
    local pat="$3"
    local runner_name="$4"
    
    if [ -z "$username" ] || [ -z "$repository" ] || [ -z "$pat" ] || [ -z "$runner_name" ]; then
        log_error "verify_github_registration: Missing required parameters"
        return 1
    fi
    
    log_info "Verifying GitHub runner registration"
    
    # Get list of runners from GitHub API
    local response
    response=$(curl -s -H "Authorization: token $pat" \
        "https://api.github.com/repos/$username/$repository/actions/runners")
    
    if echo "$response" | jq -e '.runners[]' > /dev/null 2>&1; then
        local runner_found=false
        while IFS= read -r runner; do
            local name=$(echo "$runner" | jq -r '.name')
            local status=$(echo "$runner" | jq -r '.status')
            
            if [ "$name" = "$runner_name" ]; then
                runner_found=true
                log_success "Runner found in GitHub: $name (status: $status)"
                
                if [ "$status" = "online" ]; then
                    return 0
                else
                    log_warning "Runner is registered but not online (status: $status)"
                    return 0  # Still consider this success
                fi
            fi
        done < <(echo "$response" | jq -c '.runners[]')
        
        if [ "$runner_found" = false ]; then
            log_error "Runner '$runner_name' not found in repository"
            return 1
        fi
    else
        log_error "Failed to get runner list from GitHub API"
        log_error "Response: $response"
        return 1
    fi
}

# =============================================================================
# Comprehensive System Readiness Validation
# =============================================================================

# Run all system readiness validations
# Usage: validate_system_readiness [cloud_init_timeout]
# Returns: 0 if system is ready, 1 if not ready
validate_system_readiness() {
    local cloud_init_timeout=${1:-600}  # 10 minutes default
    
    log_info "Starting comprehensive system readiness validation"
    
    local validation_failed=false
    
    # 1. Wait for cloud-init to complete
    log_info "=== Step 1: Cloud-init Status Check ==="
    if ! wait_for_cloud_init "$cloud_init_timeout"; then
        validation_failed=true
        log_error "Cloud-init validation failed"
    fi
    
    # 2. Validate system resources
    log_info "=== Step 2: System Resource Validation ==="
    if ! validate_system_resources; then
        validation_failed=true
        log_error "System resource validation failed"
    fi
    
    # 3. Check network connectivity
    log_info "=== Step 3: Network Connectivity Check ==="
    if ! check_network_connectivity; then
        validation_failed=true
        log_error "Network connectivity validation failed"
    fi
    
    # Summary
    log_info "=== System Readiness Summary ==="
    if [ "$validation_failed" = true ]; then
        log_error "System readiness validation FAILED"
        log_error "Please address the issues above before proceeding with runner installation"
        return 1
    else
        log_success "System readiness validation PASSED"
        log_success "System is ready for GitHub Actions runner installation"
        return 0
    fi
}

# =============================================================================
# Utility Functions
# =============================================================================

# Show system readiness library information
show_system_readiness_info() {
    cat << EOF
$SYSTEM_READINESS_NAME v$SYSTEM_READINESS_VERSION

AVAILABLE FUNCTIONS:

Cloud-init Validation:
  check_cloud_init_status
  wait_for_cloud_init [timeout] [check_interval]

System Resource Validation:
  check_disk_space [required_mb] [path]
  check_memory [required_mb]
  validate_system_resources

Network Connectivity:
  check_basic_connectivity
  check_github_connectivity
  check_package_repo_connectivity
  check_network_connectivity

Post-Installation Verification:
  verify_runner_dependencies
  validate_runner_service_status [runner_dir]
  verify_github_registration <username> <repository> <pat> <runner_name>

Comprehensive Validation:
  validate_system_readiness [cloud_init_timeout]

Usage:
  source scripts/system-readiness-functions.sh
  validate_system_readiness

EOF
}

# If script is run directly, show library info
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_system_readiness_info
fi