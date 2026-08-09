#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.env
source "$SCRIPT_DIR/.env"

# systemd --user units don't inherit the graphical session's DISPLAY/DBUS env by default,
# which makes the flatpak GUI launch fail silently - export them here if set in .env.
[ -n "${DISPLAY:-}" ] && export DISPLAY
[ -n "${WAYLAND_DISPLAY:-}" ] && export WAYLAND_DISPLAY
[ -n "${XDG_RUNTIME_DIR:-}" ] && export XDG_RUNTIME_DIR
[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && export DBUS_SESSION_BUS_ADDRESS

LOCK_FILE="/tmp/rc-watchdog.lock"
LOG_FILE="/tmp/rc-watchdog-flatpak.log"

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
  # Output geht in eine Log-Datei statt /dev/null, damit ein stiller Fehlschlag (z.B. fehlendes DISPLAY) sichtbar bleibt: tail -f "$LOG_FILE"
  nohup flatpak run org.prismlauncher.PrismLauncher --launch LabyMod --server opsucht.net >>"$LOG_FILE" 2>&1 &
  date +%s > "$LOCK_FILE"
fi
