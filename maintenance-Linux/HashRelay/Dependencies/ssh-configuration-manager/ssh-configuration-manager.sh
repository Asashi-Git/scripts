#!/usr/bin/env bash
# This script verify the ssh have been correctly installed and activated
# If not, it activate the service and configure it.
#
# ssh user@server 'chmod +x /path/to/script.sh && /path/to/script.sh'
#
# Author: Decarnelle Samuel

# Ensure we are root
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

NEXT="/usr/local/bin/HashRelay/ufw-configuration-manager/ufw-configuration-manager.sh"
DETECT_PATH="${DETECT_PATH:-/usr/local/bin/HashRelay/distro-and-pkgman-detect/distro-and-pkgman-detect.sh}"

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

# -------------- Detector invocation -----------------
run_detector() {
  # Validate detector path exists (file) and/or is executable
  if [[ ! -x "$DETECT_PATH" && ! -f "$DETECT_PATH" ]]; then
    log "[!] Detector not found at $DETECT_PATH"
    exit 1
  fi
  vlog "[*] Running detector (sudo bash): $DETECT_PATH kv"
  sudo bash "$DETECT_PATH" kv
  # The detector prints key=value lines (e.g., DistroID=arch, Package-Managers=pacman)
  # The trailing "kv" tells our detector to output key-value format.
}

# Capture detector output into an array, one element per line.
mapfile -t DET_OUT < <(run_detector)

# Parse detector output lines into an associative array KV
declare -Ag KV=() # -A: associative array, -g: global (in case inside a function)
for line in "${DET_OUT[@]}"; do
  [[ -z "$line" || "$line" =~ ^\# ]] && continue     # skip empty or commented lines
  if [[ "$line" =~ ^([A-Za-z0-9._-]+)=(.*)$ ]]; then # key=value pattern
    key="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"
    KV["$key"]="$val"
  fi
done

# Validate detector essentials
DISTRO_ID="${KV[DistroID]:-unknown}"
if [[ -z "$DISTRO_ID" || "$DISTRO_ID" == "unknown" ]]; then
  log "[!] Could not determine DistroID."
  for k in DistroPretty DistroID DistroLike DistroVersion WSL Container; do
    log "    detector preview: $k=${KV["$k"]:-}"
  done
  exit 1
else
  echo "Your DistroID is $DISTRO_ID"
fi

# Create the correct working path for the DistroID
case "$DISTRO_ID" in
arch | archlinux | ubuntu | debian | linuxmint)
  SSH_PATH="/etc/ssh/sshd_config"
  ;;

*)
  echo "[!] Unsupported distro '$DISTRO_ID'."
  echo "    Set SSH_PATH manually."
  exit 1
  ;;
esac

# Verify that OpenSSH is installed
is_openssh_installed() {
  if command -v sshd >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

if is_openssh_installed; then
  echo "OpenSSH server is installed."
  IS_INSTALLED=true
else
  echo "OpenSSH server is NOT installed."
  IS_INSTALLED=false
fi

# See if openssh is installed and run correctly
if systemctl is-active sshd >/dev/null 2>&1; then
  echo "SSH service is RUNNING."
  IS_RUNNING=true
else
  echo "SSH service is NOT running."
  sudo systemctl enable sshd
  sudo systemctl start sshd
  IS_RUNNING=false
  if systemctl is-active sshd >/dev/null 2>&1; then
    echo "SSH servise is now RUNNING."
    IS_RUNNING=true
  else
    echo "[!] ERROR: Unable to enable openssh, you will need to enable it yourself."
    IS_RUNNING=false
  fi
fi

# function to see if the ssh configuration si already done
get_config() {
  [[ -f "$SSH_PATH" ]] || {
    echo ""
    return
  }

  local line
  line="$(grep -E 'Match User HashRelay' "$SSH_PATH" | tail -n1 || true)"
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

RESULT=$(get_config)

# Putting the configuration inside the SSH_PATH
if [[ ! "$RESULT" == "Match User HashRelay" ]]; then
  if [[ "$IS_SERVER" == true ]]; then
    if [[ "$SSH_PATH" ]]; then
      if [[ "$IS_INSTALLED" == true ]]; then
        if [[ "$IS_RUNNING" == true ]]; then
          echo "[*] Starting to put the configuration inside the $SSH_PATH file"
          cat <<EOF | sudo tee -a "$SSH_PATH" >/dev/null
Match User HashRelay
    AllowUsers HashRelay
    PasswordAuthentication no
    PubkeyAuthentication yes
    AllowTcpForwarding no
    X11Forwarding no
    PermitTTY yes
    AuthorizedKeysFile	.ssh/id_HashRelay.pub
EOF

          echo "[*] Configuration file $SSH_PATH UPDATED !"

          # Creating the key for the ssh
          sudo -u HashRelay ssh-keygen -t ed25519 \
            -f /home/HashRelay/.ssh/id_HashRelay \
            -N "" -q

          # Restart the sshd service
          sudo systemctl restart sshd
        fi
      fi
    fi
  fi
else
  echo "[!] Skipping The config was found inside $SSH_PATH"
fi

# Then execute the next script
exec sudo bash "$NEXT"
