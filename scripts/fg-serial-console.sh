#!/usr/bin/env bash
# Mit der seriellen Konsole der FortiGate-VM verbinden.
# Setzt voraus, dass die serielle Schnittstelle in UTM als TcpServer auf Port 4555 läuft
# und die VM gestartet ist.
#
#   utmctl start <UUID>      # VM starten
#   ./fg-serial-console.sh   # verbinden (Beenden: Ctrl-C)

set -euo pipefail

HOST="127.0.0.1"
PORT="${1:-4555}"

if ! nc -z "$HOST" "$PORT" 2>/dev/null; then
    echo "Kein Listener auf ${HOST}:${PORT}."
    echo "Läuft die VM und ist die serielle Schnittstelle als TcpServer/${PORT} konfiguriert?"
    exit 1
fi

echo "Verbinde mit der FortiGate-Konsole (${HOST}:${PORT}) — Enter drücken, Beenden mit Ctrl-C."
exec nc "$HOST" "$PORT"
