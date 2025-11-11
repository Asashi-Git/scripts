#!/usr/bin/env bash
# Configure SERVER_PORT in /usr/local/bin/HashRelay/agent.conf
# This script:
#   - Reads the existing SERVER_PORT from the config (if present)
#   - Shows it and asks if you want to modify it
#   - Validates that any new input is an integer port (1–65535)
#   - Replaces or appends SERVER_PORT in the config safely (with a timestamped backup)
#   - Chains to the HashRelay client script
#
# Author: Decaarnelle Samuel

# Exit on:
#  - any command error (-e)
#  - use of an unset variable (-u)
#  - a failure anywhere in a pipeline (-o pipefail)
set -euo pipefail

title="Server Port Configurator"
CONFIG="/usr/local/bin/HashRelay/agent.conf"
NEXT="/usr/local/bin/HashRelay/hashrelay-client/hashrelay-client.sh"

# Small wrapper for gum confirm to keep calls short and readable
confirm() { gum confirm "$1"; }

# Read the last SERVER_PORT entry from CONFIG (if file exists)
# - Greps for a line starting with SERVER_PORT=
# - Takes the last occurrence (tail -n1) to handle multiple entries
# - Trims spaces and strips quotes around the value
get_existing_port() {
  [[ -f "$CONFIG" ]] || {
    echo ""
    return
  }

  local line
  line="$(grep -E '^[[:space:]]*SERVER_PORT[[:space:]]*=' "$CONFIG" | tail -n1 || true)"
  [[ -z "$line" ]] && {
    echo ""
    return
  }

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

# Strict port validator: integer 1–65535
valid_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] || return 1
  ((p >= 1 && p <= 65535)) || return 1
  return 0
}

# Persist SERVER_PORT into CONFIG:
# - Ensures directory exists (with sudo, since path is under /usr/local/bin)
# - If SERVER_PORT= exists, make a timestamped backup and replace it in-place
# - Otherwise, append a new SERVER_PORT line
set_server_port() {
  local port="$1"

  sudo mkdir -p "$(dirname -- "$CONFIG")"

  if [[ -f "$CONFIG" ]] && grep -qE '^[[:space:]]*SERVER_PORT[[:space:]]*=' "$CONFIG"; then
    sudo cp -a -- "$CONFIG" "$CONFIG.bak.$(date -Iseconds)"
    sudo sed -i -E "s|^[[:space:]]*SERVER_PORT[[:space:]]*=.*$|SERVER_PORT=$port|" "$CONFIG"
  else
    printf "SERVER_PORT=%s\n" "$port" | sudo tee -a "$CONFIG" >/dev/null
  fi
}

# Nice welcome banner
gum style --border double --margin "1 2" --padding "1 2" --border-foreground 212 \
  "Welcome to $title"

# Try to read the existing SERVER_PORT from the config
existing_port="$(get_existing_port)"

# If we already have a value, show it and ask whether to modify it
if [[ -n "$existing_port" ]]; then
  gum style --foreground 212 "Current SERVER_PORT: $existing_port"

  if ! confirm "Do you want to modify the SERVER_PORT?"; then
    echo "Keeping existing SERVER_PORT: $existing_port"
    exec sudo bash "$NEXT"
  fi
fi

# Prompt loop until we get a valid port (or user exits)
while :; do
  # Pre-fill with existing value if we had one
  port="$(gum input --placeholder 'e.g. 443' \
    ${existing_port:+--value "$existing_port"})"

  # If user pressed Enter on an empty input, exit gracefully
  [[ -z "${port:-}" ]] && {
    echo "No input provided. Exiting."
    exit 0
  }

  if ! valid_port "$port"; then
    gum style --foreground 196 "Invalid port. Enter an integer between 1 and 65535 (e.g., 443)."
    continue
  fi

  SERVER_PORT="$port"
  break
done

# Persist the chosen port into the config
set_server_port "$SERVER_PORT"
echo "Your server port is set to: $SERVER_PORT"

# Finally, chain to the client script; exec replaces the current process
exec sudo bash "$NEXT"
