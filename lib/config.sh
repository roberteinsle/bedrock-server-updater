#!/bin/bash
#
# config.sh - Configuration loader for Bedrock Server Updater
# Loads and validates configuration from .env file and server-list.json
#

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Configuration variables
CONFIG_LOADED=false

#
# Load environment configuration from .env file
# Arguments:
#   $1 - Path to .env file (optional, defaults to SCRIPT_DIR/.env)
# Returns:
#   0 on success, 1 on failure
#
load_env_config() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"

    if [[ ! -f "$env_file" ]]; then
        log_error "Configuration file not found: $env_file"
        log_error "Please copy .env.example to .env and configure it"
        return 1
    fi

    log_info "Loading configuration from: $env_file"

    # Check file permissions (should be 600 for security)
    local permissions
    permissions=$(stat -c %a "$env_file" 2>/dev/null || stat -f %A "$env_file" 2>/dev/null)

    if [[ "$permissions" != "600" ]] && [[ "$permissions" != "400" ]]; then
        log_warning "Configuration file has insecure permissions: $permissions"
        log_warning "Recommended: chmod 600 $env_file"
    fi

    # Source the .env file
    # shellcheck disable=SC1090
    source "$env_file" || {
        log_error "Failed to load configuration file: $env_file"
        return 1
    }

    log_debug "Environment configuration loaded successfully"
    return 0
}

#
# Validate required environment variables
# Returns:
#   0 if all required variables are set, 1 otherwise
#
validate_env_config() {
    local required_vars=(
        "CRAFTY_API_URL"
        "CRAFTY_API_TOKEN"
        "SMTP_HOST"
        "SMTP_PORT"
        "SMTP_USER"
        "SMTP_PASSWORD"
        "SMTP_FROM"
        "SMTP_TO"
        "BACKUP_DIR"
        "LOG_DIR"
    )

    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required configuration variables:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done
        log_error "Please check your .env file"
        return 1
    fi

    # Validate CRAFTY_API_URL format
    if [[ ! "$CRAFTY_API_URL" =~ ^https?:// ]]; then
        log_error "CRAFTY_API_URL must start with http:// or https://"
        return 1
    fi

    # Remove trailing slash from API URL
    CRAFTY_API_URL="${CRAFTY_API_URL%/}"

    # Validate SMTP_PORT is numeric
    if [[ ! "$SMTP_PORT" =~ ^[0-9]+$ ]]; then
        log_error "SMTP_PORT must be a number"
        return 1
    fi

    # Set default values for optional variables
    SMTP_USE_TLS="${SMTP_USE_TLS:-true}"
    BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
    LOG_LEVEL="${LOG_LEVEL:-INFO}"
    LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"
    SERVER_TIMEOUT="${SERVER_TIMEOUT:-30}"
    SERVER_START_WAIT="${SERVER_START_WAIT:-20}"
    DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-300}"
    DRY_RUN="${DRY_RUN:-false}"

    log_debug "Environment configuration validated successfully"
    return 0
}

#
# Load server list from JSON configuration
# Arguments:
#   $1 - Path to server-list.json (optional, defaults to SCRIPT_DIR/config/server-list.json)
# Returns:
#   0 on success, 1 on failure
#
load_server_config() {
    local config_file="${1:-${SCRIPT_DIR}/config/server-list.json}"

    if [[ ! -f "$config_file" ]]; then
        log_error "Server configuration file not found: $config_file"
        return 1
    fi

    log_info "Loading server configuration from: $config_file"

    # Validate JSON syntax
    if ! jq empty "$config_file" 2>/dev/null; then
        log_error "Invalid JSON in server configuration file: $config_file"
        return 1
    fi

    # Export config file path for other functions
    export SERVER_CONFIG_FILE="$config_file"

    log_debug "Server configuration loaded successfully"
    return 0
}

#
# Get list of all server names
# Returns:
#   Space-separated list of server names
#
get_server_names() {
    if [[ -z "$SERVER_CONFIG_FILE" ]]; then
        log_error "Server configuration not loaded"
        return 1
    fi

    jq -r '.servers[].name' "$SERVER_CONFIG_FILE" 2>/dev/null || {
        log_error "Failed to parse server names from configuration"
        return 1
    }
}

#
# Get server ID by name
# Arguments:
#   $1 - Server name
# Returns:
#   Server ID
#
get_server_id() {
    local server_name="$1"

    if [[ -z "$SERVER_CONFIG_FILE" ]]; then
        log_error "Server configuration not loaded"
        return 1
    fi

    jq -r ".servers[] | select(.name==\"$server_name\") | .id" "$SERVER_CONFIG_FILE" 2>/dev/null
}

#
# Get server path by name
# Arguments:
#   $1 - Server name
# Returns:
#   Server path
#
get_server_path() {
    local server_name="$1"

    if [[ -z "$SERVER_CONFIG_FILE" ]]; then
        log_error "Server configuration not loaded"
        return 1
    fi

    jq -r ".servers[] | select(.name==\"$server_name\") | .path" "$SERVER_CONFIG_FILE" 2>/dev/null
}

#
# Get list of files to preserve during update
# Returns:
#   JSON array of file names
#
get_preserve_files() {
    if [[ -z "$SERVER_CONFIG_FILE" ]]; then
        log_error "Server configuration not loaded"
        return 1
    fi

    jq -r '.preserve_files[]' "$SERVER_CONFIG_FILE" 2>/dev/null
}

#
# Get list of directories to preserve during update
# Returns:
#   JSON array of directory names
#
get_preserve_directories() {
    if [[ -z "$SERVER_CONFIG_FILE" ]]; then
        log_error "Server configuration not loaded"
        return 1
    fi

    jq -r '.preserve_directories[]' "$SERVER_CONFIG_FILE" 2>/dev/null
}

#
# Get list of files that can be updated
# Returns:
#   JSON array of file names
#
get_update_files() {
    if [[ -z "$SERVER_CONFIG_FILE" ]]; then
        log_error "Server configuration not loaded"
        return 1
    fi

    jq -r '.update_files[]' "$SERVER_CONFIG_FILE" 2>/dev/null
}

#
# Initialize all configuration
# Arguments:
#   $1 - Path to .env file (optional)
#   $2 - Path to server-list.json (optional)
# Returns:
#   0 on success, 1 on failure
#
init_config() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"
    local server_config="${2:-${SCRIPT_DIR}/config/server-list.json}"

    # Load environment configuration
    if ! load_env_config "$env_file"; then
        return 1
    fi

    # Validate environment configuration
    if ! validate_env_config; then
        return 1
    fi

    # Load server configuration
    if ! load_server_config "$server_config"; then
        return 1
    fi

    CONFIG_LOADED=true
    log_info "Configuration initialized successfully"
    return 0
}

#
# Check if configuration is loaded
# Returns:
#   0 if loaded, 1 otherwise
#
is_config_loaded() {
    if [[ "$CONFIG_LOADED" == "true" ]]; then
        return 0
    else
        log_error "Configuration not loaded. Call init_config first."
        return 1
    fi
}

#
# Print configuration summary (without sensitive data)
#
print_config_summary() {
    if ! is_config_loaded; then
        return 1
    fi

    log_info "=== Configuration Summary ==="
    log_info "Crafty API URL: $CRAFTY_API_URL"
    log_info "Crafty API Token: ${CRAFTY_API_TOKEN:0:10}... (hidden)"
    log_info "SMTP Host: $SMTP_HOST:$SMTP_PORT"
    log_info "SMTP User: $SMTP_USER"
    log_info "Email From: $SMTP_FROM"
    log_info "Email To: $SMTP_TO"
    log_info "Backup Directory: $BACKUP_DIR"
    log_info "Backup Retention: $BACKUP_RETENTION_DAYS days"
    log_info "Log Directory: $LOG_DIR"
    log_info "Log Level: $LOG_LEVEL"
    log_info "Log Retention: $LOG_RETENTION_DAYS days"
    log_info "Server Timeout: $SERVER_TIMEOUT seconds"
    log_info "Server Start Wait: $SERVER_START_WAIT seconds"
    log_info "Download Timeout: $DOWNLOAD_TIMEOUT seconds"
    log_info "Dry Run Mode: $DRY_RUN"

    local server_count
    server_count=$(jq '.servers | length' "$SERVER_CONFIG_FILE")
    log_info "Configured Servers: $server_count"

    local server_names
    server_names=$(get_server_names | tr '\n' ', ' | sed 's/,$//')
    log_info "Server Names: $server_names"

    log_info "==========================="
}
