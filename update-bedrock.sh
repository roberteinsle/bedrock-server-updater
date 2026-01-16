#!/bin/bash
#
# update-bedrock.sh - Main update script for Minecraft Bedrock servers
# Automatically checks for updates and applies them via Crafty Controller
#
# Exit codes:
#   0 - Success (update applied or no updates available)
#   1 - Configuration/initialization error
#   2 - Backup error
#   3 - Download error
#   4 - Update error
#   5 - Server start error (rollback performed)
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library functions
# shellcheck source=lib/platform.sh
source "${SCRIPT_DIR}/lib/platform.sh"
# shellcheck source=lib/logger.sh
source "${SCRIPT_DIR}/lib/logger.sh"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/crafty-api.sh
source "${SCRIPT_DIR}/lib/crafty-api.sh"
# shellcheck source=lib/version-check.sh
source "${SCRIPT_DIR}/lib/version-check.sh"
# shellcheck source=lib/backup.sh
source "${SCRIPT_DIR}/lib/backup.sh"
# shellcheck source=lib/update-server.sh
source "${SCRIPT_DIR}/lib/update-server.sh"
# shellcheck source=lib/notification.sh
source "${SCRIPT_DIR}/lib/notification.sh"

# Global variables
TEMP_DIR=""
DOWNLOAD_FILE=""
BACKUP_FILES=()
UPDATE_PERFORMED=false
EXIT_CODE=0

#
# Cleanup function - called on script exit
#
cleanup() {
    local exit_code=$?

    log_info "Cleaning up..."

    # Remove temporary files
    if [[ -n "$TEMP_DIR" ]] && [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_debug "Removed temporary directory: $TEMP_DIR"
    fi

    if [[ -n "$DOWNLOAD_FILE" ]] && [[ -f "$DOWNLOAD_FILE" ]]; then
        rm -f "$DOWNLOAD_FILE"
        log_debug "Removed download file: $DOWNLOAD_FILE"
    fi

    # Log script end
    log_script_end "Bedrock Server Updater" "$exit_code"

    exit "$exit_code"
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

#
# Parse command line arguments
#
DRY_RUN_MODE=false
FORCE_UPDATE=false
SKIP_BACKUP=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN_MODE=true
            log_info "Dry-run mode enabled"
            shift
            ;;
        --force)
            FORCE_UPDATE=true
            log_info "Force update mode enabled"
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            log_warning "Skipping backup (not recommended!)"
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 [OPTIONS]

Minecraft Bedrock Server Updater

OPTIONS:
  --dry-run         Test mode - check for updates but don't apply them
  --force           Force update even if version is the same
  --skip-backup     Skip backup creation (NOT RECOMMENDED)
  --verbose, -v     Enable verbose logging
  --help, -h        Show this help message

EXAMPLES:
  $0                      # Normal update check and apply
  $0 --dry-run            # Check for updates without applying
  $0 --force              # Force update regardless of version

EXIT CODES:
  0 - Success
  1 - Configuration error
  2 - Backup error
  3 - Download error
  4 - Update error
  5 - Server start error

EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

#
# Main execution
#
main() {
    # Initialize logging
    # Use local logs directory in dev mode or if LOG_DIR not set on non-Linux
    local default_log_dir="/var/log/bedrock-updater"
    if is_windows || [[ ! -d "/var/log" ]]; then
        default_log_dir="${SCRIPT_DIR}/logs"
    fi
    init_logging "${LOG_DIR:-$default_log_dir}" "${LOG_LEVEL:-INFO}"

    # Log script start
    log_script_start "Bedrock Server Updater v1.0"

    # Print platform information
    print_platform_info

    # Warn if not on Linux
    warn_if_not_linux

    # Initialize configuration
    log_info "Loading configuration..."
    if ! init_config; then
        log_error "Failed to initialize configuration"
        EXIT_CODE=1
        return 1
    fi

    # Print configuration summary
    if [[ "$VERBOSE" == "true" ]]; then
        print_config_summary
    fi

    # Override DRY_RUN from config if command line flag is set
    if [[ "$DRY_RUN_MODE" == "true" ]]; then
        DRY_RUN=true
    fi

    # Test Crafty API connection (skip in dev mode)
    if ! is_dev_mode; then
        log_info "Testing Crafty Controller API connection..."
        if ! crafty_test_connection; then
            log_error "Cannot connect to Crafty Controller API"
            send_failure_notification "API connection failed" "Initialization"
            EXIT_CODE=1
            return 1
        fi
    else
        log_warning "Dev mode: Skipping Crafty API connection test"
    fi

    # === PHASE 1: Version Check ===
    log_separator
    log_info "PHASE 1: Checking for updates..."

    # Get current version from first server via Crafty API
    local first_server
    first_server=$(get_server_names | head -n1)
    local first_server_id
    first_server_id=$(get_server_id "$first_server")

    log_info "Checking current version from server: $first_server"
    local current_version
    current_version=$(get_current_version "$first_server_id")

    if [[ -z "$current_version" ]] || [[ "$current_version" == "0.0.0.0" ]]; then
        log_warning "Could not determine current version, assuming first-time setup or update needed"
        current_version="0.0.0.0"
    else
        log_info "Current version: $current_version"
    fi

    # Get latest version info
    log_info "Checking for latest Bedrock Server version..."
    local version_info
    version_info=$(get_latest_version_info)

    if [[ -z "$version_info" ]]; then
        log_error "Failed to get latest version information"
        send_failure_notification "Could not check for updates" "Version Check"
        EXIT_CODE=3
        return 1
    fi

    # Validate that version_info contains valid JSON
    if ! echo "$version_info" | jq empty 2>/dev/null; then
        log_error "Invalid JSON response from version check"
        log_error "Response was: $version_info"
        send_failure_notification "Could not check for updates" "Version Check"
        EXIT_CODE=3
        return 1
    fi

    local latest_version
    latest_version=$(echo "$version_info" | jq -r '.version')
    local download_url
    download_url=$(echo "$version_info" | jq -r '.url')

    if [[ -z "$latest_version" ]] || [[ -z "$download_url" ]]; then
        log_error "Could not extract version or URL from response"
        log_error "Version: $latest_version, URL: $download_url"
        send_failure_notification "Could not check for updates" "Version Check"
        EXIT_CODE=3
        return 1
    fi

    log_info "Latest version available: $latest_version"

    # Check if update is needed
    if ! is_update_available "$current_version" "$latest_version" && [[ "$FORCE_UPDATE" != "true" ]]; then
        log_info "No update needed, already running latest version"
        # Optionally send notification (commented out to avoid spam)
        # send_no_update_notification "$current_version"
        EXIT_CODE=0
        return 0
    fi

    log_info "Update available: $current_version -> $latest_version"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would update from $current_version to $latest_version"
        log_info "DRY RUN: Exiting without making changes"
        EXIT_CODE=0
        return 0
    fi

    # === PHASE 2: Pre-Update ===
    log_separator
    log_info "PHASE 2: Pre-update preparation..."

    # Stop all servers
    log_info "Stopping all Minecraft servers..."
    if ! crafty_stop_all_servers; then
        log_error "Failed to stop all servers"
        send_failure_notification "Could not stop servers" "Pre-Update"
        EXIT_CODE=4
        return 1
    fi

    # Create backups
    if [[ "$SKIP_BACKUP" != "true" ]]; then
        log_info "Creating backups for all servers..."
        local backup_output
        backup_output=$(create_all_backups)

        if [[ $? -ne 0 ]]; then
            log_error "Backup creation failed"
            log_error "Restarting servers and aborting update..."
            crafty_start_all_servers
            send_failure_notification "Backup creation failed" "Pre-Update"
            EXIT_CODE=2
            return 1
        fi

        # Store backup file paths
        mapfile -t BACKUP_FILES <<< "$backup_output"
        log_info "Created ${#BACKUP_FILES[@]} backup(s)"
    else
        log_warning "Skipping backups as requested (risky!)"
    fi

    # === PHASE 3: Download ===
    log_separator
    log_info "PHASE 3: Downloading new version..."

    # Create temp directory
    TEMP_DIR=$(mktemp -d)
    DOWNLOAD_FILE="${TEMP_DIR}/bedrock-server-${latest_version}.zip"

    log_info "Downloading Bedrock Server $latest_version..."
    if ! download_bedrock_server "$download_url" "$DOWNLOAD_FILE"; then
        log_error "Download failed"
        log_error "Restarting servers and aborting update..."
        crafty_start_all_servers
        send_failure_notification "Download failed" "Download" "$(get_server_names | tr '\n' ', ')"
        EXIT_CODE=3
        return 1
    fi

    # === PHASE 4: Update ===
    log_separator
    log_info "PHASE 4: Updating servers..."

    if ! update_all_servers "$DOWNLOAD_FILE"; then
        log_error "Server update failed"
        log_warning "Attempting rollback..."

        # Rollback all servers
        if rollback_all_servers; then
            log_info "Rollback successful"
            send_rollback_notification "Update failed" "$(get_server_names | tr '\n' ', ')"
        else
            log_error "Rollback failed!"
            send_failure_notification "Update and rollback failed" "Update" "$(get_server_names | tr '\n' ', ')"
        fi

        # Restart servers
        crafty_start_all_servers
        EXIT_CODE=4
        return 1
    fi

    UPDATE_PERFORMED=true
    log_info "All servers updated successfully"

    # === PHASE 5: Post-Update ===
    log_separator
    log_info "PHASE 5: Post-update verification..."

    # Start all servers
    log_info "Starting all servers..."
    if ! crafty_start_all_servers; then
        log_error "Failed to start servers after update"
        log_warning "Attempting rollback..."

        # Rollback all servers
        if rollback_all_servers; then
            log_info "Rollback successful"
            crafty_start_all_servers
            send_rollback_notification "Servers failed to start after update" "$(get_server_names | tr '\n' ', ')"
        else
            log_error "Rollback failed!"
            send_failure_notification "Server start and rollback failed" "Post-Update" "$(get_server_names | tr '\n' ', ')"
        fi

        EXIT_CODE=5
        return 1
    fi

    # Wait for servers to stabilize
    log_info "Waiting $SERVER_START_WAIT seconds for servers to stabilize..."
    sleep "$SERVER_START_WAIT"

    # Verify all servers are running
    log_info "Verifying server status..."
    local failed_servers=()
    local server_names
    server_names=$(get_server_names)

    for server_name in $server_names; do
        local server_id
        server_id=$(get_server_id "$server_name")

        if ! crafty_is_server_running "$server_id"; then
            log_error "Server not running: $server_name"
            failed_servers+=("$server_name")
        else
            log_info "Server running: $server_name"
        fi
    done

    if [[ ${#failed_servers[@]} -gt 0 ]]; then
        log_error "${#failed_servers[@]} server(s) failed to start: ${failed_servers[*]}"
        log_warning "Attempting rollback..."

        crafty_stop_all_servers
        if rollback_all_servers; then
            log_info "Rollback successful"
            crafty_start_all_servers
            send_rollback_notification "Servers failed verification after update" "${failed_servers[*]}"
        else
            log_error "Rollback failed!"
            send_failure_notification "Verification and rollback failed" "Post-Update" "${failed_servers[*]}"
        fi

        EXIT_CODE=5
        return 1
    fi

    # === PHASE 6: Cleanup ===
    log_separator
    log_info "PHASE 6: Cleanup..."

    # Cleanup old backups
    if [[ "$SKIP_BACKUP" != "true" ]]; then
        log_info "Cleaning up old backups..."
        cleanup_old_backups "$BACKUP_DIR" "$BACKUP_RETENTION_DAYS"
    fi

    # Rotate logs
    log_info "Rotating old logs..."
    rotate_logs "$LOG_DIR" "$LOG_RETENTION_DAYS"

    # === SUCCESS ===
    log_separator
    log_info "Update completed successfully!"
    log_info "Updated from version $current_version to $latest_version"

    # Send success notification
    local server_list
    server_list=$(format_server_list)
    send_success_notification "$latest_version" "$server_list"

    EXIT_CODE=0
    return 0
}

# Run main function
main

# Exit with appropriate code
exit $EXIT_CODE
