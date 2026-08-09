#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.env
source "$SCRIPT_DIR/.env"

LOCK_FILE="/tmp/rc-watchdog.lock"

# Nicht pruefen, waehrend gerade erst neu gestartet wurde (Client braucht 1-3 Min)
if [ -f "$LOCK_FILE" ]; then
  last=$(cat "$LOCK_FILE")
  now=$(date +%s)
  if (( now - last < 240 )); then
    echo "Restart laeuft noch, ueberspringe Check."
    exit 0
  fi
fi

online=$(curl -fsS -H "Authorization: Bearer $RC_TOKEN" "$RC_API/v1/pay/online" | jq -r '.online')

if [ "$online" != "true" ]; then
  echo "Bot offline - starte Minecraft neu."
  flatpak kill org.prismlauncher.PrismLauncher || true
  pkill -f 'java.*minecraft' || true
  sleep 5
  nohup flatpak run org.prismlauncher.PrismLauncher --launch LabyMod --server opsucht.net >/dev/null 2>&1 &
  date +%s > "$LOCK_FILE"
fi
