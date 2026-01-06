# Konfigurations-Anleitung

Detaillierte Beschreibung aller Konfigurations-Optionen für den Bedrock Server Updater.

## Konfigurations-Dateien

Der Updater verwendet zwei Hauptkonfigurations-Dateien:

1. **`.env`** - Umgebungsvariablen und Credentials
2. **`config/server-list.json`** - Server-Definitionen

## .env Konfiguration

### Crafty Controller API

```bash
CRAFTY_API_URL=https://your-crafty-instance.com
CRAFTY_API_TOKEN=your-api-token-here
```

**CRAFTY_API_URL:**
- Vollständige URL zu Ihrer Crafty Controller Instanz
- Muss mit `http://` oder `https://` beginnen
- Kein Trailing-Slash am Ende

**CRAFTY_API_TOKEN:**
- API Token aus Crafty Controller (Settings > API)
- Token hat Form: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

### E-Mail Konfiguration

```bash
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=user@example.com
SMTP_PASSWORD=your-password
SMTP_FROM=bedrock-updater@example.com
SMTP_TO=admin@example.com
SMTP_USE_TLS=true
```

**SMTP_HOST:**
- Hostname oder IP des SMTP-Servers
- Beispiele: `smtp.gmail.com`, `smtp.office365.com`, `mail.yourdomain.com`

**SMTP_PORT:**
- Port des SMTP-Servers
- Übliche Werte: `25` (unencrypted), `587` (STARTTLS), `465` (SSL/TLS)

**SMTP_USER:**
- Benutzername für SMTP-Authentifizierung
- Meist die E-Mail-Adresse

**SMTP_PASSWORD:**
- Passwort für SMTP-Authentifizierung
- Bei Gmail: App-Passwort verwenden!

**SMTP_FROM:**
- Absender-Adresse für E-Mails
- Kann eine no-reply Adresse sein

**SMTP_TO:**
- Empfänger-Adresse für Benachrichtigungen
- Kann mehrere Adressen sein (kommagetrennt)

**SMTP_USE_TLS:**
- `true` - TLS/SSL verwenden (empfohlen)
- `false` - Unverschlüsselte Verbindung

### Backup Einstellungen

```bash
BACKUP_DIR=/opt/bedrock-server-updater/backups
BACKUP_RETENTION_DAYS=7
```

**BACKUP_DIR:**
- Verzeichnis für Backup-Speicherung
- Sollte genug Speicherplatz haben
- Standard: `/opt/bedrock-server-updater/backups`

**BACKUP_RETENTION_DAYS:**
- Anzahl Tage, die Backups behalten werden
- Ältere Backups werden automatisch gelöscht
- Standard: `7` (eine Woche)
- Empfohlen: 7-30 Tage

### Logging Einstellungen

```bash
LOG_DIR=/opt/bedrock-server-updater/logs
LOG_LEVEL=INFO
LOG_RETENTION_DAYS=30
```

**LOG_DIR:**
- Verzeichnis für Log-Dateien
- Standard: `/opt/bedrock-server-updater/logs`

**LOG_LEVEL:**
- Detailgrad der Logs
- Optionen: `DEBUG`, `INFO`, `WARNING`, `ERROR`
- Standard: `INFO`
- `DEBUG` für Fehlersuche, `ERROR` für Produktion

**LOG_RETENTION_DAYS:**
- Anzahl Tage, die Logs behalten werden
- Standard: `30` Tage

### Update Einstellungen

```bash
SERVER_TIMEOUT=30
SERVER_START_WAIT=20
DOWNLOAD_TIMEOUT=300
DRY_RUN=false
```

**SERVER_TIMEOUT:**
- Maximale Wartezeit (Sekunden) für Server Start/Stop
- Standard: `30` Sekunden
- Erhöhen bei langsamen Servern

**SERVER_START_WAIT:**
- Wartezeit nach Server-Start vor Status-Prüfung
- Standard: `20` Sekunden
- Bedrock Server brauchen Zeit zum Starten

**DOWNLOAD_TIMEOUT:**
- Maximale Download-Zeit (Sekunden)
- Standard: `300` (5 Minuten)
- Erhöhen bei langsamer Verbindung

**DRY_RUN:**
- `true` - Nur prüfen, keine Änderungen
- `false` - Normal ausführen
- Standard: `false`

## server-list.json Konfiguration

### Server Definition

```json
{
  "servers": [
    {
      "name": "ServerName",
      "id": "crafty-uuid",
      "path": "/crafty/servers/crafty-uuid"
    }
  ]
}
```

**name:**
- Freundlicher Name des Servers
- Wird in Logs und E-Mails verwendet
- Keine Leerzeichen empfohlen

**id:**
- Crafty Controller Server-UUID
- Format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`
- Zu finden in Crafty Controller

**path:**
- Absoluter Pfad zum Server-Verzeichnis
- Dort wo `bedrock_server` liegt
- Standard Crafty Pfad: `/crafty/servers/{uuid}`

### Mehrere Server

```json
{
  "servers": [
    {
      "name": "ToJo",
      "id": "6b7208be-109e-44b3-8206-3235bb3d9b1a",
      "path": "/crafty/servers/6b7208be-109e-44b3-8206-3235bb3d9b1a"
    },
    {
      "name": "JonasE",
      "id": "a0c97c73-f7f9-4904-a670-6403e8d314a1",
      "path": "/crafty/servers/a0c97c73-f7f9-4904-a670-6403e8d314a1"
    }
  ]
}
```

### Datei-Preservation

```json
{
  "preserve_files": [
    "allowlist.json",
    "packetlimitconfig.json",
    "permissions.json",
    "profanity_filter.wlist",
    "server.properties"
  ]
}
```

Diese Dateien werden **NIEMALS** überschrieben.

### Verzeichnis-Preservation

```json
{
  "preserve_directories": [
    "behavior_packs",
    "resource_packs",
    "config",
    "definitions",
    "worlds"
  ]
}
```

Diese Verzeichnisse werden **NIEMALS** überschrieben.

### Update-Dateien

```json
{
  "update_files": [
    "bedrock_server",
    "bedrock_server_how_to.html",
    "release-notes.txt"
  ]
}
```

**Nur** diese Dateien werden beim Update überschrieben.

## Erweiterte Konfiguration

### Mehrere E-Mail-Empfänger

```bash
SMTP_TO=admin1@example.com,admin2@example.com,admin3@example.com
```

### Unterschiedliche Backup-Retention pro Server

Aktuell global, aber kann erweitert werden:

```json
{
  "servers": [
    {
      "name": "ImportantServer",
      "backup_retention_days": 30
    }
  ]
}
```

### Custom Download URL

Falls Sie einen Mirror verwenden möchten, kann in `lib/version-check.sh` angepasst werden.

## Sicherheits-Empfehlungen

### .env Datei Berechtigungen

```bash
sudo chmod 600 /opt/bedrock-server-updater/.env
sudo chown root:root /opt/bedrock-server-updater/.env
```

Nur Root kann lesen/schreiben.

### API Token Sicherheit

- Erstellen Sie einen dedizierten API-Token in Crafty
- Verwenden Sie **nicht** Ihren Admin-Account Token
- Rotieren Sie Tokens regelmäßig

### SMTP Passwort Sicherheit

- Verwenden Sie bei Gmail/Outlook **App-Passwörter**
- Niemals Ihr Haupt-Passwort verwenden
- Erwägen Sie einen dedizierten SMTP-Account

### Backup Verschlüsselung

Optional können Backups verschlüsselt werden:

```bash
# Beispiel für GPG-Verschlüsselung
gpg --encrypt --recipient admin@example.com backup.tar.gz
```

Dies müsste in `lib/backup.sh` implementiert werden.

## Umgebungs-spezifische Konfiguration

### Entwicklung

```bash
LOG_LEVEL=DEBUG
DRY_RUN=true
BACKUP_RETENTION_DAYS=1
```

### Staging

```bash
LOG_LEVEL=INFO
DRY_RUN=false
BACKUP_RETENTION_DAYS=3
```

### Produktion

```bash
LOG_LEVEL=WARNING
DRY_RUN=false
BACKUP_RETENTION_DAYS=14
```

## Konfiguration validieren

```bash
# Script mit Dry-Run testen
sudo /opt/bedrock-server-updater/update-bedrock.sh --dry-run --verbose

# Nur Konfiguration laden
sudo bash -c "
source /opt/bedrock-server-updater/lib/config.sh
source /opt/bedrock-server-updater/lib/logger.sh
init_logging /tmp INFO
init_config
print_config_summary
"
```

## Troubleshooting

### Problem: "Configuration file not found"

```bash
sudo cp .env.example .env
sudo nano .env
```

### Problem: "Invalid JSON in server configuration"

```bash
# JSON validieren
jq empty config/server-list.json

# Wenn Fehler, Format prüfen
cat config/server-list.json | jq .
```

### Problem: E-Mails werden nicht gesendet

```bash
# SMTP-Verbindung testen
curl --url "smtp://$SMTP_HOST:$SMTP_PORT" \
     --ssl-reqd \
     --mail-from "$SMTP_FROM" \
     --mail-rcpt "$SMTP_TO" \
     --user "$SMTP_USER:$SMTP_PASSWORD" \
     -T <(echo "Subject: Test\n\nTest email")
```

## Standard-Werte

Falls ein Wert nicht in `.env` gesetzt ist:

```bash
SMTP_USE_TLS=true
BACKUP_RETENTION_DAYS=7
LOG_LEVEL=INFO
LOG_RETENTION_DAYS=30
SERVER_TIMEOUT=30
SERVER_START_WAIT=20
DOWNLOAD_TIMEOUT=300
DRY_RUN=false
```
