#!/bin/bash

# Installation Logger
# This library provides centralized logging, metrics collection, and monitoring
# for GitHub Actions runner installation processes.

# Script version and metadata
LOGGER_VERSION="1.0.0"
LOGGER_NAME="Installation Logger"

# Default log configuration
DEFAULT_LOG_DIR="/var/log/github-runner"
DEFAULT_LOG_FILE="runner-installation.log"
DEFAULT_METRICS_FILE="installation-metrics.json"
DEFAULT_MAX_LOG_SIZE="10M"
DEFAULT_MAX_LOG_FILES="5"

# Global logging configuration
LOG_DIR="${RUNNER_LOG_DIR:-$DEFAULT_LOG_DIR}"
LOG_FILE="${RUNNER_LOG_FILE:-$DEFAULT_LOG_FILE}"
METRICS_FILE="${RUNNER_METRICS_FILE:-$DEFAULT_METRICS_FILE}"
MAX_LOG_SIZE="${RUNNER_MAX_LOG_SIZE:-$DEFAULT_MAX_LOG_SIZE}"
MAX_LOG_FILES="${RUNNER_MAX_LOG_FILES:-$DEFAULT_MAX_LOG_FILES}"

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

# =============================================================================
# Logging Infrastructure Setup
# =============================================================================

# Initialize logging system
# Usage: init_logging [log_dir] [log_file]
init_logging() {
    local log_dir="${1:-$LOG_DIR}"
    local log_file="${2:-$LOG_FILE}"
    
    # Create log directory if it doesn't exist
    if [ ! -d "$log_dir" ]; then
        if ! sudo mkdir -p "$log_dir" 2>/dev/null; then
            # Fallback to user's home directory if we can't create system log dir
            log_dir="$HOME/.github-runner-logs"
            mkdir -p "$log_dir"
        fi
    fi
    
    # Set permissions if we created a system directory
    if [[ "$log_dir" == /var/log/* ]]; then
        sudo chown -R "$(whoami):$(whoami)" "$log_dir" 2>/dev/null || true
        sudo chmod 755 "$log_dir" 2>/dev/null || true
    fi
    
    # Update global variables
    LOG_DIR="$log_dir"
    LOG_FILE="$log_dir/$log_file"
    METRICS_FILE="$log_dir/$METRICS_FILE"
    
    # Create initial log entry
    log_to_file "INFO" "Logging system initialized" "log_dir=$LOG_DIR, log_file=$LOG_FILE"
    
    return 0
}

# Rotate logs if they exceed size limit
# Usage: rotate_logs
rotate_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        return 0
    fi
    
    # Check if log file exceeds size limit
    local current_size
    current_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
    local max_size_bytes
    
    # Convert size limit to bytes
    case "$MAX_LOG_SIZE" in
        *K|*k) max_size_bytes=$((${MAX_LOG_SIZE%[Kk]} * 1024)) ;;
        *M|*m) max_size_bytes=$((${MAX_LOG_SIZE%[Mm]} * 1024 * 1024)) ;;
        *G|*g) max_size_bytes=$((${MAX_LOG_SIZE%[Gg]} * 1024 * 1024 * 1024)) ;;
        *) max_size_bytes="$MAX_LOG_SIZE" ;;
    esac
    
    if [ "$current_size" -gt "$max_size_bytes" ]; then
        # Rotate existing log files
        for ((i=MAX_LOG_FILES-1; i>=1; i--)); do
            local old_file="${LOG_FILE}.$i"
            local new_file="${LOG_FILE}.$((i+1))"
            
            if [ -f "$old_file" ]; then
                if [ $i -eq $((MAX_LOG_FILES-1)) ]; then
                    rm -f "$old_file"  # Remove oldest log
                else
                    mv "$old_file" "$new_file"
                fi
            fi
        done
        
        # Move current log to .1
        mv "$LOG_FILE" "${LOG_FILE}.1"
        
        # Create new log file
        touch "$LOG_FILE"
        log_to_file "INFO" "Log rotation completed" "rotated_size=${current_size}, max_size=${max_size_bytes}"
    fi
}

# =============================================================================
# Core Logging Functions
# =============================================================================

# Write log entry to file
# Usage: log_to_file <level> <message> [details]
log_to_file() {
    local level="$1"
    local message="$2"
    local details="${3:-}"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local pid=$$
    local script_name=$(basename "${BASH_SOURCE[2]:-unknown}")
    
    # Ensure log directory exists
    if [ ! -d "$LOG_DIR" ]; then
        init_logging
    fi
    
    # Rotate logs if needed
    rotate_logs
    
    # Format log entry
    local log_entry="[$timestamp] [$level] [$pid] [$script_name] $message"
    if [ -n "$details" ]; then
        log_entry="$log_entry | $details"
    fi
    
    # Write to log file
    echo "$log_entry" >> "$LOG_FILE"
}

# Enhanced logging functions with file output
log_info_enhanced() {
    local message="$1"
    local details="${2:-}"
    
    echo -e "${BLUE}[INFO]${NC} $message"
    log_to_file "INFO" "$message" "$details"
}

log_success_enhanced() {
    local message="$1"
    local details="${2:-}"
    
    echo -e "${GREEN}[SUCCESS]${NC} $message"
    log_to_file "SUCCESS" "$message" "$details"
}

log_warning_enhanced() {
    local message="$1"
    local details="${2:-}"
    
    echo -e "${YELLOW}[WARNING]${NC} $message"
    log_to_file "WARNING" "$message" "$details"
}

log_error_enhanced() {
    local message="$1"
    local details="${2:-}"
    
    echo -e "${RED}[ERROR]${NC} $message"
    log_to_file "ERROR" "$message" "$details"
}

log_debug_enhanced() {
    local message="$1"
    local details="${2:-}"
    
    if [ "${DEBUG:-false}" = "true" ]; then
        echo -e "${CYAN}[DEBUG]${NC} $message"
    fi
    log_to_file "DEBUG" "$message" "$details"
}

# =============================================================================
# Installation Step Logging
# =============================================================================

# Log installation step start
# Usage: log_step_start <step_name> <step_number> <total_steps> [details]
log_step_start() {
    local step_name="$1"
    local step_number="$2"
    local total_steps="$3"
    local details="${4:-}"
    
    local step_info="step=${step_number}/${total_steps}, name=${step_name}"
    if [ -n "$details" ]; then
        step_info="$step_info, details=${details}"
    fi
    
    log_info_enhanced "Starting installation step: $step_name" "$step_info"
}

# Log installation step completion
# Usage: log_step_complete <step_name> <duration> [details]
log_step_complete() {
    local step_name="$1"
    local duration="$2"
    local details="${3:-}"
    
    local step_info="duration=${duration}s"
    if [ -n "$details" ]; then
        step_info="$step_info, details=${details}"
    fi
    
    log_success_enhanced "Completed installation step: $step_name" "$step_info"
}

# Log installation step failure
# Usage: log_step_failure <step_name> <error_message> <duration> [details]
log_step_failure() {
    local step_name="$1"
    local error_message="$2"
    local duration="$3"
    local details="${4:-}"
    
    local step_info="duration=${duration}s, error=${error_message}"
    if [ -n "$details" ]; then
        step_info="$step_info, details=${details}"
    fi
    
    log_error_enhanced "Failed installation step: $step_name" "$step_info"
}

# =============================================================================
# Metrics Collection
# =============================================================================

# Initialize metrics collection
# Usage: init_metrics <installation_id>
init_metrics() {
    local installation_id="$1"
    
    local metrics_data=$(cat << EOF
{
  "installation_id": "$installation_id",
  "start_time": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "user": "$(whoami)",
  "os_version": "$(lsb_release -d 2>/dev/null | cut -f2 || echo 'Unknown')",
  "kernel_version": "$(uname -r)",
  "steps": [],
  "metrics": {
    "total_duration": 0,
    "step_count": 0,
    "retry_count": 0,
    "warning_count": 0,
    "error_count": 0
  },
  "system_info": {
    "memory_mb": $(free -m | awk 'NR==2{print $2}'),
    "disk_available_mb": $(df -m / | awk 'NR==2{print $4}'),
    "cpu_count": $(nproc)
  }
}
EOF
)
    
    echo "$metrics_data" > "$METRICS_FILE"
    log_debug_enhanced "Metrics collection initialized" "file=$METRICS_FILE, id=$installation_id"
}

# Record step metrics
# Usage: record_step_metrics <step_name> <status> <duration> [retry_count] [details]
record_step_metrics() {
    local step_name="$1"
    local status="$2"
    local duration="$3"
    local retry_count="${4:-0}"
    local details="${5:-}"
    
    if [ ! -f "$METRICS_FILE" ]; then
        log_warning_enhanced "Metrics file not found, skipping metrics recording"
        return 1
    fi
    
    # Create step record
    local step_record=$(cat << EOF
{
  "name": "$step_name",
  "status": "$status",
  "duration": $duration,
  "retry_count": $retry_count,
  "timestamp": "$(date -Iseconds)",
  "details": "$details"
}
EOF
)
    
    # Update metrics file using jq if available
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq --argjson step "$step_record" '
            .steps += [$step] |
            .metrics.step_count += 1 |
            .metrics.total_duration += ($step.duration) |
            .metrics.retry_count += ($step.retry_count) |
            if $step.status == "warning" then .metrics.warning_count += 1 else . end |
            if $step.status == "error" then .metrics.error_count += 1 else . end
        ' "$METRICS_FILE" > "$temp_file" && mv "$temp_file" "$METRICS_FILE"
    else
        log_debug_enhanced "jq not available, skipping structured metrics update"
    fi
    
    log_debug_enhanced "Step metrics recorded" "step=$step_name, status=$status, duration=${duration}s"
}

# Finalize metrics collection
# Usage: finalize_metrics <final_status>
finalize_metrics() {
    local final_status="$1"
    
    if [ ! -f "$METRICS_FILE" ]; then
        log_warning_enhanced "Metrics file not found, skipping metrics finalization"
        return 1
    fi
    
    # Update final metrics using jq if available
    if command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq --arg status "$final_status" --arg end_time "$(date -Iseconds)" '
            .end_time = $end_time |
            .final_status = $status |
            .metrics.total_duration = (now - (.start_time | fromdateiso8601))
        ' "$METRICS_FILE" > "$temp_file" && mv "$temp_file" "$METRICS_FILE"
        
        log_info_enhanced "Installation metrics finalized" "status=$final_status, file=$METRICS_FILE"
    else
        log_debug_enhanced "jq not available, skipping structured metrics finalization"
    fi
}

# =============================================================================
# Installation Session Management
# =============================================================================

# Start installation session
# Usage: start_installation_session <session_name> [details]
start_installation_session() {
    local session_name="$1"
    local details="${2:-}"
    
    # Generate unique installation ID
    local installation_id="${session_name}-$(date +%s)-$$"
    
    # Initialize logging
    init_logging
    
    # Initialize metrics
    init_metrics "$installation_id"
    
    # Log session start
    local session_info="id=$installation_id"
    if [ -n "$details" ]; then
        session_info="$session_info, details=$details"
    fi
    
    log_info_enhanced "Installation session started: $session_name" "$session_info"
    
    # Export installation ID for use by other functions
    export INSTALLATION_ID="$installation_id"
    export INSTALLATION_SESSION_START=$(date +%s)
    
    echo "$installation_id"
}

# End installation session
# Usage: end_installation_session <status> [details]
end_installation_session() {
    local status="$1"
    local details="${2:-}"
    
    local session_duration=$(($(date +%s) - ${INSTALLATION_SESSION_START:-$(date +%s)}))
    
    # Finalize metrics
    finalize_metrics "$status"
    
    # Log session end
    local session_info="id=${INSTALLATION_ID:-unknown}, duration=${session_duration}s, status=$status"
    if [ -n "$details" ]; then
        session_info="$session_info, details=$details"
    fi
    
    if [ "$status" = "success" ]; then
        log_success_enhanced "Installation session completed successfully" "$session_info"
    else
        log_error_enhanced "Installation session failed" "$session_info"
    fi
    
    # Show metrics summary if available
    show_metrics_summary
}

# =============================================================================
# Metrics Reporting
# =============================================================================

# Show metrics summary
# Usage: show_metrics_summary
show_metrics_summary() {
    if [ ! -f "$METRICS_FILE" ]; then
        log_debug_enhanced "No metrics file found, skipping summary"
        return 1
    fi
    
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                            INSTALLATION METRICS                             ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if command -v jq &> /dev/null; then
        # Extract metrics using jq
        local installation_id=$(jq -r '.installation_id' "$METRICS_FILE")
        local start_time=$(jq -r '.start_time' "$METRICS_FILE")
        local end_time=$(jq -r '.end_time // "ongoing"' "$METRICS_FILE")
        local final_status=$(jq -r '.final_status // "ongoing"' "$METRICS_FILE")
        local step_count=$(jq -r '.metrics.step_count' "$METRICS_FILE")
        local retry_count=$(jq -r '.metrics.retry_count' "$METRICS_FILE")
        local warning_count=$(jq -r '.metrics.warning_count' "$METRICS_FILE")
        local error_count=$(jq -r '.metrics.error_count' "$METRICS_FILE")
        local total_duration=$(jq -r '.metrics.total_duration' "$METRICS_FILE")
        
        echo "Installation ID: $installation_id"
        echo "Start Time: $start_time"
        echo "End Time: $end_time"
        echo "Status: $final_status"
        echo "Total Duration: ${total_duration}s"
        echo "Steps Completed: $step_count"
        echo "Total Retries: $retry_count"
        echo "Warnings: $warning_count"
        echo "Errors: $error_count"
        
        # Show step breakdown
        echo ""
        echo "Step Breakdown:"
        jq -r '.steps[] | "  \(.name): \(.status) (\(.duration)s, \(.retry_count) retries)"' "$METRICS_FILE"
        
    else
        echo "Metrics file: $METRICS_FILE"
        echo "Detailed metrics require 'jq' to be installed"
    fi
    
    echo ""
    echo "Log file: $LOG_FILE"
    echo ""
}

# Export metrics to external format
# Usage: export_metrics <format> [output_file]
export_metrics() {
    local format="$1"
    local output_file="${2:-}"
    
    if [ ! -f "$METRICS_FILE" ]; then
        log_error_enhanced "No metrics file found for export"
        return 1
    fi
    
    case "$format" in
        "json")
            if [ -n "$output_file" ]; then
                cp "$METRICS_FILE" "$output_file"
                log_info_enhanced "Metrics exported to JSON" "file=$output_file"
            else
                cat "$METRICS_FILE"
            fi
            ;;
        "csv")
            if command -v jq &> /dev/null; then
                local csv_output
                csv_output=$(jq -r '
                    ["step_name", "status", "duration", "retry_count", "timestamp"],
                    (.steps[] | [.name, .status, .duration, .retry_count, .timestamp])
                    | @csv
                ' "$METRICS_FILE")
                
                if [ -n "$output_file" ]; then
                    echo "$csv_output" > "$output_file"
                    log_info_enhanced "Metrics exported to CSV" "file=$output_file"
                else
                    echo "$csv_output"
                fi
            else
                log_error_enhanced "CSV export requires 'jq' to be installed"
                return 1
            fi
            ;;
        *)
            log_error_enhanced "Unsupported export format: $format"
            return 1
            ;;
    esac
}

# =============================================================================
# Log Analysis Functions
# =============================================================================

# Search logs for patterns
# Usage: search_logs <pattern> [max_lines]
search_logs() {
    local pattern="$1"
    local max_lines="${2:-50}"
    
    if [ ! -f "$LOG_FILE" ]; then
        log_error_enhanced "Log file not found: $LOG_FILE"
        return 1
    fi
    
    echo "Searching logs for pattern: $pattern"
    echo "Log file: $LOG_FILE"
    echo ""
    
    grep -n "$pattern" "$LOG_FILE" | tail -n "$max_lines"
}

# Show recent log entries
# Usage: show_recent_logs [lines]
show_recent_logs() {
    local lines="${1:-50}"
    
    if [ ! -f "$LOG_FILE" ]; then
        log_error_enhanced "Log file not found: $LOG_FILE"
        return 1
    fi
    
    echo "Recent log entries (last $lines lines):"
    echo "Log file: $LOG_FILE"
    echo ""
    
    tail -n "$lines" "$LOG_FILE"
}

# =============================================================================
# Cleanup Functions
# =============================================================================

# Clean old logs and metrics
# Usage: cleanup_logs [days_to_keep]
cleanup_logs() {
    local days_to_keep="${1:-30}"
    
    log_info_enhanced "Cleaning up logs older than $days_to_keep days"
    
    # Clean old log files
    find "$LOG_DIR" -name "*.log*" -type f -mtime +$days_to_keep -delete 2>/dev/null || true
    
    # Clean old metrics files
    find "$LOG_DIR" -name "*.json" -type f -mtime +$days_to_keep -delete 2>/dev/null || true
    
    log_info_enhanced "Log cleanup completed"
}

# =============================================================================
# Utility Functions
# =============================================================================

# Show logger library information
show_logger_info() {
    cat << EOF
$LOGGER_NAME v$LOGGER_VERSION

CONFIGURATION:
  Log Directory: $LOG_DIR
  Log File: $LOG_FILE
  Metrics File: $METRICS_FILE
  Max Log Size: $MAX_LOG_SIZE
  Max Log Files: $MAX_LOG_FILES

AVAILABLE FUNCTIONS:

Logging Infrastructure:
  init_logging [log_dir] [log_file]
  rotate_logs

Enhanced Logging:
  log_info_enhanced <message> [details]
  log_success_enhanced <message> [details]
  log_warning_enhanced <message> [details]
  log_error_enhanced <message> [details]
  log_debug_enhanced <message> [details]

Step Logging:
  log_step_start <name> <number> <total> [details]
  log_step_complete <name> <duration> [details]
  log_step_failure <name> <error> <duration> [details]

Session Management:
  start_installation_session <name> [details]
  end_installation_session <status> [details]

Metrics Collection:
  init_metrics <installation_id>
  record_step_metrics <name> <status> <duration> [retries] [details]
  finalize_metrics <status>

Reporting:
  show_metrics_summary
  export_metrics <format> [output_file]
  search_logs <pattern> [max_lines]
  show_recent_logs [lines]

Maintenance:
  cleanup_logs [days_to_keep]

Usage:
  source scripts/installation-logger.sh
  start_installation_session "runner-config"
  log_info_enhanced "Starting installation"
  end_installation_session "success"

EOF
}

# Command line interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --show-metrics)
            show_metrics_summary
            ;;
        --search)
            search_logs "$2" "$3"
            ;;
        --recent)
            show_recent_logs "$2"
            ;;
        --export)
            export_metrics "$2" "$3"
            ;;
        --cleanup)
            cleanup_logs "$2"
            ;;
        --help|-h)
            show_logger_info
            ;;
        *)
            show_logger_info
            ;;
    esac
fi