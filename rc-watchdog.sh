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

# Der systemd-Timer laeuft minuetlich (siehe rc-watchdog.timer); wie oft WIRKLICH geprueft wird,
# steuert stattdessen diese .env-Variable - Timer-Intervalle koennen kein .env lesen.
CHECK_INTERVAL="${CHECK_INTERVAL:-15m}"
CHECK_INTERVAL_SECONDS=$(( ${CHECK_INTERVAL%m} * 60 ))
# Command, das bei einem Neustart ausgefuehrt wird - in .env anpassbar (z.B. anderes Profil/Server).
LAUNCH_CMD="${LAUNCH_CMD:-flatpak run org.prismlauncher.PrismLauncher --launch LabyMod --server opsucht.net}"

CHECK_LOCK_FILE="/tmp/rc-watchdog-check.lock"
LOCK_FILE="/tmp/rc-watchdog.lock"
LOG_FILE="/tmp/rc-watchdog-flatpak.log"

# Seltener als CHECK_INTERVAL_SECONDS pruefen, auch wenn der Timer oefter (minuetlich) feuert
if [ -f "$CHECK_LOCK_FILE" ]; then
  last_check=$(cat "$CHECK_LOCK_FILE")
  now=$(date +%s)
  if (( now - last_check < CHECK_INTERVAL_SECONDS )); then
    exit 0
  fi
fi
date +%s > "$CHECK_LOCK_FILE"

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

# Killt alle Reste eines vorherigen Laufs - nicht nur "flatpak kill" (das nichts findet, wenn der
# Sandbox-Prozess verwaist ist), sondern auch die bwrap-Sandbox und den Java-Prozess direkt.
kill_client() {
  flatpak kill org.prismlauncher.PrismLauncher || true
  pkill -f 'java.*minecraft' || true
  pkill -9 -f 'bwrap.*prismlauncher' || true
  pkill -9 -f 'org.prismlauncher.EntryPoint' || true
  sleep 8
}

# Prueft, ob nach einem Start tatsaechlich ein Java/Minecraft-Prozess laeuft.
client_is_running() {
  pgrep -f 'org.prismlauncher.EntryPoint' >/dev/null 2>&1
}

if [ "$online" != "true" ]; then
  echo "Bot offline - starte Minecraft neu."
  kill_client

  for attempt in 1 2; do
    # Output geht in eine Log-Datei statt /dev/null, damit ein stiller Fehlschlag (z.B. fehlendes DISPLAY) sichtbar bleibt: tail -f "$LOG_FILE"
    nohup $LAUNCH_CMD >>"$LOG_FILE" 2>&1 &
    sleep 20
    if client_is_running; then
      echo "Neustart erfolgreich (Versuch $attempt)."
      break
    fi
    echo "Neustart-Versuch $attempt: kein laufender Prozess erkannt."
    if [ "$attempt" -eq 1 ]; then
      # Vermutlich eine haengende D-Bus-Aktivierung/Sandbox-Leiche vom vorherigen Lauf - nochmal
      # gruendlich killen und ein zweites Mal versuchen, bevor wir aufgeben.
      kill_client
    fi
  done

  date +%s > "$LOCK_FILE"
fi
