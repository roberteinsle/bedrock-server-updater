#!/bin/bash
#
# version-check.sh - Minecraft Bedrock Server version detection
# Checks for updates from official Minecraft website
#

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source platform helpers if not already sourced
if [[ -f "${SCRIPT_DIR}/lib/platform.sh" ]] && ! declare -f is_linux &>/dev/null; then
    # shellcheck source=lib/platform.sh
    source "${SCRIPT_DIR}/lib/platform.sh"
fi

# Minecraft Bedrock Server API endpoint for download links
readonly BEDROCK_API_ENDPOINT="https://net-secondary.web.minecraft-services.net/api/v1.0/download/links"

#
# Get current installed version from Crafty Controller API
# Arguments:
#   $1 - Server ID (from Crafty)
# Returns:
#   Version string (e.g., "1.21.131.1") or "0.0.0.0" if unknown
#
get_current_version() {
    local server_id="$1"

    # In dev mode, return mock version
    if is_dev_mode; then
        log_warning "Dev mode: Returning mock version 0.0.0.0"
        echo "0.0.0.0"
        return 0
    fi

    log_debug "Getting version for server ID: $server_id"

    # Get server status from Crafty API
    local response
    if ! response=$(crafty_get_server_status "$server_id" 2>/dev/null); then
        log_warning "Could not get server status from Crafty API"
        log_info "Assuming version 0.0.0.0 to trigger update"
        echo "0.0.0.0"
        return 0
    fi

    # Extract version from API response
    # Expected path: .data.version or similar
    local version
    version=$(echo "$response" | jq -r '.data.version // .data.server_version // empty' 2>/dev/null)

    # Validate version format (must be numbers and dots, like 1.21.131)
    if [[ -n "$version" ]] && [[ "$version" != "null" ]] && [[ "$version" != "false" ]] && [[ "$version" != "true" ]]; then
        # Check if version matches expected format (numbers and dots)
        if [[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
            log_debug "Current version detected from Crafty API: $version"
            echo "$version"
            return 0
        else
            log_warning "Invalid version format from Crafty API: $version"
        fi
    else
        log_warning "Could not detect version from Crafty API response"
    fi

    log_info "Assuming version 0.0.0.0 to trigger update"
    echo "0.0.0.0"
    return 0
}

#
# Get latest Bedrock Server version and download URL
# Returns:
#   JSON object with version and url, or empty on failure
#   Format: {"version": "1.20.51.01", "url": "https://..."}
#
get_latest_version_info() {
    log_info "Checking for latest Minecraft Bedrock Server version..."

    local temp_file
    temp_file=$(mktemp)

    # Download from Minecraft API endpoint (returns JSON with download links)
    # This is more reliable than HTML scraping
    if ! curl -s -L --max-time 30 "$BEDROCK_API_ENDPOINT" -o "$temp_file"; then
        log_error "Failed to download from Minecraft API"
        rm -f "$temp_file"
        return 1
    fi

    # Verify file was downloaded and has content
    if [[ ! -s "$temp_file" ]]; then
        log_error "Downloaded file is empty"
        rm -f "$temp_file"
        return 1
    fi

    # Check if jq is available
    if ! command -v jq &>/dev/null; then
        log_error "jq is not installed - required for JSON parsing"
        rm -f "$temp_file"
        return 1
    fi

    # Validate JSON before parsing
    if ! jq empty "$temp_file" 2>/dev/null; then
        log_error "Downloaded content is not valid JSON"
        log_debug "Content: $(cat "$temp_file")"
        rm -f "$temp_file"
        return 1
    fi

    # Extract Linux download URL from JSON
    # API returns: {"result": {"links": [{"downloadType": "serverBedrockLinux", "downloadUrl": "..."}]}}
    local download_url
    download_url=$(jq -r '.result.links[] | select(.downloadType == "serverBedrockLinux") | .downloadUrl' "$temp_file")

    if [[ -z "$download_url" ]]; then
        log_error "Could not find Linux download URL in API response"
        log_debug "API response saved to: $temp_file"
        rm -f "$temp_file"
        return 1
    fi

    # Extract version from URL
    local version
    version=$(echo "$download_url" | grep -oP 'bedrock-server-\K[0-9.]+(?=\.zip)')

    if [[ -z "$version" ]]; then
        log_error "Could not extract version from download URL: $download_url"
        rm -f "$temp_file"
        return 1
    fi

    rm -f "$temp_file"

    log_info "Latest version found: $version"
    log_debug "Download URL: $download_url"

    # Return JSON
    echo "{\"version\": \"$version\", \"url\": \"$download_url\"}"
    return 0
}

#
# Compare two version strings
# Arguments:
#   $1 - Version 1
#   $2 - Version 2
# Returns:
#   0 if versions are equal
#   1 if version 1 is less than version 2
#   2 if version 1 is greater than version 2
#
compare_versions() {
    local ver1="$1"
    local ver2="$2"

    if [[ "$ver1" == "$ver2" ]]; then
        return 0
    fi

    # Split versions into arrays
    IFS='.' read -ra ver1_parts <<< "$ver1"
    IFS='.' read -ra ver2_parts <<< "$ver2"

    # Compare each part
    local max_parts=${#ver1_parts[@]}
    if [[ ${#ver2_parts[@]} -gt $max_parts ]]; then
        max_parts=${#ver2_parts[@]}
    fi

    for ((i=0; i<max_parts; i++)); do
        local part1=${ver1_parts[$i]:-0}
        local part2=${ver2_parts[$i]:-0}

        if [[ $part1 -lt $part2 ]]; then
            return 1
        elif [[ $part1 -gt $part2 ]]; then
            return 2
        fi
    done

    return 0
}

#
# Check if update is available
# Arguments:
#   $1 - Current version
#   $2 - Latest version
# Returns:
#   0 if update available, 1 if not, 2 on error
#
is_update_available() {
    local current="$1"
    local latest="$2"

    if [[ -z "$current" ]] || [[ -z "$latest" ]]; then
        log_error "Invalid version comparison: current='$current', latest='$latest'"
        return 2
    fi

    compare_versions "$current" "$latest"
    local result=$?

    if [[ $result -eq 1 ]]; then
        log_info "Update available: $current -> $latest"
        return 0
    elif [[ $result -eq 0 ]]; then
        log_info "Already up to date: $current"
        return 1
    else
        log_info "Current version is newer than available: $current > $latest"
        return 1
    fi
}

#
# Download Bedrock Server
# Arguments:
#   $1 - Download URL
#   $2 - Destination file path
# Returns:
#   0 on success, 1 on failure
#
download_bedrock_server() {
    local url="$1"
    local dest="$2"

    if [[ -z "$url" ]] || [[ -z "$dest" ]]; then
        log_error "URL and destination required for download"
        return 1
    fi

    log_info "Downloading Bedrock Server from: $url"
    log_info "Destination: $dest"

    # Create destination directory if needed
    local dest_dir
    dest_dir=$(dirname "$dest")
    if [[ ! -d "$dest_dir" ]]; then
        mkdir -p "$dest_dir" || {
            log_error "Failed to create destination directory: $dest_dir"
            return 1
        }
    fi

    # Download with progress
    if ! curl -L --max-time "$DOWNLOAD_TIMEOUT" --progress-bar "$url" -o "$dest"; then
        log_error "Download failed"
        rm -f "$dest"
        return 1
    fi

    # Verify download
    if [[ ! -f "$dest" ]]; then
        log_error "Downloaded file does not exist: $dest"
        return 1
    fi

    local file_size
    file_size=$(get_file_size "$dest")

    if [[ -z "$file_size" ]] || [[ $file_size -lt 1000000 ]]; then
        log_error "Downloaded file is too small (${file_size:-0} bytes), possibly corrupted"
        rm -f "$dest"
        return 1
    fi

    log_info "Download successful (Size: $((file_size / 1024 / 1024)) MB)"

    # Verify it's a valid zip file
    if ! unzip -t "$dest" &>/dev/null; then
        log_error "Downloaded file is not a valid zip archive"
        rm -f "$dest"
        return 1
    fi

    log_info "Download verified successfully"
    return 0
}

#
# Extract Bedrock Server archive
# Arguments:
#   $1 - Archive path (.zip)
#   $2 - Destination directory
# Returns:
#   0 on success, 1 on failure
#
extract_bedrock_server() {
    local archive="$1"
    local dest_dir="$2"

    if [[ ! -f "$archive" ]]; then
        log_error "Archive file not found: $archive"
        return 1
    fi

    if [[ -z "$dest_dir" ]]; then
        log_error "Destination directory required"
        return 1
    fi

    log_info "Extracting Bedrock Server to: $dest_dir"

    # Create destination directory
    if [[ ! -d "$dest_dir" ]]; then
        mkdir -p "$dest_dir" || {
            log_error "Failed to create destination directory: $dest_dir"
            return 1
        }
    fi

    # Extract archive
    if ! unzip -q -o "$archive" -d "$dest_dir"; then
        log_error "Failed to extract archive"
        return 1
    fi

    log_info "Extraction successful"

    # Set executable permission on bedrock_server
    if [[ -f "$dest_dir/bedrock_server" ]]; then
        chmod +x "$dest_dir/bedrock_server"
        log_debug "Set executable permission on bedrock_server"
    fi

    return 0
}

#
# Get version from archive without extracting
# Arguments:
#   $1 - Archive path (.zip)
# Returns:
#   Version string or empty on failure
#
get_version_from_archive() {
    local archive="$1"

    if [[ ! -f "$archive" ]]; then
        log_error "Archive file not found: $archive"
        return 1
    fi

    # Try to extract release-notes.txt to temp location
    local temp_dir
    temp_dir=$(mktemp -d)

    if unzip -q -j "$archive" "release-notes.txt" -d "$temp_dir" 2>/dev/null; then
        local version
        version=$(head -n 10 "$temp_dir/release-notes.txt" | grep -oP '\b[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?\b' | head -n1)
        rm -rf "$temp_dir"

        if [[ -n "$version" ]]; then
            echo "$version"
            return 0
        fi
    fi

    rm -rf "$temp_dir"
    return 1
}
