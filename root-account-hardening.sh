#!/bin/bash

# Root Account Hardening Script for Arch Linux
# This script disables direct root login by:
# 1. Changing the root shell to /usr/sbin/nologin
# 2. Locking the root password in /etc/shadow

# Check if script is run with root privileges
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root"
	exit 1
fi

echo "===== Starting Root Account Hardening ====="

# Backup original files
echo "Creating backups of original files..."
cp /etc/passwd /etc/passwd.bak.$(date +%Y%m%d%H%M%S)
cp /etc/shadow /etc/shadow.bak.$(date +%Y%m%d%H%M%S)
echo "Backups created."

# Step 1: Change root shell to /usr/sbin/nologin
echo "Changing root shell to /usr/sbin/nologin..."
sed -i 's|^root:.*$|root:x:0:0:root:/root:/usr/sbin/nologin|' /etc/passwd

# Verify the change
if grep "^root:.*:/usr/sbin/nologin$" /etc/passwd >/dev/null; then
	echo "Root shell successfully changed to /usr/sbin/nologin."
else
	echo "Failed to change root shell. Check /etc/passwd manually."
	exit 1
fi

# Step 2: Lock the root password in /etc/shadow
echo "Locking root password in /etc/shadow..."
sed -i 's|^root:\*:|root:!:|' /etc/shadow
sed -i 's|^root::|root:!:|' /etc/shadow
sed -i 's|^root:\$|root:!\$|' /etc/shadow

# Verify the lock
if grep "^root:!" /etc/shadow >/dev/null; then
	echo "Root password successfully locked."
else
	echo "Failed to lock root password. Check /etc/shadow manually."
	exit 1
fi

echo "===== Root Account Hardening Completed ====="
echo "Note: You can now only access root via sudo. Direct root login is disabled."
echo "Original configuration backed up to:"
echo "  - /etc/passwd.bak.$(ls -t /etc/passwd.bak.* | head -1 | cut -d '.' -f 3-)"
echo "  - /etc/shadow.bak.$(ls -t /etc/shadow.bak.* | head -1 | cut -d '.' -f 3-)"

exit 0
