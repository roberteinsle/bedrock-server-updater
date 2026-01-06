#!/bin/bash
#
# crafty-api.sh - Crafty Controller API integration
# Provides functions to interact with Crafty Controller REST API
#

#
# Make an API call to Crafty Controller
# Arguments:
#   $1 - HTTP method (GET, POST, PUT, DELETE)
#   $2 - API endpoint (e.g., /api/v2/servers)
#   $3 - Request body (optional, JSON string)
# Returns:
#   0 on success, 1 on failure
#   Outputs response body to stdout
#
crafty_api_call() {
    local method="$1"
    local endpoint="$2"
    local body="${3:-}"

    if [[ -z "$CRAFTY_API_URL" ]] || [[ -z "$CRAFTY_API_TOKEN" ]]; then
        log_error "Crafty API credentials not configured"
        return 1
    fi

    # Remove leading slash from endpoint if present
    endpoint="${endpoint#/}"

    local url="${CRAFTY_API_URL}/${endpoint}"
    local response_file
    response_file=$(mktemp)
    local http_code_file
    http_code_file=$(mktemp)

    log_debug "API Call: $method $url"

    # Build curl command
    local curl_cmd=(
        curl
        -s
        -X "$method"
        -H "Authorization: Bearer ${CRAFTY_API_TOKEN}"
        -H "Content-Type: application/json"
        -H "Accept: application/json"
        -w "%{http_code}"
        -o "$response_file"
    )

    # Add request body if provided
    if [[ -n "$body" ]]; then
        curl_cmd+=(-d "$body")
        log_debug "Request body: $body"
    fi

    # Add URL
    curl_cmd+=("$url")

    # Execute curl command
    local http_code
    http_code=$("${curl_cmd[@]}" 2>/dev/null)
    local curl_exit=$?

    # Read response
    local response
    response=$(<"$response_file")

    # Cleanup temp files
    rm -f "$response_file" "$http_code_file"

    # Check curl execution
    if [[ $curl_exit -ne 0 ]]; then
        log_error "API call failed: curl exit code $curl_exit"
        return 1
    fi

    # Check HTTP status code
    if [[ "$http_code" =~ ^2 ]]; then
        log_debug "API call successful: HTTP $http_code"
        echo "$response"
        return 0
    else
        log_error "API call failed: HTTP $http_code"
        log_error "Response: $response"
        return 1
    fi
}

#
# Get server status
# Arguments:
#   $1 - Server ID
# Returns:
#   0 on success, 1 on failure
#   Outputs JSON response with server stats
#
crafty_get_server_status() {
    local server_id="$1"

    if [[ -z "$server_id" ]]; then
        log_error "Server ID required"
        return 1
    fi

    log_debug "Getting status for server: $server_id"

    local response
    response=$(crafty_api_call "GET" "api/v2/servers/${server_id}/stats")
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo "$response"
        return 0
    else
        return 1
    fi
}

#
# Check if server is running
# Arguments:
#   $1 - Server ID
# Returns:
#   0 if running, 1 if stopped or error
#
crafty_is_server_running() {
    local server_id="$1"

    local response
    response=$(crafty_get_server_status "$server_id")

    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # Parse running status from JSON
    local running
    running=$(echo "$response" | jq -r '.data.running // false' 2>/dev/null)

    if [[ "$running" == "true" ]]; then
        log_debug "Server $server_id is running"
        return 0
    else
        log_debug "Server $server_id is not running"
        return 1
    fi
}

#
# Stop a server
# Arguments:
#   $1 - Server ID
# Returns:
#   0 on success, 1 on failure
#
crafty_stop_server() {
    local server_id="$1"

    if [[ -z "$server_id" ]]; then
        log_error "Server ID required"
        return 1
    fi

    log_info "Stopping server: $server_id"

    # Check if already stopped
    if ! crafty_is_server_running "$server_id"; then
        log_info "Server already stopped: $server_id"
        return 0
    fi

    local response
    response=$(crafty_api_call "POST" "api/v2/servers/${server_id}/action/stop_server")
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Stop command sent successfully for server: $server_id"

        # Wait for server to stop
        local timeout=$SERVER_TIMEOUT
        local elapsed=0

        while [[ $elapsed -lt $timeout ]]; do
            sleep 2
            elapsed=$((elapsed + 2))

            if ! crafty_is_server_running "$server_id"; then
                log_info "Server stopped successfully: $server_id"
                return 0
            fi

            log_debug "Waiting for server to stop... ($elapsed/$timeout seconds)"
        done

        log_warning "Server did not stop within $timeout seconds: $server_id"
        return 1
    else
        log_error "Failed to stop server: $server_id"
        return 1
    fi
}

#
# Start a server
# Arguments:
#   $1 - Server ID
# Returns:
#   0 on success, 1 on failure
#
crafty_start_server() {
    local server_id="$1"

    if [[ -z "$server_id" ]]; then
        log_error "Server ID required"
        return 1
    fi

    log_info "Starting server: $server_id"

    # Check if already running
    if crafty_is_server_running "$server_id"; then
        log_info "Server already running: $server_id"
        return 0
    fi

    local response
    response=$(crafty_api_call "POST" "api/v2/servers/${server_id}/action/start_server")
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Start command sent successfully for server: $server_id"

        # Wait for server to start
        local timeout=$SERVER_TIMEOUT
        local elapsed=0

        while [[ $elapsed -lt $timeout ]]; do
            sleep 2
            elapsed=$((elapsed + 2))

            if crafty_is_server_running "$server_id"; then
                log_info "Server started successfully: $server_id"
                return 0
            fi

            log_debug "Waiting for server to start... ($elapsed/$timeout seconds)"
        done

        log_warning "Server did not start within $timeout seconds: $server_id"
        return 1
    else
        log_error "Failed to start server: $server_id"
        return 1
    fi
}

#
# Restart a server
# Arguments:
#   $1 - Server ID
# Returns:
#   0 on success, 1 on failure
#
crafty_restart_server() {
    local server_id="$1"

    if [[ -z "$server_id" ]]; then
        log_error "Server ID required"
        return 1
    fi

    log_info "Restarting server: $server_id"

    # Stop server
    if ! crafty_stop_server "$server_id"; then
        log_error "Failed to stop server during restart: $server_id"
        return 1
    fi

    # Start server
    if ! crafty_start_server "$server_id"; then
        log_error "Failed to start server during restart: $server_id"
        return 1
    fi

    log_info "Server restarted successfully: $server_id"
    return 0
}

#
# Stop all configured servers
# Returns:
#   0 if all servers stopped successfully, 1 if any failed
#
crafty_stop_all_servers() {
    log_info "Stopping all configured servers..."

    local failed_servers=()
    local server_names
    server_names=$(get_server_names)

    for server_name in $server_names; do
        local server_id
        server_id=$(get_server_id "$server_name")

        log_info "Stopping server: $server_name (ID: $server_id)"

        if ! crafty_stop_server "$server_id"; then
            log_error "Failed to stop server: $server_name"
            failed_servers+=("$server_name")
        fi
    done

    if [[ ${#failed_servers[@]} -gt 0 ]]; then
        log_error "Failed to stop ${#failed_servers[@]} server(s): ${failed_servers[*]}"
        return 1
    fi

    log_info "All servers stopped successfully"
    return 0
}

#
# Start all configured servers
# Returns:
#   0 if all servers started successfully, 1 if any failed
#
crafty_start_all_servers() {
    log_info "Starting all configured servers..."

    local failed_servers=()
    local server_names
    server_names=$(get_server_names)

    for server_name in $server_names; do
        local server_id
        server_id=$(get_server_id "$server_name")

        log_info "Starting server: $server_name (ID: $server_id)"

        if ! crafty_start_server "$server_id"; then
            log_error "Failed to start server: $server_name"
            failed_servers+=("$server_name")
        fi
    done

    if [[ ${#failed_servers[@]} -gt 0 ]]; then
        log_error "Failed to start ${#failed_servers[@]} server(s): ${failed_servers[*]}"
        return 1
    fi

    log_info "All servers started successfully"
    return 0
}

#
# Get server info (name, status, etc.)
# Arguments:
#   $1 - Server ID
# Returns:
#   0 on success, 1 on failure
#   Outputs formatted server information
#
crafty_get_server_info() {
    local server_id="$1"

    local response
    response=$(crafty_get_server_status "$server_id")

    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # Parse relevant information
    local running
    running=$(echo "$response" | jq -r '.data.running // "unknown"')
    local cpu
    cpu=$(echo "$response" | jq -r '.data.cpu // "N/A"')
    local mem
    mem=$(echo "$response" | jq -r '.data.mem // "N/A"')

    echo "Server ID: $server_id"
    echo "Running: $running"
    echo "CPU: $cpu%"
    echo "Memory: $mem MB"

    return 0
}

#
# Test Crafty API connection
# Returns:
#   0 on success, 1 on failure
#
crafty_test_connection() {
    log_info "Testing Crafty Controller API connection..."

    local response
    response=$(crafty_api_call "GET" "api/v2/servers")
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "API connection successful"
        return 0
    else
        log_error "API connection failed"
        return 1
    fi
}
