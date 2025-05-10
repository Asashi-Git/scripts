#!/bin/bash

# ╔═══════════════════════════════════════════════════════════════════╗
# ║  Arch Security Suite - Complete Hardening Toolkit                  ║
# ║  Downloads and executes multiple security hardening scripts        ║
# ╚═══════════════════════════════════════════════════════════════════╝

# ┌─────────────────────────────────────────────────────────────────┐
# │ Colors for output formatting                                     │
# └─────────────────────────────────────────────────────────────────┘
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BRIGHT_BLUE='\033[1;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
PURPLE='\033[0;35m'
ORANGE='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ┌─────────────────────────────────────────────────────────────────┐
# │ Utility functions                                                │
# └─────────────────────────────────────────────────────────────────┘
print_section() {
  echo -e "\n${BLUE}${BOLD}╔════════════ $1 ════════════╗${NC}\n"
}

print_info() {
  echo -e "${CYAN}${BOLD}[INFO]${NC} $1"
}

print_step() {
  echo -e "${MAGENTA}${BOLD}[STEP $1/$2]${NC} $3"
}

print_success() {
  echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"
}

print_error() {
  echo -e "${RED}${BOLD}[ERROR]${NC} $1"
  exit 1
}

print_warning() {
  echo -e "${YELLOW}${BOLD}[WARNING]${NC} $1"
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Check if script is run as root                                   │
# └─────────────────────────────────────────────────────────────────┘
check_sudo() {
  if ! command -v sudo &>/dev/null; then
    print_error "sudo is not installed. Please install sudo first."
  fi

  # Check if user has sudo privileges
  if ! sudo -v &>/dev/null; then
    print_error "You need sudo privileges to run this script."
  fi
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Function to download and execute a script                        │
# └─────────────────────────────────────────────────────────────────┘
download_and_execute() {
  local script_name="$1"
  local step_num="$2"
  local total_steps="$3"
  local script_url="https://raw.githubusercontent.com/Asashi-Git/scripts/main/hardened-ArchLinux/${script_name}"

  print_step "$step_num" "$total_steps" "Processing ${script_name}..."

  # Download script
  print_info "Downloading ${script_name}..."
  if ! curl -o "${script_name}" "${script_url}" 2>/dev/null; then
    print_error "Failed to download ${script_name}. Check your internet connection or the URL."
  fi
  print_success "Downloaded ${script_name} successfully"

  # Make script executable
  print_info "Making ${script_name} executable..."
  if ! chmod +x "${script_name}"; then
    rm -f "${script_name}"
    print_error "Failed to make ${script_name} executable."
  fi
  print_success "${script_name} is now executable"

  # Execute script
  print_info "Executing ${script_name} with sudo..."
  if ! sudo bash "./${script_name}"; then
    print_warning "Execution of ${script_name} may have encountered issues."
  else
    print_success "${script_name} executed successfully"
  fi

  # Clean up
  print_info "Removing ${script_name}..."
  if ! rm -f "${script_name}"; then
    print_warning "Failed to remove ${script_name}. You may want to delete it manually."
  else
    print_success "${script_name} removed successfully"
  fi

  echo -e "\n${BLUE}${BOLD}╠════════════ Script ${step_num}/${total_steps} Complete ═════════════╣${NC}\n"
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Function to set up server based on user choice                   │
# └─────────────────────────────────────────────────────────────────┘
setup_server() {
  print_section "Server Setup Options"

  echo -e "${GREEN}▶${NC} Would you like to set up a specific type of server on your system?"
  echo -e "  ${YELLOW}1.${NC} Web Server (NGINX with hardened configuration)"
  echo -e "  ${YELLOW}2.${NC} Proxy/Reverse Proxy Server"
  echo -e "  ${YELLOW}3.${NC} None - Skip this step"
  echo

  local choice
  read -p "Enter your choice (1-3): " choice
  echo

  case $choice in
  1)
    print_info "Setting up a hardened web server..."
    download_and_execute "web-server-hardened.sh" "1" "1"
    print_success "Web server setup completed!"
    ;;
  2)
    print_info "Setting up a proxy/reverse proxy server..."
    download_and_execute "proxy-reverse-proxy.sh" "1" "1"
    print_success "Proxy/Reverse Proxy setup completed!"
    ;;
  3)
    print_info "Skipping server setup as requested."
    ;;
  *)
    print_warning "Invalid choice. Skipping server setup."
    ;;
  esac
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Main function                                                    │
# └─────────────────────────────────────────────────────────────────┘
main() {
  # Display header
  clear
  echo
  echo -e "${BRIGHT_BLUE}${BOLD}"
  cat <<"EOF"
   █████╗ ██████╗  ██████╗██╗  ██╗    ███████╗███████╗ ██████╗██╗   ██╗██████╗ ██╗████████╗██╗   ██╗    ███████╗██╗   ██╗██╗████████╗███████╗
  ██╔══██╗██╔══██╗██╔════╝██║  ██║    ██╔════╝██╔════╝██╔════╝██║   ██║██╔══██╗██║╚══██╔══╝╚██╗ ██╔╝    ██╔════╝██║   ██║██║╚══██╔══╝██╔════╝
  ███████║██████╔╝██║     ███████║    ███████╗█████╗  ██║     ██║   ██║██████╔╝██║   ██║    ╚████╔╝     ███████╗██║   ██║██║   ██║   █████╗  
  ██╔══██║██╔══██╗██║     ██╔══██║    ╚════██║██╔══╝  ██║     ██║   ██║██╔══██╗██║   ██║     ╚██╔╝      ╚════██║██║   ██║██║   ██║   ██╔══╝  
  ██║  ██║██║  ██║╚██████╗██║  ██║    ███████║███████╗╚██████╗╚██████╔╝██║  ██║██║   ██║      ██║       ███████║╚██████╔╝██║   ██║   ███████╗
  ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝    ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝   ╚═╝      ╚═╝       ╚══════╝ ╚═════╝ ╚═╝   ╚═╝   ╚══════╝
EOF
  echo -e "${NC}"

  echo -e "${MAGENTA}${BOLD}"
  cat <<"EOF"
    ██████╗ ██╗   ██╗    ██████╗ ███████╗ ██████╗ █████╗ ██████╗ ███╗   ██╗███████╗██╗     ██╗     ███████╗    
    ██╔══██╗╚██╗ ██╔╝    ██╔══██╗██╔════╝██╔════╝██╔══██╗██╔══██╗████╗  ██║██╔════╝██║     ██║     ██╔════╝    
    ██████╔╝ ╚████╔╝     ██║  ██║█████╗  ██║     ███████║██████╔╝██╔██╗ ██║█████╗  ██║     ██║     █████╗      
    ██╔══██╗  ╚██╔╝      ██║  ██║██╔══╝  ██║     ██╔══██║██╔══██╗██║╚██╗██║██╔══╝  ██║     ██║     ██╔══╝      
    ██████╔╝   ██║       ██████╔╝███████╗╚██████╗██║  ██║██║  ██║██║ ╚████║███████╗███████╗███████╗███████╗    
    ╚═════╝    ╚═╝       ╚═════╝ ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝╚══════╝╚══════╝    
                                                                                                                 
    ███████╗ █████╗ ███╗   ███╗██╗   ██╗███████╗██╗                                                              
    ██╔════╝██╔══██╗████╗ ████║██║   ██║██╔════╝██║                                                              
    ███████╗███████║██╔████╔██║██║   ██║█████╗  ██║                                                              
    ╚════██║██╔══██║██║╚██╔╝██║██║   ██║██╔══╝  ██║                                                              
    ███████║██║  ██║██║ ╚═╝ ██║╚██████╔╝███████╗███████╗                                                         
    ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚══════╝                                                         
EOF
  echo -e "${NC}"

  echo -e "${CYAN}${BOLD}┌─────────────────────────────────────────────────────────────────────────────────┐${NC}"
  echo -e "${CYAN}${BOLD}│ Complete System Hardening Suite - Security Scripts Downloader and Executor       │${NC}"
  echo -e "${CYAN}${BOLD}└─────────────────────────────────────────────────────────────────────────────────┘${NC}"
  echo -e "  ${GREEN}▶${NC} This script will download and execute the following hardening scripts in order:"
  echo -e "    ${YELLOW}1.${NC} root-account-hardening.sh       - Secures the root account"
  echo -e "    ${YELLOW}2.${NC} fstab-security-options.sh       - Hardens filesystem mount options"
  echo -e "    ${YELLOW}3.${NC} hardening-ssh.sh                - Secures SSH server configuration"
  echo -e "    ${YELLOW}4.${NC} otp-hardening.sh                - Implements One-Time Password authentication"
  echo -e "    ${YELLOW}5.${NC} kernel-and-network-hardening.sh - Hardens kernel and network settings"
  echo -e "    ${YELLOW}6.${NC} ufw-firewall-hardening.sh       - Configures firewall rules"
  echo -e "    ${YELLOW}7.${NC} fail2ban-hardening.sh           - Sets up intrusion prevention"
  echo
  echo -e "  ${CYAN}▶${NC} After hardening, you'll have the option to set up:"
  echo -e "    ${YELLOW}•${NC} A hardened web server"
  echo -e "    ${YELLOW}•${NC} A proxy/reverse proxy server"
  echo
  echo -e "  ${RED}⚠ WARNING:${NC} This will make significant security changes to your system."
  echo -e "  ${CYAN}ℹ NOTE:${NC} Each script will be executed with sudo privileges and then removed afterward."
  echo

  # Ask for confirmation before proceeding
  read -p "Do you want to proceed with the system hardening? (y/n): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo -e "\nOperation cancelled by user."
    exit 0
  fi

  # Check for sudo privileges
  check_sudo

  print_section "Starting Security Hardening Suite"

  # Define the scripts to be processed
  local total_scripts=7
  local scripts=(
    "root-account-hardening.sh"
    "fstab-security-options.sh"
    "hardening-ssh.sh"
    "otp-hardening.sh"
    "kernel-and-network-hardening.sh"
    "ufw-firewall-hardening.sh"
    "fail2ban-hardening.sh"
  )

  # Process each script in order
  for ((i = 0; i < ${#scripts[@]}; i++)); do
    download_and_execute "${scripts[$i]}" "$((i + 1))" "$total_scripts"
  done

  print_section "Security Hardening Complete"
  print_success "All security hardening scripts have been successfully executed!"

  # Offer server setup options
  setup_server

  print_section "Final Instructions"

  echo -e "${YELLOW}${BOLD}╔═══════════════════ Recommendations ══════════════════════╗${NC}"
  echo -e "${YELLOW}${BOLD}║${NC} 1. Reboot your system to apply all changes                ${YELLOW}${BOLD}║${NC}"
  echo -e "${YELLOW}${BOLD}║${NC} 2. Test SSH access with new security settings            ${YELLOW}${BOLD}║${NC}"
  echo -e "${YELLOW}${BOLD}║${NC} 3. Verify firewall rules are functioning as expected     ${YELLOW}${BOLD}║${NC}"
  echo -e "${YELLOW}${BOLD}║${NC} 4. Review system logs for any potential issues           ${YELLOW}${BOLD}║${NC}"
  if [[ "$choice" == "1" ]]; then
    echo -e "${YELLOW}${BOLD}║${NC} 5. Verify your web server is running correctly           ${YELLOW}${BOLD}║${NC}"
  elif [[ "$choice" == "2" ]]; then
    echo -e "${YELLOW}${BOLD}║${NC} 5. Verify your proxy server is running correctly         ${YELLOW}${BOLD}║${NC}"
  fi
  echo -e "${YELLOW}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"

  echo
  echo -e "${BRIGHT_BLUE}${BOLD}"
  cat <<"EOF"
  ███████╗███████╗ ██████╗██╗   ██╗██████╗ ██╗████████╗██╗   ██╗    ██╗  ██╗ █████╗ ██████╗ ██████╗ ███████╗███╗   ██╗███████╗██████╗ ██╗
  ██╔════╝██╔════╝██╔════╝██║   ██║██╔══██╗██║╚══██╔══╝╚██╗ ██╔╝    ██║  ██║██╔══██╗██╔══██╗██╔══██╗██╔════╝████╗  ██║██╔════╝██╔══██╗██║
monitor=HDMI-A-1,1920x1080@240,0x0,1
  ███████╗█████╗  ██║     ██║   ██║██████╔╝██║   ██║    ╚████╔╝     ███████║███████║██████╔╝██║  ██║█████╗  ██╔██╗ ██║█████╗  ██║  ██║██║
  ╚════██║██╔══╝  ██║     ██║   ██║██╔══██╗██║   ██║     ╚██╔╝      ██╔══██║██╔══██║██╔══██╗██║  ██║██╔══╝  ██║╚██╗██║██╔══╝  ██║  ██║╚═╝
  ███████║███████╗╚██████╗╚██████╔╝██║  ██║██║   ██║      ██║       ██║  ██║██║  ██║██║  ██║██████╔╝███████╗██║ ╚████║███████╗██████╔╝██╗
  ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝   ╚═╝      ╚═╝       ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚═════╝ ╚═╝
EOF
  echo -e "${NC}"

  echo -e "${GREEN}${BOLD}"
  cat <<"EOF"
    ██████╗ ██╗   ██╗    ██████╗ ███████╗ ██████╗ █████╗ ██████╗ ███╗   ██╗███████╗██╗     ██╗     ███████╗    
    ██╔══██╗╚██╗ ██╔╝    ██╔══██╗██╔════╝██╔════╝██╔══██╗██╔══██╗████╗  ██║██╔════╝██║     ██║     ██╔════╝    
    ██████╔╝ ╚████╔╝     ██║  ██║█████╗  ██║     ███████║██████╔╝██╔██╗ ██║█████╗  ██║     ██║     █████╗      
    ██╔══██╗  ╚██╔╝      ██║  ██║██╔══╝  ██║     ██╔══██║██╔══██╗██║╚██╗██║██╔══╝  ██║     ██║     ██╔══╝      
    ██████╔╝   ██║       ██████╔╝███████╗╚██████╗██║  ██║██║  ██║██║ ╚████║███████╗███████╗███████╗███████╗    
    ╚═════╝    ╚═╝       ╚═════╝ ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝╚══════╝╚══════╝    
                                                                                                                 
    ███████╗ █████╗ ███╗   ███╗██╗   ██╗███████╗██╗                                                              
    ██╔════╝██╔══██╗████╗ ████║██║   ██║██╔════╝██║                                                              
    ███████╗███████║██╔████╔██║██║   ██║█████╗  ██║                                                              
    ╚════██║██╔══██║██║╚██╔╝██║██║   ██║██╔══╝  ██║                                                              
    ███████║██║  ██║██║ ╚═╝ ██║╚██████╔╝███████╗███████╗                                                         
    ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚══════╝                                                         
EOF
  echo -e "${NC}"
}

# Execute main function
main
