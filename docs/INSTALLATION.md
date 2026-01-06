# Installation Guide

Dieses Dokument beschreibt die Installation des Bedrock Server Updaters.

## Systemvoraussetzungen

- **Betriebssystem**: Linux (Ubuntu 20.04+ oder Debian 11+ empfohlen)
- **Crafty Controller**: Version 4.7.0 oder höher
- **Berechtigungen**: Root-Zugriff (sudo)

### Benötigte Software

Die folgenden Tools werden benötigt:

- `bash` (4.0 oder höher)
- `curl` - für Downloads und API-Calls
- `jq` - für JSON-Verarbeitung
- `tar` - für Backup-Archivierung
- `unzip` - für Bedrock Server Extraction

Optional für E-Mail:
- `sendmail` oder `msmtp` (wird automatisch via curl SMTP ersetzt, falls nicht vorhanden)

## Installationsmethoden

### Methode 1: Automatische Installation (empfohlen)

1. **Repository klonen**

```bash
cd /opt
sudo git clone https://github.com/roberteinsle/bedrock-server-updater.git
cd bedrock-server-updater
```

2. **Installations-Script ausführen**

```bash
sudo ./install.sh
```

Das Script wird:
- System-Voraussetzungen prüfen und fehlende Pakete installieren
- Verzeichnis-Struktur erstellen
- Konfigurationsdatei erstellen
- Interaktiv nach Crafty API und SMTP Einstellungen fragen
- Cronjob einrichten
- Einen Test-Durchlauf ausführen

### Methode 2: Nicht-interaktive Installation

Für automatisierte Deployments oder wenn keine Benutzereingabe möglich ist:

```bash
sudo ./install.sh --non-interactive
```

Danach manuell konfigurieren:

```bash
sudo nano /opt/bedrock-server-updater/.env
```

### Methode 3: Manuelle Installation

1. **Dateien kopieren**

```bash
sudo mkdir -p /opt/bedrock-server-updater
sudo cp -r * /opt/bedrock-server-updater/
cd /opt/bedrock-server-updater
```

2. **Verzeichnisse erstellen**

```bash
sudo mkdir -p logs backups temp
sudo chmod 700 logs backups temp
```

3. **Scripts ausführbar machen**

```bash
sudo chmod +x update-bedrock.sh install.sh
sudo chmod +x lib/*.sh
```

4. **Konfiguration erstellen**

```bash
sudo cp .env.example .env
sudo chmod 600 .env
sudo nano .env
```

5. **Cronjob einrichten**

```bash
sudo crontab -e
```

Folgende Zeile hinzufügen:

```
0 3 * * * /opt/bedrock-server-updater/update-bedrock.sh >> /opt/bedrock-server-updater/logs/cron.log 2>&1
```

## Konfiguration

### 1. Crafty Controller API

Sie benötigen einen API-Token von Crafty Controller:

1. Öffnen Sie Crafty Controller Web-Interface
2. Gehen Sie zu **Settings** > **API**
3. Erstellen Sie einen neuen API-Token
4. Kopieren Sie den Token

Tragen Sie die Werte in `.env` ein:

```bash
CRAFTY_API_URL=https://your-crafty-instance.com
CRAFTY_API_TOKEN=your-api-token-here
```

### 2. SMTP E-Mail Konfiguration

Für E-Mail-Benachrichtigungen konfigurieren Sie SMTP:

```bash
SMTP_HOST=smtp.gmail.com          # Ihr SMTP Server
SMTP_PORT=587                       # SMTP Port (meist 587 oder 465)
SMTP_USER=your-email@gmail.com     # SMTP Benutzername
SMTP_PASSWORD=your-password         # SMTP Passwort
SMTP_FROM=bedrock-updater@domain.com  # Absender-Adresse
SMTP_TO=admin@domain.com           # Empfänger-Adresse
SMTP_USE_TLS=true                   # TLS verwenden
```

#### SMTP Beispiele:

**Gmail:**
```bash
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASSWORD=your-app-password  # App-Passwort erstellen!
SMTP_USE_TLS=true
```

**Office 365:**
```bash
SMTP_HOST=smtp.office365.com
SMTP_PORT=587
SMTP_USER=your-email@outlook.com
SMTP_PASSWORD=your-password
SMTP_USE_TLS=true
```

**Eigener Server:**
```bash
SMTP_HOST=mail.yourdomain.com
SMTP_PORT=587
SMTP_USER=username
SMTP_PASSWORD=password
SMTP_USE_TLS=true
```

### 3. Server-Konfiguration

Bearbeiten Sie `config/server-list.json` und tragen Sie Ihre Server ein:

```json
{
  "servers": [
    {
      "name": "MyServer1",
      "id": "crafty-server-id-uuid",
      "path": "/crafty/servers/crafty-server-id-uuid"
    }
  ]
}
```

Die Server-IDs und Pfade finden Sie in Crafty Controller.

## Überprüfung der Installation

### 1. Konfiguration testen

```bash
sudo /opt/bedrock-server-updater/update-bedrock.sh --dry-run
```

Das Script sollte:
- Konfiguration laden
- Crafty API testen
- Nach Updates suchen
- **OHNE** tatsächliche Änderungen vorzunehmen

### 2. E-Mail testen

Erstellen Sie ein Test-Script:

```bash
sudo -i
cd /opt/bedrock-server-updater
source lib/logger.sh
source lib/config.sh
source lib/notification.sh

init_logging "/opt/bedrock-server-updater/logs" "INFO"
init_config
send_test_email
```

### 3. API-Verbindung testen

```bash
curl -H "Authorization: Bearer YOUR_API_TOKEN" \
     https://your-crafty-instance.com/api/v2/servers
```

Sollte eine JSON-Liste Ihrer Server zurückgeben.

## Fehlerbehebung

### Installation schlägt fehl

**Problem:** Fehlende Pakete

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y curl jq tar unzip

# CentOS/RHEL
sudo yum install -y curl jq tar unzip

# Fedora
sudo dnf install -y curl jq tar unzip
```

**Problem:** Keine Root-Rechte

```bash
sudo ./install.sh
```

### Konfiguration

**Problem:** `.env` Datei nicht gefunden

```bash
cd /opt/bedrock-server-updater
sudo cp .env.example .env
sudo nano .env
```

**Problem:** Falsche Berechtigungen

```bash
sudo chmod 600 /opt/bedrock-server-updater/.env
sudo chmod +x /opt/bedrock-server-updater/update-bedrock.sh
```

### API-Verbindung

**Problem:** Crafty API nicht erreichbar

- Prüfen Sie CRAFTY_API_URL (mit https://)
- Prüfen Sie API Token
- Testen Sie Verbindung mit curl
- Prüfen Sie Firewall-Regeln

### Cronjob

**Problem:** Cronjob läuft nicht

```bash
# Cronjob-Status prüfen
sudo crontab -l

# Cron-Logs prüfen
sudo tail -f /var/log/syslog | grep CRON

# Script manuell testen
sudo /opt/bedrock-server-updater/update-bedrock.sh
```

## Upgrade

So aktualisieren Sie den Updater:

```bash
cd /opt/bedrock-server-updater

# Backup der Konfiguration
sudo cp .env .env.backup
sudo cp config/server-list.json config/server-list.json.backup

# Git Pull
sudo git pull

# Konfiguration wiederherstellen (falls überschrieben)
sudo cp .env.backup .env
sudo cp config/server-list.json.backup config/server-list.json

# Berechtigungen neu setzen
sudo chmod +x update-bedrock.sh install.sh
sudo chmod +x lib/*.sh
```

## Deinstallation

So entfernen Sie den Updater:

```bash
# Cronjob entfernen
sudo crontab -e
# Zeile mit "update-bedrock.sh" löschen

# Dateien entfernen
sudo rm -rf /opt/bedrock-server-updater

# Optional: Backups behalten
sudo cp -r /opt/bedrock-server-updater/backups /backup/bedrock-backups
```

## Nächste Schritte

- Lesen Sie [CONFIGURATION.md](CONFIGURATION.md) für erweiterte Konfiguration
- Lesen Sie [API.md](API.md) für Details zur Crafty API Integration
- Testen Sie das Update-System mit `--dry-run`
