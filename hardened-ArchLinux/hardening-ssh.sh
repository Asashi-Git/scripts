#!/bin/bash

# ╔═══════════════════════════════════════════════════════════════════╗
# ║  SSH Hardening Script for Arch Linux                              ║
# ║  This script installs, configures and hardens SSH                 ║
# ╚═══════════════════════════════════════════════════════════════════╝

# ┌─────────────────────────────────────────────────────────────────┐
# │ Colors for output formatting                                     │
# └─────────────────────────────────────────────────────────────────┘
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BRIGHT_BLUE='\033[1;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ┌─────────────────────────────────────────────────────────────────┐
# │ Default settings                                                 │
# └─────────────────────────────────────────────────────────────────┘
SSH_CONFIG="/etc/ssh/sshd_config"
BACKUP_DIR="/root/ssh_hardening_backup"

# ┌─────────────────────────────────────────────────────────────────┐
# │ Utility functions                                                │
# └─────────────────────────────────────────────────────────────────┘
# Function to print section headers
print_section() {
  echo -e "\n${BLUE}${BOLD}╔════════════ $1 ════════════╗${NC}\n"
}

# Function to print information
print_info() {
  echo -e "${GREEN}${BOLD}[INFO]${NC} $1"
}

# Function to print warnings
print_warning() {
  echo -e "${YELLOW}${BOLD}[WARNING]${NC} $1"
}

# Function to print errors
print_error() {
  echo -e "${RED}${BOLD}[ERROR]${NC} $1"
}

# Function to check if a command executed successfully
check_success() {
  if [ $? -eq 0 ]; then
    print_info "$1"
  else
    print_error "$2"
    exit 1
  fi
}

# Function to validate port number
validate_port() {
  local port=$1

  # Check if port is a number
  if ! [[ "$port" =~ ^[0-9]+$ ]]; then
    print_error "Port must be a number"
    return 1
  fi

  # Check if port is in the valid range (1024-65535)
  if [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
    print_error "Port must be between 1024 and 65535"
    return 1
  fi

  # Check if port is already in use
  if ss -tuln | grep -q ":$port "; then
    print_error "Port $port is already in use by another service"
    return 1
  fi

  return 0
}

# Function to validate username
validate_username() {
  local username=$1

  # Check if username exists
  if ! id "$username" &>/dev/null; then
    print_error "User '$username' does not exist"
    return 1
  fi

  return 0
}

# Function to backup a file before modifying
backup_file() {
  local file=$1
  local backup="${BACKUP_DIR}/$(basename ${file}).bak.$(date +%Y%m%d%H%M%S)"
  cp "$file" "$backup"
  print_info "Backed up $file to $backup"
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Check if running as root                                         │
# └─────────────────────────────────────────────────────────────────┘
if [[ $EUID -ne 0 ]]; then
  print_error "This script must be run as root"
  exit 1
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ Create backup directory                                          │
# └─────────────────────────────────────────────────────────────────┘
mkdir -p $BACKUP_DIR

# ┌─────────────────────────────────────────────────────────────────┐
# │ Welcome message                                                  │
# └─────────────────────────────────────────────────────────────────┘
clear
echo
echo -e "${BRIGHT_BLUE}${BOLD}"
cat <<"EOF"
  ███████╗███████╗██╗  ██╗    ██╗  ██╗ █████╗ ██████╗ ██████╗ ███████╗███╗   ██╗██╗███╗   ██╗ ██████╗ 
  ██╔════╝██╔════╝██║  ██║    ██║  ██║██╔══██╗██╔══██╗██╔══██╗██╔════╝████╗  ██║██║████╗  ██║██╔════╝ 
  ███████╗███████╗███████║    ███████║███████║██████╔╝██║  ██║█████╗  ██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
  ╚════██║╚════██║██╔══██║    ██╔══██║██╔══██║██╔══██╗██║  ██║██╔══╝  ██║╚██╗██║██║██║╚██╗██║██║   ██║
  ███████║███████║██║  ██║    ██║  ██║██║  ██║██║  ██║██████╔╝███████╗██║ ╚████║██║██║ ╚████║╚██████╔╝
  ╚══════╝╚══════╝╚═╝  ╚═╝    ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝ 
EOF
echo -e "${NC}"
echo
echo -e "${MAGENTA}"
cat <<"EOF"
  ███████╗ ██████╗ ██████╗      █████╗ ██████╗  ██████╗██╗  ██╗    ██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗
  ██╔════╝██╔═══██╗██╔══██╗    ██╔══██╗██╔══██╗██╔════╝██║  ██║    ██║     ██║████╗  ██║██║   ██║╚██╗██╔╝
  █████╗  ██║   ██║██████╔╝    ███████║██████╔╝██║     ███████║    ██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝ 
  ██╔══╝  ██║   ██║██╔══██╗    ██╔══██║██╔══██╗██║     ██╔══██║    ██║     ██║██║╚██╗██║██║   ██║ ██╔██╗ 
  ██║     ╚██████╔╝██║  ██║    ██║  ██║██║  ██║╚██████╗██║  ██║    ███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗
  ╚═╝      ╚═════╝ ╚═╝  ╚═╝    ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝    ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝
EOF
echo -e "${NC}"
echo

# ┌─────────────────────────────────────────────────────────────────┐
# │ SSH Port Configuration                                           │
# └─────────────────────────────────────────────────────────────────┘
print_section "SSH Port Configuration"

# Ask user for SSH port
while true; do
  read -e -n "${CYAN}Enter SSH port (1024-65535):${NC} "
  read SSH_PORT

  if validate_port "$SSH_PORT"; then
    print_info "Using SSH port: $SSH_PORT"
    break
  else
    print_warning "Invalid port, please try again."
  fi
done

# ┌─────────────────────────────────────────────────────────────────┐
# │ User Selection                                                   │
# └─────────────────────────────────────────────────────────────────┘
print_section "User Selection"

# Ask user for username
while true; do
  # List available users for convenience
  echo -e "${BLUE}Available non-system users:${NC}"
  awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd

  # Ask for username
  read -p "${CYAN}Enter username for SSH hardening:${NC} " USERNAME

  if validate_username "$USERNAME"; then
    print_info "Hardening SSH for user: $USERNAME"
    break
  else
    print_warning "Invalid username, please try again."
  fi
done

# ┌─────────────────────────────────────────────────────────────────┐
# │ Package Installation                                             │
# └─────────────────────────────────────────────────────────────────┘
print_section "Installing Required Packages"

print_info "Installing openssh, libpam-google-authenticator, and qrencode..."
pacman -Sy --noconfirm openssh libpam-google-authenticator qrencode
check_success "Packages installed successfully." "Failed to install packages. Check your internet connection and package availability."

# ┌─────────────────────────────────────────────────────────────────┐
# │ Configuration Backup                                             │
# └─────────────────────────────────────────────────────────────────┘
print_section "Backing Up SSH Configuration"

backup_file $SSH_CONFIG
print_info "Configuration backed up."

# ┌─────────────────────────────────────────────────────────────────┐
# │ SSH Service Configuration                                        │
# └─────────────────────────────────────────────────────────────────┘
print_section "Configuring SSH Service"

# Enable and start SSH service
systemctl enable sshd
systemctl start sshd
check_success "SSH service enabled and started." "Failed to enable or start SSH service."

# ┌─────────────────────────────────────────────────────────────────┐
# │ SSH Hardening Configuration                                      │
# └─────────────────────────────────────────────────────────────────┘
print_section "Hardening SSH Configuration"

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
check_success "New SSH configuration is valid." "New SSH configuration is invalid. Check $SSH_CONFIG.new for errors."

# Apply the new configuration
mv $SSH_CONFIG.new $SSH_CONFIG
print_info "SSH configuration hardened."

# ┌─────────────────────────────────────────────────────────────────┐
# │ RSA Key Authentication Setup                                     │
# └─────────────────────────────────────────────────────────────────┘
print_section "Setting Up RSA Key Authentication"

# Define key paths
RSA_KEY_PATH="/home/$USERNAME/.ssh/id_rsa"
PUB_KEY_PATH="/home/$USERNAME/.ssh/id_rsa.pub"
AUTH_KEYS_PATH="/home/$USERNAME/.ssh/authorized_keys"

# Create .ssh directory if it doesn't exist
mkdir -p /home/$USERNAME/.ssh
chmod 700 /home/$USERNAME/.ssh
chown $USERNAME:$USERNAME /home/$USERNAME/.ssh
print_info "SSH directory set up."

# Generate RSA key pair if it doesn't exist
if [ ! -f "$RSA_KEY_PATH" ]; then
  print_info "Generating new 4096-bit RSA key pair for $USERNAME..."
  sudo -u $USERNAME ssh-keygen -t rsa -b 4096 -f $RSA_KEY_PATH -N ""
  check_success "RSA key pair generated." "Failed to generate RSA key pair."
else
  print_info "RSA key pair already exists."
fi

# Add the public key to authorized_keys
if [ -f "$PUB_KEY_PATH" ]; then
  sudo -u $USERNAME bash -c "cat $PUB_KEY_PATH >> $AUTH_KEYS_PATH"
  chmod 600 $AUTH_KEYS_PATH
  chown $USERNAME:$USERNAME $AUTH_KEYS_PATH
  print_info "Public key added to authorized_keys."
else
  print_error "Public key not found. RSA key setup might have failed."
  exit 1
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ Apply Changes                                                    │
# └─────────────────────────────────────────────────────────────────┘
print_section "Applying Changes"

systemctl restart sshd
check_success "SSH service restarted with new configuration." "Failed to restart SSH service. Check systemctl status sshd for details."

# ┌─────────────────────────────────────────────────────────────────┐
# │ Connection Instructions                                          │
# └─────────────────────────────────────────────────────────────────┘
print_section "Connection Instructions"

# Get server IP address (primary network interface)
SERVER_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)

echo -e "${GREEN}${BOLD}┌───────────────────────────────────────────────────────────────┐${NC}"
print_info "Your SSH server is now configured with enhanced security:"
echo -e "  ${BOLD}Running on port:${NC} $SSH_PORT"
echo -e "  ${BOLD}Root login:${NC} Disabled"
echo -e "  ${BOLD}Password authentication:${NC} Disabled"
echo -e "  ${BOLD}RSA key authentication:${NC} Enabled"
echo -e "  ${BOLD}Allowed user:${NC} $USERNAME"
echo -e "${GREEN}${BOLD}└───────────────────────────────────────────────────────────────┘${NC}"

echo -e "\n${BLUE}${BOLD}To connect from a client machine:${NC}"
echo -e "${CYAN}1. Copy the private key to your client:${NC}"
echo -e "   ${BOLD}scp -P $SSH_PORT $USERNAME@${SERVER_IP}:~/.ssh/id_rsa ~/.ssh/id_rsa_server${NC}"
echo -e "${CYAN}2. Set correct permissions on the client:${NC}"
echo -e "   ${BOLD}chmod 600 ~/.ssh/id_rsa_server${NC}"
echo -e "${CYAN}3. Connect using the key:${NC}"
echo -e "   ${BOLD}ssh -p $SSH_PORT -i ~/.ssh/id_rsa_server $USERNAME@${SERVER_IP}${NC}"

echo -e "\n${MAGENTA}Backups of original configurations are stored in:${NC} $BACKUP_DIR"
print_warning "Do not close your current session until you've verified that you can connect with the new configuration."

# Generate QR code for easy key transfer (if qrencode is available)
if command -v qrencode >/dev/null; then
  KEY_QR_PATH="/home/$USERNAME/id_rsa_qr.png"
  print_info "Generating QR code of private key for secure transfer..."
  qrencode -o $KEY_QR_PATH -r $RSA_KEY_PATH
  chown $USERNAME:$USERNAME $KEY_QR_PATH
  print_info "QR code of private key saved to: $KEY_QR_PATH"
  print_info "You can scan this QR code to transfer the key to mobile devices."
fi

echo
echo -e "${BRIGHT_BLUE}${BOLD}"
cat <<"EOF"
  ██████╗ ██████╗  ██████╗ ████████╗███████╗ ██████╗████████╗███████╗██████╗ ██╗
  ██╔══██╗██╔══██╗██╔═══██╗╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝██╔════╝██╔══██╗██║
  ██████╔╝██████╔╝██║   ██║   ██║   █████╗  ██║        ██║   █████╗  ██║  ██║██║
  ██╔═══╝ ██╔══██╗██║   ██║   ██║   ██╔══╝  ██║        ██║   ██╔══╝  ██║  ██║╚═╝
  ██║     ██║  ██║╚██████╔╝   ██║   ███████╗╚██████╗   ██║   ███████╗██████╔╝██╗
  ╚═╝     ╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚══════╝ ╚═════╝   ╚═╝   ╚══════╝╚═════╝ ╚═╝
                                                                                 
  ███████╗███████╗███████╗██╗  ██╗    ███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗ 
  ██╔════╝██╔════╝██╔════╝██║  ██║    ██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗
  ███████╗███████╗███████╗███████║    ███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝
  ╚════██║╚════██║╚════██║██╔══██║    ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗
  ███████║███████║███████║██║  ██║    ███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║
  ╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝    ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝
EOF
echo -e "${NC}"

exit 0
