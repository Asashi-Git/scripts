#!/bin/bash

# SSH Hardening Script for Arch Linux
# This script:
# 1. Installs required packages
# 2. Configures and hardens the SSH server
# 3. Sets up RSA key authentication
# 4. Applies and verifies all changes

# Check if script is run with root privileges
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root"
	exit 1
fi

# Default settings
SSH_CONFIG="/etc/ssh/sshd_config"
BACKUP_DIR="/root/ssh_hardening_backup"

# Create backup directory
mkdir -p $BACKUP_DIR

echo "===== SSH Server Setup and Hardening ====="

# Function to validate port number
validate_port() {
	local port=$1

	# Check if port is a number
	if ! [[ "$port" =~ ^[0-9]+$ ]]; then
		echo "Port must be a number"
		return 1
	fi

	# Check if port is in the valid range (1024-65535)
	if [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
		echo "Port must be between 1024 and 65535"
		return 1
	fi

	# Check if port is already in use
	if ss -tuln | grep -q ":$port "; then
		echo "Port $port is already in use by another service"
		return 1
	fi

	return 0
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

# Ask user for SSH port
while true; do
	read -p "Enter SSH port (1024-65535): " SSH_PORT

	if validate_port "$SSH_PORT"; then
		echo "Using SSH port: $SSH_PORT"
		break
	else
		echo "Invalid port, please try again."
	fi
done

# Ask user for username
while true; do
	# List available users for convenience
	echo -e "\nAvailable non-system users:"
	awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd

	# Ask for username
	read -p "Enter username for SSH hardening: " USERNAME

	if validate_username "$USERNAME"; then
		echo "Hardening SSH for user: $USERNAME"
		break
	else
		echo "Invalid username, please try again."
	fi
done

# Function to backup a file before modifying
backup_file() {
	local file=$1
	local backup="${BACKUP_DIR}/$(basename ${file}).bak.$(date +%Y%m%d%H%M%S)"
	cp "$file" "$backup"
	echo "Backed up $file to $backup"
}

# Step 1: Install required packages
echo -e "\n[1/7] Installing required packages..."
pacman -Sy --noconfirm openssh libpam-google-authenticator qrencode
if [ $? -ne 0 ]; then
	echo "Failed to install packages. Check your internet connection and package availability."
	exit 1
fi
echo "✓ Packages installed successfully."

# Step 2: Backup SSH config before modifications
echo -e "\n[2/7] Creating backup of SSH configuration..."
backup_file $SSH_CONFIG
echo "✓ Configuration backed up."

# Step 3: Configure and harden SSH
echo -e "\n[3/7] Configuring SSH service..."
# Enable and start SSH service
systemctl enable sshd
systemctl start sshd

# Modify SSH configuration
echo -e "\n[4/7] Hardening SSH configuration..."

# Create a new sshd_config with our secure settings
cat >$SSH_CONFIG.new <<EOF
# SSH Server Configuration
# Hardened by setup script on $(date)

# Basic SSH settings
Port $SSH_PORT
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Authentication settings
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
ChallengeResponseAuthentication no

# Login restrictions
MaxAuthTries 3
MaxSessions 5
LoginGraceTime 30

# Connection settings
X11Forwarding no
TCPKeepAlive yes
ClientAliveInterval 300
ClientAliveCountMax 2

# Security settings
UsePAM yes
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

# Check if the new configuration is valid
sshd -t -f $SSH_CONFIG.new
if [ $? -ne 0 ]; then
	echo " New SSH configuration is invalid. Check $SSH_CONFIG.new for errors."
	exit 1
else
	# Apply the new configuration
	mv $SSH_CONFIG.new $SSH_CONFIG
	echo "✓ SSH configuration hardened."
fi

# Step 5: Generate SSH key pair if it doesn't exist
echo -e "\n[5/7] Setting up RSA key authentication..."

# Define key paths
RSA_KEY_PATH="/home/$USERNAME/.ssh/id_rsa"
PUB_KEY_PATH="/home/$USERNAME/.ssh/id_rsa.pub"
AUTH_KEYS_PATH="/home/$USERNAME/.ssh/authorized_keys"

# Create .ssh directory if it doesn't exist
mkdir -p /home/$USERNAME/.ssh
chmod 700 /home/$USERNAME/.ssh
chown $USERNAME:$USERNAME /home/$USERNAME/.ssh

# Generate RSA key pair if it doesn't exist
if [ ! -f "$RSA_KEY_PATH" ]; then
	echo "Generating new 4096-bit RSA key pair for $USERNAME..."
	sudo -u $USERNAME ssh-keygen -t rsa -b 4096 -f $RSA_KEY_PATH -N ""
	echo "✓ RSA key pair generated."
else
	echo "✓ RSA key pair already exists."
fi

# Add the public key to authorized_keys
if [ -f "$PUB_KEY_PATH" ]; then
	sudo -u $USERNAME bash -c "cat $PUB_KEY_PATH >> $AUTH_KEYS_PATH"
	chmod 600 $AUTH_KEYS_PATH
	chown $USERNAME:$USERNAME $AUTH_KEYS_PATH
	echo "✓ Public key added to authorized_keys."
else
	echo " Public key not found. RSA key setup might have failed."
	exit 1
fi

# Step 6: Apply changes
echo -e "\n[6/7] Applying changes..."
systemctl restart sshd
if [ $? -ne 0 ]; then
	echo " Failed to restart SSH service. Check systemctl status sshd for details."
	exit 1
fi
echo "✓ SSH service restarted with new configuration."

# Step 7: Provide connection instructions
echo -e "\n[7/7] Creating connection instructions..."

# Get server IP address (primary network interface)
SERVER_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)

echo -e "\n===== SSH Hardening Complete =====\n"
echo "Your SSH server is now configured with enhanced security:"
echo "  - Running on port: $SSH_PORT"
echo "  - Root login disabled"
echo "  - Password authentication disabled"
echo "  - RSA key authentication enabled"
echo "  - Only user '$USERNAME' is allowed to log in"
echo -e "\nTo connect from a client machine:"
echo "1. Copy the private key to your client:"
echo "   scp -P $SSH_PORT $USERNAME@${SERVER_IP}:~/.ssh/id_rsa ~/.ssh/id_rsa_server"
echo "2. Set correct permissions on the client:"
echo "   chmod 600 ~/.ssh/id_rsa_server"
echo "3. Connect using the key:"
echo "   ssh -p $SSH_PORT -i ~/.ssh/id_rsa_server $USERNAME@${SERVER_IP}"
echo -e "\nBackups of original configurations are stored in: $BACKUP_DIR"
echo -e "\n  WARNING: Do not close your current session until you've verified"
echo "   that you can connect with the new configuration."

# Generate QR code for easy key transfer (if qrencode is available)
if command -v qrencode >/dev/null; then
	KEY_QR_PATH="/home/$USERNAME/id_rsa_qr.png"
	echo -e "\nGenerating QR code of private key for secure transfer..."
	qrencode -o $KEY_QR_PATH -r $RSA_KEY_PATH
	chown $USERNAME:$USERNAME $KEY_QR_PATH
	echo "QR code of private key saved to: $KEY_QR_PATH"
	echo "You can scan this QR code to transfer the key to mobile devices."
fi

exit 0
