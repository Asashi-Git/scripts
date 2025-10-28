#!/usr/bin/env bash
# WireGuard Server and User Manager for Arch Linux
# Author: Your team
# Purpose: Educational use only in isolated lab environments
# Requires: bash, wg, wg-quick, wireguard-tools, systemd; optional: qrencode
# Tested on: Arch Linux
#
# Features:
# - One-time server initialization (keys, wg0.conf, NAT rules via iptables)
# - Interactive peer creation with full/split tunnel options + optional preshared key
# - Auto IP allocation from 10.0.0.0/24
# - Exports client .conf and shows QR if qrencode exists
# - List/revoke peers, regenerate client files
#
# Security Notes:
# - Keys stored under /etc/wireguard/keys with 0700 perms
# - Minimal output of private keys to terminal
# - Backups original wg0.conf to wg0.conf.bak.YYYYmmdd-HHMMSS

set -euo pipefail

WG_DIR="/etc/wireguard"
KEY_DIR="${WG_DIR}/keys"
SERVER_CONF="${WG_DIR}/wg0.conf"
SERVER_IF="wg0"
DEFAULT_VPN_NET="10.0.0.0/24"
SERVER_ADDR="10.0.0.1/24"
DEFAULT_PORT="51820" # You can randomize during setup
# Preset split-tunnel networks (your lab)
PRESET_SPLIT_NETS=("192.168.0.0/24" "192.168.40.0/24" "192.168.50.0/24" "192.168.60.0/24" "192.168.70.0/24" "192.168.80.0/24")

# --- Helpers ---------------------------------------------------------------

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "[-] Please run as root (sudo)."
    exit 1
  fi
}

cmd_exists() { command -v "$1" &>/dev/null; }

pause() { read -rp "Press Enter to continue..."; }

timestamp() { date +"%Y%m%d-%H%M%S"; }

detect_wan_iface() {
  # Detect default route interface (Internet-facing)
  ip route show default | awk '/default/ {print $5; exit}'
}

ensure_packages() {
  # Optional: install wireguard-tools if missing
  if ! cmd_exists wg || ! cmd_exists wg-quick; then
    echo "[*] Installing wireguard-tools..."
    pacman -Sy --noconfirm wireguard-tools
  fi
}

ensure_sysctl_ipfwd() {
  local f="/etc/sysctl.d/99-ipforward.conf"
  if ! grep -qs '^net.ipv4.ip_forward=1' "$f" 2>/dev/null; then
    echo "[*] Enabling net.ipv4.ip_forward..."
    echo "net.ipv4.ip_forward=1" >"$f"
    sysctl --system >/dev/null
  fi
}

backup_conf() {
  if [[ -f "$SERVER_CONF" ]]; then
    cp -a "$SERVER_CONF" "${SERVER_CONF}.bak.$(timestamp)"
    echo "[*] Backup created: ${SERVER_CONF}.bak.$(timestamp)"
  fi
}

init_dirs() {
  mkdir -p "$KEY_DIR"
  chmod 700 "$KEY_DIR"
}

gen_keypair() {
  # $1 = basename (e.g., server, client-alice)
  local base="$1"
  umask 077
  wg genkey | tee "${KEY_DIR}/${base}-priv.key" | wg pubkey >"${KEY_DIR}/${base}-pub.key"
}

gen_psk() {
  # $1 = basename
  local base="$1"
  umask 077
  wg genpsk >"${KEY_DIR}/${base}-psk.key"
}

read_key() {
  # $1 = path
  tr -d '\n' <"$1"
}

server_initialized() {
  [[ -f "$SERVER_CONF" ]]
}

allocate_client_ip() {
  # Find next free IP in 10.0.0.0/24 starting from .2
  local used
  used=$(awk '/AllowedIPs/ {print $3}' "$SERVER_CONF" 2>/dev/null | cut -d/ -f1 || true)
  for i in $(seq 2 254); do
    local cand="10.0.0.${i}"
    if ! grep -q "$cand" <<<"$used"; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}

enable_service() {
  systemctl enable --now "wg-quick@${SERVER_IF}.service"
}

restart_service() {
  systemctl restart "wg-quick@${SERVER_IF}.service"
}

# --- Server Initialization --------------------------------------------------

init_server() {
  echo "=== WireGuard Server Initialization ==="
  if server_initialized; then
    echo "[!] ${SERVER_CONF} already exists."
    read -rp "Do you want to reset/recreate the server config? (y/N): " yn
    yn=${yn:-n}
    if [[ "$yn" =~ ^[Yy]$ ]]; then
      backup_conf
    else
      echo "[*] Skipping server initialization."
      return
    fi
  fi

  ensure_packages
  ensure_sysctl_ipfwd
  init_dirs

  local wan_if
  wan_if=$(detect_wan_iface)
  if [[ -z "$wan_if" ]]; then
    read -rp "Could not auto-detect WAN interface. Enter interface name (e.g., ens18): " wan_if
  else
    echo "[*] Detected WAN interface: ${wan_if}"
  fi

  # Port and endpoint
  local port endpoint
  read -rp "Enter listen UDP port [${DEFAULT_PORT}]: " port
  port=${port:-$DEFAULT_PORT}

  read -rp "Enter public endpoint (WAN IP or FQDN): " endpoint
  if [[ -z "$endpoint" ]]; then
    echo "[-] Endpoint is required (e.g., your WAN IP 82.67.90.49 or DNS)."
    exit 1
  fi

  # Server keys
  if [[ ! -f "${KEY_DIR}/server-priv.key" ]]; then
    echo "[*] Generating server keys..."
    gen_keypair "server"
  else
    echo "[*] Server keys already exist, reusing."
  fi
  local server_priv server_pub
  server_priv=$(read_key "${KEY_DIR}/server-priv.key")
  server_pub=$(read_key "${KEY_DIR}/server-pub.key")

  # Build wg0.conf
  cat >"$SERVER_CONF" <<EOF
[Interface]
Address = ${SERVER_ADDR}
ListenPort = ${port}
PrivateKey = ${server_priv}
# NAT for VPN clients going out via ${wan_if}
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${wan_if} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${wan_if} -j MASQUERADE
EOF

  chmod 600 "$SERVER_CONF"

  echo "[*] Enabling and starting wg-quick@${SERVER_IF}..."
  enable_service

  echo "=== Server ready ==="
  echo "PublicKey: ${server_pub}"
  echo "Listen: ${port}/udp"
  echo "Endpoint: ${endpoint}:${port}"
  echo "Config: ${SERVER_CONF}"
  echo
  echo "[!] Remember to allow UDP ${port} on your firewall (UFW/pfSense) and forward it to this VM."
}

# --- Peer Management --------------------------------------------------------

add_peer() {
  if ! server_initialized; then
    echo "[-] Server not initialized yet. Run 'Initialize server' first."
    return
  fi

  local name
  read -rp "Enter new peer name (e.g., marc): " name
  [[ -z "$name" ]] && {
    echo "[-] Peer name required."
    return
  }

  # Check if peer already exists
  if grep -q "### ${name}$" "$SERVER_CONF"; then
    echo "[-] Peer '${name}' already exists in ${SERVER_CONF}."
    return
  fi

  # Full-tunnel vs Split-tunnel
  echo "Choose traffic mode:"
  echo "  1) Full tunnel (0.0.0.0/0, ::/0)"
  echo "  2) Split tunnel (choose networks)"
  read -rp "Selection [1/2]: " mode
  mode=${mode:-1}

  local allowed_ips dns
  if [[ "$mode" == "1" ]]; then
    allowed_ips="0.0.0.0/0, ::/0"
    read -rp "DNS for client (e.g., 192.168.0.254 or 1.1.1.1) [1.1.1.1]: " dns
    dns=${dns:-"1.1.1.1"}
  else
    echo "Preset local networks:"
    local idx=1
    for n in "${PRESET_SPLIT_NETS[@]}"; do
      echo "  $idx) $n"
      ((idx++))
    done
    echo "You can also add custom CIDRs later."
    local selections sel_arr=()
    read -rp "Enter numbers separated by spaces (e.g., '1 4 6'), or leave empty for manual: " selections
    if [[ -n "$selections" ]]; then
      for s in $selections; do
        if [[ "$s" =~ ^[0-9]+$ ]] && ((s >= 1 && s <= ${#PRESET_SPLIT_NETS[@]})); then
          sel_arr+=("${PRESET_SPLIT_NETS[$((s - 1))]}")
        fi
      done
    fi
    local custom=""
    read -rp "Add custom CIDRs (comma-separated, or empty): " custom
    if [[ -n "$custom" ]]; then
      # normalize commas
      IFS=',' read -r -a extra <<<"$custom"
      for e in "${extra[@]}"; do
        e=$(echo "$e" | xargs)
        [[ -n "$e" ]] && sel_arr+=("$e")
      done
    fi
    if [[ ${#sel_arr[@]} -eq 0 ]]; then
      echo "[-] No networks selected; defaulting to 192.168.0.0/24."
      sel_arr=("192.168.0.0/24")
    fi
    allowed_ips=$(
      IFS=', '
      echo "${sel_arr[*]}"
    )
    read -rp "DNS for client (e.g., 192.168.0.254) [192.168.0.254]: " dns
    dns=${dns:-"192.168.0.254"}
  fi

  # Optional preshared key
  local use_psk="n"
  read -rp "Use a preshared key for this peer? (y/N): " use_psk
  use_psk=${use_psk:-n}

  # Allocate IP
  local ip
  ip=$(allocate_client_ip) || {
    echo "[-] No free IPs available in 10.0.0.0/24."
    return
  }
  local ip_cidr="${ip}/32"
  echo "[*] Assigning ${ip_cidr} to peer '${name}'."

  # Generate keys
  gen_keypair "client-${name}"
  local priv pub
  priv=$(read_key "${KEY_DIR}/client-${name}-priv.key")
  pub=$(read_key "${KEY_DIR}/client-${name}-pub.key")

  local psk=""
  if [[ "$use_psk" =~ ^[Yy]$ ]]; then
    gen_psk "client-${name}"
    psk=$(read_key "${KEY_DIR}/client-${name}-psk.key")
  fi

  # Read server public key and endpoint/port
  local server_pub server_port endpoint
  server_pub=$(read_key "${KEY_DIR}/server-pub.key")
  server_port=$(awk -F'= ' '/^ListenPort/ {print $2}' "$SERVER_CONF")
  # Ask endpoint for client file convenience (don’t overwrite server conf)
  read -rp "Endpoint for client (host:port) [leave empty to use previously entered or IP:port]: " endpoint
  if [[ -z "$endpoint" ]]; then
    # Try to recover from earlier message or localhost IP:
    # Grabs the first non-comment 'ListenPort' and assumes admin knows host; fall back to placeholder
    endpoint="<your.public.endpoint>:${server_port}"
  fi

  # Append Peer to server config
  {
    echo ""
    echo "### ${name}"
    echo "[Peer]"
    echo "PublicKey = ${pub}"
    [[ -n "$psk" ]] && echo "PresharedKey = ${psk}"
    echo "AllowedIPs = ${ip_cidr}"
  } >>"$SERVER_CONF"

  chmod 600 "$SERVER_CONF"
  restart_service
  echo "[*] Peer '${name}' added and service restarted."

  # Create client conf
  local client_conf="${WG_DIR}/${name}.conf"
  {
    echo "[Interface]"
    echo "Address = ${ip}/24"
    echo "PrivateKey = ${priv}"
    [[ -n "$dns" ]] && echo "DNS = ${dns}"
    echo ""
    echo "[Peer]"
    echo "PublicKey = ${server_pub}"
    [[ -n "$psk" ]] && echo "PresharedKey = ${psk}"
    echo "AllowedIPs = ${allowed_ips}"
    echo "Endpoint = ${endpoint}"
    echo "PersistentKeepalive = 25"
  } >"$client_conf"
  chmod 600 "$client_conf"

  echo "=== Client file ==="
  echo "$client_conf"
  echo "You can distribute this file securely to the user."

  if cmd_exists qrencode; then
    echo "[*] Showing QR (use 'wg-quick import' on mobile):"
    qrencode -t ansiutf8 <"$client_conf"
  else
    echo "[i] Install 'qrencode' for QR output (pacman -S qrencode)."
  fi
}

list_peers() {
  if ! server_initialized; then
    echo "[-] Server not initialized yet."
    return
  fi
  echo "=== Current Peers (from ${SERVER_CONF}) ==="
  awk '
    BEGIN{peer="";name=""}
    /^### /{name=$0; sub(/^### /,"",name); print "- " name;}
  ' "$SERVER_CONF"
  echo
  echo "=== Runtime Status (wg show) ==="
  wg show
}

revoke_peer() {
  if ! server_initialized; then
    echo "[-] Server not initialized yet."
    return
  fi
  read -rp "Enter peer name to revoke: " name
  [[ -z "$name" ]] && {
    echo "[-] Name required."
    return
  }

  if ! grep -q "### ${name}$" "$SERVER_CONF"; then
    echo "[-] Peer '${name}' not found."
    return
  fi

  backup_conf
  # Remove block from '### name' until next blank line or next [Peer]/### tag
  awk -v n="### ${name}" '
    BEGIN{skip=0}
    $0==n {skip=1; next}
    skip==1 && /^\s*(\[Peer\]|### |$)/ {skip=0}
    skip==0 {print}
  ' "$SERVER_CONF" >"${SERVER_CONF}.tmp"

  mv "${SERVER_CONF}.tmp" "$SERVER_CONF"
  chmod 600 "$SERVER_CONF"
  restart_service

  # Optionally remove client files/keys
  read -rp "Delete keys and client config for '${name}'? (y/N): " del
  del=${del:-n}
  if [[ "$del" =~ ^[Yy]$ ]]; then
    rm -f "${WG_DIR}/${name}.conf" \
      "${KEY_DIR}/client-${name}-priv.key" \
      "${KEY_DIR}/client-${name}-pub.key" \
      "${KEY_DIR}/client-${name}-psk.key" 2>/dev/null || true
    echo "[*] Client files removed."
  fi
  echo "[*] Peer '${name}' revoked."
}

regen_client_conf() {
  if ! server_initialized; then
    echo "[-] Server not initialized yet."
    return
  fi

  read -rp "Enter peer name to regenerate .conf (keys unchanged): " name
  [[ -z "$name" ]] && {
    echo "[-] Name required."
    return
  }

  # Extract current IP, PSK presence, and server params
  local ip_line
  ip_line=$(awk -v n="### ${name}" '
    $0==n {flag=1}
    flag && /^AllowedIPs/ {print; exit}
  ' "$SERVER_CONF") || true

  if [[ -z "$ip_line" ]]; then
    echo "[-] Peer '${name}' not found."
    return
  fi

  local ip
  ip=$(awk -F'= ' '{print $2}' <<<"$ip_line" | cut -d'/' -f1)

  local priv pub psk_file psk=""
  priv=$(read_key "${KEY_DIR}/client-${name}-priv.key")
  pub=$(read_key "${KEY_DIR}/client-${name}-pub.key")
  psk_file="${KEY_DIR}/client-${name}-psk.key"
  if [[ -f "$psk_file" ]]; then
    psk=$(read_key "$psk_file")
  fi

  local server_pub server_port endpoint allowed_ips dns
  server_pub=$(read_key "${KEY_DIR}/server-pub.key")
  server_port=$(awk -F'= ' '/^ListenPort/ {print $2}' "$SERVER_CONF")
  read -rp "New Endpoint for client (host:port), empty to keep placeholder: " endpoint
  endpoint=${endpoint:-"<your.public.endpoint>:${server_port}"}
  read -rp "AllowedIPs for client (comma-separated) [0.0.0.0/0, ::/0]: " allowed_ips
  allowed_ips=${allowed_ips:-"0.0.0.0/0, ::/0"}
  read -rp "DNS (empty to omit) [1.1.1.1]: " dns
  dns=${dns:-"1.1.1.1"}

  local client_conf="${WG_DIR}/${name}.conf"
  {
    echo "[Interface]"
    echo "Address = ${ip}/24"
    echo "PrivateKey = ${priv}"
    [[ -n "$dns" ]] && echo "DNS = ${dns}"
    echo ""
    echo "[Peer]"
    echo "PublicKey = ${server_pub}"
    [[ -n "$psk" ]] && echo "PresharedKey = ${psk}"
    echo "AllowedIPs = ${allowed_ips}"
    echo "Endpoint = ${endpoint}"
    echo "PersistentKeepalive = 25"
  } >"$client_conf"
  chmod 600 "$client_conf"
  echo "[*] Regenerated: ${client_conf}"

  if cmd_exists qrencode; then
    echo "[*] QR:"
    qrencode -t ansiutf8 <"$client_conf"
  fi
}

# --- Menu -------------------------------------------------------------------

main_menu() {
  while true; do
    echo
    echo "================ WireGuard Manager ================"
    echo "1) Initialize server (one-time)"
    echo "2) Add new peer"
    echo "3) List peers and status"
    echo "4) Revoke a peer"
    echo "5) Regenerate client config"
    echo "6) Show server public info"
    echo "7) Exit"
    echo "==================================================="
    read -rp "Choose an option: " choice
    case "$choice" in
    1) init_server ;;
    2) add_peer ;;
    3)
      list_peers
      pause
      ;;
    4) revoke_peer ;;
    5) regen_client_conf ;;
    6)
      if server_initialized; then
        echo "Server conf: ${SERVER_CONF}"
        awk '/^\[Interface\]/{p=1} p && /^ListenPort/ {print; p=0}' "$SERVER_CONF"
        echo -n "PublicKey: "
        read_key "${KEY_DIR}/server-pub.key"
        echo
      else
        echo "[-] Server not initialized."
      fi
      pause
      ;;
    7) exit 0 ;;
    *) echo "Invalid choice" ;;
    esac
  done
}

# --- Entry ------------------------------------------------------------------

need_root
main_menu
