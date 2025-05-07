#!/bin/bash

# Fail2Ban Hardening Script for Arch Linux
# This script:
# 1. Installs Fail2Ban if not already installed
# 2. Creates custom configuration files
# 3. Sets up protection for SSH and other services
# 4. Configures email alerts (optional)
# 5. Enables and starts the Fail2Ban service

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi

# Default settings
BACKUP_DIR="/root/fail2ban_backup"
JAIL_CONF="/etc/fail2ban/jail.conf"
JAIL_LOCAL="/etc/fail2ban/jail.local"
F2B_CONF="/etc/fail2ban/fail2ban.conf"
F2B_LOCAL="/etc/fail2ban/fail2ban.local"

# Create backup directory
mkdir -p $BACKUP_DIR

echo "===== Fail2Ban Setup and Hardening ====="

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

# Function to validate email address
validate_email() {
  local email=$1

  # Simple regex for email validation
  if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    return 1
  fi

  return 0
}

# Function to validate time format (e.g., 10m, 1h, 1d)
validate_time() {
  local time=$1

  # Check if time matches format: number followed by s, m, h, or d
  if ! [[ "$time" =~ ^[0-9]+[smhd]$ ]]; then
    return 1
  fi

  return 0
}

# Step 1: Install Fail2Ban
echo -e "\n[1/5] Installing Fail2Ban..."

# Check if Fail2Ban is installed
if ! command -v fail2ban-server &>/dev/null; then
  echo "Fail2Ban not found. Installing..."
  if ! pacman -Syu fail2ban --noconfirm; then
    echo " Failed to install Fail2Ban. Please check your package manager."
    exit 1
  fi
  echo "✓ Fail2Ban installed successfully."
else
  echo "✓ Fail2Ban is already installed."
fi

# Step 2: Create configuration files
echo -e "\n[2/5] Setting up configuration files..."

# Backup original configuration files
backup_file "$JAIL_CONF"
backup_file "$F2B_CONF"

# Create local configuration files if they don't exist
if [ ! -f "$JAIL_LOCAL" ]; then
  cp "$JAIL_CONF" "$JAIL_LOCAL"
  echo "✓ Created jail.local configuration file."
else
  backup_file "$JAIL_LOCAL"
  echo "✓ Found existing jail.local file, backed up."
fi

if [ ! -f "$F2B_LOCAL" ]; then
  cp "$F2B_CONF" "$F2B_LOCAL"
  echo "✓ Created fail2ban.local configuration file."
else
  backup_file "$F2B_LOCAL"
  echo "✓ Found existing fail2ban.local file, backed up."
fi

# Step 3: Configure Fail2Ban settings
echo -e "\n[3/5] Configuring Fail2Ban settings..."

# Ask for SSH port
while true; do
  read -p "Enter the SSH port number that your server uses (default: 22): " SSH_PORT

  # Use default port if empty input
  if [ -z "$SSH_PORT" ]; then
    SSH_PORT=22
    break
  fi

  if validate_port "$SSH_PORT"; then
    echo "Using SSH port: $SSH_PORT for Fail2Ban configuration"
    break
  else
    echo "Invalid port, please try again."
  fi
done

# Ask for ban time
while true; do
  read -p "Enter ban time (e.g., 10m, 1h, 1d, default: 10m): " BANTIME

  # Use default if empty input
  if [ -z "$BANTIME" ]; then
    BANTIME="10m"
    break
  fi

  if validate_time "$BANTIME"; then
    echo "Using ban time: $BANTIME"
    break
  else
    echo "Invalid time format. Please use format like 10m, 1h, 1d."
  fi
done

# Ask for find time
while true; do
  read -p "Enter find time (time frame for max retries, e.g., 10m, default: 10m): " FINDTIME

  # Use default if empty input
  if [ -z "$FINDTIME" ]; then
    FINDTIME="10m"
    break
  fi

  if validate_time "$FINDTIME"; then
    echo "Using find time: $FINDTIME"
    break
  else
    echo "Invalid time format. Please use format like 10m, 1h, 1d."
  fi
done

# Ask for max retries
while true; do
  read -p "Enter max retries before banning (default: 5): " MAXRETRY

  # Use default if empty input
  if [ -z "$MAXRETRY" ]; then
    MAXRETRY=5
    break
  fi

  # Check if input is a positive number
  if [[ "$MAXRETRY" =~ ^[0-9]+$ ]] && [ "$MAXRETRY" -gt 0 ]; then
    echo "Using max retries: $MAXRETRY"
    break
  else
    echo "Invalid number. Please enter a positive integer."
  fi
done

# Ask if user wants email notifications
read -p "Do you want to enable email notifications for Fail2Ban events? (y/n, default: n): " EMAIL_NOTIFY
EMAIL_NOTIFY=${EMAIL_NOTIFY:-n}

# If email notifications are desired, ask for email addresses
if [[ "${EMAIL_NOTIFY,,}" == "y" ]]; then
  # Ask for destination email
  while true; do
    read -p "Enter destination email address: " DEST_EMAIL

    if [ -z "$DEST_EMAIL" ]; then
      echo "Email address can't be empty."
      continue
    fi

    if validate_email "$DEST_EMAIL"; then
      echo "Using destination email: $DEST_EMAIL"
      break
    else
      echo "Invalid email address. Please try again."
    fi
  done

  # Ask for sender email
  while true; do
    read -p "Enter sender email address (default: root@$(hostname -f)): " SENDER_EMAIL

    # Use default if empty input
    if [ -z "$SENDER_EMAIL" ]; then
      SENDER_EMAIL="root@$(hostname -f)"
      break
    fi

    if validate_email "$SENDER_EMAIL"; then
      echo "Using sender email: $SENDER_EMAIL"
      break
    else
      echo "Invalid email address. Please try again."
    fi
  done

  # Set action to include email notifications
  ACTION="action_mwl"
  echo "Email notifications will be enabled."
else
  # Default action without email
  ACTION="action_"
  echo "Email notifications will not be enabled."
fi

# Ask for IP addresses to ignore (whitelist)
echo
echo "Enter IP addresses to whitelist (ignore), one per line."
echo "Press Ctrl+D on a new line when done. Leave empty for default (localhost only)."
echo "Example: 192.168.1.0/24 or your.static.ip.address"

IGNORE_IP_LIST="127.0.0.1/8 ::1"
TEMP_IPS=()

while read -p "> " IP; do
  TEMP_IPS+=("$IP")
done

if [ ${#TEMP_IPS[@]} -gt 0 ]; then
  IGNORE_IP_LIST="$IGNORE_IP_LIST ${TEMP_IPS[*]}"
fi

echo "Using whitelist: $IGNORE_IP_LIST"

# Step 4: Update configuration files
echo -e "\n[4/5] Updating Fail2Ban configuration..."

# Update jail.local configuration file
cat >"$JAIL_LOCAL" <<EOF
[DEFAULT]
# "bantime" is the number of seconds that a host is banned
bantime = $BANTIME

# A host is banned if it has generated "maxretry" during the last "findtime"
findtime = $FINDTIME

# "maxretry" is the number of failures before a host gets banned
maxretry = $MAXRETRY

# "ignoreip" can be a list of IP addresses, CIDR masks or DNS hosts
ignoreip = $IGNORE_IP_LIST

# Default ban action
action = %(${ACTION})s

# Destination email address for notifications
destemail = ${DEST_EMAIL:-root@localhost}

# Sender email address for notifications
sender = ${SENDER_EMAIL:-root@localhost}

# Use Sendmail for sending emails
mta = sendmail

# Jail for SSH server
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = $MAXRETRY

# Jail for web authentication failures - Apache
[apache-auth]
enabled = false
port = http,https
filter = apache-auth
logpath = /var/log/apache2/error.log

# Jail for web authentication failures - Nginx
[nginx-http-auth]
enabled = false
port = http,https
filter = nginx-http-auth
logpath = /var/log/nginx/error.log

# Add more jails here as needed
EOF

echo "✓ Updated jail.local configuration."

# Step 5: Enable and start Fail2Ban
echo -e "\n[5/5] Enabling and starting Fail2Ban service..."

# First check if it's already running and stop it if needed
if systemctl is-active --quiet fail2ban; then
  systemctl stop fail2ban
  echo "Stopped existing Fail2Ban service."
fi

# Enable and start the service
systemctl enable fail2ban
if systemctl start fail2ban; then
  echo "✓ Fail2Ban service has been enabled and started."
else
  echo " Failed to start Fail2Ban service. Check logs with 'journalctl -u fail2ban'."
  exit 1
fi

# Wait a moment for service to fully start
sleep 2

# Check status
echo -e "\n===== Fail2Ban Status =====\n"
if fail2ban-client status; then
  echo -e "\nSSHD jail status:"
  fail2ban-client status sshd
else
  echo " Fail2Ban service is not responding properly. Please check logs."
  exit 1
fi

echo -e "\n===== Fail2Ban Setup Complete =====\n"
echo "Configuration summary:"
echo "  - Ban time: $BANTIME"
echo "  - Find time: $FINDTIME"
echo "  - Max retries: $MAXRETRY"
echo "  - SSH port protected: $SSH_PORT"
echo "  - Whitelisted IPs: $IGNORE_IP_LIST"
if [[ "${EMAIL_NOTIFY,,}" == "y" ]]; then
  echo "  - Email notifications: Enabled"
  echo "  - Notification recipient: $DEST_EMAIL"
else
  echo "  - Email notifications: Disabled"
fi

echo -e "\nUseful Fail2Ban commands:"
echo "  fail2ban-client status                  - Show all jails"
echo "  fail2ban-client status sshd             - Show SSHD jail status"
echo "  fail2ban-client set sshd unbanip <IP>   - Unban an IP from SSHD jail"
echo "  fail2ban-client reload                  - Reload configuration"
echo "  systemctl restart fail2ban              - Restart service"
echo "  journalctl -u fail2ban -f               - View fail2ban logs in real time"

exit 0
