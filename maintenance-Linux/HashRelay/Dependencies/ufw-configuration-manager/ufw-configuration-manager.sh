#!/usr/bin/env bash
# This script see if ufw is installed in the machine
# if it's installed, allow the port chosen by the user inside the configuration installed
# if it's not, continue to the next script
#
# Author: Decarnelle Samuel

NEXT=/usr/local/bin/HashRelay/timer-manager/timer-manager.sh

echo "=== Checking UFW status ==="

# Check if ufw is installed
if command -v ufw >/dev/null 2>&1; then
  echo "UFW is installed."
else
  echo "UFW is NOT installed."
  exit 1
fi

# Check if service is enabled
if systemctl is-enabled ufw >/dev/null 2>&1; then
  echo "UFW service is ENABLED at boot."
else
  echo "UFW service is NOT enabled at boot."
fi

# Check if service is active
if systemctl is-active ufw >/dev/null 2>&1; then
  echo "UFW service is RUNNING."
else
  echo "UFW service is NOT running."
fi

exec sudo bash "$NEXT"
