#!/bin/bash

# ╔═══════════════════════════════════════════════════════════════════╗
# ║  UFW Firewall Hardening Script for Arch Linux                     ║
# ║  This script configures UFW with security-focused settings        ║
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
# │ Utility functions                                                │
# └─────────────────────────────────────────────────────────────────┘
# Function to print section headers
print_section() {
	echo -e "\n${BLUE}${BOLD}╔════════════ $1 ════════════╗${NC}\n"
}

# Function to print information
print_info() {
	echo -e "${CYAN}${BOLD}[INFO]${NC} $1"
}

# Function to print warnings
print_warning() {
	echo -e "${YELLOW}${BOLD}[WARNING]${NC} $1"
}

# Function to print errors
print_error() {
	echo -e "${RED}${BOLD}[ERROR]${NC} $1"
}

# Function to print success messages
print_success() {
	echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"
}

# Function to check if a command succeeded
check_status() {
	if [ $? -eq 0 ]; then
		print_success "$1"
	else
		print_error "$1"
		echo -e "${YELLOW}Would you like to continue anyway? (y/n)${NC}"
		read continue_choice
		if [[ $continue_choice != "y" && $continue_choice != "Y" ]]; then
			echo "Exiting script."
			exit 1
		fi
	fi
}

# Function to get user confirmation
confirm() {
	local prompt="$1"
	local response

	while true; do
		echo -ne "${CYAN}${prompt} (y/n):${NC} "
		read response
		case $response in
		[Yy]*) return 0 ;;
		[Nn]*) return 1 ;;
		*) echo -e "${YELLOW}Please enter y or n.${NC}" ;;
		esac
	done
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Check if script is run as root                                   │
# └─────────────────────────────────────────────────────────────────┘
check_root() {
	if [ "$(id -u)" -ne 0 ]; then
		print_error "This script must be run as root"
		exit 1
	fi
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Main script                                                      │
# └─────────────────────────────────────────────────────────────────┘
main() {
	# Display header
	clear
	echo
	echo -e "${BRIGHT_BLUE}${BOLD}"
	cat <<"EOF"
  ██╗   ██╗███████╗██╗    ██╗    ███████╗██╗██████╗ ███████╗██╗    ██╗ █████╗ ██╗     ██╗     
  ██║   ██║██╔════╝██║    ██║    ██╔════╝██║██╔══██╗██╔════╝██║    ██║██╔══██╗██║     ██║     
  ██║   ██║█████╗  ██║ █╗ ██║    █████╗  ██║██████╔╝█████╗  ██║ █╗ ██║███████║██║     ██║     
  ██║   ██║██╔══╝  ██║███╗██║    ██╔══╝  ██║██╔══██╗██╔══╝  ██║███╗██║██╔══██║██║     ██║     
  ╚██████╔╝██║     ╚███╔███╔╝    ██║     ██║██║  ██║███████╗╚███╔███╔╝██║  ██║███████╗███████╗
   ╚═════╝ ╚═╝      ╚══╝╚══╝     ╚═╝     ╚═╝╚═╝  ╚═╝╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚══════╝
                                                                                               
  ██╗  ██╗ █████╗ ██████╗ ██████╗ ███████╗███╗   ██╗██╗███╗   ██╗ ██████╗                     
  ██║  ██║██╔══██╗██╔══██╗██╔══██╗██╔════╝████╗  ██║██║████╗  ██║██╔════╝                     
  ███████║███████║██████╔╝██║  ██║█████╗  ██╔██╗ ██║██║██╔██╗ ██║██║  ███╗                    
  ██╔══██║██╔══██║██╔══██╗██║  ██║██╔══╝  ██║╚██╗██║██║██║╚██╗██║██║   ██║                    
  ██║  ██║██║  ██║██║  ██║██████╔╝███████╗██║ ╚████║██║██║ ╚████║╚██████╔╝                    
  ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝                     
EOF
	echo -e "${NC}"

	echo -e "${CYAN}${BOLD}┌───────────────────────────────────────────────────────────────┐${NC}"
	echo -e "${CYAN}${BOLD}│ This script will:                                             │${NC}"
	echo -e "${CYAN}${BOLD}└───────────────────────────────────────────────────────────────┘${NC}"
	echo -e "  ${GREEN}▶${NC} Install UFW (Uncomplicated Firewall)"
	echo -e "  ${GREEN}▶${NC} Configure system network security settings"
	echo -e "  ${GREEN}▶${NC} Set up security-focused UFW rules"
	echo -e "  ${GREEN}▶${NC} Configure TCP SYN packet validation"
	echo -e "  ${GREEN}▶${NC} Enable and start UFW service"
	echo

	check_root

	print_section "Installing UFW"
	print_info "Installing Uncomplicated Firewall package..."
	pacman -S --noconfirm ufw
	check_status "UFW installation"

	print_section "System Configuration"
	print_info "Configuring /etc/default/ufw..."
	if [ -f /etc/default/ufw ]; then
		sed -i 's|IPT_SYSCTL=/etc/ufw/sysctl.conf|IPT_SYSCTL=/etc/sysctl.conf|' /etc/default/ufw
		check_status "Modified IPT_SYSCTL setting"
	else
		print_warning "/etc/default/ufw file not found. Creating it..."
		echo "IPT_SYSCTL=/etc/sysctl.conf" >/etc/default/ufw
		check_status "Created /etc/default/ufw with IPT_SYSCTL setting"
	fi

	print_section "Network Security Settings"
	print_info "Configuring network security settings..."
	SYSCTL_FILE="/etc/sysctl.d/90-network-security.conf"

	# Create or add to the sysctl configuration file
	if [ ! -f "$SYSCTL_FILE" ]; then
		touch "$SYSCTL_FILE"
	fi

	# Check if settings already exist, if not append them
	if ! grep -q "net.ipv4.icmp_echo_ignore_broadcasts = 1" "$SYSCTL_FILE"; then
		cat <<EOF >>"$SYSCTL_FILE"
# Network Security Settings
# Added by UFW Hardening Script on $(date)

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
		print_info "Network security settings already exist in $SYSCTL_FILE"
	fi

	print_info "Applying sysctl settings..."
	sysctl -p "$SYSCTL_FILE"
	check_status "Applied sysctl settings"

	print_section "SSH Configuration"
	SSH_PORT=22

	if confirm "Current SSH port is typically 22. Would you like to change it?"; then
		echo -ne "${CYAN}Enter your SSH port number (1-65535):${NC} "
		read new_ssh_port

		# Validate port number
		if [[ "$new_ssh_port" =~ ^[0-9]+$ && "$new_ssh_port" -ge 1 && "$new_ssh_port" -le 65535 ]]; then
			SSH_PORT=$new_ssh_port
		else
			print_warning "Invalid port number. Using default port 22."
		fi
	fi

	print_info "Using SSH port: ${BOLD}$SSH_PORT${NC}"

	print_section "UFW Rules Configuration"
	print_info "Setting up UFW SSH rules..."
	ufw allow "$SSH_PORT"
	check_status "Added rule to allow SSH connections on port $SSH_PORT"

	ufw limit "$SSH_PORT"
	check_status "Added rate limiting for SSH connections"

	print_section "TCP SYN Packet Validation"
	print_info "Configuring TCP SYN packet validation for IPv4..."
	BEFORE_RULES="/etc/ufw/before.rules"
	IPv4_RULES="-A ufw-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j ufw-logging-deny\n-A ufw-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j DROP"

	# Check if rules already exist
	if ! grep -q "ufw-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j DROP" "$BEFORE_RULES"; then
		# Insert the rules before the COMMIT line
		sed -i "/^COMMIT/i $IPv4_RULES" "$BEFORE_RULES"
		check_status "Added TCP SYN packet validation to before.rules"
	else
		print_info "TCP SYN packet validation rules already exist in before.rules"
	fi

	print_info "Configuring TCP SYN packet validation for IPv6..."
	BEFORE6_RULES="/etc/ufw/before6.rules"
	IPv6_RULES="-A ufw6-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j ufw6-logging-deny\n-A ufw6-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j DROP"

	# Check if rules already exist
	if ! grep -q "ufw6-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j DROP" "$BEFORE6_RULES"; then
		# Insert the rules before the COMMIT line
		sed -i "/^COMMIT/i $IPv6_RULES" "$BEFORE6_RULES"
		check_status "Added TCP SYN packet validation to before6.rules"
	else
		print_info "TCP SYN packet validation rules already exist in before6.rules"
	fi

	print_section "Enabling UFW"
	print_info "Checking UFW status..."
	UFW_STATUS=$(ufw status | grep -o "Status: active")
	if [ -z "$UFW_STATUS" ]; then
		print_info "Enabling UFW..."
		echo "y" | ufw enable # Auto-confirm the prompt
		check_status "Enabled UFW"
	else
		print_info "UFW is already active. Reloading rules..."
		ufw reload
		check_status "Reloaded UFW rules"
	fi

	print_info "Setting UFW to start on boot..."
	systemctl enable ufw --now
	check_status "UFW enabled and started"

	print_section "Summary"

	echo -e "${GREEN}${BOLD}┌───────────────────────────────────────────────────────────────┐${NC}"
	echo -e "${GREEN}${BOLD}│ UFW Firewall Configuration Complete                           │${NC}"
	echo -e "${GREEN}${BOLD}└───────────────────────────────────────────────────────────────┘${NC}"
	echo
	echo -e "${CYAN}${BOLD}Current UFW Status:${NC}"
	echo -e "───────────────────────────────────────────────────────────────"
	ufw status verbose
	echo -e "───────────────────────────────────────────────────────────────"

	echo -e "\n${YELLOW}${BOLD}┌───────────────────────────────────────────────────────────────┐${NC}"
	echo -e "${YELLOW}${BOLD}│ Important Notes                                                │${NC}"
	echo -e "${YELLOW}${BOLD}└───────────────────────────────────────────────────────────────┘${NC}"

	echo -e "  ${YELLOW}!${NC} If you changed the SSH port, update your SSH client settings"
	echo -e "  ${YELLOW}!${NC} If connected via SSH now, don't close this session until you've"
	echo -e "     confirmed that you can connect on the new port"
	echo -e "  ${YELLOW}!${NC} To add more rules, use: ${BOLD}sudo ufw allow <port>/<protocol>${NC}"
	echo -e "  ${YELLOW}!${NC} To check firewall status: ${BOLD}sudo ufw status verbose${NC}"

	echo
	echo -e "${BRIGHT_BLUE}${BOLD}"
	cat <<"EOF"
  ███████╗███████╗ ██████╗██╗   ██╗██████╗ ██╗████████╗██╗   ██╗    ███████╗███╗   ██╗██╗  ██╗ █████╗ ███╗   ██╗ ██████╗███████╗██████╗ 
  ██╔════╝██╔════╝██╔════╝██║   ██║██╔══██╗██║╚══██╔══╝╚██╗ ██╔╝    ██╔════╝████╗  ██║██║  ██║██╔══██╗████╗  ██║██╔════╝██╔════╝██╔══██╗
  ███████╗█████╗  ██║     ██║   ██║██████╔╝██║   ██║    ╚████╔╝     █████╗  ██╔██╗ ██║███████║███████║██╔██╗ ██║██║     █████╗  ██║  ██║
  ╚════██║██╔══╝  ██║     ██║   ██║██╔══██╗██║   ██║     ╚██╔╝      ██╔══╝  ██║╚██╗██║██╔══██║██╔══██║██║╚██╗██║██║     ██╔══╝  ██║  ██║
  ███████║███████╗╚██████╗╚██████╔╝██║  ██║██║   ██║      ██║       ███████╗██║ ╚████║██║  ██║██║  ██║██║ ╚████║╚██████╗███████╗██████╔╝
  ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝   ╚═╝      ╚═╝       ╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝╚══════╝╚═════╝ 
EOF
	echo -e "${NC}"
}

# Execute main function
main
