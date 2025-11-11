#!/usr/bin/env bash
# Configure SERVER_IP (IPv4 only) in /usr/local/bin/HashRelay/agent.conf
# This script:
#   - Reads the existing SERVER_IP from the config (if present)
#   - Shows it and asks if you want to modify it
#   - Validates that any new input is a strict IPv4 (no IPv6/FQDN/localhost)
#   - Pings the IPv4 (non-fatal if it fails; user can still choose to save)
#   - Replaces or appends SERVER_IP in the config safely (with a timestamped backup)
#   - Chains to the HashRelay client script
#
# Author: Decaarnelle Samuel

# Exit on:
#  - any command error (-e)
#  - use of an unset variable (-u)
#  - a failure anywhere in a pipeline (-o pipefail)
set -euo pipefail

title="Server IPv4 Configurator"
CONFIG="/usr/local/bin/HashRelay/agent.conf"
NEXT="/usr/local/bin/HashRelay/hashrelay-client/hashrelay-client.sh"

# Small wrapper for gum confirm to keep calls short and readable
confirm() { gum confirm "$1"; }

# Read the last SERVER_IP entry from CONFIG (if file exists)
# - Greps for a line starting with SERVER_IP=
# - Takes the last occurrence (tail -n1) to handle multiple entries
# - Trims spaces and strips quotes around the value
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

# Strict IPv4 validator:
# - Shape: dotted-quad only (N.N.N.N with 1–3 digits per octet)
# - Range: each octet must be 0–255
# - No hostnames, no IPv6, no "localhost"
valid_ipv4() {
  local ip="$1"

  # Quick shape check
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

  # Split and check each octet range
  # IFS stands for Internal Field Separator.
  # It’s a special shell variable that controls how Bash splits strings into “fields”
  # during word splitting and when using the read builtin
  IFS='.' read -r o1 o2 o3 o4 <<<"$ip"
  for o in "$o1" "$o2" "$o3" "$o4"; do # split an IPv4 into four octets using dot as the delimiter
    # Must be numeric and within 0–255
    [[ "$o" =~ ^[0-9]+$ ]] || return 1
    ((o >= 0 && o <= 255)) || return 1
  done

  return 0
}

# Persist SERVER_IP into CONFIG:
# - Ensures directory exists (with sudo, since path is under /usr/local/bin)
# - If SERVER_IP= exists, make a timestamped backup and replace it in-place
# - Otherwise, append a new SERVER_IP line
set_server_ip() {
  local ip="$1"

  # Make sure the target directory exists
  sudo mkdir -p "$(dirname -- "$CONFIG")"

  if [[ -f "$CONFIG" ]] && grep -qE '^[[:space:]]*SERVER_IP[[:space:]]*=' "$CONFIG"; then
    # Backup for audit/rollback safety
    sudo cp -a -- "$CONFIG" "$CONFIG.bak.$(date -Iseconds)"

    # Replace the whole SERVER_IP line safely (anchored at start)
    sudo sed -i -E "s|^[[:space:]]*SERVER_IP[[:space:]]*=.*$|SERVER_IP=$ip|" "$CONFIG"
  else
    # Append when key is absent or file doesn’t exist
    printf "SERVER_IP=%s\n" "$ip" | sudo tee -a "$CONFIG" >/dev/null
  fi
}

# Ping using IPv4 only (-4). Wrapped with gum spinner for UX.
# Returns ping's exit status so caller can decide what to do.
ping_host_v4() {
  local ip="$1"
  gum spin --title "Pinging (IPv4) $ip" -- ping -4 -c 4 -- "$ip"
}

# Nice welcome banner
gum style --border double --margin "1 2" --padding "1 2" --border-foreground 212 \
  "Welcome to $title"

# Try to read the existing SERVER_IP from the config
existing_ip="$(get_existing)"

# If we already have a value, show it and ask whether to modify it
if [[ -n "$existing_ip" ]]; then
  gum style --foreground 212 "Current SERVER_IP: $existing_ip"

  # If user declines modification, keep current value and continue workflow
  if ! confirm "Do you want to modify the SERVER_IP?"; then
    echo "Keeping existing SERVER_IP: $existing_ip"

    # Optional reachability check; non-fatal if it fails
    ping_host_v4 "$existing_ip" || true

    # Chain to the client script (replace current shell with it)
    exec sudo bash "$NEXT"
  fi
fi

# Prompt loop until we get a valid IPv4 (or user exits)
while :; do
  # Pre-fill with existing value if we had one
  host="$(gum input --placeholder 'e.g. 192.168.10.100' \
    ${existing_ip:+--value "$existing_ip"})"

  # If user pressed Enter on an empty input, exit gracefully
  [[ -z "${host:-}" ]] && {
    echo "No input provided. Exiting."
    exit 0
  }

  # Enforce IPv4-only
  if ! valid_ipv4 "$host"; then
    gum style --foreground 196 "Invalid IPv4 address. Use dotted-quad with octets 0–255 (e.g., 10.0.0.5)."
    continue
  fi

  # Try to ping; if it fails, let the user decide to keep or retry
  if ! ping_host_v4 "$host"; then
    if ! confirm "Ping failed. Save \"$host\" anyway?"; then
      # User chose not to save; loop back and ask again
      continue
    fi
  fi

  # If we reach here, we have a valid IPv4, optionally unreachable by ping
  SERVER_IP="$host"
  break
done

# Persist the chosen IPv4 into the config
set_server_ip "$SERVER_IP"
echo "Your server IP is set to: $SERVER_IP"

# Finally, chain to the client script; exec replaces the current process
exec sudo bash "$NEXT"
