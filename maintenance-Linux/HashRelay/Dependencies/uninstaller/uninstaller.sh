#!/usr/bin/env bash
# This script uninstall the agent
#
# Author: Decarnelle Samuel

# Ensure we are root
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "HashRelay must be run as root (use sudo)." >&2
  exit 1
fi

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

# Ask the user to confirm his choice to uninstall HashRelay
if [[ "$IS_CLIENT" == true ]]; then
  sudo systemctl disable --now hashrelay-backups.timer
  rm -rf /usr/local/bin/HashRelay
  rm -rf /usr/local/bin/hashrelay
  rm -rf /var/log/HashRelay
  rm -rf /etc/systemd/system/hashrelay-backups.service
  rm -rf /etc/systemd/system/hashrelay-backups.timer
  sudo systemctl daemon-reload
else
  sudo systemctl disable --now hashrealy-delete.timer
  sudo systemctl disable --now hashrealy-receiver.timer
  rm -rf /usr/local/bin/HashRelay
  rm -rf /usr/local/bin/hashrelay
  rm -rf /var/log/HashRelay
  rm -rf /etc/systemd/system/hashrelay-delete.service
  rm -rf /etc/systemd/system/hashrelay-delete.timer
  rm -rf /etc/systemd/system/hashrelay-receiver.service
  rm -rf /etc/systemd/system/hashrelay-receiver.timer
  sudo systemctl daemon-reload
fi

echo "[!] HashRelay have been uninstalled"
