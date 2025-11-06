#!/bin/bash
# This script is for education purpose
# The goal is to make a backup of the important files inside the web server like:
# /etc, /var/www, and /var/lib/mysql
#
# This script is created by Samuel Decarnelle

# Ensure we are root (needed for /etc, /var/lib/mysql, etc.)
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

# Adding the path variables
etc_path="/etc"
www_path="/var/www"
mysql_path="/var/lib/mysql"
http_path="/data/http"

# Creating the backup destination
dest="/var/log/backup/"

# Creating the variable for the date
now="$(date +%Y%m%d)"

# Creating the backup repo
mkdir -p "$dest"

# Making a backup with tar
tar -czf "$dest/backup-etc-$now.tar.gz" "$etc_path"
tar -czf "$dest/backup-www-$now.tar.gz" "$www_path"
tar -czf "$dest/backup-mysql-$now.tar.gz" "$mysql_path"
tar -czf "$dest/backup-http-$now.tar.gz" "$http_path"

if [ $? -eq 0 ]; then
  echo "Backup done: $dest (timestamp: $now)"
else
  echo "Error ! The backup cannot be done proprely. Contact you administrator !"
fi
