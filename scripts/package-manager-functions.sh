#!/bin/bash

# Package Manager Monitoring Functions
# This library provides comprehensive package manager monitoring and conflict
# resolution for GitHub Actions runner installation, including detection of
# running processes, lock management, and retry mechanisms.

# Script version and metadata
PACKAGE_MANAGER_VERSION="1.0.0"
PACKAGE_MANAGER_NAME="Package Manager Monitoring Functions"

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
# Package Manager Detection Functions
# =============================================================================

# Check if apt is currently running
# Usage: check_apt_running
# Returns: 0 if running, 1 if not running
check_apt_running() {
    log_debug "Checking for running apt processes"
    
    # Check for various apt-related processes
    local apt_processes=("apt" "apt-get" "aptitude" "dpkg" "unattended-upgrade")
    
    for process in "${apt_processes[@]}"; do
        if pgrep -f "$process" > /dev/null; then
            log_debug "Found running process: $process"
            return 0
        fi
    done
    
    log_debug "No apt processes running"
    return 1
}

# Check if dpkg is locked
# Usage: check_dpkg_locked
# Returns: 0 if locked, 1 if not locked
check_dpkg_locked() {
    log_debug "Checking dpkg lock status"
    
    # Check for dpkg lock files
    local lock_files=(
        "/var/lib/dpkg/lock"
        "/var/lib/dpkg/lock-frontend"
        "/var/cache/apt/archives/lock"
        "/var/lib/apt/lists/lock"
    )
    
    for lock_file in "${lock_files[@]}"; do
        if [ -f "$lock_file" ]; then
            # Try to get an exclusive lock on the file
            if ! flock -n 9 2>/dev/null 9<"$lock_file"; then
                log_debug "Lock file is locked: $lock_file"
                return 0
            fi
        fi
    done
    
    log_debug "No dpkg locks detected"
    return 1
}

# Get processes holding dpkg locks
# Usage: get_lock_holders
# Returns: Prints process information, returns 0 if found, 1 if none
get_lock_holders() {
    log_debug "Identifying processes holding dpkg locks"
    
    local lock_holders=()
    
    # Use lsof to find processes with open lock files
    local lock_files=(
        "/var/lib/dpkg/lock"
        "/var/lib/dpkg/lock-frontend"
        "/var/cache/apt/archives/lock"
        "/var/lib/apt/lists/lock"
    )
    
    for lock_file in "${lock_files[@]}"; do
        if [ -f "$lock_file" ]; then
            local holders
            if holders=$(lsof "$lock_file" 2>/dev/null | awk 'NR>1 {print $2":"$1}'); then
                if [ -n "$holders" ]; then
                    while IFS=':' read -r pid cmd; do
                        lock_holders+=("PID $pid ($cmd) holding $lock_file")
                    done <<< "$holders"
                fi
            fi
        fi
    done
    
    # Also check for common package management processes
    local package_processes=("apt" "apt-get" "dpkg" "unattended-upgrade" "packagekit")
    for process in "${package_processes[@]}"; do
        local pids
        if pids=$(pgrep -f "$process"); then
            while read -r pid; do
                local cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
                lock_holders+=("PID $pid ($cmd) - $process process")
            done <<< "$pids"
        fi
    done
    
    if [ ${#lock_holders[@]} -gt 0 ]; then
        printf '%s\n' "${lock_holders[@]}"
        return 0
    else
        log_debug "No lock holders found"
        return 1
    fi
}

# Check all package managers for activity
# Usage: check_package_managers
# Returns: 0 if busy, 1 if free
check_package_managers() {
    log_debug "Checking all package managers for activity"
    
    local busy=false
    
    # Check apt processes
    if check_apt_running; then
        log_debug "Package managers are busy (apt processes running)"
        busy=true
    fi
    
    # Check dpkg locks
    if check_dpkg_locked; then
        log_debug "Package managers are busy (dpkg locked)"
        busy=true
    fi
    
    # Check for unattended-upgrades specifically
    if systemctl is-active --quiet unattended-upgrades; then
        log_debug "Package managers are busy (unattended-upgrades active)"
        busy=true
    fi
    
    if [ "$busy" = true ]; then
        return 0
    else
        log_debug "Package managers are free"
        return 1
    fi
}

# =============================================================================
# Package Manager Waiting Functions
# =============================================================================

# Show progress while waiting for package managers
# Usage: show_package_wait_progress <current_wait> <max_wait>
show_package_wait_progress() {
    local current_wait="$1"
    local max_wait="$2"
    
    local percentage=$((current_wait * 100 / max_wait))
    local bar_length=20
    local filled_length=$((percentage * bar_length / 100))
    
    local bar=""
    for ((i=0; i<filled_length; i++)); do
        bar="${bar}█"
    done
    for ((i=filled_length; i<bar_length; i++)); do
        bar="${bar}░"
    done
    
    local time_remaining=$((max_wait - current_wait))
    printf "\r${BLUE}[INFO]${NC} Waiting for package managers [%s] %d%% (%ds remaining)" \
        "$bar" "$percentage" "$time_remaining"
}

# Wait for package managers to become available
# Usage: wait_for_package_managers [timeout] [check_interval]
# Returns: 0 if available, 1 if timeout
wait_for_package_managers() {
    local timeout=${1:-300}  # 5 minutes default
    local check_interval=${2:-10}  # 10 seconds default
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    log_info "Checking package manager availability (timeout: ${timeout}s)"
    
    # First check if package managers are already free
    if ! check_package_managers; then
        log_success "Package managers are already available"
        return 0
    fi
    
    log_info "Package managers are busy, waiting for availability..."
    
    # Show what's holding the locks
    local lock_holders
    if lock_holders=$(get_lock_holders); then
        log_info "Current lock holders:"
        echo "$lock_holders" | sed 's/^/  /'
    fi
    
    local current_wait=0
    while [ $(date +%s) -lt $end_time ]; do
        if ! check_package_managers; then
            echo ""  # New line after progress bar
            log_success "Package managers are now available"
            return 0
        fi
        
        # Show progress
        show_package_wait_progress "$current_wait" "$timeout"
        
        sleep "$check_interval"
        current_wait=$((current_wait + check_interval))
    done
    
    echo ""  # New line after progress bar
    log_error "Timeout waiting for package managers after ${timeout} seconds"
    
    # Show current status for debugging
    log_info "Current package manager status:"
    if lock_holders=$(get_lock_holders); then
        echo "$lock_holders" | sed 's/^/  /'
    else
        echo "  No specific lock holders identified"
    fi
    
    return 1
}

# =============================================================================
# Retry Mechanism Functions
# =============================================================================

# Calculate exponential backoff delay
# Usage: calculate_backoff_delay <retry_count> <base_delay> [max_delay]
# Returns: Prints delay in seconds
calculate_backoff_delay() {
    local retry_count="$1"
    local base_delay="$2"
    local max_delay="${3:-300}"  # 5 minutes default max
    
    # Calculate exponential backoff: base_delay * (2 ^ retry_count)
    local delay=$((base_delay * (1 << retry_count)))
    
    # Cap at maximum delay
    if [ "$delay" -gt "$max_delay" ]; then
        delay="$max_delay"
    fi
    
    echo "$delay"
}

# Execute command with retry and exponential backoff
# Usage: retry_with_backoff <max_retries> <base_delay> <command> [args...]
# Returns: 0 if success, 1 if all retries failed
retry_with_backoff() {
    local max_retries="$1"
    local base_delay="$2"
    shift 2
    local command=("$@")
    
    log_info "Executing command with retry: ${command[*]}"
    log_info "Max retries: $max_retries, Base delay: ${base_delay}s"
    
    local retry_count=0
    
    while [ $retry_count -le $max_retries ]; do
        if [ $retry_count -eq 0 ]; then
            log_info "Attempt $((retry_count + 1))/$((max_retries + 1)): ${command[*]}"
        else
            log_info "Retry $retry_count/$max_retries: ${command[*]}"
        fi
        
        # Execute the command
        if "${command[@]}"; then
            if [ $retry_count -eq 0 ]; then
                log_success "Command succeeded on first attempt"
            else
                log_success "Command succeeded after $retry_count retries"
            fi
            return 0
        fi
        
        local exit_code=$?
        retry_count=$((retry_count + 1))
        
        if [ $retry_count -le $max_retries ]; then
            local delay
            delay=$(calculate_backoff_delay $((retry_count - 1)) "$base_delay")
            
            log_warning "Command failed (exit code: $exit_code), retrying in ${delay}s..."
            
            # Wait for package managers to be free before retrying
            if check_package_managers; then
                log_info "Package managers are busy, waiting before retry..."
                wait_for_package_managers 120 5  # Wait up to 2 minutes
            fi
            
            # Show countdown
            for ((i=delay; i>0; i--)); do
                printf "\r${YELLOW}[WARNING]${NC} Retrying in %ds..." "$i"
                sleep 1
            done
            echo ""  # New line after countdown
        else
            log_error "Command failed after $max_retries retries (final exit code: $exit_code)"
            return 1
        fi
    done
    
    return 1
}

# Retry package installation with conflict handling
# Usage: retry_package_install <package_command> [max_retries] [base_delay]
# Returns: 0 if success, 1 if failed
retry_package_install() {
    local package_command="$1"
    local max_retries="${2:-3}"
    local base_delay="${3:-30}"
    
    log_info "Installing packages with conflict handling: $package_command"
    
    # Pre-installation checks
    log_info "Pre-installation package manager check..."
    if ! wait_for_package_managers 300 10; then
        log_error "Package managers are still busy, cannot proceed with installation"
        return 1
    fi
    
    # Wrapper function to handle package installation
    install_packages() {
        log_debug "Executing package installation: $package_command"
        
        # Set environment variables for non-interactive installation
        export DEBIAN_FRONTEND=noninteractive
        export NEEDRESTART_MODE=a
        
        # Execute the package command
        eval "$package_command"
    }
    
    # Retry the installation with backoff
    if retry_with_backoff "$max_retries" "$base_delay" install_packages; then
        log_success "Package installation completed successfully"
        return 0
    else
        log_error "Package installation failed after all retries"
        return 1
    fi
}

# =============================================================================
# Package Installation Utilities
# =============================================================================

# Update package lists with retry
# Usage: update_package_lists [max_retries]
# Returns: 0 if success, 1 if failed
update_package_lists() {
    local max_retries="${1:-3}"
    
    log_info "Updating package lists"
    
    # Wait for package managers first
    if ! wait_for_package_managers 300 10; then
        log_error "Cannot update package lists - package managers are busy"
        return 1
    fi
    
    # Update with retry
    if retry_with_backoff "$max_retries" 30 apt-get update -y; then
        log_success "Package lists updated successfully"
        return 0
    else
        log_error "Failed to update package lists"
        return 1
    fi
}

# Install specific packages with retry
# Usage: install_packages_with_retry <package1> [package2] ... [max_retries]
# Returns: 0 if success, 1 if failed
install_packages_with_retry() {
    local packages=()
    local max_retries=3
    
    # Parse arguments - last argument might be max_retries if it's a number
    while [ $# -gt 0 ]; do
        if [ $# -eq 1 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
            max_retries="$1"
        else
            packages+=("$1")
        fi
        shift
    done
    
    if [ ${#packages[@]} -eq 0 ]; then
        log_error "No packages specified for installation"
        return 1
    fi
    
    log_info "Installing packages: ${packages[*]}"
    
    # Create installation command
    local install_cmd="apt-get install -y ${packages[*]}"
    
    # Install with retry
    if retry_package_install "$install_cmd" "$max_retries"; then
        log_success "Packages installed successfully: ${packages[*]}"
        return 0
    else
        log_error "Failed to install packages: ${packages[*]}"
        return 1
    fi
}

# Install runner dependencies with comprehensive retry
# Usage: install_runner_dependencies [runner_dir]
# Returns: 0 if success, 1 if failed
install_runner_dependencies() {
    local runner_dir="${1:-$HOME/actions-runner}"
    
    log_info "Installing GitHub Actions runner dependencies"
    
    if [ ! -d "$runner_dir" ]; then
        log_error "Runner directory not found: $runner_dir"
        return 1
    fi
    
    if [ ! -f "$runner_dir/bin/installdependencies.sh" ]; then
        log_error "Runner dependency installer not found: $runner_dir/bin/installdependencies.sh"
        return 1
    fi
    
    cd "$runner_dir"
    
    # Install dependencies with retry
    local install_cmd="sudo ./bin/installdependencies.sh"
    
    if retry_package_install "$install_cmd" 3 30; then
        log_success "Runner dependencies installed successfully"
        return 0
    else
        log_error "Failed to install runner dependencies"
        return 1
    fi
}

# =============================================================================
# System Update Management
# =============================================================================

# Check if system updates are in progress
# Usage: check_system_updates
# Returns: 0 if updates running, 1 if not running
check_system_updates() {
    log_debug "Checking for system updates in progress"
    
    # Check for unattended-upgrades
    if systemctl is-active --quiet unattended-upgrades; then
        log_debug "Unattended upgrades are running"
        return 0
    fi
    
    # Check for update-manager
    if pgrep -f "update-manager" > /dev/null; then
        log_debug "Update manager is running"
        return 0
    fi
    
    # Check for apt daily services
    local apt_services=("apt-daily.service" "apt-daily-upgrade.service")
    for service in "${apt_services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_debug "APT daily service is running: $service"
            return 0
        fi
    done
    
    log_debug "No system updates detected"
    return 1
}

# Wait for system updates to complete
# Usage: wait_for_system_updates [timeout]
# Returns: 0 if complete, 1 if timeout
wait_for_system_updates() {
    local timeout="${1:-600}"  # 10 minutes default
    local check_interval=15
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    log_info "Checking for system updates (timeout: ${timeout}s)"
    
    if ! check_system_updates; then
        log_success "No system updates in progress"
        return 0
    fi
    
    log_info "System updates in progress, waiting for completion..."
    
    local current_wait=0
    while [ $(date +%s) -lt $end_time ]; do
        if ! check_system_updates; then
            echo ""  # New line after progress
            log_success "System updates completed"
            return 0
        fi
        
        # Show progress
        show_package_wait_progress "$current_wait" "$timeout"
        
        sleep "$check_interval"
        current_wait=$((current_wait + check_interval))
    done
    
    echo ""  # New line after progress
    log_warning "Timeout waiting for system updates (continuing anyway)"
    return 1
}

# =============================================================================
# Comprehensive Package Management
# =============================================================================

# Comprehensive package manager preparation
# Usage: prepare_package_managers [timeout]
# Returns: 0 if ready, 1 if issues
prepare_package_managers() {
    local timeout="${1:-600}"  # 10 minutes default
    
    log_info "Preparing package managers for installation"
    
    local issues=0
    
    # 1. Wait for system updates to complete
    log_info "=== Step 1: System Updates Check ==="
    if ! wait_for_system_updates "$timeout"; then
        log_warning "System updates check completed with timeout"
        # Don't fail here, just warn
    fi
    
    # 2. Wait for package managers to be free
    log_info "=== Step 2: Package Manager Availability ==="
    if ! wait_for_package_managers 300 10; then
        issues=$((issues + 1))
        log_error "Package managers are still busy"
    fi
    
    # 3. Update package lists
    log_info "=== Step 3: Package List Update ==="
    if ! update_package_lists 3; then
        issues=$((issues + 1))
        log_error "Failed to update package lists"
    fi
    
    # Summary
    log_info "=== Package Manager Preparation Summary ==="
    if [ $issues -eq 0 ]; then
        log_success "Package managers are ready for installation"
        return 0
    else
        log_error "Package manager preparation failed with $issues issues"
        return 1
    fi
}

# =============================================================================
# Utility Functions
# =============================================================================

# Show package manager library information
show_package_manager_info() {
    cat << EOF
$PACKAGE_MANAGER_NAME v$PACKAGE_MANAGER_VERSION

AVAILABLE FUNCTIONS:

Package Manager Detection:
  check_apt_running
  check_dpkg_locked
  get_lock_holders
  check_package_managers

Waiting Functions:
  show_package_wait_progress <current> <max>
  wait_for_package_managers [timeout] [interval]

Retry Mechanisms:
  calculate_backoff_delay <retry> <base> [max]
  retry_with_backoff <retries> <delay> <command> [args...]
  retry_package_install <command> [retries] [delay]

Package Installation:
  update_package_lists [retries]
  install_packages_with_retry <packages...> [retries]
  install_runner_dependencies [runner_dir]

System Update Management:
  check_system_updates
  wait_for_system_updates [timeout]

Comprehensive Management:
  prepare_package_managers [timeout]

Usage:
  source scripts/package-manager-functions.sh
  prepare_package_managers

EOF
}

# If script is run directly, show library info
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_package_manager_info
fi