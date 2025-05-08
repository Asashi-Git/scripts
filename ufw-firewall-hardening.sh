#!/bin/bash

# UFW Configuration Script for Arch Linux
# This script configures UFW with security-focused settings

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
	echo "This script must be run as root"
	exit 1
fi

echo "===== UFW Configuration Script for Arch Linux ====="
echo "This script will:"
echo "  1. Install UFW"
echo "  2. Configure system settings"
echo "  3. Set up UFW rules"
echo "  4. Configure TCP SYN packet validation"
echo ""

# Function to check if a command succeeded
check_status() {
	if [ $? -eq 0 ]; then
		echo "[SUCCESS] $1"
	else
		echo "[ERROR] $1"
		echo "Would you like to continue anyway? (y/n)"
		read continue_choice
		if [[ $continue_choice != "y" && $continue_choice != "Y" ]]; then
			echo "Exiting script."
			exit 1
		fi
	fi
}

# Step 1: Install UFW
echo "Installing UFW..."
pacman -S --noconfirm ufw
check_status "UFW installation"

# Step 2: Change IPT_SYSCTL in /etc/default/ufw
echo "Configuring /etc/default/ufw..."
if [ -f /etc/default/ufw ]; then
	sed -i 's|IPT_SYSCTL=/etc/ufw/sysctl.conf|IPT_SYSCTL=/etc/sysctl.conf|' /etc/default/ufw
	check_status "Modified IPT_SYSCTL setting"
else
	echo "[WARNING] /etc/default/ufw file not found. Creating it..."
	echo "IPT_SYSCTL=/etc/sysctl.conf" >/etc/default/ufw
	check_status "Created /etc/default/ufw with IPT_SYSCTL setting"
fi

# Step 3: Add sysctl settings
echo "Configuring network security settings..."
SYSCTL_FILE="/etc/sysctl.d/90-network-security.conf"

# Create or add to the sysctl configuration file
if [ ! -f "$SYSCTL_FILE" ]; then
	touch "$SYSCTL_FILE"
fi

# Check if settings already exist, if not append them
if ! grep -q "net.ipv4.icmp_echo_ignore_broadcasts = 1" "$SYSCTL_FILE"; then
	cat <<EOF >>"$SYSCTL_FILE"

# ICMP redirects section:
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.icmp_echo_ignore_all = 0

# Log martians section:
net.ipv4.conf.all.log_martians = 0
net.ipv4.conf.default.log_martians = 0
EOF
	check_status "Added network security settings"
else
	echo "[INFO] Network security settings already exist in $SYSCTL_FILE"
fi

# Apply sysctl settings
echo "Applying sysctl settings..."
sysctl -p "$SYSCTL_FILE"
check_status "Applied sysctl settings"

# Step 4: Configure SSH port
echo "Current SSH port is typically 22. Would you like to change it? (y/n)"
read change_ssh_port
SSH_PORT=22

if [[ $change_ssh_port == "y" || $change_ssh_port == "Y" ]]; then
	echo "Enter your SSH port number (1-65535):"
	read new_ssh_port

	# Validate port number
	if [[ "$new_ssh_port" =~ ^[0-9]+$ && "$new_ssh_port" -ge 1 && "$new_ssh_port" -le 65535 ]]; then
		SSH_PORT=$new_ssh_port
	else
		echo "[WARNING] Invalid port number. Using default port 22."
	fi
fi

echo "Using SSH port: $SSH_PORT"

# Step 5: Configure UFW rules for SSH
echo "Setting up UFW SSH rules..."
ufw allow "$SSH_PORT"
check_status "Added rule to allow SSH connections on port $SSH_PORT"

ufw limit "$SSH_PORT"
check_status "Added rate limiting for SSH connections"

# Step 6: Add TCP SYN packet validation to before.rules
echo "Configuring TCP SYN packet validation for IPv4..."
BEFORE_RULES="/etc/ufw/before.rules"
IPv4_RULES="-A ufw-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j ufw-logging-deny\n-A ufw-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j DROP"

# Check if rules already exist
if ! grep -q "ufw-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j DROP" "$BEFORE_RULES"; then
	# Insert the rules before the COMMIT line
	sed -i "/^COMMIT/i $IPv4_RULES" "$BEFORE_RULES"
	check_status "Added TCP SYN packet validation to before.rules"
else
	echo "[INFO] TCP SYN packet validation rules already exist in before.rules"
fi

# Step 7: Add TCP SYN packet validation to before6.rules
echo "Configuring TCP SYN packet validation for IPv6..."
BEFORE6_RULES="/etc/ufw/before6.rules"
IPv6_RULES="-A ufw6-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j ufw6-logging-deny\n-A ufw6-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j DROP"

# Check if rules already exist
if ! grep -q "ufw6-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j DROP" "$BEFORE6_RULES"; then
	# Insert the rules before the COMMIT line
	sed -i "/^COMMIT/i $IPv6_RULES" "$BEFORE6_RULES"
	check_status "Added TCP SYN packet validation to before6.rules"
else
	echo "[INFO] TCP SYN packet validation rules already exist in before6.rules"
fi

# Step 8: Check if UFW is enabled, if not, enable it
echo "Checking UFW status..."
UFW_STATUS=$(ufw status | grep -o "Status: active")
if [ -z "$UFW_STATUS" ]; then
	echo "Enabling UFW..."
	echo "y" | ufw enable # Auto-confirm the prompt
	check_status "Enabled UFW"
else
	echo "UFW is already active. Reloading rules..."
	ufw reload
	check_status "Reloaded UFW rules"
fi

echo ""
echo "===== UFW Configuration Complete ====="
echo "Current UFW Status:"
ufw status verbose
echo ""
echo "If you changed the SSH port, make sure to update your SSH client settings."
echo "If you're connected via SSH now, don't close this session until you've confirmed"
echo "that you can connect on the new port."
