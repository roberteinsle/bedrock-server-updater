#!/bin/bash
#
# update-server.sh - Server update functions
# Handles the actual update process for Bedrock servers
#

#
# Update a single server with new Bedrock version
# Arguments:
#   $1 - Server name
#   $2 - Server path
#   $3 - New version archive path (.zip)
# Returns:
#   0 on success, 1 on failure
#
update_single_server() {
    local server_name="$1"
    local server_path="$2"
    local new_archive="$3"

    if [[ -z "$server_name" ]] || [[ -z "$server_path" ]] || [[ -z "$new_archive" ]]; then
        log_error "Server name, path, and archive required for update"
        return 1
    fi

    if [[ ! -d "$server_path" ]]; then
        log_error "Server directory does not exist: $server_path"
        return 1
    fi

    if [[ ! -f "$new_archive" ]]; then
        log_error "Archive file not found: $new_archive"
        return 1
    fi

    log_info "Updating server: $server_name"
    log_info "Server path: $server_path"

    # Create temporary extraction directory
    local temp_dir
    temp_dir=$(mktemp -d)

    if [[ ! -d "$temp_dir" ]]; then
        log_error "Failed to create temporary directory"
        return 1
    fi

    log_debug "Temporary directory: $temp_dir"

    # Extract new version to temp directory
    log_info "Extracting new version..."
    if ! extract_bedrock_server "$new_archive" "$temp_dir"; then
        log_error "Failed to extract new version"
        rm -rf "$temp_dir"
        return 1
    fi

    # Get list of files that can be updated
    local update_files
    mapfile -t update_files < <(get_update_files)

    if [[ ${#update_files[@]} -eq 0 ]]; then
        log_error "No update files defined in configuration"
        rm -rf "$temp_dir"
        return 1
    fi

    # Copy updateable files to server directory
    log_info "Copying updated files..."
    local updated_count=0
    local failed_files=()

    for file in "${update_files[@]}"; do
        local src="$temp_dir/$file"
        local dst="$server_path/$file"

        if [[ -f "$src" ]]; then
            log_debug "Updating file: $file"

            # Backup existing file if it exists
            if [[ -f "$dst" ]]; then
                cp -p "$dst" "$dst.old" || {
                    log_warning "Failed to backup existing file: $file"
                }
            fi

            # Copy new file
            if cp -f "$src" "$dst"; then
                ((updated_count++))

                # Set executable permission for bedrock_server
                if [[ "$file" == "bedrock_server" ]]; then
                    chmod +x "$dst"
                    log_debug "Set executable permission on bedrock_server"
                fi

                # Remove backup if copy was successful
                rm -f "$dst.old"
            else
                log_error "Failed to copy file: $file"
                failed_files+=("$file")

                # Restore from backup if available
                if [[ -f "$dst.old" ]]; then
                    mv "$dst.old" "$dst"
                    log_warning "Restored original file: $file"
                fi
            fi
        else
            log_warning "File not found in new version: $file"
        fi
    done

    # Cleanup temporary directory
    rm -rf "$temp_dir"

    # Check if update was successful
    if [[ ${#failed_files[@]} -gt 0 ]]; then
        log_error "Failed to update ${#failed_files[@]} file(s): ${failed_files[*]}"
        return 1
    fi

    log_info "Successfully updated $updated_count file(s) for server: $server_name"
    return 0
}

#
# Update all configured servers
# Arguments:
#   $1 - New version archive path (.zip)
# Returns:
#   0 if all servers updated successfully, 1 if any failed
#
update_all_servers() {
    local new_archive="$1"

    if [[ -z "$new_archive" ]]; then
        log_error "Archive path required"
        return 1
    fi

    if [[ ! -f "$new_archive" ]]; then
        log_error "Archive file not found: $new_archive"
        return 1
    fi

    log_info "Updating all servers with new version..."

    local failed_servers=()
    local server_names
    server_names=$(get_server_names)

    for server_name in $server_names; do
        local server_path
        server_path=$(get_server_path "$server_name")

        log_info "Updating server: $server_name"

        if update_single_server "$server_name" "$server_path" "$new_archive"; then
            log_info "Successfully updated: $server_name"
        else
            log_error "Failed to update: $server_name"
            failed_servers+=("$server_name")
        fi
    done

    if [[ ${#failed_servers[@]} -gt 0 ]]; then
        log_error "Failed to update ${#failed_servers[@]} server(s): ${failed_servers[*]}"
        return 1
    fi

    log_info "All servers updated successfully"
    return 0
}

#
# Verify server files after update
# Arguments:
#   $1 - Server path
# Returns:
#   0 if verification passes, 1 if issues found
#
verify_server_files() {
    local server_path="$1"

    if [[ ! -d "$server_path" ]]; then
        log_error "Server directory does not exist: $server_path"
        return 1
    fi

    log_debug "Verifying server files in: $server_path"

    local issues=0

    # Check if bedrock_server exists and is executable
    if [[ ! -f "$server_path/bedrock_server" ]]; then
        log_error "bedrock_server not found"
        ((issues++))
    elif [[ ! -x "$server_path/bedrock_server" ]]; then
        log_error "bedrock_server is not executable"
        ((issues++))
    fi

    # Check if server.properties exists (required config file)
    if [[ ! -f "$server_path/server.properties" ]]; then
        log_warning "server.properties not found (may be first-time setup)"
    fi

    # Check if worlds directory exists
    if [[ ! -d "$server_path/worlds" ]]; then
        log_warning "worlds directory not found (may be first-time setup)"
    fi

    if [[ $issues -gt 0 ]]; then
        log_error "Server verification failed with $issues issue(s)"
        return 1
    fi

    log_debug "Server verification passed"
    return 0
}

#
# Rollback a server to previous backup
# Arguments:
#   $1 - Server name
#   $2 - Server path
#   $3 - Backup file (optional, uses latest if not provided)
# Returns:
#   0 on success, 1 on failure
#
rollback_server() {
    local server_name="$1"
    local server_path="$2"
    local backup_file="${3:-}"

    if [[ -z "$server_name" ]] || [[ -z "$server_path" ]]; then
        log_error "Server name and path required for rollback"
        return 1
    fi

    # Get latest backup if not specified
    if [[ -z "$backup_file" ]]; then
        backup_file=$(get_latest_backup "$server_name")

        if [[ -z "$backup_file" ]]; then
            log_error "No backup found for rollback: $server_name"
            return 1
        fi
    fi

    log_warning "Rolling back server: $server_name"
    log_info "Using backup: $backup_file"

    # Verify backup before restoring
    if ! verify_backup "$backup_file"; then
        log_error "Backup verification failed, cannot rollback"
        return 1
    fi

    # Restore from backup
    if restore_backup "$backup_file" "$server_path"; then
        log_info "Rollback successful: $server_name"
        return 0
    else
        log_error "Rollback failed: $server_name"
        return 1
    fi
}

#
# Rollback all servers to their latest backups
# Returns:
#   0 if all rollbacks successful, 1 if any failed
#
rollback_all_servers() {
    log_warning "Rolling back all servers..."

    local failed_servers=()
    local server_names
    server_names=$(get_server_names)

    for server_name in $server_names; do
        local server_path
        server_path=$(get_server_path "$server_name")

        log_info "Rolling back server: $server_name"

        if rollback_server "$server_name" "$server_path"; then
            log_info "Rollback successful: $server_name"
        else
            log_error "Rollback failed: $server_name"
            failed_servers+=("$server_name")
        fi
    done

    if [[ ${#failed_servers[@]} -gt 0 ]]; then
        log_error "Failed to rollback ${#failed_servers[@]} server(s): ${failed_servers[*]}"
        return 1
    fi

    log_info "All servers rolled back successfully"
    return 0
}

#
# Check if preserved files still exist after update
# Arguments:
#   $1 - Server path
# Returns:
#   0 if all preserved files exist, 1 if any missing
#
check_preserved_files() {
    local server_path="$1"

    if [[ ! -d "$server_path" ]]; then
        log_error "Server directory does not exist: $server_path"
        return 1
    fi

    log_debug "Checking preserved files in: $server_path"

    local missing_files=()

    # Check preserved files
    local preserve_files
    mapfile -t preserve_files < <(get_preserve_files)

    for file in "${preserve_files[@]}"; do
        if [[ ! -f "$server_path/$file" ]]; then
            # Some files are optional, only warn
            log_debug "Preserved file not found (may not exist): $file"
        fi
    done

    # Check preserved directories
    local preserve_dirs
    mapfile -t preserve_dirs < <(get_preserve_directories)

    for dir in "${preserve_dirs[@]}"; do
        if [[ ! -d "$server_path/$dir" ]]; then
            log_debug "Preserved directory not found (may not exist): $dir"
        fi
    done

    return 0
}

#
# Create a pre-update snapshot of file checksums
# Arguments:
#   $1 - Server path
# Returns:
#   Path to checksum file
#
create_checksum_snapshot() {
    local server_path="$1"

    if [[ ! -d "$server_path" ]]; then
        log_error "Server directory does not exist: $server_path"
        return 1
    fi

    local checksum_file
    checksum_file=$(mktemp)

    log_debug "Creating checksum snapshot: $checksum_file"

    # Create checksums for all preserved files
    local preserve_files
    mapfile -t preserve_files < <(get_preserve_files)

    for file in "${preserve_files[@]}"; do
        if [[ -f "$server_path/$file" ]]; then
            md5sum "$server_path/$file" 2>/dev/null >> "$checksum_file" || true
        fi
    done

    echo "$checksum_file"
    return 0
}

#
# Verify preserved files haven't changed
# Arguments:
#   $1 - Server path
#   $2 - Checksum file from create_checksum_snapshot
# Returns:
#   0 if no changes, 1 if changes detected
#
verify_preserved_files() {
    local server_path="$1"
    local checksum_file="$2"

    if [[ ! -f "$checksum_file" ]]; then
        log_error "Checksum file not found: $checksum_file"
        return 1
    fi

    log_debug "Verifying preserved files against snapshot"

    # Check checksums
    if md5sum -c "$checksum_file" --quiet 2>/dev/null; then
        log_debug "All preserved files intact"
        rm -f "$checksum_file"
        return 0
    else
        log_error "Some preserved files have changed!"
        rm -f "$checksum_file"
        return 1
    fi
}
