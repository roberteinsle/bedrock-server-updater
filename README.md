# Minecraft Bedrock Server Updater

Automatisches Update-System für Minecraft Bedrock Server, die über Crafty Controller verwaltet werden.

## Features

- Automatische Update-Erkennung von offiziellen Minecraft Bedrock Server Releases
- Integration mit Crafty Controller API für sicheres Server-Management
- Vollständige Backups vor jedem Update
- Preservation von Konfigurationsdateien und Spielerdaten
- Automatischer Rollback bei Fehlern
- E-Mail-Benachrichtigungen (Success/Failure)
- Umfassendes Logging
- Cronjob-Integration für automatische tägliche Updates

## Voraussetzungen

- Linux System (Ubuntu/Debian empfohlen)
- Crafty Controller 4.7.0 oder höher
- Bash 4.0+
- jq (JSON processor)
- curl
- tar

## Quick Start

```bash
# Repository klonen
cd /opt
git clone https://github.com/roberteinsle/bedrock-server-updater.git
cd bedrock-server-updater

# Installationsscript ausführen
sudo ./install.sh

# Konfiguration anpassen
sudo nano .env

# Ersten Test durchführen
sudo ./update-bedrock.sh --dry-run
```

## Konfiguration

Kopieren Sie `.env.example` zu `.env` und passen Sie die Werte an:

```bash
cp .env.example .env
nano .env
```

### Erforderliche Konfiguration:

- **CRAFTY_API_URL**: URL Ihrer Crafty Controller Instanz
- **CRAFTY_API_TOKEN**: API Token von Crafty Controller
- **SMTP_HOST**: SMTP Server für E-Mail-Benachrichtigungen
- **SMTP_USER**: SMTP Benutzername
- **SMTP_PASSWORD**: SMTP Passwort
- **SMTP_TO**: E-Mail-Adresse für Benachrichtigungen

Siehe [docs/CONFIGURATION.md](docs/CONFIGURATION.md) für Details.

## Server-Konfiguration

Die zu verwaltenden Minecraft Server werden in [config/server-list.json](config/server-list.json) definiert:

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

## Verwendung

### Manueller Update-Check

```bash
sudo /opt/bedrock-server-updater/update-bedrock.sh
```

### Dry-Run (Test ohne Änderungen)

```bash
sudo /opt/bedrock-server-updater/update-bedrock.sh --dry-run
```

### Automatische Updates via Cronjob

Das Installationsscript richtet automatisch einen täglichen Cronjob ein. Sie können die Zeit anpassen:

```bash
sudo crontab -e

# Beispiel: Täglich um 3:00 Uhr
0 3 * * * /opt/bedrock-server-updater/update-bedrock.sh
```

## Sicherheit

- Alle Credentials werden in `.env` gespeichert (nicht in Git)
- `.env` Datei hat Permissions 600 (nur Owner)
- API-Tokens und Passwörter werden niemals geloggt
- Backups werden mit restrictive Permissions gespeichert

## Fehlerbehandlung

Das Script implementiert mehrere Sicherheitsmechanismen:

1. **Backup vor jedem Update**: Vollständiges Backup aller Server
2. **Automatischer Rollback**: Bei Fehlern wird die alte Version wiederhergestellt
3. **E-Mail-Benachrichtigungen**: Admins werden über Erfolg/Fehler informiert
4. **Umfassendes Logging**: Alle Aktionen werden protokolliert

## Datei-Preservation

Folgende Dateien werden während Updates NICHT überschrieben:

- `allowlist.json` - Whitelist
- `packetlimitconfig.json` - Netzwerk-Einstellungen
- `permissions.json` - Spielerrechte
- `profanity_filter.wlist` - Wortfilter
- `server.properties` - Server-Konfiguration
- Verzeichnisse: `worlds/`, `behavior_packs/`, `resource_packs/`, `config/`, `definitions/`

## Logs

Logs werden gespeichert in:
- `/opt/bedrock-server-updater/logs/update-YYYY-MM-DD.log`
- Automatische Log-Rotation nach 30 Tagen

## Backups

Backups werden gespeichert in:
- `/opt/bedrock-server-updater/backups/backup-SERVERNAME-YYYY-MM-DD-HHmmss.tar.gz`
- Standard Retention: 7 Tage (konfigurierbar)

## Dokumentation

- [Installation Guide](docs/INSTALLATION.md)
- [Configuration Guide](docs/CONFIGURATION.md)
- [Crafty API Integration](docs/API.md)

## Troubleshooting

### Script startet nicht
```bash
# Permissions prüfen
ls -la /opt/bedrock-server-updater/update-bedrock.sh

# Ausführbar machen
chmod +x /opt/bedrock-server-updater/update-bedrock.sh
```

### E-Mails werden nicht gesendet
```bash
# SMTP-Einstellungen in .env prüfen
cat /opt/bedrock-server-updater/.env

# Manuellen E-Mail-Test durchführen
source /opt/bedrock-server-updater/lib/notification.sh
send_email "Test" "This is a test email"
```

### Crafty API Fehler
```bash
# API Token prüfen
curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://your-crafty-url/api/v2/servers
```

## Lizenz

MIT License - siehe [LICENSE](LICENSE)

## Autor

Robert Einsle - [robert@einsle.com](mailto:robert@einsle.com)

## Contributing

Pull Requests sind willkommen! Bitte öffnen Sie zuerst ein Issue, um größere Änderungen zu besprechen.

## Support

Bei Problemen oder Fragen öffnen Sie bitte ein [GitHub Issue](https://github.com/roberteinsle/bedrock-server-updater/issues).
