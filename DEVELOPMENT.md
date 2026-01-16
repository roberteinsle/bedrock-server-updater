# Development Guide

This guide is for developers working on the Bedrock Server Updater codebase.

## Development Environment Setup

### Windows (Recommended for Development)

1. Install Git for Windows (includes Git Bash)
2. Install jq (JSON processor):
   ```bash
   # Download from https://stedolan.github.io/jq/download/
   # Or use Chocolatey: choco install jq
   ```

3. Clone the repository:
   ```bash
   cd /c/Users/your-username/Projects
   git clone https://github.com/roberteinsle/bedrock-server-updater.git
   cd bedrock-server-updater
   ```

4. Create a test `.env` file (optional for local testing):
   ```bash
   cp .env.example .env
   # Edit .env with dummy values if you want to test config loading
   ```

### Linux (Production Environment)

Follow the installation instructions in the main README.md.

## Development Workflow

### 1. Local Development (Windows)

The script automatically detects Windows and enables **Development Mode**, which:
- Skips Crafty API connection tests
- Allows non-existent server paths
- Returns mock data (version 0.0.0.0)
- Skips Linux-only binary executions
- Uses cross-platform file operations

**Testing locally:**

```bash
# Syntax check (always run this first!)
bash -n update-bedrock.sh
bash -n lib/*.sh

# Validate JSON configuration
jq empty config/server-list.json

# Test dry-run (dev mode auto-enabled on Windows)
./update-bedrock.sh --dry-run --verbose

# Explicit dev mode (works on any platform)
DEV_MODE=true ./update-bedrock.sh --dry-run --verbose
```

### 2. Git Workflow

```bash
# Create feature branch
git checkout -b feature/your-feature-name

# Make changes
# ... edit files ...

# Check syntax
bash -n update-bedrock.sh lib/*.sh

# Test locally
./update-bedrock.sh --dry-run --verbose

# Commit changes
git add .
git commit -m "Description of changes"

# Push to GitHub
git push origin feature/your-feature-name
```

### 3. Deployment to Server

```bash
# SSH to your Linux server
ssh user@your-server.com

# Navigate to installation directory
cd /opt/bedrock-server-updater

# Pull latest changes
sudo git pull

# Test on server (NOT dev mode - real environment)
sudo ./update-bedrock.sh --dry-run --verbose

# If tests pass, run for real
sudo ./update-bedrock.sh
```

## Platform-Specific Code

### Adding New Platform-Compatible Features

When adding functionality that may differ between operating systems:

1. **Import platform helpers:**
   ```bash
   # At the top of your library file
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

   if [[ -f "${SCRIPT_DIR}/lib/platform.sh" ]] && ! declare -f is_linux &>/dev/null; then
       source "${SCRIPT_DIR}/lib/platform.sh"
   fi
   ```

2. **Use platform detection:**
   ```bash
   # Check if running on Linux
   if is_linux; then
       # Linux-specific code
       some_linux_command
   fi

   # Check if in dev mode (Windows or DEV_MODE=true)
   if is_dev_mode; then
       log_warning "Dev mode: Skipping production check"
       return 0
   fi
   ```

3. **Use cross-platform helpers:**
   ```bash
   # Instead of direct stat commands:
   file_size=$(get_file_size "$file_path")
   permissions=$(get_file_permissions "$file_path")
   ```

### Platform Helper Functions

Available in [lib/platform.sh](lib/platform.sh):

- `detect_os()` - Returns: Linux, macOS, Windows, or Unknown
- `is_linux()` - True if running on Linux
- `is_windows()` - True if running on Windows (Git Bash, MINGW, etc.)
- `is_macos()` - True if running on macOS
- `is_dev_mode()` - True if DEV_MODE=true or running on Windows
- `get_file_size(file)` - Cross-platform file size
- `get_file_permissions(file)` - Cross-platform permissions
- `print_platform_info()` - Log platform details
- `warn_if_not_linux()` - Warn if not on Linux, auto-enable dev mode on Windows

## Testing Checklist

Before pushing code:

- [ ] Syntax check passes: `bash -n update-bedrock.sh lib/*.sh`
- [ ] JSON validation passes: `jq empty config/server-list.json`
- [ ] Local dry-run succeeds: `./update-bedrock.sh --dry-run --verbose`
- [ ] ShellCheck passes (if available): `shellcheck update-bedrock.sh lib/*.sh`
- [ ] Changes documented in commit message
- [ ] CLAUDE.md updated if architecture changed
- [ ] Tested on Linux server with `--dry-run` before production

## Common Development Tasks

### Adding a New Configuration Option

1. Add to `.env.example` with comment
2. Add to `validate_env_config()` in [lib/config.sh](lib/config.sh) if required
3. Document in [docs/CONFIGURATION.md](docs/CONFIGURATION.md)
4. Update CLAUDE.md if it affects architecture

### Adding a New Library Module

1. Create `lib/your-module.sh`
2. Add source line in [update-bedrock.sh](update-bedrock.sh)
3. Follow existing patterns (error handling, logging, etc.)
4. Import platform.sh if needed for OS-specific code
5. Update CLAUDE.md with module description

### Modifying Version Detection

All version detection is in [lib/version-check.sh](lib/version-check.sh):
- `get_current_version()` - Detect installed version (3 methods)
- `get_latest_version_info()` - Scrape Mojang download page
- `compare_versions()` - Version comparison logic

When testing version detection locally on Windows, the script will return mock version "0.0.0.0" if server paths don't exist.

### Debugging

Enable verbose logging:
```bash
./update-bedrock.sh --dry-run --verbose
```

Check logs:
```bash
# On Linux server
tail -f /opt/bedrock-server-updater/logs/update-$(date +%Y-%m-%d).log

# On Windows (local)
tail -f logs/update-$(date +%Y-%m-%d).log
```

Set DEBUG log level in `.env`:
```bash
LOG_LEVEL=DEBUG
```

## Code Style Guidelines

- Use `set -euo pipefail` for strict error handling
- All functions return 0 on success, 1 on failure
- Use `log_debug`, `log_info`, `log_warning`, `log_error` for logging
- Never log sensitive data (tokens, passwords)
- Check return codes: `if ! function_name; then`
- Use shellcheck directives to suppress false positives
- Follow existing naming conventions (snake_case for functions)

## Security Considerations

- Never commit `.env` files (already in .gitignore)
- API tokens should have minimal permissions
- Use app passwords for SMTP, not account passwords
- Backups contain sensitive data - secure accordingly
- File permissions: `.env` should be 600 (owner only)

## Resources

- [Crafty Controller API Docs](docs/API.md)
- [Configuration Guide](docs/CONFIGURATION.md)
- [Installation Guide](docs/INSTALLATION.md)
- [CLAUDE.md](CLAUDE.md) - Architecture and development guide
- [ShellCheck](https://www.shellcheck.net/) - Shell script linter

## Getting Help

- Check existing issues: https://github.com/roberteinsle/bedrock-server-updater/issues
- Create new issue with:
  - OS and version
  - Error messages
  - Log excerpts (redact sensitive data!)
  - Steps to reproduce
