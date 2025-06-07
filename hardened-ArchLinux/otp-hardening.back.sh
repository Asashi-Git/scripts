#!/bin/bash

# ╔═══════════════════════════════════════════════════════════════════╗
# ║  OTP Authentication Hardening Script for Arch Linux               ║
# ║  This script configures One-Time Password (OTP) for SSH access    ║
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

# Function to print success messages
print_success() {
	echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"
}

# Function to get user confirmation - FIXED to properly display colors
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

# Function to check if the script is run with sudo privileges
check_sudo() {
	if [[ $EUID -ne 0 ]]; then
		print_error "This script must be run as root or with sudo privileges."
		exit 1
	fi
}

# Function to backup a file before modifying it
backup_file() {
	local file=$1
	local backup_file="${file}.bak.$(date +%Y%m%d%H%M%S)"

	print_info "Creating backup of $file to $backup_file"
	cp "$file" "$backup_file"

	if [[ $? -ne 0 ]]; then
		print_error "Failed to create backup of $file. Exiting."
		exit 1
	else
		print_success "Backup created successfully."
	fi
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Function to check and set timezone                               │
# └─────────────────────────────────────────────────────────────────┘
check_and_set_timezone() {
	print_section "System Time Check"

	print_info "Current date and time:"
	echo -e "${CYAN}$(date)${NC}"

	if confirm "Is the date and time correct?"; then
		print_success "Time verification completed."
	else
		echo
		echo -e -n "${CYAN}Enter your continent (default: Europe): ${NC}"
		read continent
		echo -e -n "${CYAN}Enter your capital (default: Paris): ${NC}"
		read capital

		continent=${continent:-Europe}
		capital=${capital:-Paris}

		print_info "Setting timezone to $continent/$capital"
		timedatectl set-timezone "$continent/$capital"

		if [[ $? -ne 0 ]]; then
			print_error "Failed to set timezone. Please check if the continent and capital are valid."
			exit 1
		fi

		print_success "Timezone updated successfully."
		print_info "Updated date and time:"
		echo -e "${CYAN}$(date)${NC}"
	fi
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Function to install google-authenticator                         │
# └─────────────────────────────────────────────────────────────────┘
install_google_authenticator() {
	print_section "Google Authenticator Installation"

	if ! pacman -Q libpam-google-authenticator &>/dev/null && ! pacman -Q google-authenticator &>/dev/null; then
		print_info "Google Authenticator is not installed. Installing..."
		pacman -S --noconfirm libpam-google-authenticator || pacman -S --noconfirm google-authenticator

		if [[ $? -ne 0 ]]; then
			print_error "Failed to install Google Authenticator. Exiting."
			exit 1
		else
			print_success "Google Authenticator installed successfully."
		fi
	else
		print_success "Google Authenticator is already installed."
	fi
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Function to configure Google Authenticator                       │
# └─────────────────────────────────────────────────────────────────┘
configure_google_authenticator() {
	print_section "Google Authenticator Configuration"

	print_info "Configuring Google Authenticator..."
	echo -e "${YELLOW}${BOLD}Please follow the instructions to set up your OTP.${NC}"
	echo -e "${YELLOW}${BOLD}It is recommended to answer 'y' to all questions for secure setup.${NC}"
	echo -e "${BLUE}${BOLD}┌────────────────────────────────────────────────────────────┐${NC}"
	echo -e "${BLUE}${BOLD}│ Recommended settings:                                      │${NC}"
	echo -e "${BLUE}${BOLD}│ • Time-based tokens                     -> y               │${NC}"
	echo -e "${BLUE}${BOLD}│ • Update .google_authenticator file     -> y               │${NC}"
	echo -e "${BLUE}${BOLD}│ • Disallow token reuse                  -> y               │${NC}"
	echo -e "${BLUE}${BOLD}│ • Allow 30s time skew                   -> y               │${NC}"
	echo -e "${BLUE}${BOLD}│ • Rate limit authentication attempts    -> y               │${NC}"
	echo -e "${BLUE}${BOLD}└────────────────────────────────────────────────────────────┘${NC}"
	echo

	# Run Google Authenticator setup for the current user
	sudo -u $SUDO_USER google-authenticator

	if [[ $? -ne 0 ]]; then
		print_error "Failed to configure Google Authenticator. Exiting."
		exit 1
	fi

	print_success "Google Authenticator configuration completed."
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Function to modify PAM configuration for SSH                     │
# └─────────────────────────────────────────────────────────────────┘
configure_pam_sshd() {
	print_section "PAM Configuration for SSH"
	local pam_file="/etc/pam.d/sshd"

	print_info "Configuring PAM for SSH..."
	backup_file "$pam_file"

	# Check if the line is already there
	if ! grep -q "auth required pam_google_authenticator.so" "$pam_file"; then
		# Find the line with #%PAM-1.0 and add our line after it
		sed -i '/#%PAM-1.0/a auth required pam_google_authenticator.so' "$pam_file"

		if [[ $? -ne 0 ]]; then
			print_error "Failed to modify $pam_file. Exiting."
			exit 1
		fi

		print_success "Added Google Authenticator to PAM configuration."
	else
		print_success "Google Authenticator is already configured in PAM."
	fi
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Function to modify SSH daemon configuration                      │
# └─────────────────────────────────────────────────────────────────┘
configure_sshd() {
	print_section "SSH Daemon Configuration"
	local sshd_config="/etc/ssh/sshd_config"
	local archlinux_conf="/etc/ssh/sshd_config.d/99-archlinux.conf"

	print_info "Configuring SSH daemon..."
	backup_file "$sshd_config"

	# Array of settings to check and set
	declare -A settings=(
		["PasswordAuthentication"]="no"
		["KbdInteractiveAuthentication"]="yes"
		["UsePAM"]="yes"
		["ChallengeResponseAuthentication"]="yes"
		["AuthenticationMethods"]="publickey,keyboard-interactive"
		["LoginGraceTime"]="20"
		["MaxAuthTries"]="3"
		["MaxSessions"]="5"
		["PermitEmptyPasswords"]="no"
		["ClientAliveInterval"]="60"
		["ClientAliveCountMax"]="3"
		["X11Forwarding"]="no"
		["AllowAgentForwarding"]="no"
		["AllowTcpForwarding"]="no"
	)

	# Check and set each configuration
	for key in "${!settings[@]}"; do
		value="${settings[$key]}"

		# Check if the setting exists
		if grep -q "^#*[[:space:]]*${key}[[:space:]]" "$sshd_config"; then
			# Setting exists, update it
			sed -i "s/^#*[[:space:]]*${key}[[:space:]].*/${key} ${value}/" "$sshd_config"
			print_info "Updated: ${key} ${value}"
		else
			# Setting doesn't exist, add it
			echo "${key} ${value}" >>"$sshd_config"
			print_info "Added: ${key} ${value}"
		fi
	done

	print_success "SSH daemon configuration updated."

	# Comment out all lines in 99-archlinux.conf if it exists
	if [[ -f "$archlinux_conf" ]]; then
		backup_file "$archlinux_conf"

		print_info "Commenting out all lines in $archlinux_conf"
		sed -i 's/^/#/' "$archlinux_conf"

		if [[ $? -ne 0 ]]; then
			print_error "Failed to modify $archlinux_conf. Exiting."
			exit 1
		else
			print_success "Commented out all lines in $archlinux_conf."
		fi
	else
		print_info "$archlinux_conf does not exist. Skipping."
	fi
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Function to apply SSH configuration changes                      │
# └─────────────────────────────────────────────────────────────────┘
apply_ssh_config() {
	print_section "Applying SSH Configuration"

	print_info "Testing SSH configuration..."
	sshd -t

	if [[ $? -ne 0 ]]; then
		print_error "SSH configuration test failed. Please check your configuration."
		exit 1
	else
		print_success "SSH configuration test passed."
	fi

	print_info "Restarting SSH daemon..."
	systemctl restart sshd

	if [[ $? -ne 0 ]]; then
		print_error "Failed to restart SSH daemon. Exiting."
		exit 1
	fi

	print_success "SSH daemon restarted successfully."
	print_success "OTP configuration has been applied."
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Main function                                                    │
# └─────────────────────────────────────────────────────────────────┘
main() {
	clear
	echo
	echo -e "${BRIGHT_BLUE}${BOLD}"
	cat <<"EOF"
   ██████╗ ████████╗██████╗     ██╗  ██╗ █████╗ ██████╗ ██████╗ ███████╗███╗   ██╗██╗███╗   ██╗ ██████╗ 
  ██╔═══██╗╚══██╔══╝██╔══██╗    ██║  ██║██╔══██╗██╔══██╗██╔══██╗██╔════╝████╗  ██║██║████╗  ██║██╔════╝ 
  ██║   ██║   ██║   ██████╔╝    ███████║███████║██████╔╝██║  ██║█████╗  ██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
  ██║   ██║   ██║   ██╔═══╝     ██╔══██║██╔══██║██╔══██╗██║  ██║██╔══╝  ██║╚██╗██║██║██║╚██╗██║██║   ██║
  ╚██████╔╝   ██║   ██║         ██║  ██║██║  ██║██║  ██║██████╔╝███████╗██║ ╚████║██║██║ ╚████║╚██████╔╝
   ╚═════╝    ╚═╝   ╚═╝         ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝ 
                                                                                                        
  ██████╗ ██╗   ██╗    ██╗      █████╗ ██╗   ██╗███████╗██████╗                                         
  ██╔══██╗╚██╗ ██╔╝    ██║     ██╔══██╗╚██╗ ██╔╝██╔════╝██╔══██╗                                        
  ██████╔╝ ╚████╔╝     ██║     ███████║ ╚████╔╝ █████╗  ██████╔╝                                        
  ██╔══██╗  ╚██╔╝      ██║     ██╔══██║  ╚██╔╝  ██╔══╝  ██╔══██╗                                        
  ██████╔╝   ██║       ███████╗██║  ██║   ██║   ███████╗██║  ██║                                        
  ╚═════╝    ╚═╝       ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝                                        
EOF
	echo -e "${NC}"

	check_sudo
	check_and_set_timezone
	install_google_authenticator
	configure_google_authenticator
	configure_pam_sshd
	configure_sshd
	apply_ssh_config

	print_section "Summary"

	echo -e "${GREEN}${BOLD}┌───────────────────────────────────────────────────────────────┐${NC}"
	echo -e "${GREEN}${BOLD}│ OTP Configuration Completed                                   │${NC}"
	echo -e "${GREEN}${BOLD}└───────────────────────────────────────────────────────────────┘${NC}"

	echo -e "  ${GREEN}✓${NC} Google Authenticator installed and configured"
	echo -e "  ${GREEN}✓${NC} PAM configured for SSH authentication"
	echo -e "  ${GREEN}✓${NC} SSH hardened with secure configuration"
	echo -e "  ${GREEN}✓${NC} Time-based One-Time Password (TOTP) enabled"
	echo
	echo -e "${YELLOW}${BOLD}┌───────────────────────────────────────────────────────────────┐${NC}"
	echo -e "${YELLOW}${BOLD}│ Important Security Notes                                      │${NC}"
	echo -e "${YELLOW}${BOLD}└───────────────────────────────────────────────────────────────┘${NC}"
	echo -e "  ${YELLOW}!${NC} Make sure to keep your recovery codes in a secure location"
	echo -e "  ${YELLOW}!${NC} You can now log in using your SSH key and OTP token"
	echo -e "  ${YELLOW}!${NC} Do not disconnect from your current session until you verify"
	echo -e "     that you can successfully authenticate with the new method"

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
