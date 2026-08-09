# rc-payout-watchdog

Watchdog für den Remote-Control Payout-Bot (Minecraft-Client via PrismLauncher/flatpak). Prüft
regelmäßig über `remote-control-api`, ob der Bot noch mit dem Minecraft-Server verbunden ist, und
startet den Client bei Bedarf automatisch neu.

## Installation

```bash
mkdir -p ~/scripts
git clone https://github.com/Clan-IMG/rc-payout-watchdog.git ~/scripts/rc-payout-watchdog
cd ~/scripts/rc-payout-watchdog

# .env selbst anlegen - wird NICHT aus GitHub geladen, bleibt lokal auf dem Server
cp .env.example .env
nano .env
chmod +x rc-watchdog.sh

mkdir -p ~/.config/systemd/user
cp rc-watchdog.service rc-watchdog.timer ~/.config/systemd/user/

# Timer laeuft auch ohne aktive grafische Anmeldung/Reboot zuverlaessig weiter
loginctl enable-linger $USER

systemctl --user daemon-reload
systemctl --user enable --now rc-watchdog.timer
```

## `.env` konfigurieren

| Variable | Pflicht | Beschreibung |
| --- | --- | --- |
| `RC_API` | ja | Basis-URL von `remote-control-api`, z.B. `https://rc.clan-img.net` |
| `RC_TOKEN` | ja | Bearer-Token (derselbe, den der Mod per `/rc token <token>` nutzt) |
| `CHECK_INTERVAL` | nein (Default `15m`) | Wie oft tatsächlich geprüft wird, in Minuten (optional mit `m`-Suffix) |
| `LAUNCH_CMD` | nein | Befehl zum Neustarten des Clients, z.B. anderes Profil/Server |
| `DISPLAY` / `WAYLAND_DISPLAY` / `XDG_RUNTIME_DIR` / `DBUS_SESSION_BUS_ADDRESS` | meist ja | Grafische Sitzung, siehe unten |

`systemd --user` erbt normalerweise NICHT die DISPLAY/DBUS-Umgebung der grafischen Sitzung,
wodurch `flatpak run` (eine GUI-App) sonst stillschweigend fehlschlägt. Werte aus einer laufenden
Desktop-Sitzung ermitteln:

```bash
for pid in $(pgrep -u "$USER"); do
  grep -q '^DISPLAY=\|^WAYLAND_DISPLAY=' "/proc/$pid/environ" 2>/dev/null && \
    tr '\0' '\n' < "/proc/$pid/environ" | grep -E '^(DISPLAY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS)=' && break
done
```

`XDG_RUNTIME_DIR` und `DBUS_SESSION_BUS_ADDRESS` lassen sich meist auch direkt aus der eigenen
UID ableiten:

```bash
id -u
ls -ld /run/user/$(id -u)
ls -l /run/user/$(id -u)/bus
```

→ `XDG_RUNTIME_DIR=/run/user/<uid>` und `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/<uid>/bus`.

**Achtung Format:** `DISPLAY` braucht den führenden Doppelpunkt (`:11.0`, nicht `11.0`),
`DBUS_SESSION_BUS_ADDRESS` braucht das `unix:path=`-Präfix (nicht nur den nackten Pfad).

## Nach Änderungen an `.env` oder `rc-watchdog.sh`

Kein Reload nötig — der `oneshot`-Service liest beides bei jedem Timer-Tick neu ein.

## Nach Änderungen an `rc-watchdog.service` / `rc-watchdog.timer` (z.B. per `git pull`)

```bash
cd ~/scripts/rc-payout-watchdog
git pull
cp rc-watchdog.service rc-watchdog.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user restart rc-watchdog.timer
```

## Kontrolle / Debugging

```bash
# Naechster/letzter Lauf
systemctl --user list-timers rc-watchdog.timer

# Logs des Watchdog-Skripts selbst
journalctl --user -u rc-watchdog.service --no-pager -n 50
journalctl --user -u rc-watchdog.service -f

# Output des zuletzt gestarteten Clients (bei einem Neustart)
tail -f /tmp/rc-watchdog-flatpak.log

# Sofort manuell ausfuehren, ohne auf den Timer zu warten
rm -f /tmp/rc-watchdog-check.lock   # umgeht das CHECK_INTERVAL
~/scripts/rc-payout-watchdog/rc-watchdog.sh
```

## Deinstallieren

```bash
systemctl --user disable --now rc-watchdog.timer
rm ~/.config/systemd/user/rc-watchdog.service ~/.config/systemd/user/rc-watchdog.timer
systemctl --user daemon-reload
```
