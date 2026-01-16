#!/bin/bash
#
# platform.sh - Platform detection and compatibility helpers
# Provides OS detection and cross-platform compatibility functions
#

# Detect current OS
detect_os() {
    case "$(uname -s)" in
        Linux*)     echo "Linux";;
        Darwin*)    echo "macOS";;
        CYGWIN*)    echo "Windows";;
        MINGW*)     echo "Windows";;
        MSYS*)      echo "Windows";;
        *)          echo "Unknown";;
    esac
}

# Check if running on Linux
is_linux() {
    [[ "$(detect_os)" == "Linux" ]]
}

# Check if running on Windows (Git Bash, MINGW, etc.)
is_windows() {
    [[ "$(detect_os)" == "Windows" ]]
}

# Check if running on macOS
is_macos() {
    [[ "$(detect_os)" == "macOS" ]]
}

# Check if in development mode (Windows or explicit DEV_MODE=true)
is_dev_mode() {
    if [[ "${DEV_MODE:-false}" == "true" ]]; then
        return 0
    fi

    is_windows
}

#
# Get file size in a cross-platform way
# Arguments:
#   $1 - File path
# Returns:
#   File size in bytes
#
get_file_size() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "0"
        return 1
    fi

    if is_linux; then
        stat -c%s "$file" 2>/dev/null
    else
        # macOS, BSD, or Windows
        stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0"
    fi
}

#
# Get file permissions in a cross-platform way
# Arguments:
#   $1 - File path
# Returns:
#   File permissions (e.g., "600")
#
get_file_permissions() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 1
    fi

    if is_linux; then
        stat -c %a "$file" 2>/dev/null
    else
        # macOS, BSD, or Windows
        stat -f %A "$file" 2>/dev/null || stat -c %a "$file" 2>/dev/null || echo ""
    fi
}

#
# Check if a server path exists or is mockable in dev mode
# Arguments:
#   $1 - Server path
# Returns:
#   0 if path exists or in dev mode, 1 otherwise
#
check_server_path() {
    local server_path="$1"

    if [[ -d "$server_path" ]]; then
        return 0
    fi

    if is_dev_mode; then
        log_debug "Dev mode: Skipping server path check for $server_path"
        return 0
    fi

    return 1
}

#
# Print platform information
#
print_platform_info() {
    log_info "=== Platform Information ==="
    log_info "Operating System: $(detect_os)"
    log_info "Kernel: $(uname -s)"
    log_info "Kernel Version: $(uname -r)"
    log_info "Architecture: $(uname -m)"
    log_info "Hostname: $(hostname)"

    if is_dev_mode; then
        log_info "Development Mode: ENABLED"
    else
        log_info "Development Mode: DISABLED"
    fi

    log_info "=========================="
}

#
# Warn if not running on Linux (production environment)
#
warn_if_not_linux() {
    if ! is_linux; then
        log_warning "This script is designed to run on Linux"
        log_warning "Current OS: $(detect_os)"
        log_warning "Some features may not work correctly"

        if is_windows; then
            log_info "Development mode auto-enabled for Windows"
            export DEV_MODE=true
        fi
    fi
}
