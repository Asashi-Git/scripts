#!/usr/bin/env bash
# This script verify the ssh have been correctly installed and activated
# If not, it activate the service and configure it.
#
# Author: Decarnelle Samuel

NEXT="/usr/local/bin/HashRelay/ufw-configuration-manager/ufw-configuration-manager.sh"

if systemctl is-active sshd >/dev/null 2>&1; then
  echo "SSH service is RUNNING."
  exec sudo bash "$NEXT"
else
  echo "SSH service is NOT running."
  echo "Enable ssh yourself"
  exec sudo bash "$NEXT"
fi

# Command to do for the ssh config
#
# Match User HashRelay
#    AllowUsers HashRelay
#    PasswordAuthentication no
#    PubkeyAuthentication yes
#    AllowTcpForwarding no
#    X11Forwarding no
#    PermitTTY yes
#    AuthorizedKeysFile	.ssh/id_HashRelay.pub
#
# sudo -u HashRelay ssh-keygen -t ed25519 -f /home/HashRelay/.ssh/id_HashRelay
# sudo -u HashRelay cat /home/HashRelay/.ssh/id_HashRelay.pub >> /home/sam/.ssh/authorized_keys
#
# ssh user@server 'chmod +x /path/to/script.sh && /path/to/script.sh'
