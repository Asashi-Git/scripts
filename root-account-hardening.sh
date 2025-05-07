#!/bin/bash

# Root User Hardening Script for Arch Linux
# This script disables direct root login by:
# 1. Changing the root shell to /usr/sbin/nologin
# 2. Replacing the root password hash with '!' in /etc/shadow

# Check if running with sudo/root privileges
if [ "$EUID" -ne 0 ]; then
	echo "Error: This script must be run as root or with sudo privileges."
	exit 1
fi

echo "[*] Starting root account hardening process..."

# Backup original files
echo "[*] Creating backups of configuration files..."
cp /etc/passwd /etc/passwd.bak.$(date +%Y%m%d-%H%M%S)
cp /etc/shadow /etc/shadow.bak.$(date +%Y%m%d-%H%M%S)

# Change root shell to nologin in /etc/passwd
echo "[*] Changing root shell to /usr/sbin/nologin in /etc/passwd..."
sed -i 's|^root:.*$|root:x:0:0:root:/root:/usr/sbin/nologin|' /etc/passwd

# Verify the change
if grep -q "root:x:0:0:root:/root:/usr/sbin/nologin" /etc/passwd; then
	echo "[+] Successfully changed root shell to /usr/sbin/nologin"
else
	echo "[-] Failed to change root shell."
	echo "    Please check /etc/passwd manually."
	exit 1
fi

# Replace the root password hash with '!' in /etc/shadow
echo "[*] Replacing root password hash with '!' in /etc/shadow..."

# Use sed to replace the second field (between first and second colon) with '!'
sed -i 's/^root:[^:]*:/root:!:/' /etc/shadow

# Verify the change
if grep -q "^root:!:" /etc/shadow; then
	echo "[+] Successfully replaced root password hash with '!'"
else
	echo "[-] Failed to replace root password hash."
	echo "    Please check /etc/shadow manually."
	exit 1
fi

echo "[+] Root account hardening completed successfully!"
echo "[+] Backups created: /etc/passwd.bak.* and /etc/shadow.bak.*"
echo "[!] You can still access root privileges using sudo"
echo "[!] If you need to reverse these changes, restore from the backup files"

exit 0
