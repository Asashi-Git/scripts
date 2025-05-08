#!/bin/bash

# Arch Linux Security Options Script
# This script adds security options to /etc/fstab:
# 1. Restricts /proc visibility with hidepid=2
# 2. Secures /tmp with nosuid, nodev, noexec flags

# Check if script is run with root privileges
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root"
	exit 1
fi

echo "===== Adding Security Options to /etc/fstab ====="

# Create a backup of the original fstab file
BACKUP_FILE="/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
echo "Creating backup of /etc/fstab at $BACKUP_FILE"
cp /etc/fstab "$BACKUP_FILE"
echo "Backup created."

# Function to check if an entry already exists
entry_exists() {
	local pattern="$1"
	grep -q "$pattern" /etc/fstab
	return $?
}

# Check and add /proc with hidepid=2 if it doesn't exist
echo "Checking for secure /proc configuration..."
if ! entry_exists "^proc.*hidepid=2"; then
	echo "Adding secure /proc entry with hidepid=2"
	echo -e "\n# Security: Hide process information from other users" >>/etc/fstab
	echo "proc           /proc            proc            hidepid=2 0 0" >>/etc/fstab
	echo "/proc secured with hidepid=2"
else
	echo "Secure /proc entry already exists in fstab"
fi

# Check and add /tmp with security options if it doesn't exist
echo "Checking for secure /tmp configuration..."
if ! entry_exists "^tmpfs.*\/tmp.*nosuid,nodev,noexec"; then
	echo "Adding secure /tmp entry with nosuid, nodev, noexec flags"
	echo -e "\n# Security: Secure /tmp directory" >>/etc/fstab
	echo "tmpfs          /tmp             tmpfs           nosuid,nodev,noexec 0 0" >>/etc/fstab
	echo "/tmp secured with nosuid, nodev, noexec flags"
else
	echo "Secure /tmp entry already exists in fstab"
fi

echo "===== Security Options Added to /etc/fstab ====="
echo "To apply changes without rebooting, run:"
echo "  sudo mount -o remount /proc"
echo "  sudo mount -o remount /tmp"
echo ""
echo "Original /etc/fstab backed up to: $BACKUP_FILE"

exit 0
