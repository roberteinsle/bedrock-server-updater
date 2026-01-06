# Crafty Controller API Dokumentation

Dieses Dokument beschreibt die Integration mit der Crafty Controller API.

## API Übersicht

Der Bedrock Server Updater verwendet die Crafty Controller REST API v2 für:
- Server Status abfragen
- Server starten
- Server stoppen
- Server-Informationen abrufen

## Authentifizierung

### API Token erstellen

1. Öffnen Sie Crafty Controller Web-Interface
2. Navigieren Sie zu **Settings** > **API**
3. Klicken Sie auf **Create API Key**
4. Geben Sie einen Namen ein (z.B. "Bedrock Updater")
5. Wählen Sie Berechtigungen:
   - `servers:read` - Server-Status lesen
   - `servers:start` - Server starten
   - `servers:stop` - Server stoppen
6. Kopieren Sie den generierten Token

### Token verwenden

Der Token wird im HTTP Header übergeben:

```bash
Authorization: Bearer YOUR_API_TOKEN_HERE
```

## API Endpoints

### Base URL

```
https://your-crafty-instance.com/api/v2
```

### 1. Server Liste abrufen

**GET** `/servers`

Gibt Liste aller Server zurück.

```bash
curl -H "Authorization: Bearer TOKEN" \
     https://crafty.example.com/api/v2/servers
```

Response:
```json
{
  "status": "ok",
  "data": [
    {
      "server_id": "uuid-here",
      "server_name": "My Server",
      "server_type": "bedrock",
      ...
    }
  ]
}
```

### 2. Server Status abrufen

**GET** `/servers/{server_id}/stats`

Gibt detaillierte Server-Statistiken zurück.

```bash
curl -H "Authorization: Bearer TOKEN" \
     https://crafty.example.com/api/v2/servers/UUID/stats
```

Response:
```json
{
  "status": "ok",
  "data": {
    "running": true,
    "cpu": 15.5,
    "mem": 1024,
    "mem_percent": 25.5,
    "players": ["Player1", "Player2"]
  }
}
```

**Wichtige Felder:**
- `running` (boolean) - Server läuft
- `cpu` (float) - CPU Auslastung in %
- `mem` (int) - RAM Nutzung in MB
- `players` (array) - Liste aktiver Spieler

### 3. Server stoppen

**POST** `/servers/{server_id}/action/stop_server`

Stoppt einen laufenden Server.

```bash
curl -X POST \
     -H "Authorization: Bearer TOKEN" \
     -H "Content-Type: application/json" \
     https://crafty.example.com/api/v2/servers/UUID/action/stop_server
```

Response:
```json
{
  "status": "ok",
  "message": "Server stop command sent"
}
```

**Hinweise:**
- Der API-Call gibt sofort zurück
- Server braucht Zeit zum Stoppen (5-30 Sekunden)
- Status muss nachträglich geprüft werden

### 4. Server starten

**POST** `/servers/{server_id}/action/start_server`

Startet einen gestoppten Server.

```bash
curl -X POST \
     -H "Authorization: Bearer TOKEN" \
     -H "Content-Type: application/json" \
     https://crafty.example.com/api/v2/servers/UUID/action/start_server
```

Response:
```json
{
  "status": "ok",
  "message": "Server start command sent"
}
```

**Hinweise:**
- Der API-Call gibt sofort zurück
- Server braucht Zeit zum Starten (10-60 Sekunden)
- Status muss nachträglich geprüft werden

### 5. Server neu starten

**POST** `/servers/{server_id}/action/restart_server`

Neustart eines Servers (Stop + Start).

```bash
curl -X POST \
     -H "Authorization: Bearer TOKEN" \
     -H "Content-Type: application/json" \
     https://crafty.example.com/api/v2/servers/UUID/action/restart_server
```

## Implementation im Updater

### API Call Wrapper

`lib/crafty-api.sh` enthält Wrapper-Funktionen:

```bash
# Generic API call
crafty_api_call "GET" "api/v2/servers/UUID/stats"

# Specific functions
crafty_get_server_status "UUID"
crafty_is_server_running "UUID"
crafty_stop_server "UUID"
crafty_start_server "UUID"
crafty_restart_server "UUID"
```

### Status Polling

Nach Start/Stop wird der Status gepollt:

```bash
crafty_stop_server() {
    # Send stop command
    crafty_api_call "POST" "api/v2/servers/$1/action/stop_server"

    # Wait and poll status
    timeout=$SERVER_TIMEOUT
    while [ $timeout -gt 0 ]; do
        if ! crafty_is_server_running "$1"; then
            return 0  # Success
        fi
        sleep 2
        timeout=$((timeout - 2))
    done

    return 1  # Timeout
}
```

### Error Handling

Alle API-Calls haben Error Handling:

```bash
if crafty_stop_server "UUID"; then
    echo "Success"
else
    echo "Failed"
    # Rollback or notify
fi
```

## HTTP Status Codes

- **200** - OK
- **201** - Created
- **400** - Bad Request (ungültige Parameter)
- **401** - Unauthorized (Token falsch/abgelaufen)
- **403** - Forbidden (keine Berechtigung)
- **404** - Not Found (Server existiert nicht)
- **500** - Internal Server Error

## Rate Limiting

Crafty Controller hat Rate Limiting:

- Empfohlen: Max 10 Requests/Minute pro API Key
- Bei Überschreitung: HTTP 429 (Too Many Requests)

Der Updater respektiert dies durch:
- Minimale API-Calls (nur wenn nötig)
- Polling-Intervalle (2 Sekunden zwischen Checks)

## Debugging

### API-Calls loggen

```bash
# In lib/crafty-api.sh DEBUG aktivieren
LOG_LEVEL=DEBUG

# Dann zeigt jeder API-Call:
log_debug "API Call: GET /api/v2/servers/UUID/stats"
log_debug "Response: {...}"
```

### Manueller API-Test

```bash
# Test Token
curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://crafty.example.com/api/v2/servers

# Test Server Status
curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://crafty.example.com/api/v2/servers/UUID/stats | jq .

# Test Server Stop
curl -X POST \
     -H "Authorization: Bearer YOUR_TOKEN" \
     https://crafty.example.com/api/v2/servers/UUID/action/stop_server
```

### Häufige Fehler

**401 Unauthorized:**
```
Lösung: Überprüfen Sie CRAFTY_API_TOKEN in .env
```

**404 Not Found:**
```
Lösung: Überprüfen Sie Server ID in config/server-list.json
```

**Connection Refused:**
```
Lösung:
- Ist Crafty Controller erreichbar?
- Firewall-Regel prüfen
- CRAFTY_API_URL korrekt?
```

## Sicherheit

### Best Practices

1. **Dedicated API Token**
   - Erstellen Sie einen separaten Token nur für den Updater
   - Nicht Ihren Admin-Token verwenden

2. **Minimal Permissions**
   - Nur Berechtigungen geben, die benötigt werden
   - `servers:read`, `servers:start`, `servers:stop`

3. **Token Rotation**
   - Tokens regelmäßig erneuern (z.B. alle 90 Tage)
   - Alte Tokens löschen

4. **HTTPS verwenden**
   - **Immer** `https://` verwenden, nie `http://`
   - Token wird sonst im Klartext übertragen

5. **Token sicher speichern**
   ```bash
   chmod 600 /opt/bedrock-server-updater/.env
   ```

### Token niemals loggen

```bash
# FALSCH - Token wird geloggt
log_info "Using token: $CRAFTY_API_TOKEN"

# RICHTIG - Token wird ausgeblendet
log_info "Using token: ${CRAFTY_API_TOKEN:0:10}..."
```

## API Limits

### Timeouts

```bash
# In .env konfigurierbar
SERVER_TIMEOUT=30        # Max. Wartezeit für Start/Stop
DOWNLOAD_TIMEOUT=300     # Max. Download-Zeit
```

### Concurrent Requests

Der Updater macht API-Calls sequenziell:

```bash
for server in servers; do
    crafty_stop_server $server
done
```

Nicht parallel, um API nicht zu überlasten.

## Weitere Informationen

- [Crafty Controller Dokumentation](https://docs.craftycontrol.com/)
- [Crafty Controller GitHub](https://gitlab.com/crafty-controller/crafty-4)

## Beispiel-Integration

Vollständiges Beispiel für eigene Scripts:

```bash
#!/bin/bash

CRAFTY_API_URL="https://crafty.example.com"
CRAFTY_API_TOKEN="your-token-here"
SERVER_ID="uuid-here"

# Stop Server
curl -X POST \
     -H "Authorization: Bearer $CRAFTY_API_TOKEN" \
     -H "Content-Type: application/json" \
     "$CRAFTY_API_URL/api/v2/servers/$SERVER_ID/action/stop_server"

# Wait
sleep 10

# Check Status
STATUS=$(curl -s \
     -H "Authorization: Bearer $CRAFTY_API_TOKEN" \
     "$CRAFTY_API_URL/api/v2/servers/$SERVER_ID/stats" \
     | jq -r '.data.running')

if [ "$STATUS" = "false" ]; then
    echo "Server stopped"
else
    echo "Server still running"
fi

# Start Server
curl -X POST \
     -H "Authorization: Bearer $CRAFTY_API_TOKEN" \
     -H "Content-Type: application/json" \
     "$CRAFTY_API_URL/api/v2/servers/$SERVER_ID/action/start_server"
```
