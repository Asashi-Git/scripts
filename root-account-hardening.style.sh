#!/bin/bash

# ╔═══════════════════════════════════════════════════════════════════╗
# ║  Root Account Hardening Script for Arch Linux                     ║
# ║  This script secures the root account by locking it down          ║
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

# Function to print success messages
print_success() {
	echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"
}

# Function to print error messages
print_error() {
	echo -e "${RED}${BOLD}[ERROR]${NC} $1"
}

# Function to print warning messages
print_warning() {
	echo -e "${YELLOW}${BOLD}[WARNING]${NC} $1"
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Check for root privileges                                        │
# └─────────────────────────────────────────────────────────────────┘
check_root() {
	if [ "$EUID" -ne 0 ]; then
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
  ██████╗  ██████╗  ██████╗ ████████╗     █████╗  ██████╗ ██████╗ ██████╗ ██╗   ██╗███╗   ██╗████████╗
  ██╔══██╗██╔═══██╗██╔═══██╗╚══██╔══╝    ██╔══██╗██╔════╝██╔════╝██╔═══██╗██║   ██║████╗  ██║╚══██╔══╝
  ██████╔╝██║   ██║██║   ██║   ██║       ███████║██║     ██║     ██║   ██║██║   ██║██╔██╗ ██║   ██║   
  ██╔══██╗██║   ██║██║   ██║   ██║       ██╔══██║██║     ██║     ██║   ██║██║   ██║██║╚██╗██║   ██║   
  ██║  ██║╚██████╔╝╚██████╔╝   ██║       ██║  ██║╚██████╗╚██████╗╚██████╔╝╚██████╔╝██║ ╚████║   ██║   
  ╚═╝  ╚═╝ ╚═════╝  ╚═════╝    ╚═╝       ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   
                                                                                                      
  ██╗  ██╗ █████╗ ██████╗ ██████╗ ███████╗███╗   ██╗██╗███╗   ██╗ ██████╗                             
  ██║  ██║██╔══██╗██╔══██╗██╔══██╗██╔════╝████╗  ██║██║████╗  ██║██╔════╝                             
  ███████║███████║██████╔╝██║  ██║█████╗  ██╔██╗ ██║██║██╔██╗ ██║██║  ███╗                            
  ██╔══██║██╔══██║██╔══██╗██║  ██║██╔══╝  ██║╚██╗██║██║██║╚██╗██║██║   ██║                            
  ██║  ██║██║  ██║██║  ██║██████╔╝███████╗██║ ╚████║██║██║ ╚████║╚██████╔╝                            
  ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝                             
EOF
	echo -e "${NC}"

	check_root

	print_section "Preparing System"

	print_info "Creating backups of essential files..."
	cp /etc/passwd /etc/passwd.backup
	cp /etc/shadow /etc/shadow.backup
	print_success "Backups created at /etc/passwd.backup and /etc/shadow.backup"

	print_section "Changing Root Shell"

	print_info "Setting root's shell to /usr/sbin/nologin..."
	awk -F: '$1=="root" {$NF="/usr/sbin/nologin"}1' OFS=: /etc/passwd >/tmp/passwd.new
	if [ $? -eq 0 ]; then
		cat /tmp/passwd.new >/etc/passwd
		rm /tmp/passwd.new
		print_success "Root shell changed successfully"
	else
		print_error "Failed to change root shell"
	fi

	print_section "Disabling Root Password"

	print_info "Locking root password..."
	awk -F: '$1=="root" {$2="!"}1' OFS=: /etc/shadow >/tmp/shadow.new
	if [ $? -eq 0 ]; then
		cat /tmp/shadow.new >/etc/shadow
		rm /tmp/shadow.new
		print_success "Root password locked successfully"
	else
		print_error "Failed to lock root password"
	fi

	print_section "Verification"

	print_info "Verifying changes..."

	if grep -q "^root:.*:/usr/sbin/nologin$" /etc/passwd; then
		print_success "Verified: Root shell is now /usr/sbin/nologin"
	else
		print_error "Error: Root shell was not changed correctly"
	fi

	if grep -q "^root:!:" /etc/shadow; then
		print_success "Verified: Root password is now locked"
	else
		print_error "Error: Root password was not locked correctly"
	fi

	print_section "Summary"

	echo -e "${GREEN}${BOLD}┌───────────────────────────────────────────────────────────────┐${NC}"
	echo -e "${GREEN}${BOLD}│ Root Account Hardening Complete                               │${NC}"
	echo -e "${GREEN}${BOLD}└───────────────────────────────────────────────────────────────┘${NC}"

	echo -e "  ${GREEN}✓${NC} Root account can no longer be logged into directly"
	echo -e "  ${GREEN}✓${NC} Root password has been locked"
	echo -e "  ${GREEN}✓${NC} Root shell changed to /usr/sbin/nologin"
	echo -e "  ${GREEN}✓${NC} Original files backed up for reference"

	echo -e "\n${YELLOW}${BOLD}┌───────────────────────────────────────────────────────────────┐${NC}"
	echo -e "${YELLOW}${BOLD}│ Security Notes                                                 │${NC}"
	echo -e "${YELLOW}${BOLD}└───────────────────────────────────────────────────────────────┘${NC}"

	echo -e "  ${YELLOW}!${NC} Administrative access now requires ${BOLD}sudo${NC}"
	echo -e "  ${YELLOW}!${NC} Make sure you have at least one admin user with sudo privileges"
	echo -e "  ${YELLOW}!${NC} For emergency recovery, use the Arch installation media"

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
