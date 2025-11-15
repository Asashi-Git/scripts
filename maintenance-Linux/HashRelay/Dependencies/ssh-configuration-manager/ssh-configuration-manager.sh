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
  exec sudo bash "$NEXT"
fi
