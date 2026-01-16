#!/bin/bash
#
# Debug script - Run this on your server and send me the output
#

echo "=== System Information ==="
uname -a
echo ""

echo "=== Check if timeout command exists ==="
command -v timeout && timeout --version || echo "timeout command NOT found"
echo ""

echo "=== Check server path ==="
SERVER_PATH="/data/coolify/crafty/servers/6b7208be-109e-44b3-8206-3235bb3d9b1a"
echo "Checking: $SERVER_PATH"
ls -la "$SERVER_PATH" 2>&1 | head -20
echo ""

echo "=== Check release-notes.txt ==="
if [[ -f "$SERVER_PATH/release-notes.txt" ]]; then
    echo "File exists!"
    echo "First 10 lines:"
    head -n 10 "$SERVER_PATH/release-notes.txt"
    echo ""
    echo "Version detection test:"
    head -n 10 "$SERVER_PATH/release-notes.txt" | grep -oP '\b[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?\b' | head -n1
else
    echo "File NOT found!"
fi
echo ""

echo "=== Check bedrock_server binary ==="
if [[ -f "$SERVER_PATH/bedrock_server" ]]; then
    echo "File exists!"
    ls -lh "$SERVER_PATH/bedrock_server"
    file "$SERVER_PATH/bedrock_server" 2>/dev/null || echo "file command not available"
else
    echo "File NOT found!"
fi
echo ""

echo "=== Test version detection directly ==="
cd /data/coolify/crafty/bedrock-server-updater || exit 1
source lib/platform.sh
source lib/logger.sh
init_logging "/tmp" "DEBUG"
source lib/version-check.sh

echo "Calling get_current_version..."
version=$(get_current_version "$SERVER_PATH")
echo "Result: $version"
echo "Exit code: $?"
