#!/bin/bash

# Root User Hardening Script for Arch Linux
# This script disables direct root login by:
# 1. Changing the root shell to /usr/sbin/nologin
# 2. Locking the root password in /etc/shadow by adding '!' before the hash

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

# Lock root password in /etc/shadow by adding '!' before the hash value
echo "[*] Locking root password in /etc/shadow..."

# Extract the current root line from /etc/shadow
ROOT_LINE=$(grep "^root:" /etc/shadow)

# Check if root password is already locked
if [[ "$ROOT_LINE" == root:\!* ]]; then
	echo "[*] Root password is already locked."
else
	# Add a '!' at the beginning of the password field while preserving the original hash
	# This changes root:$hash:... to root:!$hash:...
	sed -i 's/^root:$ [^!] $ /root:!\1/' /etc/shadow

	# Verify the change
	if grep -q "^root:!" /etc/shadow; then
		echo "[+] Successfully locked root password by adding '!' before the hash"
	else
		echo "[-] Failed to lock root password."
		echo "    Please check /etc/shadow manually."
		exit 1
	fi
fi

echo "[+] Root account hardening completed successfully!"
echo "[+] Backups created: /etc/passwd.bak.* and /etc/shadow.bak.*"
echo "[!] You can still access root privileges using sudo"
echo "[!] If you need to reverse these changes, restore from the backup files"

exit 0
