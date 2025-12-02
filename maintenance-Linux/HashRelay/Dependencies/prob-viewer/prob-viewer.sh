#!/usr/bin/env bash
# This script is used by HashRelay client to see the state of the
# configured server.
# If the server is up, it continue to the next script to sent the backups
# if the server is down, it don't try to send anything to the server
#
# Author: Decarnelle Samuel

# Ensure we are root
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

NEXT="/usr/local/bin/HashRelay/scp/scp.sh"
CONFIG="/usr/local/bin/HashRelay/agent.conf"

# Get the Ip address of the server inside the config file
get_existing() {
  [[ -f "$CONFIG" ]] || {
    echo ""
    return
  }

  local line
  # Find lines like: SERVER_IP = 1.2.3.4
  line="$(grep -E '^[[:space:]]*SERVER_IP[[:space:]]*=' "$CONFIG" | tail -n1 || true)"
  [[ -z "$line" ]] && {
    echo ""
    return
  }

  # Extract the right-hand side of '='
  line="${line#*=}"

  # Trim leading/trailing whitespace
  line="${line#"${line%%[![:space:]]*}"}" # ltrim
  line="${line%"${line##*[![:space:]]}"}" # rtrim

  # Remove surrounding single/double quotes, if any
  line="${line%\"}"
  line="${line#\"}"
  line="${line%\'}"
  line="${line#\'}"

  echo "$line"
}
IP_ADD=$(get_existing)

# See if we are onto a client or a server configuration
CLIENT_OR_SERVER=$(/usr/local/bin/HashRelay/agent-detector/agent-detector.sh)
# Let's print the result:
if [[ "$CLIENT_OR_SERVER" == "true" ]]; then
  IS_CLIENT=true
  printf 'Client is considered: %s\n' "$IS_CLIENT"
else
  IS_SERVER=true
  printf 'Server is considered: %s\n' "$IS_SERVER"
fi

# Ping the IP of the server
ping_host_v4() {
  ping -4 -c 4 "$1" >/dev/null 2>&1
}

if [[ -n "$IP_ADD" ]]; then
  echo "Pinging $IP_ADD ..."

  if ping_host_v4 "$IP_ADD"; then
    echo "The server $IP_ADD seems up"
    IS_UP=true
  else
    echo "The server $IP_ADD seems down"
    IS_UP=false
  fi

else
  echo "ERROR: Ip address not configured !"
fi

# Make the script output an error if the server is not up
# usefull to be called inside another script via :
# if /usr/local/bin/HashRelay/prob-viewer/prob-viewer.sh; then
#  echo "Server is up"
# else
#   echo "Server is down"
# fi
if [[ "$IS_UP" == true ]]; then
  exit 0
else
  exit 1
fi
