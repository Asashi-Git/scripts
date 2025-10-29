#!/usr/bin/env bash
# WireGuard Server and User Manager for Arch Linux
# Purpose: Educational use only in isolated lab environments
# Requires: bash, wg, wg-quick, wireguard-tools, systemd; optional: qrencode, curl, iptables, ufw, python3
# Tested on: Arch Linux
set -euo pipefail

WG_DIR="/etc/wireguard"
KEY_DIR="${WG_DIR}/keys"
SERVER_CONF="${WG_DIR}/wg0.conf"
SERVER_IF="wg0"
DEFAULT_VPN_NET="10.0.0.0/24"
SERVER_ADDR="10.0.0.1/24"
DEFAULT_PORT="51820"
PRESET_SPLIT_NETS=("192.168.0.0/24" "192.168.40.0/24" "192.168.50.0/24" "192.168.60.0/24" "192.168.70.0/24" "192.168.80.0/24")
TMP_HTTP_PORT="8080"
UFW_RULE_COMMENT="wg-tmp-http"

# ------------------------- Helpers -------------------------

need_root() { if [[ $EUID -ne 0 ]]; then
  echo "[-] Please run as root (sudo)."
  exit 1
fi; }
cmd_exists() { command -v "$1" &>/dev/null; }
pause() { read -rp "Press Enter to continue..."; }
timestamp() { date +"%Y%m%d-%H%M%S"; }
detect_wan_iface() { ip route show default | awk '/default/ {print $5; exit}'; }

detect_public_ip() {
  local ip=""
  if cmd_exists curl; then
    ip=$(curl -4fsS --max-time 3 ifconfig.me || true)
    [[ -z "${ip}" ]] && ip=$(curl -4fsS --max-time 3 icanhazip.com || true)
  fi
  echo "${ip}"
}

detect_local_ip() {
  hostname -I 2>/dev/null | awk '{print $1}'
}

ensure_packages() {
  if ! cmd_exists wg || ! cmd_exists wg-quick; then
    echo "[*] Installing wireguard-tools..."
    pacman -Sy --noconfirm wireguard-tools
  fi
  if ! cmd_exists curl; then
    echo "[*] Installing curl..."
    pacman -Sy --noconfirm curl
  fi
  if ! cmd_exists qrencode; then
    echo "[i] qrencode not found (optional, for QR output)."
  fi
  if ! cmd_exists python3; then
    echo "[*] Installing python..."
    pacman -Sy --noconfirm python
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
    local bkp="${SERVER_CONF}.bak.$(timestamp)"
    cp -a "$SERVER_CONF" "$bkp"
    chmod 600 "$bkp"
    echo "[*] Backup created: $bkp"
  fi
}

init_dirs() {
  mkdir -p "$KEY_DIR"
  chmod 700 "$KEY_DIR"
  chmod 700 "$WG_DIR"
}

umask_strict() { umask 077; }

gen_keypair() {
  # $1 = basename (e.g., server, client-alice)
  local base="$1"
  umask_strict
  wg genkey | tee "${KEY_DIR}/${base}-priv.key" | wg pubkey >"${KEY_DIR}/${base}-pub.key"
  chmod 600 "${KEY_DIR}/${base}-priv.key" "${KEY_DIR}/${base}-pub.key"
}

read_key() { cat "$1"; }

server_initialized() { [[ -f "$SERVER_CONF" ]]; }

get_listen_port() { awk -F'= *' '/^ListenPort/ {print $2}' "$SERVER_CONF" 2>/dev/null || true; }

# -------------------- UFW 8080 open/close --------------------

ufw_is_active() {
  if ! cmd_exists ufw; then return 1; fi
  ufw status | grep -qi "Status: active"
}

ufw_open_8080() {
  if ufw_is_active; then
    # Only add if not present
    if ! ufw status numbered | grep -qE "\b${TMP_HTTP_PORT}(/tcp)?\b.*${UFW_RULE_COMMENT}"; then
      echo "[*] UFW active: allowing tcp/${TMP_HTTP_PORT} temporarily"
      ufw allow ${TMP_HTTP_PORT}/tcp comment "${UFW_RULE_COMMENT}" >/dev/null
    fi
  fi
}

ufw_close_8080() {
  if ufw_is_active; then
    # Delete rules by comment
    local mapfile_out
    mapfile -t mapfile_out < <(ufw status numbered | nl -ba | sed -n 's/^\s*\([0-9]\+\)\s*\[\s*\([0-9]\+\)\]\s*\(.*\)$/\2 \3/p')
    # Above extracts: "<rule_number> <rule_text>"
    # We must delete from highest to lowest index to avoid renumbering issues.
    local to_delete=()
    while IFS= read -r line; do
      :
    done < <(printf "%s\n" "${mapfile_out[@]}")
    # Récupère les numéros de règle contenant notre commentaire
    while read -r num rest; do
      if [[ "$rest" == *"$UFW_RULE_COMMENT"* ]]; then
        to_delete+=("$num")
      fi
    done < <(printf "%s\n" "${mapfile_out[@]}")

    # Supprime en ordre inverse
    for n in $(printf "%s\n" "${to_delete[@]}" | sort -rn); do
      yes | ufw delete "$n" >/dev/null 2>&1 || true
    done
  fi
}

# -------------------- Server init --------------------

init_server() {
  ensure_packages
  ensure_sysctl_ipfwd
  init_dirs
  backup_conf

  local port pub_ip wan_if
  read -rp "Listen port [${DEFAULT_PORT}]: " port
  port=${port:-$DEFAULT_PORT}
  pub_ip=$(detect_public_ip || true)
  wan_if=$(detect_wan_iface)

  if [[ -z "$wan_if" ]]; then
    echo "[-] Could not detect WAN interface; continue anyway (edit PostUp/PostDown later)."
  else
    echo "[i] Detected WAN interface: $wan_if"
  fi

  if [[ ! -f "${KEY_DIR}/server-priv.key" ]]; then
    echo "[*] Generating server keypair..."
    gen_keypair "server"
  fi
  local server_priv server_pub
  server_priv=$(read_key "${KEY_DIR}/server-priv.key")
  server_pub=$(read_key "${KEY_DIR}/server-pub.key")

  cat >"$SERVER_CONF" <<EOF
[Interface]
Address = ${SERVER_ADDR}
ListenPort = ${port}
PrivateKey = ${server_priv}
SaveConfig = true
# NAT (iptables). Adjust iface if detect_wan_iface failed.
PostUp = iptables -t nat -A POSTROUTING -o ${wan_if:-eth0} -j MASQUERADE; iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o ${wan_if:-eth0} -j MASQUERADE; iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT
EOF
  chmod 600 "$SERVER_CONF"
  echo "[*] Created $SERVER_CONF"
  echo "[i] Server public key: $server_pub"

  # Enable and start
  systemctl enable --now "wg-quick@${SERVER_IF}" >/dev/null
  systemctl is-active "wg-quick@${SERVER_IF}" && echo "[*] Service wg-quick@${SERVER_IF} is active."

  # Endpoint info
  if [[ -n "$pub_ip" ]]; then
    echo "[i] Detected public endpoint: ${pub_ip}:$port"
  else
    echo "[i] No public IP detected; you can set a DNS name or ensure Internet access."
  fi
}

# --------------- IP allocation and helpers ---------------

ip_to_int() {
  local IFS=.
  read -r a b c d <<<"$1"
  echo $(((a << 24) + (b << 16) + (c << 8) + d))
}
int_to_ip() {
  local ip=$1
  printf "%d.%d.%d.%d" $(((ip >> 24) & 255)) $(((ip >> 16) & 255)) $(((ip >> 8) & 255)) $((ip & 255))
}

next_available_ip() {
  # Scans existing AllowedIPs in server conf; returns next IP in 10.0.0.0/24 starting from 10.0.0.2
  local network="10.0.0"
  local used=()
  if [[ -f "$SERVER_CONF" ]]; then
    used+=("$(awk -F'= *' '/^Address/ {print $2}' "$SERVER_CONF" | cut -d'/' -f1)")
    used+=($(awk -F'= *' '/^AllowedIPs/ {print $2}' "$SERVER_CONF" | tr ',' '\n' | tr -d ' ' | grep -E "^${network}\." | cut -d'/' -f1 || true))
  fi
  local base=$(ip_to_int "${network}.1")
  local i
  for ((i = 2; i < 255; i++)); do
    local candidate_ip="${network}.${i}"
    local found=0
    for x in "${used[@]}"; do
      [[ "$x" == "$candidate_ip" ]] && found=1 && break
    done
    if [[ $found -eq 0 ]]; then
      echo "$candidate_ip"
      return 0
    fi
  done
  return 1
}

server_endpoint() {
  # Prefer detected public IP; else try existing Endpoint in a client conf generation context.
  local port
  port=$(get_listen_port)
  local ip=$(detect_public_ip || true)
  if [[ -n "$ip" && -n "$port" ]]; then
    echo "${ip}:${port}"
  elif [[ -n "$port" ]]; then
    echo "CHANGE_ME_DNS_OR_IP:${port}"
  else
    echo "CHANGE_ME_DNS_OR_IP:${DEFAULT_PORT}"
  fi
}

# --------------------- Peer management ---------------------

add_peer() {
  if ! server_initialized; then
    echo "[-] Server not initialized."
    return
  fi

  read -rp "New peer name (no spaces recommended): " name_raw
  [[ -z "$name_raw" ]] && {
    echo "[-] Name required."
    return
  }

  local safe_name
  safe_name=$(echo "$name_raw" | tr -cd 'A-Za-z0-9._-')
  if [[ -z "$safe_name" ]]; then
    echo "[-] Invalid name (allowed: A-Za-z0-9._-)"
    return
  fi
  if [[ "$safe_name" != "$name_raw" ]]; then echo "[i] Using sanitized name: $safe_name"; fi

  local ip
  ip=$(next_available_ip) || {
    echo "[-] No free IP left in ${DEFAULT_VPN_NET}"
    return
  }

  echo "[1] Full tunnel (0.0.0.0/0)  [2] Split tunnel (choose presets) [3] Custom"
  read -rp "AllowedIPs mode [1/2/3]: " mode
  local allowed_ips=""
  case "${mode:-1}" in
  1) allowed_ips="0.0.0.0/0, ::/0" ;;
  2) allowed_ips=$(
    IFS=,
    echo "${PRESET_SPLIT_NETS[*]}"
  ) ;;
  3) read -rp "Enter AllowedIPs (comma-separated): " allowed_ips ;;
  *) allowed_ips="0.0.0.0/0, ::/0" ;;
  esac

  read -rp "Add preshared key? [y/N]: " use_psk
  local psk=""
  if [[ "${use_psk,,}" == "y" ]]; then
    psk=$(wg genpsk)
  fi

  read -rp "Client DNS (optional, comma-separated, e.g. 1.1.1.1,9.9.9.9): " dns
  local endpoint server_pub
  server_pub=$(read_key "${KEY_DIR}/server-pub.key")
  endpoint=$(server_endpoint)

  # Keys
  gen_keypair "client-${safe_name}"
  local priv pub
  priv=$(read_key "${KEY_DIR}/client-${safe_name}-priv.key")
  pub=$(read_key "${KEY_DIR}/client-${safe_name}-pub.key")

  # Add to server conf
  backup_conf
  {
    echo ""
    echo "[Peer]"
    echo "PublicKey = ${pub}"
    [[ -n "$psk" ]] && echo "PresharedKey = ${psk}"
    echo "AllowedIPs = ${ip}/32"
  } >>"$SERVER_CONF"

  # Apply live
  wg set "$SERVER_IF" peer "$pub" $([[ -n "$psk" ]] && printf "preshared-key %s " <(echo "$psk")) allowed-ips "${ip}/32"

  # Client conf
  local client_conf="${WG_DIR}/${safe_name}.conf"
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
  echo "[*] Client config written: $client_conf"

  if cmd_exists qrencode; then
    echo "[*] QR (scan with WireGuard mobile):"
    qrencode -t ansiutf8 <"$client_conf"
  fi
}

list_peers() {
  if ! server_initialized; then
    echo "[-] Server not initialized."
    return
  fi
  echo "Interfaces:"
  wg show interfaces
  echo
  wg show "$SERVER_IF"
}

revoke_peer() {
  if ! server_initialized; then
    echo "[-] Server not initialized."
    return
  fi
  read -rp "Peer name to revoke: " name
  [[ -z "$name" ]] && {
    echo "[-] Name required."
    return
  }
  local pub_key_file="${KEY_DIR}/client-${name}-pub.key"
  if [[ ! -f "$pub_key_file" ]]; then
    echo "[-] Unknown peer keys: $pub_key_file"
    return
  fi
  local pub
  pub=$(read_key "$pub_key_file")

  # Remove live
  wg set "$SERVER_IF" peer "$pub" remove || true

  # Edit server conf (remove block [Peer] ... PublicKey=pub)
  backup_conf
  awk -v pk="$pub" '
    BEGIN{skip=0}
    /^\[Peer\]/{buf=""; block=1; skip=0}
    {
      if(block){buf=buf $0 ORS}
      else{print}
      if($0 ~ /^PublicKey *=/){
        split($0,a,"= "); if(a[2]==pk){skip=1}
      }
    }
    /^\s*$/{ if(block){ if(!skip){printf "%s", buf} block=0; buf=""} }
    END{ if(block && !skip){printf "%s", buf} }
  ' "$SERVER_CONF" >"${SERVER_CONF}.tmp" && mv "${SERVER_CONF}.tmp" "$SERVER_CONF"

  echo "[*] Revoked peer $name. You may delete $WG_DIR/${name}.conf and keys if desired."
}

regen_client_conf() {
  if ! server_initialized; then
    echo "[-] Server not initialized."
    return
  fi
  read -rp "Peer name to regenerate: " name
  local client_conf="${WG_DIR}/${name}.conf"
  if [[ ! -f "$client_conf" ]]; then
    echo "[-] Not found: $client_conf"
    return
  fi

  local ip priv psk server_pub endpoint allowed_ips dns
  ip=$(awk -F'= *' '/^\[Interface\]/{f=1} f && /^Address/ {print $2; exit}' "$client_conf" | cut -d'/' -f1)
  priv=$(awk -F'= *' '/^\[Interface\]/{f=1} f && /^PrivateKey/ {print $2; exit}' "$client_conf")
  dns=$(awk -F'= *' '/^\[Interface\]/{f=1} f && /^DNS/ {print $2; exit}' "$client_conf" || true)
  allowed_ips=$(awk -F'= *' '/^\[Peer\]/{f=1} f && /^AllowedIPs/ {print $2; exit}' "$client_conf")
  psk=$(awk -F'= *' '/^\[Peer\]/{f=1} f && /^PresharedKey/ {print $2; exit}' "$client_conf" || true)
  server_pub=$(read_key "${KEY_DIR}/server-pub.key")
  endpoint=$(server_endpoint)

  {
    echo "[Interface]"
    echo "Address = ${ip}/24"
    echo "PrivateKey = ${priv}"
    [[ -n "$dns" ]] && echo "DNS = ${dns}"
    echo
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

# ----------------- Export + temporary HTTP server -----------------

export_and_serve_peer() {
  read -rp "Peer name to export: " name_raw
  [[ -z "$name_raw" ]] && {
    echo "[-] Peer name required."
    return
  }

  local safe_name
  safe_name=$(echo "$name_raw" | tr -cd 'A-Za-z0-9._-')
  if [[ -z "$safe_name" ]]; then
    echo "[-] Peer name results in empty safe filename. Use alphanum/._-"
    return
  fi
  if [[ "$safe_name" != "$name_raw" ]]; then
    echo "[i] Using sanitized filename: ${safe_name}.conf (from '${name_raw}')"
  fi

  local src="${WG_DIR}/${name_raw}.conf"
  if [[ ! -f "$src" ]]; then
    echo "[-] ${src} not found. Generate it first (menu 2/5)."
    return
  fi

  local tmpdir
  tmpdir=$(mktemp -d -p /tmp wgexport-XXXX)
  chmod 700 "$tmpdir"

  # Secure copy and served copy
  cp -a "$src" "${tmpdir}/${safe_name}.conf.secure"
  chmod 600 "${tmpdir}/${safe_name}.conf.secure"
  cp -a "$src" "${tmpdir}/${safe_name}.conf"
  chmod 644 "${tmpdir}/${safe_name}.conf"

  if [[ ! -f "${tmpdir}/${safe_name}.conf" ]]; then
    echo "[-] Unexpected: file not present in temp dir."
    rm -rf "$tmpdir"
    return
  fi

  local pub_ip local_ip
  pub_ip=$(detect_public_ip || true)
  local_ip=$(detect_local_ip || true)

  ufw_open_8080

  echo "[*] Starting temporary HTTP server on 0.0.0.0:${TMP_HTTP_PORT}"
  echo "    Index:  http://${local_ip:-127.0.0.1}:${TMP_HTTP_PORT}/"
  echo "    File :  http://${local_ip:-127.0.0.1}:${TMP_HTTP_PORT}/${safe_name}.conf"
  [[ -n "$pub_ip" ]] && {
    echo "    WAN   :  http://${pub_ip}:${TMP_HTTP_PORT}/${safe_name}.conf (requires pfSense NAT/port-fwd + hairpin for LAN)"
  }

  echo "[i] Press Enter to stop. HTTP logs will be shown below."
  (python3 -m http.server "${TMP_HTTP_PORT}" --bind 0.0.0.0 --directory "$tmpdir") &
  local srv_pid=$!

  sleep 0.3
  if cmd_exists curl; then
    echo "[i] Self-test (local):"
    curl -sI "http://127.0.0.1:${TMP_HTTP_PORT}/${safe_name}.conf" || true
  fi

  read -r # wait for Enter

  kill "$srv_pid" 2>/dev/null || true
  wait "$srv_pid" 2>/dev/null || true
  ufw_close_8080
  rm -rf "$tmpdir"
  echo "[*] Temporary HTTP server stopped and files removed."
}

# ----------------- Edit client .conf (AllowedIPs/DNS) -----------------

edit_peer_conf() {
  read -rp "Peer name to edit: " name
  local client_conf="${WG_DIR}/${name}.conf"
  if [[ ! -f "$client_conf" ]]; then
    echo "[-] Not found: $client_conf"
    return
  fi

  echo "1) Set/replace DNS"
  echo "2) Set/replace AllowedIPs"
  echo "3) Set both DNS and AllowedIPs"
  read -rp "Choose [1/2/3]: " choice

  local new_dns new_allowed
  case "$choice" in
  1)
    read -rp "DNS (comma-separated): " new_dns
    ;;
  2)
    read -rp "AllowedIPs (comma-separated): " new_allowed
    ;;
  3)
    read -rp "DNS (comma-separated): " new_dns
    read -rp "AllowedIPs (comma-separated): " new_allowed
    ;;
  *)
    echo "[-] Invalid choice"
    return
    ;;
  esac

  backup="${client_conf}.bak.$(timestamp)"
  cp -a "$client_conf" "$backup"
  chmod 600 "$backup"

  awk -v dns="$new_dns" -v aip="$new_allowed" '
    BEGIN{in_if=0; in_peer=0; dns_set=0; aip_set=0}
    /^\[Interface\]/{in_if=1; in_peer=0}
    /^\[Peer\]/{in_if=0; in_peer=1}
    {
      if(in_if && dns!="" && $0 ~ /^DNS *=/){ if(!dns_set){print "DNS = " dns; dns_set=1} next }
      if(in_peer && aip!="" && $0 ~ /^AllowedIPs *=/){ if(!aip_set){print "AllowedIPs = " aip; aip_set=1} next }
      print
    }
    END{
      if(dns!="" && !dns_set){
        print ""; print "[Interface]"; print "DNS = " dns
      }
      if(aip!="" && !aip_set){
        print ""; print "[Peer]"; print "AllowedIPs = " aip
      }
    }
  ' "$backup" >"$client_conf"

  chmod 600 "$client_conf"
  echo "[*] Updated: $client_conf"
  [[ -n "$new_dns" ]] && echo "    DNS = $new_dns"
  [[ -n "$new_allowed" ]] && echo "    AllowedIPs = $new_allowed"
}

# ----------------- Show server public info -----------------

show_server_info() {
  if server_initialized; then
    echo "Server conf: ${SERVER_CONF}"
    awk '/^\[Interface\]/{p=1} p && /^ListenPort/ {print; p=0}' "$SERVER_CONF"
    echo -n "PublicKey: "
    read_key "${KEY_DIR}/server-pub.key"
    echo
    local ep_host=$(detect_public_ip || true)
    local ep_port=$(awk -F'= *' '/^ListenPort/ {print $2}' "$SERVER_CONF")
    [[ -n "$ep_host" ]] && echo "Endpoint (auto): ${ep_host}:${ep_port}"
  else
    echo "[-] Server not initialized."
  fi
}

# ------------------------- Menu -------------------------

main_menu() {
  while true; do
    echo
    echo "================ WireGuard Manager ================"
    echo "1) Initialize server (one-time)"
    echo "2) Add new peer"
    echo "3) List peers and status"
    echo "4) Revoke a peer"
    echo "5) Regenerate client config"
    echo "6) Export a client .conf and serve it temporarily (HTTP 8080)"
    echo "7) Edit a client .conf (AllowedIPs/DNS)"
    echo "8) Show server public info"
    echo "9) Exit"
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
    6) export_and_serve_peer ;;
    7) edit_peer_conf ;;
    8)
      show_server_info
      pause
      ;;
    9) exit 0 ;;
    *) echo "Invalid choice" ;;
    esac
  done
}

# ------------------------- Entry -------------------------
need_root
main_menu
