#!/bin/bash

# Installation Error Handler
# This library provides centralized error handling, diagnostic information
# collection, and user feedback for GitHub Actions runner installation.

# Script version and metadata
ERROR_HANDLER_VERSION="1.0.0"
ERROR_HANDLER_NAME="Installation Error Handler"

# Color codes for output formatting (if not already defined)
if [ -z "$RED" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
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
# Error Code Definitions
# =============================================================================

# Error codes for different failure types
declare -A ERROR_CODES=(
    ["SYSTEM_NOT_READY"]="100"
    ["CLOUD_INIT_TIMEOUT"]="101"
    ["INSUFFICIENT_RESOURCES"]="102"
    ["NETWORK_CONNECTIVITY"]="103"
    ["PACKAGE_MANAGER_BUSY"]="200"
    ["PACKAGE_INSTALL_FAILED"]="201"
    ["DEPENDENCY_MISSING"]="202"
    ["DPKG_LOCK_TIMEOUT"]="203"
    ["RUNNER_DOWNLOAD_FAILED"]="300"
    ["RUNNER_CONFIG_FAILED"]="301"
    ["RUNNER_SERVICE_FAILED"]="302"
    ["GITHUB_AUTH_FAILED"]="303"
    ["GITHUB_REGISTRATION_FAILED"]="304"
    ["UNKNOWN_ERROR"]="999"
)

# =============================================================================
# Diagnostic Information Collection
# =============================================================================

# Collect system diagnostic information
# Usage: collect_system_diagnostics
# Returns: Prints diagnostic information
collect_system_diagnostics() {
    log_info "Collecting system diagnostic information..."
    
    echo "=== SYSTEM DIAGNOSTICS ==="
    echo "Timestamp: $(date)"
    echo "Hostname: $(hostname)"
    echo "User: $(whoami)"
    echo "Working Directory: $(pwd)"
    echo ""
    
    echo "--- System Information ---"
    echo "OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo 'Unknown')"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "Uptime: $(uptime)"
    echo ""
    
    echo "--- Resource Usage ---"
    echo "Memory:"
    free -h | sed 's/^/  /'
    echo ""
    echo "Disk Space:"
    df -h / /tmp 2>/dev/null | sed 's/^/  /'
    echo ""
    
    echo "--- Network Status ---"
    echo "Network Interfaces:"
    ip addr show | grep -E '^[0-9]+:|inet ' | sed 's/^/  /'
    echo ""
    echo "DNS Configuration:"
    cat /etc/resolv.conf 2>/dev/null | sed 's/^/  /' || echo "  Unable to read DNS config"
    echo ""
    
    echo "--- Process Information ---"
    echo "Load Average: $(cat /proc/loadavg)"
    echo "Running Processes: $(ps aux | wc -l)"
    echo ""
}

# Collect package manager diagnostics
# Usage: collect_package_diagnostics
# Returns: Prints package manager diagnostic information
collect_package_diagnostics() {
    log_info "Collecting package manager diagnostic information..."
    
    echo "=== PACKAGE MANAGER DIAGNOSTICS ==="
    
    echo "--- APT Status ---"
    echo "APT Version: $(apt --version 2>/dev/null | head -1 || echo 'Not available')"
    echo ""
    
    echo "--- Running Package Processes ---"
    local package_processes=("apt" "apt-get" "dpkg" "unattended-upgrade" "packagekit")
    for process in "${package_processes[@]}"; do
        local pids
        if pids=$(pgrep -f "$process" 2>/dev/null); then
            echo "$process processes:"
            while read -r pid; do
                local cmd=$(ps -p "$pid" -o pid,ppid,cmd --no-headers 2>/dev/null || echo "$pid - unknown")
                echo "  $cmd"
            done <<< "$pids"
        else
            echo "$process: Not running"
        fi
    done
    echo ""
    
    echo "--- Lock Files Status ---"
    local lock_files=(
        "/var/lib/dpkg/lock"
        "/var/lib/dpkg/lock-frontend"
        "/var/cache/apt/archives/lock"
        "/var/lib/apt/lists/lock"
    )
    
    for lock_file in "${lock_files[@]}"; do
        if [ -f "$lock_file" ]; then
            echo "Lock file: $lock_file"
            echo "  Permissions: $(ls -l "$lock_file" | awk '{print $1, $3, $4}')"
            
            # Try to identify lock holder
            local holder
            if holder=$(lsof "$lock_file" 2>/dev/null | awk 'NR>1 {print $2":"$1}'); then
                if [ -n "$holder" ]; then
                    echo "  Held by: $holder"
                else
                    echo "  Status: Available"
                fi
            else
                echo "  Status: Cannot determine"
            fi
        else
            echo "Lock file: $lock_file (not found)"
        fi
    done
    echo ""
    
    echo "--- System Services ---"
    local services=("unattended-upgrades" "apt-daily" "apt-daily-upgrade")
    for service in "${services[@]}"; do
        local status
        if status=$(systemctl is-active "$service" 2>/dev/null); then
            echo "$service: $status"
        else
            echo "$service: Not available"
        fi
    done
    echo ""
    
    echo "--- Recent APT History ---"
    if [ -f /var/log/apt/history.log ]; then
        echo "Last 10 APT operations:"
        tail -20 /var/log/apt/history.log | grep -E "^(Start-Date|Commandline|End-Date)" | tail -10 | sed 's/^/  /'
    else
        echo "APT history not available"
    fi
    echo ""
}

# Collect network diagnostics
# Usage: collect_network_diagnostics
# Returns: Prints network diagnostic information
collect_network_diagnostics() {
    log_info "Collecting network diagnostic information..."
    
    echo "=== NETWORK DIAGNOSTICS ==="
    
    echo "--- Connectivity Tests ---"
    local test_hosts=("8.8.8.8" "1.1.1.1" "github.com" "api.github.com")
    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 3 "$host" &>/dev/null; then
            echo "Ping to $host: SUCCESS"
        else
            echo "Ping to $host: FAILED"
        fi
    done
    echo ""
    
    echo "--- DNS Resolution ---"
    local dns_hosts=("github.com" "api.github.com" "archive.ubuntu.com")
    for host in "${dns_hosts[@]}"; do
        if nslookup "$host" &>/dev/null; then
            echo "DNS resolution for $host: SUCCESS"
        else
            echo "DNS resolution for $host: FAILED"
        fi
    done
    echo ""
    
    echo "--- Port Connectivity ---"
    local endpoints=("github.com:443" "api.github.com:443" "archive.ubuntu.com:80")
    for endpoint in "${endpoints[@]}"; do
        local host=$(echo "$endpoint" | cut -d: -f1)
        local port=$(echo "$endpoint" | cut -d: -f2)
        
        if timeout 5 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
            echo "Connection to $endpoint: SUCCESS"
        else
            echo "Connection to $endpoint: FAILED"
        fi
    done
    echo ""
    
    echo "--- Routing Information ---"
    echo "Default Route:"
    ip route show default | sed 's/^/  /' || echo "  Unable to get routing info"
    echo ""
}

# Collect GitHub-specific diagnostics
# Usage: collect_github_diagnostics [username] [repository] [pat]
# Returns: Prints GitHub diagnostic information
collect_github_diagnostics() {
    local username="$1"
    local repository="$2"
    local pat="$3"
    
    log_info "Collecting GitHub diagnostic information..."
    
    echo "=== GITHUB DIAGNOSTICS ==="
    
    echo "--- GitHub API Status ---"
    if curl -s --max-time 10 "https://api.github.com/zen" > /dev/null; then
        echo "GitHub API: Accessible"
    else
        echo "GitHub API: Not accessible"
    fi
    echo ""
    
    if [ -n "$pat" ]; then
        echo "--- Authentication Test ---"
        local auth_response
        if auth_response=$(curl -s -w "%{http_code}" -H "Authorization: token $pat" "https://api.github.com/user" 2>/dev/null); then
            local http_code="${auth_response: -3}"
            case $http_code in
                200)
                    echo "GitHub Authentication: SUCCESS"
                    ;;
                401)
                    echo "GitHub Authentication: FAILED (Invalid token)"
                    ;;
                403)
                    echo "GitHub Authentication: FAILED (Insufficient permissions)"
                    ;;
                *)
                    echo "GitHub Authentication: FAILED (HTTP $http_code)"
                    ;;
            esac
        else
            echo "GitHub Authentication: FAILED (Network error)"
        fi
        echo ""
        
        if [ -n "$username" ] && [ -n "$repository" ]; then
            echo "--- Repository Access Test ---"
            local repo_response
            if repo_response=$(curl -s -w "%{http_code}" -H "Authorization: token $pat" \
                "https://api.github.com/repos/$username/$repository" 2>/dev/null); then
                local http_code="${repo_response: -3}"
                case $http_code in
                    200)
                        echo "Repository Access: SUCCESS"
                        ;;
                    404)
                        echo "Repository Access: FAILED (Repository not found)"
                        ;;
                    403)
                        echo "Repository Access: FAILED (Access denied)"
                        ;;
                    *)
                        echo "Repository Access: FAILED (HTTP $http_code)"
                        ;;
                esac
            else
                echo "Repository Access: FAILED (Network error)"
            fi
            echo ""
        fi
    fi
    
    echo "--- GitHub Status Page ---"
    if curl -s --max-time 10 "https://www.githubstatus.com/api/v2/status.json" > /dev/null; then
        echo "GitHub Status Page: Accessible"
    else
        echo "GitHub Status Page: Not accessible"
    fi
    echo ""
}

# Collect comprehensive diagnostic information
# Usage: collect_diagnostic_info [username] [repository] [pat]
# Returns: Prints all diagnostic information
collect_diagnostic_info() {
    local username="$1"
    local repository="$2"
    local pat="$3"
    
    echo "==============================================================================="
    echo "COMPREHENSIVE DIAGNOSTIC REPORT"
    echo "Generated: $(date)"
    echo "==============================================================================="
    echo ""
    
    collect_system_diagnostics
    echo ""
    collect_package_diagnostics
    echo ""
    collect_network_diagnostics
    echo ""
    collect_github_diagnostics "$username" "$repository" "$pat"
    
    echo "==============================================================================="
    echo "END OF DIAGNOSTIC REPORT"
    echo "==============================================================================="
}

# =============================================================================
# Error Message and Troubleshooting Functions
# =============================================================================

# Show detailed error with context and troubleshooting
# Usage: show_detailed_error <error_code> <error_message> [context]
show_detailed_error() {
    local error_code="$1"
    local error_message="$2"
    local context="${3:-}"
    
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                 ERROR DETAILS                                   ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${RED}Error Code:${NC} $error_code"
    echo -e "${RED}Error Message:${NC} $error_message"
    if [ -n "$context" ]; then
        echo -e "${RED}Context:${NC} $context"
    fi
    echo -e "${RED}Timestamp:${NC} $(date)"
    echo ""
    
    # Show specific troubleshooting based on error code
    case $error_code in
        "${ERROR_CODES[CLOUD_INIT_TIMEOUT]}")
            show_cloud_init_troubleshooting
            ;;
        "${ERROR_CODES[PACKAGE_MANAGER_BUSY]}")
            show_package_manager_troubleshooting
            ;;
        "${ERROR_CODES[NETWORK_CONNECTIVITY]}")
            show_network_troubleshooting
            ;;
        "${ERROR_CODES[GITHUB_AUTH_FAILED]}")
            show_github_auth_troubleshooting
            ;;
        "${ERROR_CODES[INSUFFICIENT_RESOURCES]}")
            show_resource_troubleshooting
            ;;
        *)
            show_general_troubleshooting
            ;;
    esac
}

# Cloud-init specific troubleshooting
show_cloud_init_troubleshooting() {
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                          CLOUD-INIT TROUBLESHOOTING                         ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Cloud-init is taking longer than expected to complete. This can happen when:"
    echo "• The instance is still initializing"
    echo "• System updates are running in the background"
    echo "• Network connectivity is slow"
    echo ""
    echo -e "${CYAN}Troubleshooting Steps:${NC}"
    echo "1. Check cloud-init status:"
    echo "   cloud-init status --long"
    echo ""
    echo "2. Monitor cloud-init logs:"
    echo "   tail -f /var/log/cloud-init-output.log"
    echo ""
    echo "3. Check for running processes:"
    echo "   ps aux | grep cloud-init"
    echo ""
    echo "4. If cloud-init is stuck, you can try:"
    echo "   sudo cloud-init clean --reboot"
    echo ""
    echo -e "${YELLOW}Note:${NC} You can also skip cloud-init waiting with --force flag (not recommended)"
    echo ""
}

# Package manager troubleshooting
show_package_manager_troubleshooting() {
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                       PACKAGE MANAGER TROUBLESHOOTING                       ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Package managers are busy or locked. This commonly occurs when:"
    echo "• Automatic updates are running"
    echo "• Another package installation is in progress"
    echo "• Previous installation was interrupted"
    echo ""
    echo -e "${CYAN}Troubleshooting Steps:${NC}"
    echo "1. Check what's holding the locks:"
    echo "   sudo lsof /var/lib/dpkg/lock*"
    echo ""
    echo "2. Check running package processes:"
    echo "   ps aux | grep -E '(apt|dpkg|unattended-upgrade)'"
    echo ""
    echo "3. Wait for automatic updates to complete:"
    echo "   sudo systemctl status unattended-upgrades"
    echo ""
    echo "4. If processes are stuck, you can try:"
    echo "   sudo killall apt apt-get dpkg"
    echo "   sudo dpkg --configure -a"
    echo "   sudo apt-get update"
    echo ""
    echo -e "${YELLOW}Warning:${NC} Only kill processes if you're sure they're stuck"
    echo ""
}

# Network troubleshooting
show_network_troubleshooting() {
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                          NETWORK TROUBLESHOOTING                            ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Network connectivity issues detected. This can be caused by:"
    echo "• Internet connection problems"
    echo "• DNS resolution issues"
    echo "• Firewall or security group restrictions"
    echo "• GitHub service outages"
    echo ""
    echo -e "${CYAN}Troubleshooting Steps:${NC}"
    echo "1. Test basic connectivity:"
    echo "   ping -c 3 8.8.8.8"
    echo ""
    echo "2. Test DNS resolution:"
    echo "   nslookup github.com"
    echo ""
    echo "3. Test GitHub connectivity:"
    echo "   curl -I https://api.github.com"
    echo ""
    echo "4. Check security group rules (AWS):"
    echo "   • Ensure outbound HTTPS (443) is allowed"
    echo "   • Ensure outbound HTTP (80) is allowed"
    echo ""
    echo "5. Check GitHub status:"
    echo "   Visit: https://www.githubstatus.com/"
    echo ""
}

# GitHub authentication troubleshooting
show_github_auth_troubleshooting() {
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                      GITHUB AUTHENTICATION TROUBLESHOOTING                  ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "GitHub authentication failed. This can be caused by:"
    echo "• Invalid or expired Personal Access Token (PAT)"
    echo "• Insufficient token permissions"
    echo "• Repository access restrictions"
    echo "• Network connectivity issues"
    echo ""
    echo -e "${CYAN}Troubleshooting Steps:${NC}"
    echo "1. Verify your PAT is valid:"
    echo "   curl -H \"Authorization: token YOUR_PAT\" https://api.github.com/user"
    echo ""
    echo "2. Check PAT permissions:"
    echo "   • Ensure 'repo' scope is enabled"
    echo "   • For organization repos, ensure appropriate org permissions"
    echo ""
    echo "3. Verify repository access:"
    echo "   • Check you have admin permissions on the repository"
    echo "   • Ensure Actions are enabled in repository settings"
    echo ""
    echo "4. Generate a new PAT if needed:"
    echo "   Visit: https://github.com/settings/tokens"
    echo ""
    echo -e "${YELLOW}Required PAT Scopes:${NC}"
    echo "• repo (Full control of private repositories)"
    echo "• workflow (Update GitHub Action workflows)"
    echo ""
}

# Resource troubleshooting
show_resource_troubleshooting() {
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                         RESOURCE TROUBLESHOOTING                            ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Insufficient system resources detected. This can be caused by:"
    echo "• Low disk space"
    echo "• Insufficient memory"
    echo "• High system load"
    echo ""
    echo -e "${CYAN}Troubleshooting Steps:${NC}"
    echo "1. Check disk space:"
    echo "   df -h"
    echo ""
    echo "2. Free up disk space if needed:"
    echo "   sudo apt-get clean"
    echo "   sudo apt-get autoremove"
    echo ""
    echo "3. Check memory usage:"
    echo "   free -h"
    echo ""
    echo "4. Check system load:"
    echo "   top"
    echo ""
    echo "5. Consider using a larger instance type if resources are consistently low"
    echo ""
}

# General troubleshooting
show_general_troubleshooting() {
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                           GENERAL TROUBLESHOOTING                           ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}General Troubleshooting Steps:${NC}"
    echo "1. Check system logs:"
    echo "   sudo journalctl -xe"
    echo ""
    echo "2. Verify system status:"
    echo "   systemctl status"
    echo ""
    echo "3. Check available resources:"
    echo "   df -h && free -h"
    echo ""
    echo "4. Test network connectivity:"
    echo "   ping -c 3 github.com"
    echo ""
    echo "5. Try running the installation with debug mode:"
    echo "   DEBUG=true ./configure-repository-runner.sh [options]"
    echo ""
    echo "6. If issues persist, collect diagnostic information:"
    echo "   ./installation-error-handler.sh --collect-diagnostics"
    echo ""
}

# =============================================================================
# Progress Reporting Functions
# =============================================================================

# Show installation progress
# Usage: show_installation_progress <step_name> <current_step> <total_steps> [details]
show_installation_progress() {
    local step_name="$1"
    local current_step="$2"
    local total_steps="$3"
    local details="${4:-}"
    
    local percentage=$((current_step * 100 / total_steps))
    local bar_length=30
    local filled_length=$((percentage * bar_length / 100))
    
    local bar=""
    for ((i=0; i<filled_length; i++)); do
        bar="${bar}█"
    done
    for ((i=filled_length; i<bar_length; i++)); do
        bar="${bar}░"
    done
    
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                            INSTALLATION PROGRESS                            ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Step ${current_step}/${total_steps}:${NC} $step_name"
    echo -e "${BLUE}Progress:${NC} [${bar}] ${percentage}%"
    if [ -n "$details" ]; then
        echo -e "${BLUE}Details:${NC} $details"
    fi
    echo ""
}

# Show completion summary
# Usage: show_completion_summary <success> <total_time> [errors]
show_completion_summary() {
    local success="$1"
    local total_time="$2"
    local errors="${3:-0}"
    
    echo ""
    if [ "$success" = "true" ]; then
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║                           INSTALLATION SUCCESSFUL                           ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}✓${NC} GitHub Actions runner installation completed successfully"
    else
        echo -e "${RED}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                            INSTALLATION FAILED                              ║${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${RED}✗${NC} GitHub Actions runner installation failed"
    fi
    
    echo -e "${BLUE}Total Time:${NC} ${total_time}s"
    if [ "$errors" -gt 0 ]; then
        echo -e "${YELLOW}Warnings/Errors:${NC} $errors"
    fi
    echo ""
}

# =============================================================================
# Main Error Handler Function
# =============================================================================

# Handle installation error with comprehensive reporting
# Usage: handle_installation_error <error_type> <error_message> [context] [username] [repository] [pat]
handle_installation_error() {
    local error_type="$1"
    local error_message="$2"
    local context="${3:-}"
    local username="${4:-}"
    local repository="${5:-}"
    local pat="${6:-}"
    
    local error_code="${ERROR_CODES[$error_type]:-${ERROR_CODES[UNKNOWN_ERROR]}}"
    
    # Show detailed error
    show_detailed_error "$error_code" "$error_message" "$context"
    
    # Collect and show diagnostic information
    echo -e "${CYAN}Collecting diagnostic information...${NC}"
    echo ""
    collect_diagnostic_info "$username" "$repository" "$pat"
    
    # Suggest next steps
    echo ""
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║                                NEXT STEPS                                   ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "1. Review the error details and troubleshooting steps above"
    echo "2. Address any identified issues"
    echo "3. Retry the installation with the same command"
    echo "4. If issues persist, save this diagnostic report for support"
    echo ""
    echo -e "${YELLOW}Support Resources:${NC}"
    echo "• GitHub Actions Documentation: https://docs.github.com/en/actions"
    echo "• GitHub Actions Runner Documentation: https://docs.github.com/en/actions/hosting-your-own-runners"
    echo "• Ubuntu Package Management: https://help.ubuntu.com/community/AptGet/Howto"
    echo ""
}

# =============================================================================
# Utility Functions
# =============================================================================

# Show error handler library information
show_error_handler_info() {
    cat << EOF
$ERROR_HANDLER_NAME v$ERROR_HANDLER_VERSION

AVAILABLE FUNCTIONS:

Diagnostic Collection:
  collect_system_diagnostics
  collect_package_diagnostics
  collect_network_diagnostics
  collect_github_diagnostics [username] [repository] [pat]
  collect_diagnostic_info [username] [repository] [pat]

Error Handling:
  show_detailed_error <code> <message> [context]
  handle_installation_error <type> <message> [context] [username] [repository] [pat]

Progress Reporting:
  show_installation_progress <step> <current> <total> [details]
  show_completion_summary <success> <time> [errors]

Troubleshooting Guides:
  show_cloud_init_troubleshooting
  show_package_manager_troubleshooting
  show_network_troubleshooting
  show_github_auth_troubleshooting
  show_resource_troubleshooting
  show_general_troubleshooting

Error Codes:
  SYSTEM_NOT_READY (100)
  CLOUD_INIT_TIMEOUT (101)
  INSUFFICIENT_RESOURCES (102)
  NETWORK_CONNECTIVITY (103)
  PACKAGE_MANAGER_BUSY (200)
  PACKAGE_INSTALL_FAILED (201)
  DEPENDENCY_MISSING (202)
  DPKG_LOCK_TIMEOUT (203)
  RUNNER_DOWNLOAD_FAILED (300)
  RUNNER_CONFIG_FAILED (301)
  RUNNER_SERVICE_FAILED (302)
  GITHUB_AUTH_FAILED (303)
  GITHUB_REGISTRATION_FAILED (304)
  UNKNOWN_ERROR (999)

Usage:
  source scripts/installation-error-handler.sh
  handle_installation_error "PACKAGE_MANAGER_BUSY" "dpkg is locked" "During runner installation"

EOF
}

# Command line interface for diagnostic collection
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --collect-diagnostics)
            collect_diagnostic_info "$2" "$3" "$4"
            ;;
        --help|-h)
            show_error_handler_info
            ;;
        *)
            show_error_handler_info
            ;;
    esac
fi