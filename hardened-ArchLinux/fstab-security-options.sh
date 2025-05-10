#!/bin/bash

# ╔═══════════════════════════════════════════════════════════════════╗
# ║  Arch Linux fstab Security Options Script                         ║
# ║  This script adds security options to /etc/fstab                  ║
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

# Function to check if a command executed successfully
check_success() {
	if [ $? -eq 0 ]; then
		print_info "$1"
	else
		print_error "$2"
		exit 1
	fi
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Check if running as root                                         │
# └─────────────────────────────────────────────────────────────────┘
if [[ $EUID -ne 0 ]]; then
	print_error "This script must be run as root"
	exit 1
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ Welcome message                                                  │
# └─────────────────────────────────────────────────────────────────┘
clear
echo
echo -e "${BRIGHT_BLUE}${BOLD}"
cat <<"EOF"
  ███████╗███████╗████████╗ █████╗ ██████╗     ███████╗███████╗ ██████╗██╗   ██╗██████╗ ██╗████████╗██╗   ██╗
  ██╔════╝██╔════╝╚══██╔══╝██╔══██╗██╔══██╗    ██╔════╝██╔════╝██╔════╝██║   ██║██╔══██╗██║╚══██╔══╝╚██╗ ██╔╝
  █████╗  ███████╗   ██║   ███████║██████╔╝    ███████╗█████╗  ██║     ██║   ██║██████╔╝██║   ██║    ╚████╔╝ 
  ██╔══╝  ╚════██║   ██║   ██╔══██║██╔══██╗    ╚════██║██╔══╝  ██║     ██║   ██║██╔══██╗██║   ██║     ╚██╔╝  
  ██║     ███████║   ██║   ██║  ██║██████╔╝    ███████║███████╗╚██████╗╚██████╔╝██║  ██║██║   ██║      ██║   
  ╚═╝     ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═════╝     ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝   ╚═╝      ╚═╝   
EOF
echo -e "${NC}"
echo
echo -e "${MAGENTA}"
cat <<"EOF"
   ██████╗ ██████╗ ████████╗██╗ ██████╗ ███╗   ██╗███████╗    ███████╗ ██████╗ ██████╗     ██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗
  ██╔═══██╗██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║██╔════╝    ██╔════╝██╔═══██╗██╔══██╗    ██║     ██║████╗  ██║██║   ██║╚██╗██╔╝
  ██║   ██║██████╔╝   ██║   ██║██║   ██║██╔██╗ ██║███████╗    █████╗  ██║   ██║██████╔╝    ██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝ 
  ██║   ██║██╔═══╝    ██║   ██║██║   ██║██║╚██╗██║╚════██║    ██╔══╝  ██║   ██║██╔══██╗    ██║     ██║██║╚██╗██║██║   ██║ ██╔██╗ 
  ╚██████╔╝██║        ██║   ██║╚██████╔╝██║ ╚████║███████║    ██║     ╚██████╔╝██║  ██║    ███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗
   ╚═════╝ ╚═╝        ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝    ╚═╝      ╚═════╝ ╚═╝  ╚═╝    ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝
EOF
echo -e "${NC}"
echo

print_section "Adding Security Options to /etc/fstab"

# ┌─────────────────────────────────────────────────────────────────┐
# │ Create a backup of the original fstab file                       │
# └─────────────────────────────────────────────────────────────────┘
BACKUP_FILE="/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
print_info "Creating backup of /etc/fstab at $BACKUP_FILE"
cp /etc/fstab "$BACKUP_FILE"
check_success "Backup created successfully." "Failed to create backup of /etc/fstab"

# ┌─────────────────────────────────────────────────────────────────┐
# │ Function to check if an entry already exists                     │
# └─────────────────────────────────────────────────────────────────┘
entry_exists() {
	local pattern="$1"
	grep -q "$pattern" /etc/fstab
	return $?
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Check and add /proc with hidepid=2 if it doesn't exist          │
# └─────────────────────────────────────────────────────────────────┘
print_section "Configuring /proc security"

print_info "Checking for secure /proc configuration..."
if ! entry_exists "^proc.*hidepid=2"; then
	echo -e "\n# Security: Hide process information from other users" >>/etc/fstab
	echo "proc           /proc            proc            hidepid=2 0 0" >>/etc/fstab
	print_info "/proc secured with hidepid=2"
else
	print_warning "Secure /proc entry already exists in fstab"
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ Check and add /tmp with security options if it doesn't exist     │
# └─────────────────────────────────────────────────────────────────┘
print_section "Configuring /tmp security"

print_info "Checking for secure /tmp configuration..."
if ! entry_exists "^tmpfs.*\/tmp.*nosuid,nodev,noexec"; then
	echo -e "\n# Security: Secure /tmp directory" >>/etc/fstab
	echo "tmpfs          /tmp             tmpfs           nosuid,nodev,noexec 0 0" >>/etc/fstab
	print_info "/tmp secured with nosuid, nodev, noexec flags"
else
	print_warning "Secure /tmp entry already exists in fstab"
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ Summary and next steps                                           │
# └─────────────────────────────────────────────────────────────────┘
print_section "Security Options Added"

echo -e "${GREEN}${BOLD}┌───────────────────────────────────────────────────────────────┐${NC}"
print_info "Security options have been added to /etc/fstab"
print_info "Original /etc/fstab backed up to: $BACKUP_FILE"
echo -e "${GREEN}${BOLD}└───────────────────────────────────────────────────────────────┘${NC}"

print_section "Applying Changes"

echo -e "${CYAN}To apply changes without rebooting, run:${NC}"
echo -e "  ${BOLD}sudo mount -o remount /proc${NC}"
echo -e "  ${BOLD}sudo mount -o remount /tmp${NC}"
echo

if confirm "Would you like to apply these changes now?"; then
	print_info "Applying changes..."

	if mount -o remount /proc; then
		print_info "/proc remounted successfully with new options"
	else
		print_warning "Failed to remount /proc. The change will take effect after reboot."
	fi

	if mount -o remount /tmp; then
		print_info "/tmp remounted successfully with new options"
	else
		print_warning "Failed to remount /tmp. The change will take effect after reboot."
	fi
else
	print_info "Changes will take effect after reboot."
fi

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

exit 0
