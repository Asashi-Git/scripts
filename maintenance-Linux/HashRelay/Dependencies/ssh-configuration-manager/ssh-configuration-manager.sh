#!/usr/bin/env bash
# This script verify the ssh have been correctly installed and activated
# If not, it activate the service and configure it.
#
# Author: Decarnelle Samuel

NEXT="/usr/local/bin/HashRelay/ufw-configuration-manager/ufw-configuration-manager.sh"
DETECT_PATH="${DETECT_PATH:-/usr/local/bin/HashRelay/distro-and-pkgman-detect/distro-and-pkgman-detect.sh}"

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

# See if openssh is installed and run correctly
if systemctl is-active sshd >/dev/null 2>&1; then
  echo "SSH service is RUNNING."
else
  echo "SSH service is NOT running."
  echo "Enable ssh yourself"
fi

# Command to do for the ssh config
#
# cat <<EOF | sudo tee -a sshd_path >/dev/null
# Match User HashRelay
#    AllowUsers HashRelay
#    PasswordAuthentication no
#    PubkeyAuthentication yes
#    AllowTcpForwarding no
#    X11Forwarding no
#    PermitTTY yes
#    AuthorizedKeysFile	.ssh/id_HashRelay.pub
# EOF
#
#
# sudo -u HashRelay ssh-keygen -t ed25519 -f /home/HashRelay/.ssh/id_HashRelay
# sudo -u HashRelay cat /home/HashRelay/.ssh/id_HashRelay.pub >> /home/sam/.ssh/authorized_keys
#
# ssh user@server 'chmod +x /path/to/script.sh && /path/to/script.sh'

exec sudo bash "$NEXT"
