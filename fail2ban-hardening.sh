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

# ANSI color codes for better readability
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m" # No Color

# Create backup directory
mkdir -p $BACKUP_DIR

echo -e "${BLUE}===== Fail2Ban Setup and Hardening =====${NC}"

# Function to backup a file before modifying
backup_file() {
	local file=$1
	local backup="${BACKUP_DIR}/$(basename ${file}).bak.$(date +%Y%m%d%H%M%S)"

	# Only backup if file exists
	if [ -f "$file" ]; then
		cp "$file" "$backup"
		echo -e "${GREEN}✓${NC} Backed up $file to $backup"
	fi
}

# Function to validate port number
validate_port() {
	local port=$1

	# Check if port is a number
	if ! [[ "$port" =~ ^[0-9]+$ ]]; then
		echo -e "${RED}Port must be a number${NC}"
		return 1
	fi

	# Check if port is in the valid range (1-65535)
	if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
		echo -e "${RED}Port must be between 1 and 65535${NC}"
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

# Function to get yes/no input with default
get_yes_no() {
	local prompt=$1
	local default=$2

	while true; do
		if [[ "$default" == "y" ]]; then
			read -p "$prompt [Y/n]: " answer
			answer=${answer:-y}
		else
			read -p "$prompt [y/N]: " answer
			answer=${answer:-n}
		fi

		case ${answer,,} in
		y | yes) return 0 ;;
		n | no) return 1 ;;
		*) echo -e "${YELLOW}Please answer yes (y) or no (n)${NC}" ;;
		esac
	done
}

# Function to check if sendmail is installed
check_mail_capabilities() {
	if ! command -v sendmail &>/dev/null && ! command -v msmtp &>/dev/null; then
		echo -e "${YELLOW}Warning: No mail transfer agent found (sendmail or msmtp).${NC}"
		echo -e "${YELLOW}You may need to install a mail service to receive email notifications.${NC}"
		echo -e "${YELLOW}Suggested packages: postfix, exim, msmtp, or ssmtp${NC}"

		if get_yes_no "Would you like to install msmtp (a simple mail transfer agent)?" "n"; then
			if ! pacman -S msmtp --noconfirm; then
				echo -e "${RED}Failed to install msmtp. Email notifications may not work.${NC}"
			else
				echo -e "${GREEN}✓${NC} msmtp installed successfully."
			fi
		fi
	fi
}

# Step 1: Install Fail2Ban
echo -e "\n${BLUE}[1/5] Installing Fail2Ban...${NC}"

# Check if Fail2Ban is installed
if ! command -v fail2ban-server &>/dev/null; then
	echo "Fail2Ban not found. Installing..."
	if ! pacman -Syu fail2ban --noconfirm; then
		echo -e "${RED}✗ Failed to install Fail2Ban. Please check your package manager.${NC}"
		exit 1
	fi
	echo -e "${GREEN}✓${NC} Fail2Ban installed successfully."
else
	echo -e "${GREEN}✓${NC} Fail2Ban is already installed."
fi

# Step 2: Create configuration files
echo -e "\n${BLUE}[2/5] Setting up configuration files...${NC}"

# Backup original configuration files
backup_file "$JAIL_CONF"
backup_file "$F2B_CONF"

# Create local configuration files if they don't exist
if [ ! -f "$JAIL_LOCAL" ]; then
	cp "$JAIL_CONF" "$JAIL_LOCAL"
	echo -e "${GREEN}✓${NC} Created jail.local configuration file."
else
	backup_file "$JAIL_LOCAL"
	echo -e "${GREEN}✓${NC} Found existing jail.local file, backed up."
fi

if [ ! -f "$F2B_LOCAL" ]; then
	cp "$F2B_CONF" "$F2B_LOCAL"
	echo -e "${GREEN}✓${NC} Created fail2ban.local configuration file."
else
	backup_file "$F2B_LOCAL"
	echo -e "${GREEN}✓${NC} Found existing fail2ban.local file, backed up."
fi

# Step 3: Configure Fail2Ban settings
echo -e "\n${BLUE}[3/5] Configuring Fail2Ban settings...${NC}"

# Ask if user wants to use default configuration
echo -e "${YELLOW}Fail2Ban Configuration Options${NC}"
echo "You can use default settings or customize:"
echo "Default settings:"
echo "  - Ban time: 10m (10 minutes)"
echo "  - Find time: 10m (10 minutes)"
echo "  - Max retries: 5"

if get_yes_no "Would you like to customize these settings?" "y"; then
	CUSTOM_CONFIG=true
else
	CUSTOM_CONFIG=false
	BANTIME="10m"
	FINDTIME="10m"
	MAXRETRY=5
	echo -e "${GREEN}Using default settings.${NC}"
fi

# Ask for SSH port
while true; do
	read -p "Enter the SSH port number that your server uses (default: 22): " SSH_PORT

	# Use default port if empty input
	if [ -z "$SSH_PORT" ]; then
		SSH_PORT=22
		break
	fi

	if validate_port "$SSH_PORT"; then
		echo -e "${GREEN}Using SSH port: $SSH_PORT for Fail2Ban configuration${NC}"
		break
	else
		echo -e "${RED}Invalid port, please try again.${NC}"
	fi
done

# Ask for ban time if user wants to customize
if [ "$CUSTOM_CONFIG" = true ]; then
	echo -e "\n${YELLOW}Ban Time Configuration${NC}"
	echo "This is how long an IP will be banned after too many failed attempts."
	echo "Examples: 10m (10 minutes), 1h (1 hour), 1d (1 day), 1w (1 week)"

	while true; do
		read -p "Enter ban time (default: 10m): " BANTIME

		# Use default if empty input
		if [ -z "$BANTIME" ]; then
			BANTIME="10m"
			break
		fi

		if validate_time "$BANTIME"; then
			echo -e "${GREEN}Using ban time: $BANTIME${NC}"
			break
		else
			echo -e "${RED}Invalid time format. Please use format like 10m, 1h, 1d.${NC}"
		fi
	done

	# Ask for find time
	echo -e "\n${YELLOW}Find Time Configuration${NC}"
	echo "This is the time window during which Fail2Ban counts failures."
	echo "If there are more than maxretry failures in this time window, the IP gets banned."

	while true; do
		read -p "Enter find time (default: 10m): " FINDTIME

		# Use default if empty input
		if [ -z "$FINDTIME" ]; then
			FINDTIME="10m"
			break
		fi

		if validate_time "$FINDTIME"; then
			echo -e "${GREEN}Using find time: $FINDTIME${NC}"
			break
		else
			echo -e "${RED}Invalid time format. Please use format like 10m, 1h, 1d.${NC}"
		fi
	done

	# Ask for max retries
	echo -e "\n${YELLOW}Max Retry Configuration${NC}"
	echo "This is the number of failures allowed within the find time before an IP is banned."

	while true; do
		read -p "Enter max retries before banning (default: 5): " MAXRETRY

		# Use default if empty input
		if [ -z "$MAXRETRY" ]; then
			MAXRETRY=5
			break
		fi

		# Check if input is a positive number
		if [[ "$MAXRETRY" =~ ^[0-9]+$ ]] && [ "$MAXRETRY" -gt 0 ]; then
			echo -e "${GREEN}Using max retries: $MAXRETRY${NC}"
			break
		else
			echo -e "${RED}Invalid number. Please enter a positive integer.${NC}"
		fi
	done
fi

# Ask if user wants email notifications
echo -e "\n${YELLOW}Email Notification Configuration${NC}"
if get_yes_no "Do you want to enable email notifications for Fail2Ban events?" "n"; then
	EMAIL_NOTIFY=true

	# Check if mail capabilities are available
	check_mail_capabilities

	# Ask for destination email
	echo -e "\n${YELLOW}Destination Email Configuration${NC}"
	echo "This is the email address where notifications will be sent."

	while true; do
		read -p "Enter destination email address: " DEST_EMAIL

		if [ -z "$DEST_EMAIL" ]; then
			echo -e "${RED}Email address can't be empty.${NC}"
			continue
		fi

		if validate_email "$DEST_EMAIL"; then
			echo -e "${GREEN}Using destination email: $DEST_EMAIL${NC}"
			break
		else
			echo -e "${RED}Invalid email address. Please try again.${NC}"
		fi
	done

	# Ask for sender email
	echo -e "\n${YELLOW}Sender Email Configuration${NC}"
	echo "This is the 'from' address that will appear on notification emails."

	while true; do
		read -p "Enter sender email address (default: root@$(hostname -f)): " SENDER_EMAIL

		# Use default if empty input
		if [ -z "$SENDER_EMAIL" ]; then
			SENDER_EMAIL="root@$(hostname -f)"
			break
		fi

		if validate_email "$SENDER_EMAIL"; then
			echo -e "${GREEN}Using sender email: $SENDER_EMAIL${NC}"
			break
		else
			echo -e "${RED}Invalid email address. Please try again.${NC}"
		fi
	done

	# Set action to include email notifications
	ACTION="action_mwl"
	echo -e "${GREEN}Email notifications will be enabled.${NC}"
else
	EMAIL_NOTIFY=false
	# Default action without email
	ACTION="action_"
	DEST_EMAIL="root@localhost"
	SENDER_EMAIL="root@$(hostname -f)"
	echo -e "${YELLOW}Email notifications will not be enabled.${NC}"
fi

# Ask for IP addresses to ignore (whitelist)
echo -e "\n${YELLOW}IP Whitelist Configuration${NC}"
echo "Enter IP addresses to whitelist (ignore), one per line."
echo "These IPs will never be banned by Fail2Ban."
echo "Press Enter on an empty line when done. Default: localhost only."
echo "Examples: 192.168.1.0/24 or your.static.ip.address"

IGNORE_IP_LIST="127.0.0.1/8 ::1"
TEMP_IPS=()

echo -e "${BLUE}Start entering IPs (one per line, press Enter twice when done):${NC}"
while true; do
	read -p "> " IP

	# Break on empty line
	if [ -z "$IP" ]; then
		break
	fi

	TEMP_IPS+=("$IP")
done

if [ ${#TEMP_IPS[@]} -gt 0 ]; then
	IGNORE_IP_LIST="$IGNORE_IP_LIST ${TEMP_IPS[*]}"
fi

echo -e "${GREEN}Using whitelist: $IGNORE_IP_LIST${NC}"

# Advanced options
echo -e "\n${YELLOW}Advanced Configuration${NC}"
if get_yes_no "Would you like to configure additional services to protect (e.g., Apache, Nginx)?" "n"; then
	PROTECT_APACHE=false
	PROTECT_NGINX=false

	if get_yes_no "Do you want to protect Apache web server?" "n"; then
		PROTECT_APACHE=true
		echo -e "${GREEN}Apache protection will be enabled.${NC}"
	fi

	if get_yes_no "Do you want to protect Nginx web server?" "n"; then
		PROTECT_NGINX=true
		echo -e "${GREEN}Nginx protection will be enabled.${NC}"
	fi
fi

# Step 4: Update configuration files
echo -e "\n${BLUE}[4/5] Updating Fail2Ban configuration...${NC}"

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
destemail = ${DEST_EMAIL}

# Sender email address for notifications
sender = ${SENDER_EMAIL}

# Use Sendmail for sending emails
mta = sendmail

# Jail for SSH server
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = $MAXRETRY
EOF

# Add Apache protection if requested
if [ "$PROTECT_APACHE" = true ]; then
	cat >>"$JAIL_LOCAL" <<EOF

# Jail for web authentication failures - Apache
[apache-auth]
enabled = true
port = http,https
filter = apache-auth
logpath = /var/log/apache2/error.log
maxretry = $MAXRETRY

[apache-badbots]
enabled = true
port = http,https
filter = apache-badbots
logpath = /var/log/apache2/access.log
maxretry = 2

[apache-noscript]
enabled = true
port = http,https
filter = apache-noscript
logpath = /var/log/apache2/access.log
maxretry = 6
EOF
else
	cat >>"$JAIL_LOCAL" <<EOF

# Jail for web authentication failures - Apache
[apache-auth]
enabled = false
port = http,https
filter = apache-auth
logpath = /var/log/apache2/error.log
EOF
fi

# Add Nginx protection if requested
if [ "$PROTECT_NGINX" = true ]; then
	cat >>"$JAIL_LOCAL" <<EOF

# Jail for web authentication failures - Nginx
[nginx-http-auth]
enabled = true
port = http,https
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = $MAXRETRY

[nginx-badbots]
enabled = true
port = http,https
filter = nginx-badbots
logpath = /var/log/nginx/access.log
maxretry = 2
EOF
else
	cat >>"$JAIL_LOCAL" <<EOF

# Jail for web authentication failures - Nginx
[nginx-http-auth]
enabled = false
port = http,https
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
EOF
fi

# Add common footer
cat >>"$JAIL_LOCAL" <<EOF

# Add more jails here as needed
EOF

echo -e "${GREEN}✓${NC} Updated jail.local configuration."

# Step 5: Enable and start Fail2Ban
echo -e "\n${BLUE}[5/5] Enabling and starting Fail2Ban service...${NC}"

# First check if it's already running and stop it if needed
if systemctl is-active --quiet fail2ban; then
	systemctl stop fail2ban
	echo "Stopped existing Fail2Ban service."
fi

# Enable and start the service
systemctl enable fail2ban
if systemctl start fail2ban; then
	echo -e "${GREEN}✓${NC} Fail2Ban service has been enabled and started."
else
	echo -e "${RED}✗ Failed to start Fail2Ban service. Check logs with 'journalctl -u fail2ban'.${NC}"
	exit 1
fi

# Wait a moment for service to fully start
sleep 2

# Check status
echo -e "\n${BLUE}===== Fail2Ban Status =====${NC}\n"
if fail2ban-client status; then
	echo -e "\n${BLUE}SSHD jail status:${NC}"
	fail2ban-client status sshd
else
	echo -e "${RED}✗ Fail2Ban service is not responding properly. Please check logs.${NC}"
	exit 1
fi

echo -e "\n${GREEN}===== Fail2Ban Setup Complete =====${NC}\n"
echo -e "${BLUE}Configuration summary:${NC}"
echo "  - Ban time: $BANTIME"
echo "  - Find time: $FINDTIME"
echo "  - Max retries: $MAXRETRY"
echo "  - SSH port protected: $SSH_PORT"
echo "  - Whitelisted IPs: $IGNORE_IP_LIST"
if [ "$EMAIL_NOTIFY" = true ]; then
	echo "  - Email notifications: Enabled"
	echo "  - Notification recipient: $DEST_EMAIL"
	echo "  - Sender email: $SENDER_EMAIL"
else
	echo "  - Email notifications: Disabled"
fi

if [ "$PROTECT_APACHE" = true ]; then
	echo "  - Apache protection: Enabled"
else
	echo "  - Apache protection: Disabled"
fi

if [ "$PROTECT_NGINX" = true ]; then
	echo "  - Nginx protection: Enabled"
else
	echo "  - Nginx protection: Disabled"
fi

echo -e "\n${BLUE}Useful Fail2Ban commands:${NC}"
echo "  fail2ban-client status                  - Show all jails"
echo "  fail2ban-client status sshd             - Show SSHD jail status"
echo "  fail2ban-client set sshd unbanip <IP>   - Unban an IP from SSHD jail"
echo "  fail2ban-client reload                  - Reload configuration"
echo "  systemctl restart fail2ban              - Restart service"
echo "  journalctl -u fail2ban -f               - View fail2ban logs in real time"

exit 0
