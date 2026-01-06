#!/bin/bash
#
# backup.sh - Backup and restore functions for Minecraft Bedrock servers
# Handles full server backups before updates
#

#
# Create a backup of a server directory
# Arguments:
#   $1 - Server name
#   $2 - Server path
#   $3 - Backup directory
# Returns:
#   0 on success, 1 on failure
#   Outputs backup file path to stdout
#
create_backup() {
    local server_name="$1"
    local server_path="$2"
    local backup_dir="${3:-$BACKUP_DIR}"

    if [[ -z "$server_name" ]] || [[ -z "$server_path" ]]; then
        log_error "Server name and path required for backup"
        return 1
    fi

    if [[ ! -d "$server_path" ]]; then
        log_error "Server directory does not exist: $server_path"
        return 1
    fi

    # Create backup directory if it doesn't exist
    if [[ ! -d "$backup_dir" ]]; then
        mkdir -p "$backup_dir" || {
            log_error "Failed to create backup directory: $backup_dir"
            return 1
        }
        chmod 700 "$backup_dir"
    fi

    # Generate backup filename with timestamp
    local timestamp
    timestamp=$(date +%Y-%m-%d-%H%M%S)
    local backup_file="${backup_dir}/backup-${server_name}-${timestamp}.tar.gz"

    log_info "Creating backup for server: $server_name"
    log_info "Source: $server_path"
    log_info "Destination: $backup_file"

    # Create temporary backup file to ensure atomic operation
    local temp_backup="${backup_file}.tmp"

    # Create tar.gz backup
    if tar -czf "$temp_backup" -C "$(dirname "$server_path")" "$(basename "$server_path")" 2>/dev/null; then
        # Move temp file to final location
        mv "$temp_backup" "$backup_file" || {
            log_error "Failed to move backup file"
            rm -f "$temp_backup"
            return 1
        }

        # Set restrictive permissions
        chmod 600 "$backup_file"

        # Get backup file size
        local file_size
        file_size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null)
        local size_mb=$((file_size / 1024 / 1024))

        log_info "Backup created successfully: $backup_file (${size_mb} MB)"
        echo "$backup_file"
        return 0
    else
        log_error "Failed to create backup archive"
        rm -f "$temp_backup"
        return 1
    fi
}

#
# Create backups for all configured servers
# Arguments:
#   $1 - Backup directory (optional, uses $BACKUP_DIR if not provided)
# Returns:
#   0 if all backups successful, 1 if any failed
#   Outputs newline-separated list of backup file paths
#
create_all_backups() {
    local backup_dir="${1:-$BACKUP_DIR}"

    log_info "Creating backups for all servers..."

    local failed_servers=()
    local backup_files=()
    local server_names
    server_names=$(get_server_names)

    for server_name in $server_names; do
        local server_path
        server_path=$(get_server_path "$server_name")

        log_info "Backing up server: $server_name"

        local backup_file
        backup_file=$(create_backup "$server_name" "$server_path" "$backup_dir")

        if [[ $? -eq 0 ]] && [[ -n "$backup_file" ]]; then
            backup_files+=("$backup_file")
            log_info "Backup successful: $server_name"
        else
            failed_servers+=("$server_name")
            log_error "Backup failed: $server_name"
        fi
    done

    # Output backup files
    for file in "${backup_files[@]}"; do
        echo "$file"
    done

    if [[ ${#failed_servers[@]} -gt 0 ]]; then
        log_error "Failed to backup ${#failed_servers[@]} server(s): ${failed_servers[*]}"
        return 1
    fi

    log_info "All server backups completed successfully"
    return 0
}

#
# Restore a server from backup
# Arguments:
#   $1 - Backup file path
#   $2 - Server path (destination)
# Returns:
#   0 on success, 1 on failure
#
restore_backup() {
    local backup_file="$1"
    local server_path="$2"

    if [[ -z "$backup_file" ]] || [[ -z "$server_path" ]]; then
        log_error "Backup file and server path required for restore"
        return 1
    fi

    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file does not exist: $backup_file"
        return 1
    fi

    log_info "Restoring backup: $backup_file"
    log_info "Destination: $server_path"

    # Create parent directory if it doesn't exist
    local parent_dir
    parent_dir=$(dirname "$server_path")
    if [[ ! -d "$parent_dir" ]]; then
        mkdir -p "$parent_dir" || {
            log_error "Failed to create parent directory: $parent_dir"
            return 1
        }
    fi

    # Backup existing directory if it exists
    if [[ -d "$server_path" ]]; then
        local temp_backup="${server_path}.rollback-$(date +%Y%m%d-%H%M%S)"
        log_warning "Moving existing directory to: $temp_backup"
        mv "$server_path" "$temp_backup" || {
            log_error "Failed to move existing directory"
            return 1
        }
    fi

    # Extract backup
    local extract_dir
    extract_dir=$(dirname "$server_path")

    if tar -xzf "$backup_file" -C "$extract_dir" 2>/dev/null; then
        log_info "Backup restored successfully"

        # Set permissions on bedrock_server executable
        if [[ -f "$server_path/bedrock_server" ]]; then
            chmod +x "$server_path/bedrock_server"
        fi

        # Remove temporary rollback directory if restore was successful
        if [[ -d "${server_path}.rollback-"* ]]; then
            rm -rf "${server_path}.rollback-"*
        fi

        return 0
    else
        log_error "Failed to extract backup"

        # Restore from temp backup if available
        if [[ -d "${server_path}.rollback-"* ]]; then
            log_warning "Restoring from temporary backup"
            mv "${server_path}.rollback-"* "$server_path"
        fi

        return 1
    fi
}

#
# Get the most recent backup for a server
# Arguments:
#   $1 - Server name
#   $2 - Backup directory (optional)
# Returns:
#   Path to most recent backup file, or empty if none found
#
get_latest_backup() {
    local server_name="$1"
    local backup_dir="${2:-$BACKUP_DIR}"

    if [[ -z "$server_name" ]]; then
        log_error "Server name required"
        return 1
    fi

    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup directory does not exist: $backup_dir"
        return 1
    fi

    # Find most recent backup file for this server
    local latest_backup
    latest_backup=$(find "$backup_dir" -name "backup-${server_name}-*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2-)

    if [[ -n "$latest_backup" ]]; then
        echo "$latest_backup"
        return 0
    else
        log_warning "No backup found for server: $server_name"
        return 1
    fi
}

#
# Cleanup old backups
# Arguments:
#   $1 - Backup directory
#   $2 - Retention days
# Returns:
#   0 on success, 1 on failure
#
cleanup_old_backups() {
    local backup_dir="${1:-$BACKUP_DIR}"
    local retention_days="${2:-$BACKUP_RETENTION_DAYS}"

    if [[ ! -d "$backup_dir" ]]; then
        log_warning "Backup directory does not exist: $backup_dir"
        return 1
    fi

    log_info "Cleaning up backups older than $retention_days days in $backup_dir"

    local deleted_count=0
    local total_size=0

    # Find and delete old backup files
    while IFS= read -r -d '' backup_file; do
        local file_size
        file_size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null)
        total_size=$((total_size + file_size))

        rm -f "$backup_file"
        ((deleted_count++))
        log_debug "Deleted old backup: $backup_file"
    done < <(find "$backup_dir" -name "backup-*.tar.gz" -type f -mtime +"$retention_days" -print0 2>/dev/null)

    if [[ $deleted_count -gt 0 ]]; then
        local size_mb=$((total_size / 1024 / 1024))
        log_info "Deleted $deleted_count old backup(s), freed ${size_mb} MB"
    else
        log_debug "No old backups to delete"
    fi

    return 0
}

#
# List all backups for a server
# Arguments:
#   $1 - Server name
#   $2 - Backup directory (optional)
# Returns:
#   List of backup files with details
#
list_backups() {
    local server_name="$1"
    local backup_dir="${2:-$BACKUP_DIR}"

    if [[ -z "$server_name" ]]; then
        log_error "Server name required"
        return 1
    fi

    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup directory does not exist: $backup_dir"
        return 1
    fi

    log_info "Backups for server: $server_name"
    log_info "Directory: $backup_dir"
    log_separator

    local backup_count=0

    while IFS= read -r backup_file; do
        if [[ -f "$backup_file" ]]; then
            ((backup_count++))

            local file_size
            file_size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null)
            local size_mb=$((file_size / 1024 / 1024))

            local file_date
            file_date=$(stat -c %y "$backup_file" 2>/dev/null || stat -f %Sm -t "%Y-%m-%d %H:%M:%S" "$backup_file" 2>/dev/null)

            echo "File: $(basename "$backup_file")"
            echo "Size: ${size_mb} MB"
            echo "Date: $file_date"
            echo "---"
        fi
    done < <(find "$backup_dir" -name "backup-${server_name}-*.tar.gz" -type f | sort -r)

    log_info "Total backups: $backup_count"
    return 0
}

#
# Get total size of all backups
# Arguments:
#   $1 - Backup directory (optional)
# Returns:
#   Total size in bytes
#
get_backup_total_size() {
    local backup_dir="${1:-$BACKUP_DIR}"

    if [[ ! -d "$backup_dir" ]]; then
        echo "0"
        return 1
    fi

    local total_size=0

    while IFS= read -r backup_file; do
        local file_size
        file_size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null)
        total_size=$((total_size + file_size))
    done < <(find "$backup_dir" -name "backup-*.tar.gz" -type f)

    echo "$total_size"
    return 0
}

#
# Verify backup integrity
# Arguments:
#   $1 - Backup file path
# Returns:
#   0 if valid, 1 if corrupted
#
verify_backup() {
    local backup_file="$1"

    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file does not exist: $backup_file"
        return 1
    fi

    log_debug "Verifying backup: $backup_file"

    # Test tar.gz integrity
    if tar -tzf "$backup_file" >/dev/null 2>&1; then
        log_debug "Backup verification successful"
        return 0
    else
        log_error "Backup file is corrupted: $backup_file"
        return 1
    fi
}
