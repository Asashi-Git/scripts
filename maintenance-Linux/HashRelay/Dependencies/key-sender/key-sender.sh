#!/usr/bin/env bash
# TODO: sudo -u HashRelay python3 -m http.server 36150 --directory /home/HashRelay/.ssh
#
# Author: Decarnelle Samuel

PORT="36150"
DIRECTORY="/home/HashRelay/.ssh"
NEXT="/usr/local/bin/HashRelay/hashrelay-server/hashrelay-server.sh"

export_and_serve_key() {
  (python3 -m http.server "$PORT" --bind 0.0.0.0 --directory "$DIRECTORY" >/dev/null 2>&1) &
  SRV_PID=$(sudo ps -aux | grep -E '[3]6150' | awk '{print $2}' | head -n1)

  echo "Booting temporary HTTP server"
  sleep 1
}

if [[ ! "$SRV_PID" ]]; then
  export_and_serve_key
else
  read -rp "Press Enter to stop the temporary HTTP server..."
  kill "$SRV_PID" 2>/dev/null || true
  wait "$SRV_PID" 2>/dev/null || true
fi

exec sudo bash "$NEXT"
