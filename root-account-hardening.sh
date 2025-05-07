#!/bin/bash

# Simple script to harden the root account on Arch Linux
# 1. Changes root's shell to /usr/sbin/nologin
# 2. Locks root's password by inserting '!' for the password field

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
	echo "This script must be run as root"
	exit 1
fi

echo "[*] Creating backups..."
cp /etc/passwd /etc/passwd.backup
cp /etc/shadow /etc/shadow.backup

# Task 1: Change root shell in /etc/passwd
echo "[*] Changing root shell to /usr/sbin/nologin..."
awk -F: '$1=="root" {$NF="/usr/sbin/nologin"}1' OFS=: /etc/passwd >/tmp/passwd.new
if [ $? -eq 0 ]; then
	cat /tmp/passwd.new >/etc/passwd
	rm /tmp/passwd.new
	echo "[+] Root shell changed successfully"
else
	echo "[-] Failed to change root shell"
fi

# Task 2: Replace root's password with ! in /etc/shadow
echo "[*] Locking root password..."
awk -F: '$1=="root" {$2="!"}1' OFS=: /etc/shadow >/tmp/shadow.new
if [ $? -eq 0 ]; then
	cat /tmp/shadow.new >/etc/shadow
	rm /tmp/shadow.new
	echo "[+] Root password locked successfully"
else
	echo "[-] Failed to lock root password"
fi

# Verify changes
echo "[*] Verifying changes..."

if grep -q "^root:.*:/usr/sbin/nologin$" /etc/passwd; then
	echo "[+] Verified: root shell is now /usr/sbin/nologin"
else
	echo "[-] Error: root shell was not changed correctly"
fi

if grep -q "^root:!:" /etc/shadow; then
	echo "[+] Verified: root password is now locked"
else
	echo "[-] Error: root password was not locked correctly"
fi

echo "[*] Completed. Backups saved as /etc/passwd.backup and /etc/shadow.backup"
