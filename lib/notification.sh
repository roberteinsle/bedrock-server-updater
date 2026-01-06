#!/bin/bash
#
# notification.sh - Email notification functions
# Sends email notifications via SMTP
#

#
# Send email via SMTP using curl
# Arguments:
#   $1 - Subject
#   $2 - Body (plain text or HTML)
#   $3 - Content type (optional, defaults to plain)
# Returns:
#   0 on success, 1 on failure
#
send_email() {
    local subject="$1"
    local body="$2"
    local content_type="${3:-plain}"

    if [[ -z "$subject" ]] || [[ -z "$body" ]]; then
        log_error "Subject and body required for email"
        return 1
    fi

    # Check SMTP configuration
    if [[ -z "$SMTP_HOST" ]] || [[ -z "$SMTP_PORT" ]] || [[ -z "$SMTP_USER" ]] || [[ -z "$SMTP_FROM" ]] || [[ -z "$SMTP_TO" ]]; then
        log_error "SMTP configuration incomplete"
        return 1
    fi

    log_info "Sending email notification..."
    log_debug "To: $SMTP_TO"
    log_debug "Subject: $subject"

    # Create temporary file for email body
    local email_file
    email_file=$(mktemp)

    # Build email headers and body
    {
        echo "From: $SMTP_FROM"
        echo "To: $SMTP_TO"
        echo "Subject: $subject"
        echo "Date: $(date -R)"

        if [[ "$content_type" == "html" ]]; then
            echo "Content-Type: text/html; charset=UTF-8"
        else
            echo "Content-Type: text/plain; charset=UTF-8"
        fi

        echo ""
        echo "$body"
    } > "$email_file"

    # Determine SMTP URL
    local smtp_url
    if [[ "${SMTP_USE_TLS,,}" == "true" ]]; then
        smtp_url="smtp://${SMTP_HOST}:${SMTP_PORT}"
    else
        smtp_url="smtp://${SMTP_HOST}:${SMTP_PORT}"
    fi

    # Send email using curl
    local curl_cmd=(
        curl
        --silent
        --mail-from "$SMTP_FROM"
        --mail-rcpt "$SMTP_TO"
        --upload-file "$email_file"
        --user "${SMTP_USER}:${SMTP_PASSWORD}"
    )

    # Add TLS option if enabled
    if [[ "${SMTP_USE_TLS,,}" == "true" ]]; then
        curl_cmd+=(--ssl-reqd)
    fi

    curl_cmd+=("$smtp_url")

    # Execute curl command
    if "${curl_cmd[@]}" 2>/dev/null; then
        log_info "Email sent successfully to: $SMTP_TO"
        rm -f "$email_file"
        return 0
    else
        log_error "Failed to send email"
        log_debug "Email content saved to: $email_file"
        return 1
    fi
}

#
# Send success notification
# Arguments:
#   $1 - Version updated to
#   $2 - List of updated servers (newline-separated)
# Returns:
#   0 on success, 1 on failure
#
send_success_notification() {
    local version="$1"
    local servers="$2"

    local subject="[Bedrock Updater] Update erfolgreich auf Version $version"

    local body
    body=$(cat <<EOF
Minecraft Bedrock Server Update erfolgreich abgeschlossen

================================================================================

Neue Version: $version
Datum: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)

Aktualisierte Server:
$servers

Status: Alle Server sind wieder online und laufen mit der neuen Version.

Log-Datei: $LOG_FILE

================================================================================

Dies ist eine automatische Benachrichtigung vom Bedrock Server Updater.
EOF
)

    send_email "$subject" "$body" "plain"
}

#
# Send failure notification
# Arguments:
#   $1 - Error message
#   $2 - Phase where error occurred
#   $3 - Affected servers (optional)
# Returns:
#   0 on success, 1 on failure
#
send_failure_notification() {
    local error_message="$1"
    local phase="$2"
    local affected_servers="${3:-N/A}"

    local subject="[Bedrock Updater] ⚠️ Update fehlgeschlagen"

    local body
    body=$(cat <<EOF
Minecraft Bedrock Server Update ist fehlgeschlagen!

================================================================================

Fehler: $error_message
Phase: $phase
Datum: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)

Betroffene Server:
$affected_servers

Aktion: Rollback wurde durchgeführt (falls möglich)
Status: Server sollten mit der vorherigen Version laufen

WICHTIG: Bitte überprüfen Sie die Server manuell!

Log-Datei: $LOG_FILE

================================================================================

Dies ist eine automatische Benachrichtigung vom Bedrock Server Updater.
Bitte prüfen Sie die Server und Log-Dateien für weitere Details.
EOF
)

    send_email "$subject" "$body" "plain"
}

#
# Send warning notification
# Arguments:
#   $1 - Warning message
#   $2 - Details
# Returns:
#   0 on success, 1 on failure
#
send_warning_notification() {
    local warning_message="$1"
    local details="$2"

    local subject="[Bedrock Updater] ⚠️ Warnung"

    local body
    body=$(cat <<EOF
Minecraft Bedrock Server Updater - Warnung

================================================================================

Warnung: $warning_message
Datum: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)

Details:
$details

Log-Datei: $LOG_FILE

================================================================================

Dies ist eine automatische Benachrichtigung vom Bedrock Server Updater.
EOF
)

    send_email "$subject" "$body" "plain"
}

#
# Send no update notification (optional, for debugging)
# Arguments:
#   $1 - Current version
# Returns:
#   0 on success, 1 on failure
#
send_no_update_notification() {
    local current_version="$1"

    local subject="[Bedrock Updater] Keine Updates verfügbar"

    local body
    body=$(cat <<EOF
Minecraft Bedrock Server Update Check

================================================================================

Status: Keine Updates verfügbar
Aktuelle Version: $current_version
Datum: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)

Die Server laufen bereits mit der neuesten Version.

Log-Datei: $LOG_FILE

================================================================================

Dies ist eine automatische Benachrichtigung vom Bedrock Server Updater.
EOF
)

    send_email "$subject" "$body" "plain"
}

#
# Send rollback notification
# Arguments:
#   $1 - Reason for rollback
#   $2 - Servers rolled back
# Returns:
#   0 on success, 1 on failure
#
send_rollback_notification() {
    local reason="$1"
    local servers="$2"

    local subject="[Bedrock Updater] 🔄 Rollback durchgeführt"

    local body
    body=$(cat <<EOF
Minecraft Bedrock Server Rollback durchgeführt

================================================================================

Grund: $reason
Datum: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)

Wiederhergestellte Server:
$servers

Status: Server wurden auf die vorherige Version zurückgesetzt
Aktion: Alle Server sollten wieder normal laufen

WICHTIG: Bitte überprüfen Sie die Server manuell!

Log-Datei: $LOG_FILE

================================================================================

Dies ist eine automatische Benachrichtigung vom Bedrock Server Updater.
Das Update wurde rückgängig gemacht und die Server laufen mit der vorherigen Version.
EOF
)

    send_email "$subject" "$body" "plain"
}

#
# Send test email
# Returns:
#   0 on success, 1 on failure
#
send_test_email() {
    local subject="[Bedrock Updater] Test E-Mail"

    local body
    body=$(cat <<EOF
Minecraft Bedrock Server Updater - Test E-Mail

================================================================================

Dies ist eine Test-E-Mail vom Bedrock Server Updater.

Konfiguration:
- SMTP Host: $SMTP_HOST
- SMTP Port: $SMTP_PORT
- SMTP User: $SMTP_USER
- From: $SMTP_FROM
- To: $SMTP_TO
- TLS: $SMTP_USE_TLS

Datum: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)

Wenn Sie diese E-Mail erhalten, ist die E-Mail-Konfiguration korrekt eingerichtet.

================================================================================

Dies ist eine Test-Benachrichtigung vom Bedrock Server Updater.
EOF
)

    send_email "$subject" "$body" "plain"
}

#
# Format server list for email
# Arguments:
#   None (uses configured servers)
# Returns:
#   Formatted server list with status
#
format_server_list() {
    local server_names
    server_names=$(get_server_names)

    local output=""

    for server_name in $server_names; do
        local server_id
        server_id=$(get_server_id "$server_name")

        # Try to get server status
        local status="Unknown"
        if crafty_is_server_running "$server_id" 2>/dev/null; then
            status="✓ Running"
        else
            status="✗ Stopped"
        fi

        output+="  - $server_name: $status\n"
    done

    echo -e "$output"
}

#
# Send comprehensive update report
# Arguments:
#   $1 - Status (success/failure/warning)
#   $2 - Old version
#   $3 - New version
#   $4 - Details/Error message
# Returns:
#   0 on success, 1 on failure
#
send_update_report() {
    local status="$1"
    local old_version="$2"
    local new_version="$3"
    local details="$4"

    case "$status" in
        success)
            local servers
            servers=$(format_server_list)
            send_success_notification "$new_version" "$servers"
            ;;
        failure)
            send_failure_notification "$details" "Update" "$(get_server_names | tr '\n' ', ')"
            ;;
        warning)
            send_warning_notification "Update completed with warnings" "$details"
            ;;
        *)
            log_error "Unknown status for update report: $status"
            return 1
            ;;
    esac
}
