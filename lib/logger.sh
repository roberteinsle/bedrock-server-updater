#!/bin/bash
#
# logger.sh - Logging functions for Bedrock Server Updater
# Provides structured logging with different log levels
#

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARNING=2
readonly LOG_LEVEL_ERROR=3

# Color codes for terminal output
readonly COLOR_RESET='\033[0m'
readonly COLOR_DEBUG='\033[0;36m'    # Cyan
readonly COLOR_INFO='\033[0;32m'     # Green
readonly COLOR_WARNING='\033[0;33m'  # Yellow
readonly COLOR_ERROR='\033[0;31m'    # Red

# Global variables
LOG_FILE=""
CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO}

#
# Initialize logging system
# Arguments:
#   $1 - Log directory
#   $2 - Log level (DEBUG, INFO, WARNING, ERROR)
#
init_logging() {
    local log_dir="$1"
    local log_level="${2:-INFO}"

    # Create log directory if it doesn't exist
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" || {
            echo "ERROR: Failed to create log directory: $log_dir" >&2
            return 1
        }
    fi

    # Set log file path with current date
    LOG_FILE="${log_dir}/update-$(date +%Y-%m-%d).log"

    # Set log level
    case "${log_level^^}" in
        DEBUG)   CURRENT_LOG_LEVEL=$LOG_LEVEL_DEBUG ;;
        INFO)    CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO ;;
        WARNING) CURRENT_LOG_LEVEL=$LOG_LEVEL_WARNING ;;
        ERROR)   CURRENT_LOG_LEVEL=$LOG_LEVEL_ERROR ;;
        *)       CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO ;;
    esac

    # Create log file if it doesn't exist
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE" || {
            echo "ERROR: Failed to create log file: $LOG_FILE" >&2
            return 1
        }
        chmod 600 "$LOG_FILE"
    fi

    log_info "=== Logging initialized ==="
    log_info "Log file: $LOG_FILE"
    log_info "Log level: $log_level"

    return 0
}

#
# Internal logging function
# Arguments:
#   $1 - Log level (DEBUG, INFO, WARNING, ERROR)
#   $2 - Log level numeric value
#   $3 - Color code
#   $@ - Message
#
_log() {
    local level="$1"
    local level_value="$2"
    local color="$3"
    shift 3
    local message="$*"

    # Check if message should be logged based on current log level
    if [[ $level_value -lt $CURRENT_LOG_LEVEL ]]; then
        return 0
    fi

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local log_entry="[$timestamp] [$level] $message"

    # Write to log file
    if [[ -n "$LOG_FILE" ]]; then
        echo "$log_entry" >> "$LOG_FILE"
    fi

    # Write to console with color
    if [[ -t 1 ]]; then
        # Terminal output - use colors
        echo -e "${color}[$timestamp] [$level]${COLOR_RESET} $message"
    else
        # Non-terminal output - no colors
        echo "$log_entry"
    fi
}

#
# Log debug message
# Arguments:
#   $@ - Message
#
log_debug() {
    _log "DEBUG" $LOG_LEVEL_DEBUG "$COLOR_DEBUG" "$@"
}

#
# Log info message
# Arguments:
#   $@ - Message
#
log_info() {
    _log "INFO" $LOG_LEVEL_INFO "$COLOR_INFO" "$@"
}

#
# Log warning message
# Arguments:
#   $@ - Message
#
log_warning() {
    _log "WARNING" $LOG_LEVEL_WARNING "$COLOR_WARNING" "$@"
}

#
# Log error message
# Arguments:
#   $@ - Message
#
log_error() {
    _log "ERROR" $LOG_LEVEL_ERROR "$COLOR_ERROR" "$@"
}

#
# Rotate old log files
# Arguments:
#   $1 - Log directory
#   $2 - Retention days
#
rotate_logs() {
    local log_dir="$1"
    local retention_days="${2:-30}"

    if [[ ! -d "$log_dir" ]]; then
        log_warning "Log directory does not exist: $log_dir"
        return 1
    fi

    log_info "Rotating logs older than $retention_days days in $log_dir"

    local deleted_count=0

    # Find and delete log files older than retention period
    while IFS= read -r -d '' log_file; do
        rm -f "$log_file"
        ((deleted_count++))
        log_debug "Deleted old log file: $log_file"
    done < <(find "$log_dir" -name "update-*.log" -type f -mtime +"$retention_days" -print0)

    if [[ $deleted_count -gt 0 ]]; then
        log_info "Deleted $deleted_count old log file(s)"
    else
        log_debug "No old log files to delete"
    fi

    return 0
}

#
# Log separator line
#
log_separator() {
    local separator="============================================================"
    if [[ -n "$LOG_FILE" ]]; then
        echo "$separator" >> "$LOG_FILE"
    fi
    echo "$separator"
}

#
# Log script start
# Arguments:
#   $1 - Script name
#
log_script_start() {
    local script_name="$1"
    log_separator
    log_info "Starting: $script_name"
    log_info "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "Hostname: $(hostname)"
    log_info "User: $(whoami)"
    log_separator
}

#
# Log script end
# Arguments:
#   $1 - Script name
#   $2 - Exit code
#
log_script_end() {
    local script_name="$1"
    local exit_code="${2:-0}"

    log_separator
    if [[ $exit_code -eq 0 ]]; then
        log_info "Completed: $script_name (Exit code: $exit_code)"
    else
        log_error "Failed: $script_name (Exit code: $exit_code)"
    fi
    log_info "Duration: $SECONDS seconds"
    log_separator
}
