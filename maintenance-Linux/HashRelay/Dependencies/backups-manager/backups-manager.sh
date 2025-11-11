#!/bin/bash
# This script is used to fetch the BACKUP_CONF file
# and backup each file to the BACKUP_DIR with tar.
#
# Author: Decarnelle Samuel

# Ensure we are root
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

BACKUP_CONF="/usr/local/bin/HashRelay/backups-manager/backups.conf"
BACKUP_DIR="/home/HashRelay/backups"
BACKUP_NAME=""
# Creating the variable for the date
NOW="$(date +%Y%m%d)"

# Creating the backup repo
mkdir -p "$BACKUP_DIR"

# Making a backup with tar
tar -czf "$BACKUP_DIR/backup-http-$NOW.tar.gz" "$BACKUP_NAME"

if [ $? -eq 0 ]; then
  echo "Backup done: $BACKUP_NAME (timestamp: $NOW)"
else
  echo "Error ! The backup cannot be done proprely. Contact you administrator !"
fi
