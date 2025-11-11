#!/usr/bin/env bash
# Configure SERVER_IP (IPv4 only) in /usr/local/bin/HashRelay/agent.conf
# Author: Decaarnelle Samuel

set -euo pipefail

title="Server IPv4 Configurator"
CONFIG="/usr/local/bin/HashRelay/agent.conf"
NEXT="/usr/local/bin/HashRelay/hashrelay-client/hashrelay-client.sh"

confirm() { gum confirm "$1"; }

get_existing() {
  [[ -f "$CONFIG" ]] || {
    echo ""
    return
  }
  local line
  line="$(grep -E '^[[:space:]]*SERVER_IP[[:space:]]*=' "$CONFIG" | tail -n1 || true)"
  [[ -z "$line" ]] && {
    echo ""
    return
  }
  line="${line#*=}"
  line="${line#"${line%%[![:space:]]*}"}" # ltrim
  line="${line%"${line##*[![:space:]]}"}" # rtrim
  line="${line%\"}"
  line="${line#\"}"
  line="${line%\'}"
  line="${line#\'}"
  echo "$line"
}

# Strict IPv4 validator: dotted-quad, octets 0–255
valid_ipv4() {
  local ip="$1"
  # quick shape check
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  # range check each octet
  IFS='.' read -r o1 o2 o3 o4 <<<"$ip"
  for o in "$o1" "$o2" "$o3" "$o4"; do
    # disallow leading +/-, empty, and >255
    [[ "$o" =~ ^[0-9]+$ ]] || return 1
    ((o >= 0 && o <= 255)) || return 1
  done
  return 0
}

set_server_ip() {
  local ip="$1"
  sudo mkdir -p "$(dirname -- "$CONFIG")"
  if [[ -f "$CONFIG" ]] && grep -qE '^[[:space:]]*SERVER_IP[[:space:]]*=' "$CONFIG"; then
    sudo cp -a -- "$CONFIG" "$CONFIG.bak.$(date -Iseconds)"
    sudo sed -i -E "s|^[[:space:]]*SERVER_IP[[:space:]]*=.*$|SERVER_IP=$ip|" "$CONFIG"
  else
    printf "SERVER_IP=%s\n" "$ip" | sudo tee -a "$CONFIG" >/dev/null
  fi
}

ping_host_v4() {
  local ip="$1"
  gum spin --title "Pinging (IPv4) $ip" -- ping -4 -c 4 -- "$ip"
}

gum style --border double --margin "1 2" --padding "1 2" --border-foreground 212 \
  "Welcome to $title"

existing_ip="$(get_existing)"
if [[ -n "$existing_ip" ]]; then
  gum style --foreground 212 "Current SERVER_IP: $existing_ip"
  if ! confirm "Do you want to modify the SERVER_IP?"; then
    echo "Keeping existing SERVER_IP: $existing_ip"
    # Optional reachability check (non-fatal)
    ping_host_v4 "$existing_ip" || true
    exec sudo bash "$NEXT"
  fi
fi

# Prompt until we get a valid IPv4
while :; do
  host="$(gum input --placeholder "e.g. 192.168.10.100" \
    ${existing_ip:+--value "$existing_ip"})"
  [[ -z "${host:-}" ]] && {
    echo "No input provided. Exiting."
    exit 0
  }

  if ! valid_ipv4 "$host"; then
    gum style --foreground 196 "Invalid IPv4 address. Use dotted-quad with octets 0–255 (e.g., 10.0.0.5)."
    continue
  fi

  # Try ping (user may still save if unreachable)
  if ! ping_host_v4 "$host"; then
    if ! confirm "Ping failed. Save \"$host\" anyway?"; then
      continue
    fi
  fi

  SERVER_IP="$host"
  break
done

set_server_ip "$SERVER_IP"
echo "Your server IP is set to: $SERVER_IP"

exec sudo bash "$NEXT"
