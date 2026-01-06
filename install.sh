#!/bin/bash
#
# install.sh - Installation script for Bedrock Server Updater
# Sets up the updater on a Linux system
#

set -euo pipefail

# Colors for output
readonly COLOR_RESET='\033[0m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_BLUE='\033[0;34m'

# Installation configuration
INSTALL_DIR="/opt/bedrock-server-updater"
INTERACTIVE=true

#
# Print colored message
#
print_info() {
    echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} $*"
}

print_warning() {
    echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} $*"
}

print_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*"
}

print_step() {
    echo -e "\n${COLOR_BLUE}==>${COLOR_RESET} $*"
}

#
# Check if running as root
#
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

#
# Check system requirements
#
check_requirements() {
    print_step "Checking system requirements..."

    local missing_tools=()

    # Check for required commands
    local required_tools=("curl" "tar" "jq" "unzip")

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_info "Installing missing tools..."

        # Detect package manager
        if command -v apt-get &>/dev/null; then
            apt-get update
            apt-get install -y "${missing_tools[@]}"
        elif command -v yum &>/dev/null; then
            yum install -y "${missing_tools[@]}"
        elif command -v dnf &>/dev/null; then
            dnf install -y "${missing_tools[@]}"
        else
            print_error "Could not detect package manager. Please install manually: ${missing_tools[*]}"
            exit 1
        fi

        print_info "Tools installed successfully"
    else
        print_info "All required tools are installed"
    fi

    # Check for optional email tools
    if ! command -v sendmail &>/dev/null && ! command -v msmtp &>/dev/null; then
        print_warning "No mail client found (sendmail/msmtp)"
        print_warning "Email notifications will use curl SMTP (basic functionality)"
    fi
}

#
# Create directory structure
#
create_directories() {
    print_step "Creating directory structure..."

    # Get script directory (where install.sh is located)
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # If not already in target directory, copy files
    if [[ "$script_dir" != "$INSTALL_DIR" ]]; then
        print_info "Copying files to $INSTALL_DIR..."

        # Create installation directory
        mkdir -p "$INSTALL_DIR"

        # Copy all files
        cp -r "$script_dir"/* "$INSTALL_DIR/"

        print_info "Files copied successfully"
    else
        print_info "Already in installation directory"
    fi

    # Create subdirectories
    print_info "Creating subdirectories..."
    mkdir -p "$INSTALL_DIR/logs"
    mkdir -p "$INSTALL_DIR/backups"
    mkdir -p "$INSTALL_DIR/temp"

    # Set permissions
    chmod 755 "$INSTALL_DIR"
    chmod 700 "$INSTALL_DIR/logs"
    chmod 700 "$INSTALL_DIR/backups"
    chmod 700 "$INSTALL_DIR/temp"

    # Make scripts executable
    chmod +x "$INSTALL_DIR/update-bedrock.sh"
    chmod +x "$INSTALL_DIR/install.sh"
    find "$INSTALL_DIR/lib" -name "*.sh" -exec chmod +x {} \;

    print_info "Directory structure created"
}

#
# Create configuration file
#
create_config() {
    print_step "Setting up configuration..."

    local env_file="$INSTALL_DIR/.env"

    if [[ -f "$env_file" ]]; then
        print_warning "Configuration file already exists: $env_file"
        if [[ "$INTERACTIVE" == "true" ]]; then
            read -p "Do you want to overwrite it? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Keeping existing configuration"
                return 0
            fi
        else
            print_info "Keeping existing configuration (use --force to overwrite)"
            return 0
        fi
    fi

    # Copy example config
    if [[ -f "$INSTALL_DIR/.env.example" ]]; then
        cp "$INSTALL_DIR/.env.example" "$env_file"
        chmod 600 "$env_file"
        print_info "Created configuration file: $env_file"

        if [[ "$INTERACTIVE" == "true" ]]; then
            configure_interactive
        else
            print_warning "Configuration file created with default values"
            print_warning "Please edit $env_file before running the updater"
        fi
    else
        print_error "Example configuration file not found"
        return 1
    fi
}

#
# Interactive configuration
#
configure_interactive() {
    print_step "Interactive configuration..."

    local env_file="$INSTALL_DIR/.env"

    print_info "Please enter the following configuration details:"
    print_info "(Press Enter to keep default values shown in brackets)"
    echo ""

    # Crafty API configuration
    read -p "Crafty Controller API URL: " -r crafty_url
    if [[ -n "$crafty_url" ]]; then
        sed -i "s|CRAFTY_API_URL=.*|CRAFTY_API_URL=$crafty_url|" "$env_file"
    fi

    read -p "Crafty Controller API Token: " -r crafty_token
    if [[ -n "$crafty_token" ]]; then
        sed -i "s|CRAFTY_API_TOKEN=.*|CRAFTY_API_TOKEN=$crafty_token|" "$env_file"
    fi

    echo ""
    read -p "Configure email notifications? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "SMTP Host: " -r smtp_host
        if [[ -n "$smtp_host" ]]; then
            sed -i "s|SMTP_HOST=.*|SMTP_HOST=$smtp_host|" "$env_file"
        fi

        read -p "SMTP Port [587]: " -r smtp_port
        smtp_port=${smtp_port:-587}
        sed -i "s|SMTP_PORT=.*|SMTP_PORT=$smtp_port|" "$env_file"

        read -p "SMTP User: " -r smtp_user
        if [[ -n "$smtp_user" ]]; then
            sed -i "s|SMTP_USER=.*|SMTP_USER=$smtp_user|" "$env_file"
        fi

        read -s -p "SMTP Password: " -r smtp_password
        echo ""
        if [[ -n "$smtp_password" ]]; then
            sed -i "s|SMTP_PASSWORD=.*|SMTP_PASSWORD=$smtp_password|" "$env_file"
        fi

        read -p "Email From: " -r smtp_from
        if [[ -n "$smtp_from" ]]; then
            sed -i "s|SMTP_FROM=.*|SMTP_FROM=$smtp_from|" "$env_file"
        fi

        read -p "Email To (notification recipient): " -r smtp_to
        if [[ -n "$smtp_to" ]]; then
            sed -i "s|SMTP_TO=.*|SMTP_TO=$smtp_to|" "$env_file"
        fi
    fi

    echo ""
    # Update paths in config
    sed -i "s|BACKUP_DIR=.*|BACKUP_DIR=$INSTALL_DIR/backups|" "$env_file"
    sed -i "s|LOG_DIR=.*|LOG_DIR=$INSTALL_DIR/logs|" "$env_file"

    print_info "Configuration saved"
}

#
# Setup cron job
#
setup_cron() {
    print_step "Setting up cron job..."

    if [[ "$INTERACTIVE" != "true" ]]; then
        print_info "Skipping cron setup in non-interactive mode"
        print_info "To setup cron manually, add this line to crontab:"
        print_info "  0 3 * * * $INSTALL_DIR/update-bedrock.sh"
        return 0
    fi

    read -p "Do you want to setup a daily cron job? (Y/n): " -r
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_info "Skipping cron setup"
        print_info "To setup cron manually later:"
        print_info "  sudo crontab -e"
        print_info "  Add: 0 3 * * * $INSTALL_DIR/update-bedrock.sh"
        return 0
    fi

    # Ask for cron schedule
    print_info "When should the update check run?"
    print_info "Examples:"
    print_info "  1) Daily at 3:00 AM (recommended)"
    print_info "  2) Daily at 6:00 AM"
    print_info "  3) Custom schedule"

    read -p "Choose option [1]: " -r schedule_choice
    schedule_choice=${schedule_choice:-1}

    local cron_schedule
    case "$schedule_choice" in
        1)
            cron_schedule="0 3 * * *"
            ;;
        2)
            cron_schedule="0 6 * * *"
            ;;
        3)
            read -p "Enter cron schedule (e.g., '0 3 * * *'): " -r cron_schedule
            ;;
        *)
            cron_schedule="0 3 * * *"
            ;;
    esac

    # Add to crontab
    local cron_cmd="$cron_schedule $INSTALL_DIR/update-bedrock.sh >> $INSTALL_DIR/logs/cron.log 2>&1"

    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "update-bedrock.sh"; then
        print_warning "Cron job already exists"
        read -p "Do you want to update it? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Remove old entry and add new one
            (crontab -l 2>/dev/null | grep -v "update-bedrock.sh"; echo "$cron_cmd") | crontab -
            print_info "Cron job updated"
        fi
    else
        # Add new cron job
        (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
        print_info "Cron job added: $cron_schedule"
    fi
}

#
# Run test
#
run_test() {
    print_step "Running test..."

    if [[ "$INTERACTIVE" != "true" ]]; then
        print_info "Skipping test in non-interactive mode"
        return 0
    fi

    read -p "Do you want to run a test (dry-run)? (Y/n): " -r
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_info "Skipping test"
        return 0
    fi

    print_info "Running dry-run test..."
    if "$INSTALL_DIR/update-bedrock.sh" --dry-run; then
        print_info "Test completed successfully"
    else
        print_error "Test failed. Please check the configuration and logs."
        return 1
    fi
}

#
# Print installation summary
#
print_summary() {
    echo ""
    echo "========================================================================"
    echo ""
    echo -e "${COLOR_GREEN}Installation completed successfully!${COLOR_RESET}"
    echo ""
    echo "Installation directory: $INSTALL_DIR"
    echo "Configuration file: $INSTALL_DIR/.env"
    echo "Log directory: $INSTALL_DIR/logs"
    echo "Backup directory: $INSTALL_DIR/backups"
    echo ""
    echo "Next steps:"
    echo "1. Edit configuration: nano $INSTALL_DIR/.env"
    echo "2. Test the updater: $INSTALL_DIR/update-bedrock.sh --dry-run"
    echo "3. Run manual update: $INSTALL_DIR/update-bedrock.sh"
    echo ""
    echo "The cron job will automatically check for updates daily."
    echo ""
    echo "For more information, see the README.md file."
    echo ""
    echo "========================================================================"
    echo ""
}

#
# Main installation
#
main() {
    echo ""
    echo "========================================================================"
    echo "  Minecraft Bedrock Server Updater - Installation"
    echo "========================================================================"
    echo ""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --non-interactive)
                INTERACTIVE=false
                shift
                ;;
            --dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                echo "Usage: $0 [--non-interactive] [--dir /path/to/install]"
                exit 1
                ;;
        esac
    done

    # Run installation steps
    check_root
    check_requirements
    create_directories
    create_config
    setup_cron
    run_test
    print_summary

    exit 0
}

# Run main function
main "$@"
