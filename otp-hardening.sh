#!/bin/bash

# 2FA Hardening Script for SSH on Arch Linux
# This script:
# 1. Sets up the correct time zone
# 2. Installs and configures Google Authenticator
# 3. Configures PAM for SSH 2FA
# 4. Sets up advanced SSH security parameters
# 5. Applies and verifies all changes

# Check if script is run with root privileges
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root"
	exit 1
fi

# Default settings
SSH_CONFIG="/etc/ssh/sshd_config"
PAM_SSH_CONFIG="/etc/pam.d/sshd"
ARCH_SSH_CONFIG="/etc/ssh/sshd_config.d/99-archlinux.conf"
BACKUP_DIR="/root/ssh_2fa_backup"

# Create backup directory
mkdir -p $BACKUP_DIR

echo "===== SSH 2FA Setup and Hardening ====="

# Function to backup a file before modifying
backup_file() {
	local file=$1
	local backup="${BACKUP_DIR}/$(basename ${file}).bak.$(date +%Y%m%d%H%M%S)"
	cp "$file" "$backup"
	echo "Backed up $file to $backup"
}

# Function to validate username
validate_username() {
	local username=$1

	# Check if username exists
	if ! id "$username" &>/dev/null; then
		echo "User '$username' does not exist"
		return 1
	fi

	return 0
}

# Ask user for username
while true; do
	# List available users for convenience
	echo -e "\nAvailable non-system users:"
	awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd

	# Ask for username
	read -p "Enter username for 2FA configuration: " USERNAME

	if validate_username "$USERNAME"; then
		echo "Setting up 2FA for user: $USERNAME"
		break
	else
		echo "Invalid username, please try again."
	fi
done

# Step 1: Set up correct time zone
echo -e "\n[1/6] Setting up correct time zone..."
current_time=$(date)
echo "Current system time: $current_time"

read -p "Is this the correct time? (y/n): " time_correct
if [[ "$time_correct" != "y" && "$time_correct" != "Y" ]]; then
	# List available time zones
	timedatectl list-timezones | grep -E "^(Africa|America|Asia|Atlantic|Australia|Europe|Indian|Pacific)/" | less

	read -p "Enter your time zone (e.g., Europe/London): " timezone
	timedatectl set-timezone "$timezone"
	echo "Time zone set to: $(timedatectl | grep "Time zone" | awk '{print $3}')"
fi
echo "✓ Time zone configured."

# Step 2: Install required packages
echo -e "\n[2/6] Installing required packages..."
pacman -Sy --noconfirm libpam-google-authenticator qrencode
if [ $? -ne 0 ]; then
	echo "Failed to install packages. Check your internet connection and package availability."
	exit 1
fi
echo "✓ Packages installed successfully."

# Step 3: Configure Google Authenticator for the user
echo -e "\n[3/6] Configuring Google Authenticator for $USERNAME..."

# Define path for Google Authenticator configuration
GA_CONFIG="/home/$USERNAME/.google_authenticator"

# Check if configuration already exists and backup if needed
if [ -f "$GA_CONFIG" ]; then
	backup_file "$GA_CONFIG"
fi

# Create Google Authenticator configuration
echo -e "Setting up Google Authenticator for $USERNAME...\n"
echo "You will need to answer the following questions:"
echo "- \"Do you want authentication tokens to be time-based?\" → y (Uses time-based OTP tokens)"
echo "- \"Do you want to disallow multiple uses...?\" → y (Prevents replay attacks)"
echo "- \"Do you want to increase the original window...?\" → n (Maintains tight time synchronization requirements)"
echo "- \"Do you want to enable rate-limiting?\" → y (Prevents brute force attacks)"
echo

# Run google-authenticator as the user
echo "Launching Google Authenticator configuration tool..."
echo "IMPORTANT: Scan the QR code with your authenticator app and save the emergency scratch codes securely!"
echo

sleep 2
# Run as the specified user
sudo -u $USERNAME google-authenticator

# Check if configuration was created successfully
if [ -f "$GA_CONFIG" ]; then
	chmod 600 "$GA_CONFIG" # Ensure proper permissions
	chown $USERNAME:$USERNAME "$GA_CONFIG"
	echo "✓ Google Authenticator configured for $USERNAME."
else
	echo " Failed to configure Google Authenticator. Check for errors above."
	exit 1
fi

# Step 4: Configure PAM for SSH 2FA
echo -e "\n[4/6] Configuring PAM for SSH 2FA..."
backup_file "$PAM_SSH_CONFIG"

# Make sure PAM is configured to use Google Authenticator
if grep -q "auth required pam_google_authenticator.so" "$PAM_SSH_CONFIG"; then
	echo "Google Authenticator PAM module already configured."
else
	# Add Google Authenticator at the beginning of PAM config
	sed -i '1s/^/auth required pam_google_authenticator.so\n/' "$PAM_SSH_CONFIG"
	echo "Added Google Authenticator to PAM SSH configuration."
fi
echo "✓ PAM configured for 2FA."

# Step 5: Configure SSH to use PAM and other security settings
echo -e "\n[5/6] Configuring SSH for 2FA and enhancing security..."

# Backup SSH configuration files
backup_file "$SSH_CONFIG"
if [ -f "$ARCH_SSH_CONFIG" ]; then
	backup_file "$ARCH_SSH_CONFIG"
fi

# Update SSH configuration for 2FA
echo "Updating SSH configuration for 2FA..."

# Create a temporary file with the required configurations
cat >/tmp/ssh_2fa_config <<EOF
# SSH Server Configuration with 2FA
# Updated by 2FA setup script on $(date)

# Basic SSH settings
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Authentication settings
PasswordAuthentication no
KbdInteractiveAuthentication yes
UsePAM yes
ChallengeResponseAuthentication yes
AuthenticationMethods publickey,keyboard-interactive

# Login restrictions
LoginGraceTime 20
MaxAuthTries 3
MaxSessions 5
PermitEmptyPasswords no

# Connection settings
ClientAliveInterval 60
ClientAliveCountMax 3

# Security settings
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
TCPKeepAlive yes
PrintMotd no
PrintLastLog yes
UsePrivilegeSeparation sandbox
StrictModes yes

# Allow specific users (uncomment and modify as needed)
AllowUsers $USERNAME

# Logging
SyslogFacility AUTH
LogLevel VERBOSE
EOF

# Check if we need to modify the existing config or replace it
if grep -q "^Include /etc/ssh/sshd_config.d/\*.conf" "$SSH_CONFIG"; then
	# Arch Linux uses include files, so we need to update the arch-specific config
	echo "# This file was modified by the 2FA setup script on $(date)" >"$ARCH_SSH_CONFIG"
	echo "# The original file is backed up at: $BACKUP_DIR" >>"$ARCH_SSH_CONFIG"
	echo "# All settings are now managed in the main sshd_config file" >>"$ARCH_SSH_CONFIG"

	# Append our configuration to the main SSH config
	cat /tmp/ssh_2fa_config >>"$SSH_CONFIG"
else
	# Replace the existing config with our new one
	cp /tmp/ssh_2fa_config "$SSH_CONFIG"
fi

# Clean up the temporary file
rm /tmp/ssh_2fa_config

# Check if the new configuration is valid
sshd -t
if [ $? -ne 0 ]; then
	echo " New SSH configuration is invalid. Reverting to backup..."
	cp "$BACKUP_DIR/$(basename ${SSH_CONFIG}).bak."* "$SSH_CONFIG"
	echo "Please check the output above for errors and fix your SSH configuration."
	exit 1
else
	echo "✓ SSH configuration for 2FA completed successfully."
fi

# Step 6: Apply changes
echo -e "\n[6/6] Applying changes..."
systemctl restart sshd
if [ $? -ne 0 ]; then
	echo " Failed to restart SSH service. Check systemctl status sshd for details."
	exit 1
fi
echo "✓ SSH service restarted with new 2FA configuration."

# Get server IP address (primary network interface)
SERVER_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)

echo -e "\n===== SSH 2FA Hardening Complete =====\n"
echo "Your SSH server is now configured with 2FA:"
echo "  - Google Authenticator configured for user: $USERNAME"
echo "  - PAM configured to require 2FA"
echo "  - SSH configured to use both public key and 2FA"
echo "  - Enhanced security settings applied"
echo -e "\nTo connect to your server:"
echo "1. You'll need both your SSH key AND the 2FA code from your authenticator app"
echo "2. When connecting, you'll be asked for your verification code after key authentication"
echo -e "\nTest your connection with:"
echo "   ssh $USERNAME@${SERVER_IP}"
echo -e "\nBackups of original configurations are stored in: $BACKUP_DIR"
echo -e "\n  WARNING: Do not close your current session until you've verified"
echo "   that you can connect with the new 2FA configuration."
echo -e "\nIf you get locked out, you'll need to access the server directly"
echo "or through rescue mode to restore the backup configurations."

exit 0
