#!/bin/bash

# UFW Firewall Hardening Script for Arch Linux
# This script:
# 1. Installs UFW if not already installed
# 2. Configures sysctl settings for network security
# 3. Sets up UFW with hardened rules
# 4. Adds protection against invalid packets and port scanning
# 5. Secures SSH access

# Check if script is run with root privileges
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root"
	exit 1
fi

# Default settings
NETWORK_CONF="/etc/sysctl.d/90-network-security.conf"
BACKUP_DIR="/root/ufw_backup"
UFW_BEFORE_RULES="/etc/ufw/before.rules"
UFW_BEFORE6_RULES="/etc/ufw/before6.rules"

# Create backup directory
mkdir -p $BACKUP_DIR

echo "===== UFW Firewall Setup and Hardening ====="

# Function to backup a file before modifying
backup_file() {
	local file=$1
	local backup="${BACKUP_DIR}/$(basename ${file}).bak.$(date +%Y%m%d%H%M%S)"

	# Only backup if file exists
	if [ -f "$file" ]; then
		cp "$file" "$backup"
		echo "✓ Backed up $file to $backup"
	fi
}

# Function to validate port number
validate_port() {
	local port=$1

	# Check if port is a number
	if ! [[ "$port" =~ ^[0-9]+$ ]]; then
		echo "Port must be a number"
		return 1
	fi

	# Check if port is in the valid range (1-65535)
	if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
		echo "Port must be between 1 and 65535"
		return 1
	fi

	return 0
}

# Step 1: Check and Install UFW
echo -e "\n[1/5] Checking and installing UFW..."

# Check if UFW is installed
if ! command -v ufw &>/dev/null; then
	echo "UFW not found. Installing..."
	if ! pacman -Syu ufw --noconfirm; then
		echo " Failed to install UFW. Please check your package manager."
		exit 1
	fi
	echo "✓ UFW installed successfully."
else
	echo "✓ UFW is already installed."
fi

# Check UFW status and reset if needed
ufw_status=$(ufw status verbose | grep -o "Status: active")
if [ -n "$ufw_status" ]; then
	echo "UFW is currently active. Disabling and resetting..."
	ufw disable
	ufw reset
	echo "✓ UFW has been reset."
else
	echo "✓ UFW is not active, proceeding with configuration."
fi

# Step 2: Update sysctl Network Security Configuration
echo -e "\n[2/5] Updating sysctl network security settings..."

# Backup existing config if it exists
backup_file "$NETWORK_CONF"

# Check if the file exists, if not create it
if [ ! -f "$NETWORK_CONF" ]; then
	touch "$NETWORK_CONF"
	echo "✓ Created new network security configuration file."
else
	echo "✓ Found existing network security configuration file."
fi

# Add or update ICMP settings
if grep -q "icmp_echo_ignore_broadcasts" "$NETWORK_CONF"; then
	echo "ICMP settings already exist in $NETWORK_CONF. Updating..."
	sed -i '/icmp_echo_ignore_broadcasts/c\net.ipv4.icmp_echo_ignore_broadcasts = 1' "$NETWORK_CONF"
	sed -i '/icmp_ignore_bogus_error_responses/c\net.ipv4.icmp_ignore_bogus_error_responses = 1' "$NETWORK_CONF"
	sed -i '/icmp_echo_ignore_all/c\net.ipv4.icmp_echo_ignore_all = 0' "$NETWORK_CONF"
else
	echo "Adding ICMP settings to $NETWORK_CONF..."
	cat >>"$NETWORK_CONF" <<'EOF'

# ICMP settings (added by UFW hardening script)
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.icmp_echo_ignore_all = 0
EOF
fi

# Add or update log_martians settings
if grep -q "log_martians" "$NETWORK_CONF"; then
	echo "log_martians settings already exist in $NETWORK_CONF. Updating..."
	sed -i '/net.ipv4.conf.all.log_martians/c\net.ipv4.conf.all.log_martians = 1' "$NETWORK_CONF"
	sed -i '/net.ipv4.conf.default.log_martians/c\net.ipv4.conf.default.log_martians = 1' "$NETWORK_CONF"
else
	echo "Adding log_martians settings to $NETWORK_CONF..."
	cat >>"$NETWORK_CONF" <<'EOF'

# Log suspicious packets (added by UFW hardening script)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
EOF
fi

# Apply sysctl settings
echo "Applying updated sysctl settings..."
sysctl --system

if [ $? -ne 0 ]; then
	echo " Failed to apply sysctl settings. Check the output above for errors."
	exit 1
else
	echo "✓ Successfully applied sysctl settings."
fi

# Step 3: Configure SSH access
echo -e "\n[3/5] Configuring SSH access..."

# Ask user for SSH port
while true; do
	read -p "Enter the SSH port number that your server uses (default: 22): " SSH_PORT

	# Use default port if empty input
	if [ -z "$SSH_PORT" ]; then
		SSH_PORT=22
	fi

	if validate_port "$SSH_PORT"; then
		echo "Using SSH port: $SSH_PORT for UFW configuration"
		break
	else
		echo "Invalid port, please try again."
	fi
done

# Step 4: Modify UFW rules files to block invalid packets
echo -e "\n[4/5] Hardening UFW rules to block invalid packets and port scanning..."

# Backup before.rules and before6.rules
backup_file "$UFW_BEFORE_RULES"
backup_file "$UFW_BEFORE6_RULES"

# Function to add anti-portscanning rules to before.rules files
add_antipscan_rules() {
	local rules_file=$1
	local prefix=$2

	# Define INSERT_POINT based on file type (IPv4 or IPv6)
	local INSERT_POINT
	if [[ "$prefix" == "ufw-before" ]]; then
		INSERT_POINT="# End required lines"
	else
		INSERT_POINT="# End required lines"
	fi

	# Check if anti-port scanning rules already exist
	if grep -q "${prefix}-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN" "$rules_file"; then
		echo "Anti-port scanning rules already exist in $rules_file"
	else
		echo "Adding anti-port scanning rules to $rules_file"

		# Create temporary file with updated rules
		local temp_file=$(mktemp)

		awk -v insert_point="$INSERT_POINT" -v prefix="$prefix" '
        {print}
        $0 ~ insert_point {
            print ""
            print "# Block invalid packets (added by UFW hardening script)"
            print "-A " prefix "-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j " prefix "-logging-deny"
            print "-A " prefix "-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j DROP"
            print ""
            print "# Block port scanning (added by UFW hardening script)"
            print "-A " prefix "-input -p tcp -m conntrack --ctstate NEW -m recent --set"
            print "-A " prefix "-input -p tcp -m conntrack --ctstate NEW -m recent --update --seconds 30 --hitcount 6 -j " prefix "-logging-deny"
            print "-A " prefix "-input -p tcp -m conntrack --ctstate NEW -m recent --update --seconds 30 --hitcount 6 -j DROP"
            print ""
        }
        ' "$rules_file" >"$temp_file"

		# Replace original file with updated one
		cat "$temp_file" >"$rules_file"
		rm "$temp_file"
	fi
}

# Add anti-port scanning rules to IPv4 and IPv6 rule files
add_antipscan_rules "$UFW_BEFORE_RULES" "ufw-before"
add_antipscan_rules "$UFW_BEFORE6_RULES" "ufw6-before"

echo "✓ UFW rules files have been hardened."

# Step 5: Configure and enable UFW
echo -e "\n[5/5] Configuring and enabling UFW..."

# Set default UFW policies
echo "Setting default policies (deny incoming, allow outgoing)..."
ufw default deny incoming
ufw default allow outgoing

# Allow SSH with rate limiting
echo "Allowing SSH on port $SSH_PORT with rate limiting..."
ufw allow "$SSH_PORT/tcp" comment "SSH"
ufw limit "$SSH_PORT/tcp" comment "SSH rate limited"

# Enable logging
echo "Enabling UFW logging..."
ufw logging on

# Enable UFW with confirmation bypass
echo "Enabling UFW firewall..."
echo "y" | ufw enable

if [ $? -ne 0 ]; then
	echo " Failed to enable UFW. Check the output above for errors."
	exit 1
else
	# Reload UFW to apply all changes
	ufw reload
	echo "✓ UFW has been enabled and configured successfully."
fi

# Display status
echo -e "\n===== UFW Configuration Complete =====\n"
ufw status verbose

echo -e "\nFirewall configuration summary:"
echo "  - Default policy: Deny incoming, allow outgoing"
echo "  - SSH allowed and rate-limited on port $SSH_PORT"
echo "  - Added protection against port scanning"
echo "  - Added protection against invalid packets"
echo "  - Updated sysctl network security parameters"
echo -e "\nImportant commands:"
echo "  ufw status verbose   - Show detailed firewall status"
echo "  ufw allow <port>     - Allow traffic on a specific port"
echo "  ufw deny <port>      - Deny traffic on a specific port"
echo "  ufw disable          - Disable the firewall"
echo "  ufw reload           - Apply configuration changes"

exit 0
