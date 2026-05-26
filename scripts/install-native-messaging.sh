#!/usr/bin/env bash
set -euo pipefail

EXTENSION_ID="${1:-}"
if [[ -z "$EXTENSION_ID" ]]; then
  echo "Usage: $0 <chrome-extension-id>" >&2
  exit 1
fi

CHROME_HOSTS_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
mkdir -p "$CHROME_HOSTS_DIR"

cat > "$CHROME_HOSTS_DIR/com.stira.extensionbridge.json" <<EOF
{
  "name": "com.stira.extensionbridge",
  "description": "Stira browser extension bridge",
  "path": "/Applications/Stira.app/Contents/MacOS/StiraExtensionBridge",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://${EXTENSION_ID}/"]
}
EOF

echo "Native messaging host installed for extension ID: $EXTENSION_ID"
echo "Manifest written to: $CHROME_HOSTS_DIR/com.stira.extensionbridge.json"
