#!/usr/bin/env bash
# WireGuard Server and User Manager for Arch Linux
# Purpose: Educational use only in isolated lab environments
set -euo pipefail

WG_DIR="/etc/wireguard"
KEY_DIR="${WG_DIR}/keys"
SERVER_CONF="${WG_DIR}/wg0.conf"
SERVER_IF="wg0"
DEFAULT_VPN_NET="10.0.0.0/24"
SERVER_ADDR="10.0.0.1/24"
DEFAULT_PORT="51820"
PRESET_SPLIT_NETS=("192.168.0.0/24" "192.168.40.0/24" "192.168.50.0/24" "192.168.60.0/24" "192.168.70.0/24" "192.168.80.0/24")

# --- Helpers ---------------------------------------------------------------

need_root() { if [[ $EUID -ne 0 ]]; then
  echo "[-] Please run as root (sudo)."
  exit 1
fi; }
cmd_exists() { command -v "$1" &>/dev/null; }
pause() { read -rp "Press Enter to continue..."; }
timestamp() { date +"%Y%m%d-%H%M%S"; }
detect_wan_iface() { ip route show default | awk '/default/ {print $5; exit}'; }

# NEW: détecter IP publique proprement (fallback si ifconfig.me indispo)
detect_public_ip() {
  local ip=""
  if cmd_exists curl; then
    ip=$(curl -4fsS --max-time 3 ifconfig.me || true)
    [[ -z "${ip}" ]] && ip=$(curl -4fsS --max-time 3 icanhazip.com || true)
  fi
  echo "${ip}"
}

# NEW: IP locale “principale” (affichage URL LAN)
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
  if ! cmd_exists python3; then
    echo "[*] Installing python (for temporary HTTP server)..."
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
    local bk="${SERVER_CONF}.bak.$(timestamp)"
    cp -a "$SERVER_CONF" "$bk"
    echo "[*] Backup created: $bk"
  fi
}

init_dirs() {
  mkdir -p "$KEY_DIR"
  chmod 700 "$KEY_DIR"
}

gen_keypair() {
  local base="$1"
  umask 077
  wg genkey | tee "${KEY_DIR}/${base}-priv.key" | wg pubkey >"${KEY_DIR}/${base}-pub.key"
}

gen_psk() {
  local base="$1"
  umask 077
  wg genpsk >"${KEY_DIR}/${base}-psk.key"
}
read_key() { tr -d '\n' <"$1"; }
server_initialized() { [[ -f "$SERVER_CONF" ]]; }

allocate_client_ip() {
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

enable_service() { systemctl enable --now "wg-quick@${SERVER_IF}.service"; }
restart_service() { systemctl restart "wg-quick@${SERVER_IF}.service"; }

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

  local port endpoint_host endpoint_auto
  read -rp "Enter listen UDP port [${DEFAULT_PORT}]: " port
  port=${port:-$DEFAULT_PORT}

  # NEW: endpoint auto via IP publique détectée
  endpoint_auto=$(detect_public_ip || true)
  if [[ -n "$endpoint_auto" ]]; then
    endpoint_host="$endpoint_auto"
    echo "[*] Detected public IP: ${endpoint_host}"
  else
    echo "[!] Unable to detect public IP automatically."
    read -rp "Enter public endpoint host (WAN IP or FQDN): " endpoint_host
    [[ -z "$endpoint_host" ]] && {
      echo "[-] Endpoint is required."
      exit 1
    }
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
  echo "Endpoint: ${endpoint_host}:${port}"
  echo "Config: ${SERVER_CONF}"
  echo
  echo "[!] Remember to allow UDP ${port} on your firewall and forward it to this VM."
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

  if grep -q "### ${name}$" "$SERVER_CONF"; then
    echo "[-] Peer '${name}' already exists in ${SERVER_CONF}."
    return
  fi

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
    local selections sel_arr=()
    read -rp "Enter numbers separated by spaces (e.g., '1 4 6'), or leave empty for manual: " selections
    if [[ -n "$selections" ]]; then
      for s in $selections; do
        if [[ "$s" =~ ^[0-9]+$ ]] && ((s >= 1 && s <= ${#PRESET_SPLIT_NETS[@]})); then sel_arr+=("${PRESET_SPLIT_NETS[$((s - 1))]}"); fi
      done
    fi
    local custom=""
    read -rp "Add custom CIDRs (comma-separated, or empty): " custom
    if [[ -n "$custom" ]]; then
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

  local use_psk="n"
  read -rp "Use a preshared key for this peer? (y/N): " use_psk
  use_psk=${use_psk:-n}

  local ip ip_cidr
  ip=$(allocate_client_ip) || {
    echo "[-] No free IPs available in 10.0.0.0/24."
    return
  }
  ip_cidr="${ip}/32"
  echo "[*] Assigning ${ip_cidr} to peer '${name}'."

  gen_keypair "client-${name}"
  local priv pub
  priv=$(read_key "${KEY_DIR}/client-${name}-priv.key")
  pub=$(read_key "${KEY_DIR}/client-${name}-pub.key")

  local psk=""
  if [[ "$use_psk" =~ ^[Yy]$ ]]; then
    gen_psk "client-${name}"
    psk=$(read_key "${KEY_DIR}/client-${name}-psk.key")
  fi

  local server_pub server_port endpoint_host endpoint
  server_pub=$(read_key "${KEY_DIR}/server-pub.key")
  server_port=$(awk -F'= ' '/^ListenPort/ {print $2}' "$SERVER_CONF")
  # NEW: propose endpoint auto (public IP) + port
  endpoint_host=$(detect_public_ip || true)
  if [[ -z "$endpoint_host" ]]; then
    read -rp "Endpoint host (FQDN or IP) [enter to use LAN IP]: " endpoint_host
    [[ -z "$endpoint_host" ]] && endpoint_host="$(detect_local_ip)"
  else
    echo "[*] Detected public IP for endpoint: ${endpoint_host}"
  fi
  endpoint="${endpoint_host}:${server_port}"

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
  if cmd_exists qrencode; then
    echo "[*] Showing QR:"
    qrencode -t ansiutf8 <"$client_conf"
  else echo "[i] Install 'qrencode' for QR output."; fi
}

list_peers() {
  if ! server_initialized; then
    echo "[-] Server not initialized yet."
    return
  fi
  echo "=== Current Peers (from ${SERVER_CONF}) ==="
  awk '/^### /{sub(/^### /,""); print "- "$0;}' "$SERVER_CONF" || true
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
  awk -v n="### ${name}" '
    BEGIN{skip=0}
    $0==n {skip=1; next}
    skip==1 && /^\s*(\[Peer\]|### |$)/ {skip=0}
    skip==0 {print}
  ' "$SERVER_CONF" >"${SERVER_CONF}.tmp"
  mv "${SERVER_CONF}.tmp" "$SERVER_CONF"
  chmod 600 "$SERVER_CONF"
  restart_service
  read -rp "Delete keys and client config for '${name}'? (y/N): " del
  del=${del:-n}
  if [[ "$del" =~ ^[Yy]$ ]]; then
    rm -f "${WG_DIR}/${name}.conf" "${KEY_DIR}/client-${name}-priv.key" "${KEY_DIR}/client-${name}-pub.key" "${KEY_DIR}/client-${name}-psk.key" 2>/dev/null || true
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

  local ip_line ip priv psk pub
  ip_line=$(awk -v n="### ${name}" '$0==n {flag=1} flag && /^AllowedIPs/ {print; exit}' "$SERVER_CONF") || true
  [[ -z "$ip_line" ]] && {
    echo "[-] Peer '${name}' not found."
    return
  }
  ip=$(awk -F'= ' '{print $2}' <<<"$ip_line" | cut -d'/' -f1)

  priv=$(read_key "${KEY_DIR}/client-${name}-priv.key")
  pub=$(read_key "${KEY_DIR}/client-${name}-pub.key")
  [[ -f "${KEY_DIR}/client-${name}-psk.key" ]] && psk=$(read_key "${KEY_DIR}/client-${name}-psk.key") || psk=""

  local server_pub server_port endpoint_host endpoint allowed_ips dns
  server_pub=$(read_key "${KEY_DIR}/server-pub.key")
  server_port=$(awk -F'= ' '/^ListenPort/ {print $2}' "$SERVER_CONF")
  endpoint_host=$(detect_public_ip || true)
  [[ -z "$endpoint_host" ]] && endpoint_host="$(detect_local_ip)"
  endpoint="${endpoint_host}:${server_port}"
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

# --- NEW: UFW helpers + HTTP export ----------------------------------------

ufw_is_active() {
  cmd_exists ufw && ufw status 2>/dev/null | grep -qi "Status: active"
}

ufw_open_8080() {
  if ufw_is_active; then
    echo "[*] UFW active: allowing TCP 8080 temporarily (rule 'wg-tmp-http')"
    ufw allow 8080/tcp comment 'wg-tmp-http' >/dev/null
  fi
}

ufw_close_8080() {
  if ufw_is_active; then
    echo "[*] Removing UFW rule for TCP 8080"
    # Delete by comment is not trivial; remove by port
    yes | ufw delete allow 8080/tcp >/dev/null || true
  fi
}

export_and_serve_peer() {
  # Copie le .conf d’un peer dans un dossier /tmp dédié et lance un HTTP server
  read -rp "Peer name to export: " name
  local src="${WG_DIR}/${name}.conf"
  if [[ ! -f "$src" ]]; then
    echo "[-] ${src} not found. Generate it first."
    return
  fi

  local tmpdir
  tmpdir=$(mktemp -d -p /tmp wgexport-XXXX)
  chmod 700 "$tmpdir"

  # Copie stricte + copie lisible par le serveur web (0644)
  cp -a "$src" "${tmpdir}/${name}.conf.secure"
  chmod 600 "${tmpdir}/${name}.conf.secure"
  cp -a "$src" "${tmpdir}/${name}.conf"
  chmod 644 "${tmpdir}/${name}.conf"

  local pub_ip local_ip
  pub_ip=$(detect_public_ip || true)
  local_ip=$(detect_local_ip || true)
  echo "[*] Exported to: ${tmpdir}/${name}.conf"

  ufw_open_8080

  echo "[*] Starting temporary HTTP server on 0.0.0.0:8080"
  echo "    LAN URL:  http://${local_ip:-<LAN_IP>}:8080/${name}.conf"
  [[ -n "$pub_ip" ]] && echo "    WAN URL:  http://${pub_ip}:8080/${name}.conf (requires pfSense NAT/port-fwd)"

  # Lance en arrière-plan et attend Enter pour arrêter
  (cd "$tmpdir" && python3 -m http.server 8080 --bind 0.0.0.0 >/dev/null 2>&1) &
  local srv_pid=$!

  read -rp "Press Enter to stop the temporary HTTP server..."
  kill "$srv_pid" 2>/dev/null || true
  wait "$srv_pid" 2>/dev/null || true

  ufw_close_8080

  # Purge
  rm -rf "$tmpdir"
  echo "[*] Temporary files removed and HTTP server stopped."
}

# --- NEW: Edit a client .conf (AllowedIPs / DNS) ---------------------------

edit_peer_conf() {
  read -rp "Peer name to edit: " name
  local conf="${WG_DIR}/${name}.conf"
  if [[ ! -f "$conf" ]]; then
    echo "[-] ${conf} not found."
    return
  fi

  echo "What do you want to edit?"
  echo "  1) AllowedIPs (in [Peer])"
  echo "  2) DNS (in [Interface])"
  echo "  3) Both"
  read -rp "Choice [1/2/3]: " ch
  ch=${ch:-3}

  local new_allowed="" new_dns=""
  if [[ "$ch" == "1" || "$ch" == "3" ]]; then
    read -rp "New AllowedIPs (comma-separated, e.g., 0.0.0.0/0, ::/0): " new_allowed
  fi
  if [[ "$ch" == "2" || "$ch" == "3" ]]; then
    read -rp "New DNS (comma-separated or single IP, leave empty to remove): " new_dns
  fi

  # awk réécrit le fichier en mettant à jour/ajoutant les lignes
  awk -v set_allowed="$new_allowed" -v set_dns="$new_dns" '
    BEGIN{
      in_iface=0; in_peer=0;
      done_dns=0; done_allowed=0;
    }
    /^\[Interface\]/{in_iface=1; in_peer=0}
    /^\[Peer\]/{in_peer=1; in_iface=0}

    {
      # Update DNS in [Interface]
      if(in_iface && set_dns!=""){
        if($0 ~ /^DNS[[:space:]]*=/){ if(!done_dns){ print "DNS = " set_dns; done_dns=1; } next }
      }
      # Remove DNS if empty string explicitly requested (user hit enter? we keep existing)
      if(in_iface && set_dns=="" && $0 ~ /^DNS[[:space:]]*=/){ next }

      # Update AllowedIPs in [Peer]
      if(in_peer && set_allowed!=""){
        if($0 ~ /^AllowedIPs[[:space:]]*=/){ if(!done_allowed){ print "AllowedIPs = " set_allowed; done_allowed=1; } next }
      }

      print
    }
    END{
      # If needed, append keys if they did not exist
      if(set_dns!="" && !done_dns){
        print ""
        print "[Interface]"
        print "DNS = " set_dns
      }
      if(set_allowed!="" && !done_allowed){
        print ""
        print "[Peer]"
        print "AllowedIPs = " set_allowed
      }
    }
  ' "$conf" >"${conf}.tmp"

  mv "${conf}.tmp" "$conf"
  chmod 600 "$conf"
  echo "[*] Updated: $conf"
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
      if server_initialized; then
        echo "Server conf: ${SERVER_CONF}"
        awk '/^\[Interface\]/{p=1} p && /^ListenPort/ {print; p=0}' "$SERVER_CONF"
        echo -n "PublicKey: "
        read_key "${KEY_DIR}/server-pub.key"
        echo
        local ep_host=$(detect_public_ip || true)
        local ep_port=$(awk -F'= ' '/^ListenPort/ {print $2}' "$SERVER_CONF")
        [[ -n "$ep_host" ]] && echo "Endpoint (auto): ${ep_host}:${ep_port}"
      else
        echo "[-] Server not initialized."
      fi
      pause
      ;;
    9) exit 0 ;;
    *) echo "Invalid choice" ;;
    esac
  done
}

# --- Entry ------------------------------------------------------------------
need_root
main_menu
