# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Automated update system for Minecraft Bedrock Dedicated Servers managed through Crafty Controller. Written in Bash with a modular library architecture. The system checks for new Bedrock server releases, creates backups, applies updates via Crafty Controller's REST API, and sends email notifications.

## Key Commands

### Testing and Development
```bash
# Test update process without making changes
sudo ./update-bedrock.sh --dry-run

# Run with verbose logging for debugging
sudo ./update-bedrock.sh --verbose

# Force update even if version is the same
sudo ./update-bedrock.sh --force

# Initial installation (sets up directories, cronjob, dependencies)
sudo ./install.sh
```

### Local Testing on Windows (Development)
```bash
# The script auto-detects Windows (Git Bash/MINGW) and enables dev mode
# Dev mode skips API checks, allows non-existent server paths, and uses mock data

# Syntax validation without running
bash -n update-bedrock.sh
bash -n lib/*.sh

# Test configuration loading (will auto-enable dev mode on Windows)
./update-bedrock.sh --dry-run --verbose

# Explicit dev mode (useful on any platform for testing)
DEV_MODE=true ./update-bedrock.sh --dry-run --verbose

# Validate JSON configuration
jq empty config/server-list.json
```

### Configuration
```bash
# Create configuration from template
cp .env.example .env

# Edit main configuration (API tokens, SMTP, paths, timeouts)
nano .env

# Edit server definitions (server UUIDs, paths, preserved files)
nano config/server-list.json

# Validate configuration
sudo ./update-bedrock.sh --dry-run --verbose
```

### Testing Individual Components
```bash
# Test Crafty API connection
source lib/config.sh && source lib/crafty-api.sh && init_config && crafty_test_connection

# Test SMTP email notifications
source lib/notification.sh && source lib/config.sh && init_config && send_email "Test" "Test message"

# Validate JSON configuration
jq empty config/server-list.json
```

### Log and Backup Management
```bash
# View latest log
tail -f logs/update-$(date +%Y-%m-%d).log

# List all backups
ls -lh backups/

# Restore from backup (manual process)
tar -xzf backups/backup-SERVERNAME-YYYY-MM-DD-HHmmss.tar.gz -C /tmp/
```

## Architecture

### Platform Support and Development Mode

The codebase includes cross-platform compatibility for development:

- **Production Environment**: Linux servers with Crafty Controller
- **Development Environment**: Windows (Git Bash/MINGW), macOS, or Linux
- **Auto-Detection**: [lib/platform.sh](lib/platform.sh) detects OS and enables dev mode on Windows automatically
- **Dev Mode Features**:
  - Skips Crafty API connection tests
  - Allows non-existent server paths (returns mock version 0.0.0.0)
  - Bypasses Linux-specific commands (e.g., bedrock_server binary execution)
  - Skips file permission checks on Windows
  - Uses cross-platform stat commands via helper functions

**Platform Functions**:
- `is_linux()`, `is_windows()`, `is_macos()`: OS detection
- `is_dev_mode()`: Returns true on Windows or when DEV_MODE=true
- `get_file_size()`, `get_file_permissions()`: Cross-platform file operations
- `warn_if_not_linux()`: Displays warning and auto-enables dev mode on non-Linux systems

### Execution Flow (6 Phases)

The main script ([update-bedrock.sh](update-bedrock.sh)) orchestrates a strict 6-phase update process:

1. **Version Check**: Query current server version and check Mojang's official download page for latest release
2. **Pre-Update**: Stop all servers via Crafty API, create tar.gz backups of each server directory
3. **Download**: Download new bedrock-server.zip from Mojang to temp directory
4. **Update**: Extract and apply updates to each server while preserving config files and world data
5. **Post-Update**: Start servers, wait for stabilization, verify all servers are running
6. **Cleanup**: Remove old backups/logs based on retention settings, send success notification

At any failure point, the script attempts automatic rollback from backups and restarts servers.

### Modular Library System

All logic is separated into focused library modules in [lib/](lib/):

- **[platform.sh](lib/platform.sh)** (~150 lines): OS detection, cross-platform compatibility helpers, dev mode support
- **[config.sh](lib/config.sh)** (321 lines): Loads `.env` and `server-list.json`, validates configuration, provides getters for server info (name, ID, path)
- **[crafty-api.sh](lib/crafty-api.sh)** (409 lines): REST API client for Crafty Controller - makes authenticated curl calls, manages server start/stop/status operations
- **[version-check.sh](lib/version-check.sh)** (323 lines): Scrapes Mojang's download page for latest Bedrock version and download URL, compares version numbers
- **[backup.sh](lib/backup.sh)** (386 lines): Creates tar.gz backups with timestamps, stores rollback metadata, handles cleanup of old backups
- **[update-server.sh](lib/update-server.sh)** (412 lines): Extracts new server files, preserves configured files/directories, performs rollback on failure
- **[notification.sh](lib/notification.sh)** (401 lines): Sends HTML emails via SMTP using curl, provides templates for success/failure/rollback notifications
- **[logger.sh](lib/logger.sh)** (225 lines): Structured logging with levels (DEBUG/INFO/WARNING/ERROR), file rotation, script start/end markers

### Configuration System

**[.env](.env.example)** - Environment variables:
- `CRAFTY_API_URL`, `CRAFTY_API_TOKEN`: Crafty Controller API credentials
- `SMTP_*`: Email notification settings (host, port, user, password, TLS)
- `BACKUP_DIR`, `BACKUP_RETENTION_DAYS`: Backup storage and cleanup
- `LOG_DIR`, `LOG_LEVEL`, `LOG_RETENTION_DAYS`: Logging configuration
- `SERVER_TIMEOUT`, `SERVER_START_WAIT`, `DOWNLOAD_TIMEOUT`: Operation timeouts
- `DRY_RUN`: Test mode flag

**[config/server-list.json](config/server-list.json)** - Server definitions:
- `servers[]`: Array of servers with `name`, `id` (Crafty UUID), `path` (absolute path to server directory)
- `preserve_files[]`: Config files never overwritten (allowlist.json, permissions.json, server.properties, etc.)
- `preserve_directories[]`: Directories never touched (worlds/, behavior_packs/, resource_packs/, etc.)
- `update_files[]`: Specific files to update (bedrock_server binary, release-notes.txt, etc.)

### Exit Codes

The main script returns specific exit codes for different failure scenarios:
- `0`: Success (update applied or no update needed)
- `1`: Configuration/initialization error
- `2`: Backup creation failed
- `3`: Download failed
- `4`: Update application failed
- `5`: Server failed to start after update (rollback performed)

### Rollback Mechanism

On any failure during update or post-update phases:
1. Stop all servers via Crafty API
2. Extract backup tar.gz files back to original server paths
3. Restart all servers
4. Send rollback notification email
5. Exit with appropriate error code

Backups are stored as `backup-SERVERNAME-YYYY-MM-DD-HHmmss.tar.gz` and include metadata for identification.

## Development Considerations

### Windows Development Workflow

The typical development workflow when working on Windows:

1. **Edit code** on Windows using any editor
2. **Local syntax check**: `bash -n update-bedrock.sh`
3. **Local dry-run test** (auto dev mode): `./update-bedrock.sh --dry-run --verbose`
4. **Commit and push**: `git add . && git commit -m "..." && git push`
5. **Deploy on server**: SSH to Linux server, `git pull`
6. **Test on server**: `sudo ./update-bedrock.sh --dry-run`
7. **Run for real**: `sudo ./update-bedrock.sh`

Dev mode automatically:
- Skips Crafty API tests that would fail without server access
- Returns mock versions (0.0.0.0) for non-existent server paths
- Skips Linux-only commands that hang on Windows
- Uses cross-platform file operations

### When Modifying API Calls

All Crafty API interactions go through `crafty_api_call()` in [lib/crafty-api.sh](lib/crafty-api.sh). It handles:
- Bearer token authentication headers
- Response parsing and HTTP code validation
- Temporary file management for responses
- Debug logging of requests/responses

API token requires permissions: `servers:read`, `servers:start`, `servers:stop`.

### When Adding New Preserved Files

Edit [config/server-list.json](config/server-list.json):
- Add to `preserve_files[]` for individual files
- Add to `preserve_directories[]` for entire directories
- These are consulted by `update_server()` in [lib/update-server.sh](lib/update-server.sh)

### When Changing Update Logic

The update process in [lib/update-server.sh](lib/update-server.sh):
1. Extracts new server files to temp directory
2. Iterates through each server path
3. Copies ONLY files in `update_files[]` from extraction to server directory
4. Leaves all `preserve_files[]` and `preserve_directories[]` untouched
5. Sets execute permissions on bedrock_server binary

Any changes must maintain this preservation behavior to avoid data loss.

### Logging Best Practices

Use the logger functions from [lib/logger.sh](lib/logger.sh):
- `log_debug()`: Detailed info only shown with --verbose
- `log_info()`: Normal operation status updates
- `log_warning()`: Non-fatal issues (e.g., insecure permissions)
- `log_error()`: Fatal errors that prevent continuation
- `log_separator()`: Visual separators between phases

Never log sensitive data (API tokens, SMTP passwords, etc.).

### Error Handling

The main script uses `set -euo pipefail` for strict error handling:
- All library functions return 0 on success, 1 on failure
- Check return codes with `if ! function_name; then`
- Use `trap cleanup EXIT INT TERM` for cleanup on any exit
- Always log errors before returning non-zero

### Testing Approach

Before modifying core logic:
1. **Local (Windows)**: Run `bash -n` for syntax, then `./update-bedrock.sh --dry-run` (dev mode auto-enabled)
2. **Server (Linux)**: Run with `--dry-run` to test version checking and API connectivity
3. Test on a single non-production server first
4. Use `--verbose` to see detailed operation flow including platform detection
5. Check logs in `logs/update-YYYY-MM-DD.log` for any warnings
6. Verify backup creation works before testing actual updates

### Adding Platform-Specific Code

When adding new functionality that may differ by OS:
1. Source [lib/platform.sh](lib/platform.sh) at the top of your library file
2. Use `is_linux()`, `is_windows()`, `is_dev_mode()` for conditional logic
3. Use helper functions like `get_file_size()` instead of direct `stat` calls
4. Test behavior on both Windows (dev) and Linux (production)

## Required Environment

- **Platform**: Linux (Ubuntu/Debian recommended, but supports RHEL/CentOS)
- **Crafty Controller**: 4.7.0 or higher with API enabled
- **Dependencies**: bash 4.0+, curl, jq, tar, unzip
- **Permissions**: Script must run as root (uses sudo for server file operations)
- **Cronjob**: Typically runs daily via `/etc/cron.d/bedrock-updater`
