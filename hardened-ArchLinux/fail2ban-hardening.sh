#!/bin/bash

# ╔═══════════════════════════════════════════════════════════════════╗
# ║  Fail2Ban Hardening Script for Arch Linux                         ║
# ║  This script installs, configures and hardens Fail2Ban            ║
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
BACKUP_DIR="/root/fail2ban_backup"
JAIL_CONF="/etc/fail2ban/jail.conf"
JAIL_LOCAL="/etc/fail2ban/jail.local"
F2B_CONF="/etc/fail2ban/fail2ban.conf"
F2B_LOCAL="/etc/fail2ban/fail2ban.local"

# ┌─────────────────────────────────────────────────────────────────┐
# │ Check if running as root                                         │
# └─────────────────────────────────────────────────────────────────┘
if [[ $EUID -ne 0 ]]; then
	echo -e "${RED}${BOLD}[ERROR]${NC} This script must be run as root"
	exit 1
fi

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

# Function to backup a file before modifying
backup_file() {
	local file=$1
	local backup="${BACKUP_DIR}/$(basename ${file}).bak.$(date +%Y%m%d%H%M%S)"

	# Only backup if file exists
	if [ -f "$file" ]; then
		cp "$file" "$backup"
		print_info "Backed up $file to $backup"
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

	# Check if port is in the valid range (1-65535)
	if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
		print_error "Port must be between 1 and 65535"
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

# Function to get user confirmation
confirm() {
	local prompt="$1"
	local response

	while true; do
		echo -e -n "${CYAN}${prompt} [y/n]:${NC} "
		read response
		case $response in
		[Yy]*) return 0 ;;
		[Nn]*) return 1 ;;
		*) echo -e "${YELLOW}Please enter y or n.${NC}" ;;
		esac
	done
}

# Function to get yes/no input with default
get_yes_no() {
	local prompt=$1
	local default=$2

	while true; do
		if [[ "$default" == "y" ]]; then
			echo -e -n "${CYAN}${prompt} [Y/n]:${NC} "
			read answer
			answer=${answer:-y}
		else
			echo -e -n "${CYAN}${prompt} [y/N]:${NC} "
			read answer
			answer=${answer:-n}
		fi

		case ${answer,,} in
		y | yes) return 0 ;;
		n | no) return 1 ;;
		*) print_warning "Please answer yes (y) or no (n)" ;;
		esac
	done
}

# Function to check if sendmail is installed
check_mail_capabilities() {
	if ! command -v sendmail &>/dev/null && ! command -v msmtp &>/dev/null; then
		print_warning "No mail transfer agent found (sendmail or msmtp)."
		print_warning "You may need to install a mail service to receive email notifications."
		print_warning "Suggested packages: postfix, exim, msmtp, or ssmtp"

		if get_yes_no "Would you like to install msmtp (a simple mail transfer agent)?" "n"; then
			if ! pacman -S msmtp --noconfirm; then
				print_error "Failed to install msmtp. Email notifications may not work."
			else
				print_info "msmtp installed successfully."
			fi
		fi
	fi
}

# Create backup directory
mkdir -p $BACKUP_DIR

# ┌─────────────────────────────────────────────────────────────────┐
# │ Welcome message                                                  │
# └─────────────────────────────────────────────────────────────────┘
clear
echo
echo -e "${BRIGHT_BLUE}${BOLD}"
cat <<"EOF"
  ███████╗ █████╗ ██╗██╗     ██████╗ ██████╗  █████╗ ███╗   ██╗
  ██╔════╝██╔══██╗██║██║     ╚════██╗██╔══██╗██╔══██╗████╗  ██║
  █████╗  ███████║██║██║      █████╔╝██████╔╝███████║██╔██╗ ██║
  ██╔══╝  ██╔══██║██║██║      ╚═══██╗██╔══██╗██╔══██║██║╚██╗██║
  ██║     ██║  ██║██║███████╗██████╔╝██████╔╝██║  ██║██║ ╚████║
  ╚═╝     ╚═╝  ╚═╝╚═╝╚══════╝╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝
EOF
echo -e "${NC}"
echo
echo -e "${MAGENTA}"
cat <<"EOF"
  ██╗  ██╗ █████╗ ██████╗ ██████╗ ███████╗███╗   ██╗██╗███╗   ██╗ ██████╗ 
  ██║  ██║██╔══██╗██╔══██╗██╔══██╗██╔════╝████╗  ██║██║████╗  ██║██╔════╝ 
  ███████║███████║██████╔╝██║  ██║█████╗  ██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
  ██╔══██║██╔══██║██╔══██╗██║  ██║██╔══╝  ██║╚██╗██║██║██║╚██╗██║██║   ██║
  ██║  ██║██║  ██║██║  ██║██████╔╝███████╗██║ ╚████║██║██║ ╚████║╚██████╔╝
  ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝ 
EOF
echo -e "${NC}"

# ┌─────────────────────────────────────────────────────────────────┐
# │ Install Fail2Ban                                                 │
# └─────────────────────────────────────────────────────────────────┘
print_section "Installing Fail2Ban"

# Check if Fail2Ban is installed
if ! command -v fail2ban-server &>/dev/null; then
	print_info "Fail2Ban not found. Installing..."
	if ! pacman -Syu fail2ban --noconfirm; then
		print_error "Failed to install Fail2Ban. Please check your package manager."
		exit 1
	fi
	print_info "Fail2Ban installed successfully."
else
	print_info "Fail2Ban is already installed."
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ Setting up configuration files                                   │
# └─────────────────────────────────────────────────────────────────┘
print_section "Setting up configuration files"

# Backup original configuration files
backup_file "$JAIL_CONF"
backup_file "$F2B_CONF"

# Create local configuration files if they don't exist
if [ ! -f "$JAIL_LOCAL" ]; then
	cp "$JAIL_CONF" "$JAIL_LOCAL"
	print_info "Created jail.local configuration file."
else
	backup_file "$JAIL_LOCAL"
	print_info "Found existing jail.local file, backed up."
fi

if [ ! -f "$F2B_LOCAL" ]; then
	cp "$F2B_CONF" "$F2B_LOCAL"
	print_info "Created fail2ban.local configuration file."
else
	backup_file "$F2B_LOCAL"
	print_info "Found existing fail2ban.local file, backed up."
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ Configure Fail2Ban settings                                      │
# └─────────────────────────────────────────────────────────────────┘
print_section "Configuring Fail2Ban settings"

# Ask if user wants to use default configuration
echo -e "${YELLOW}${BOLD}Fail2Ban Configuration Options${NC}"
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
	print_info "Using default settings."
fi

# Ask for SSH port
while true; do
	echo -e -n "${CYAN}Enter the SSH port number that your server uses (default: 22):${NC} "
	read SSH_PORT

	# Use default port if empty input
	if [ -z "$SSH_PORT" ]; then
		SSH_PORT=22
		break
	fi

	if validate_port "$SSH_PORT"; then
		print_info "Using SSH port: $SSH_PORT for Fail2Ban configuration"
		break
	else
		print_error "Invalid port, please try again."
	fi
done

# Ask for ban time if user wants to customize
if [ "$CUSTOM_CONFIG" = true ]; then
	echo -e "\n${YELLOW}${BOLD}Ban Time Configuration${NC}"
	echo "This is how long an IP will be banned after too many failed attempts."
	echo "Examples: 10m (10 minutes), 1h (1 hour), 1d (1 day), 1w (1 week)"

	while true; do
		echo -e -n "${CYAN}Enter ban time (default: 10m):${NC} "
		read BANTIME

		# Use default if empty input
		if [ -z "$BANTIME" ]; then
			BANTIME="10m"
			break
		fi

		if validate_time "$BANTIME"; then
			print_info "Using ban time: $BANTIME"
			break
		else
			print_error "Invalid time format. Please use format like 10m, 1h, 1d."
		fi
	done

	# Ask for find time
	echo -e "\n${YELLOW}${BOLD}Find Time Configuration${NC}"
	echo "This is the time window during which Fail2Ban counts failures."
	echo "If there are more than maxretry failures in this time window, the IP gets banned."

	while true; do
		echo -e -n "${CYAN}Enter find time (default: 10m):${NC} "
		read FINDTIME

		# Use default if empty input
		if [ -z "$FINDTIME" ]; then
			FINDTIME="10m"
			break
		fi

		if validate_time "$FINDTIME"; then
			print_info "Using find time: $FINDTIME"
			break
		else
			print_error "Invalid time format. Please use format like 10m, 1h, 1d."
		fi
	done

	# Ask for max retries
	echo -e "\n${YELLOW}${BOLD}Max Retry Configuration${NC}"
	echo "This is the number of failures allowed within the find time before an IP is banned."

	while true; do
		echo -e -n "${CYAN}Enter max retries before banning (default: 5):${NC} "
		read MAXRETRY

		# Use default if empty input
		if [ -z "$MAXRETRY" ]; then
			MAXRETRY=5
			break
		fi

		# Check if input is a positive number
		if [[ "$MAXRETRY" =~ ^[0-9]+$ ]] && [ "$MAXRETRY" -gt 0 ]; then
			print_info "Using max retries: $MAXRETRY"
			break
		else
			print_error "Invalid number. Please enter a positive integer."
		fi
	done
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ Email Notification Configuration                                 │
# └─────────────────────────────────────────────────────────────────┘
echo -e "\n${YELLOW}${BOLD}Email Notification Configuration${NC}"
if get_yes_no "Do you want to enable email notifications for Fail2Ban events?" "n"; then
	EMAIL_NOTIFY=true

	# Check if mail capabilities are available
	check_mail_capabilities

	# Ask for destination email
	echo -e "\n${YELLOW}${BOLD}Destination Email Configuration${NC}"
	echo "This is the email address where notifications will be sent."

	while true; do
		echo -e -n "${CYAN}Enter destination email address:${NC} "
		read DEST_EMAIL

		if [ -z "$DEST_EMAIL" ]; then
			print_error "Email address can't be empty."
			continue
		fi

		if validate_email "$DEST_EMAIL"; then
			print_info "Using destination email: $DEST_EMAIL"
			break
		else
			print_error "Invalid email address. Please try again."
		fi
	done

	# Ask for sender email
	echo -e "\n${YELLOW}${BOLD}Sender Email Configuration${NC}"
	echo "This is the 'from' address that will appear on notification emails."

	while true; do
		echo -e -n "${CYAN}Enter sender email address (default: root@$(hostname -f)):${NC} "
		read SENDER_EMAIL

		# Use default if empty input
		if [ -z "$SENDER_EMAIL" ]; then
			SENDER_EMAIL="root@$(hostname -f)"
			break
		fi

		if validate_email "$SENDER_EMAIL"; then
			print_info "Using sender email: $SENDER_EMAIL"
			break
		else
			print_error "Invalid email address. Please try again."
		fi
	done

	# Set action to include email notifications
	ACTION="action_mwl"
	print_info "Email notifications will be enabled."
else
	EMAIL_NOTIFY=false
	# Default action without email
	ACTION="action_"
	DEST_EMAIL="root@localhost"
	SENDER_EMAIL="root@$(hostname -f)"
	print_warning "Email notifications will not be enabled."
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ IP Whitelist Configuration                                       │
# └─────────────────────────────────────────────────────────────────┘
echo -e "\n${YELLOW}${BOLD}IP Whitelist Configuration${NC}"
echo "Enter IP addresses to whitelist (ignore), one per line."
echo "These IPs will never be banned by Fail2Ban."
echo "Press Enter on an empty line when done. Default: localhost only."
echo "Examples: 192.168.1.0/24 or your.static.ip.address"

IGNORE_IP_LIST="127.0.0.1/8 ::1"
TEMP_IPS=()

echo -e "${BLUE}Start entering IPs (one per line, press Enter twice when done):${NC}"
while true; do
	echo -e -n "${CYAN}> ${NC}"
	read IP

	# Break on empty line
	if [ -z "$IP" ]; then
		break
	fi

	TEMP_IPS+=("$IP")
done

if [ ${#TEMP_IPS[@]} -gt 0 ]; then
	IGNORE_IP_LIST="$IGNORE_IP_LIST ${TEMP_IPS[*]}"
fi

print_info "Using whitelist: $IGNORE_IP_LIST"

# ┌─────────────────────────────────────────────────────────────────┐
# │ Advanced Configuration                                           │
# └─────────────────────────────────────────────────────────────────┘
echo -e "\n${YELLOW}${BOLD}Advanced Configuration${NC}"
if get_yes_no "Would you like to configure additional services to protect (e.g., Apache, Nginx)?" "n"; then
	PROTECT_APACHE=false
	PROTECT_NGINX=false

	if get_yes_no "Do you want to protect Apache web server?" "n"; then
		PROTECT_APACHE=true
		print_info "Apache protection will be enabled."
	fi

	if get_yes_no "Do you want to protect Nginx web server?" "n"; then
		PROTECT_NGINX=true
		print_info "Nginx protection will be enabled."
	fi
else
	PROTECT_APACHE=false
	PROTECT_NGINX=false
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ Update configuration files                                       │
# └─────────────────────────────────────────────────────────────────┘
print_section "Updating Fail2Ban configuration"

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

print_info "Updated jail.local configuration."

# ┌─────────────────────────────────────────────────────────────────┐
# │ Enable and start Fail2Ban service                                │
# └─────────────────────────────────────────────────────────────────┘
print_section "Enabling and starting Fail2Ban service"

# First check if it's already running and stop it if needed
if systemctl is-active --quiet fail2ban; then
	systemctl stop fail2ban
	print_info "Stopped existing Fail2Ban service."
fi

# Enable and start the service
systemctl enable fail2ban
if systemctl start fail2ban; then
	print_info "Fail2Ban service has been enabled and started."
else
	print_error "Failed to start Fail2Ban service. Check logs with 'journalctl -u fail2ban'."
	exit 1
fi

# Wait a moment for service to fully start
sleep 2

# ┌─────────────────────────────────────────────────────────────────┐
# │ Check service status                                             │
# └─────────────────────────────────────────────────────────────────┘
print_section "Fail2Ban Status"

if fail2ban-client status; then
	echo -e "\n${BLUE}${BOLD}SSHD jail status:${NC}"
	fail2ban-client status sshd
else
	print_error "Fail2Ban service is not responding properly. Please check logs."
	exit 1
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ Installation complete                                            │
# └─────────────────────────────────────────────────────────────────┘
echo
echo -e "${BRIGHT_BLUE}${BOLD}"
cat <<"EOF"
  ███████╗ █████╗ ██╗██╗     ██████╗ ██████╗  █████╗ ███╗   ██╗
  ██╔════╝██╔══██╗██║██║     ╚════██╗██╔══██╗██╔══██╗████╗  ██║
  █████╗  ███████║██║██║      █████╔╝██████╔╝███████║██╔██╗ ██║
  ██╔══╝  ██╔══██║██║██║      ╚═══██╗██╔══██╗██╔══██║██║╚██╗██║
  ██║     ██║  ██║██║███████╗██████╔╝██████╔╝██║  ██║██║ ╚████║
  ╚═╝     ╚═╝  ╚═╝╚═╝╚══════╝╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝
EOF
echo -e "${NC}"
echo
echo -e "${MAGENTA}"
cat <<"EOF"
  ███████╗███████╗████████╗██╗   ██╗██████╗      ██████╗ ██████╗ ███╗   ███╗██████╗ ██╗     ███████╗████████╗███████╗██╗
  ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗    ██╔════╝██╔═══██╗████╗ ████║██╔══██╗██║     ██╔════╝╚══██╔══╝██╔════╝██║
  ███████╗█████╗     ██║   ██║   ██║██████╔╝    ██║     ██║   ██║██╔████╔██║██████╔╝██║     █████╗     ██║   █████╗  ██║
  ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝     ██║     ██║   ██║██║╚██╔╝██║██╔═══╝ ██║     ██╔══╝     ██║   ██╔══╝  ╚═╝
  ███████║███████╗   ██║   ╚██████╔╝██║         ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║     ███████╗███████╗   ██║   ███████╗██╗
  ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝          ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚══════╝╚══════╝   ╚═╝   ╚══════╝╚═╝
EOF
echo -e "${NC}"

print_section "Configuration Summary"

echo -e "${GREEN}${BOLD}┌───────────────────────────────────────────────────────────────┐${NC}"
echo -e "  ${BOLD}Ban time:${NC} $BANTIME"
echo -e "  ${BOLD}Find time:${NC} $FINDTIME"
echo -e "  ${BOLD}Max retries:${NC} $MAXRETRY"
echo -e "  ${BOLD}SSH port protected:${NC} $SSH_PORT"
echo -e "  ${BOLD}Whitelisted IPs:${NC} $IGNORE_IP_LIST"

if [ "$EMAIL_NOTIFY" = true ]; then
	echo -e "  ${BOLD}Email notifications:${NC} Enabled"
	echo -e "  ${BOLD}Notification recipient:${NC} $DEST_EMAIL"
	echo -e "  ${BOLD}Sender email:${NC} $SENDER_EMAIL"
else
	echo -e "  ${BOLD}Email notifications:${NC} Disabled"
fi

if [ "$PROTECT_APACHE" = true ]; then
	echo -e "  ${BOLD}Apache protection:${NC} Enabled"
else
	echo -e "  ${BOLD}Apache protection:${NC} Disabled"
fi

if [ "$PROTECT_NGINX" = true ]; then
	echo -e "  ${BOLD}Nginx protection:${NC} Enabled"
else
	echo -e "  ${BOLD}Nginx protection:${NC} Disabled"
fi
echo -e "${GREEN}${BOLD}└───────────────────────────────────────────────────────────────┘${NC}"

print_section "Useful Fail2Ban Commands"

echo -e "  ${CYAN}fail2ban-client status${NC}                  - Show all jails"
echo -e "  ${CYAN}fail2ban-client status sshd${NC}             - Show SSHD jail status"
echo -e "  ${CYAN}fail2ban-client set sshd unbanip <IP>${NC}   - Unban an IP from SSHD jail"
echo -e "  ${CYAN}fail2ban-client reload${NC}                  - Reload configuration"
echo -e "  ${CYAN}systemctl restart fail2ban${NC}              - Restart service"
echo -e "  ${CYAN}journalctl -u fail2ban -f${NC}               - View fail2ban logs in real time"

exit 0
