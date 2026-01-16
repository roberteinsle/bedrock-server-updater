# Minecraft Bedrock Server Updater

Automated update system for Minecraft Bedrock Servers managed through Crafty Controller.

## Features

- Automatic update detection from official Minecraft Bedrock Server releases
- Integration with Crafty Controller API for secure server management
- Full backups before every update
- Preservation of configuration files and player data
- Automatic rollback on errors
- Email notifications (success/failure)
- Comprehensive logging
- Cronjob integration for automatic daily updates

## Prerequisites

- Linux system (Ubuntu/Debian recommended)
- Crafty Controller 4.7.0 or higher
- Bash 4.0+
- jq (JSON processor)
- curl or wget
- tar

## Quick Start

```bash
# Clone repository
cd /opt
git clone https://github.com/roberteinsle/bedrock-server-updater.git
cd bedrock-server-updater

# Run installation script
sudo ./install.sh

# Adjust configuration
sudo nano .env

# Run first test
sudo ./update-bedrock.sh --dry-run
```

## Configuration

Copy `.env.example` to `.env` and adjust the values:

```bash
cp .env.example .env
nano .env
```

### Required Configuration:

- **CRAFTY_API_URL**: URL of your Crafty Controller instance
- **CRAFTY_API_TOKEN**: API token from Crafty Controller
- **SMTP_HOST**: SMTP server for email notifications
- **SMTP_USER**: SMTP username
- **SMTP_PASSWORD**: SMTP password
- **SMTP_TO**: Email address for notifications

See [docs/CONFIGURATION.md](docs/CONFIGURATION.md) for details.

## Server Configuration

The Minecraft servers to manage are defined in [config/server-list.json](config/server-list.json):

```json
{
  "servers": [
    {
      "name": "Server1",
      "id": "crafty-server-uuid",
      "path": "/crafty/servers/crafty-server-uuid"
    }
  ]
}
```

## Usage

### Manual Update Check

```bash
sudo /opt/bedrock-server-updater/update-bedrock.sh
```

### Dry-Run (Test without changes)

```bash
sudo /opt/bedrock-server-updater/update-bedrock.sh --dry-run
```

### Automatic Updates via Cronjob

The installation script automatically sets up a daily cronjob. You can adjust the time:

```bash
sudo crontab -e

# Example: Daily at 3:00 AM
0 3 * * * /opt/bedrock-server-updater/update-bedrock.sh
```

## Security

- All credentials are stored in `.env` (not in Git)
- `.env` file has permissions 600 (owner only)
- API tokens and passwords are never logged
- Backups are stored with restrictive permissions

## Error Handling

The script implements several safety mechanisms:

1. **Backup before every update**: Full backup of all servers
2. **Automatic rollback**: On errors, the old version is restored
3. **Email notifications**: Admins are notified of success/failure
4. **Comprehensive logging**: All actions are logged

## File Preservation

The following files are NOT overwritten during updates:

- `allowlist.json` - Whitelist
- `packetlimitconfig.json` - Network settings
- `permissions.json` - Player permissions
- `profanity_filter.wlist` - Word filter
- `server.properties` - Server configuration
- Directories: `worlds/`, `behavior_packs/`, `resource_packs/`, `config/`, `definitions/`

## Logs

Logs are stored in:
- `/opt/bedrock-server-updater/logs/update-YYYY-MM-DD.log`
- Automatic log rotation after 30 days

## Backups

Backups are stored in:
- `/opt/bedrock-server-updater/backups/backup-SERVERNAME-YYYY-MM-DD-HHmmss.tar.gz`
- Default retention: 7 days (configurable)

## Documentation

- [Installation Guide](docs/INSTALLATION.md)
- [Configuration Guide](docs/CONFIGURATION.md)
- [Crafty API Integration](docs/API.md)

## Troubleshooting

### Script won't start
```bash
# Check permissions
ls -la /opt/bedrock-server-updater/update-bedrock.sh

# Make executable
chmod +x /opt/bedrock-server-updater/update-bedrock.sh
```

### Emails not being sent
```bash
# Check SMTP settings in .env
cat /opt/bedrock-server-updater/.env

# Run manual email test
source /opt/bedrock-server-updater/lib/notification.sh
send_email "Test" "This is a test email"
```

### Crafty API errors
```bash
# Check API token
curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://your-crafty-url/api/v2/servers
```

## License

MIT License - see [LICENSE](LICENSE)

## Author

Robert Einsle - [robert@einsle.com](mailto:robert@einsle.com)

## Contributing

Pull requests are welcome! Please open an issue first to discuss major changes.

## Support

For problems or questions, please open a [GitHub Issue](https://github.com/roberteinsle/bedrock-server-updater/issues).
