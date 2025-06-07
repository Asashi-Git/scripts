#!/bin/bash

# ╔═══════════════════════════════════════════════════════════════════╗
# ║  OTP Authentication Hardening Script for Arch Linux               ║
# ║  This script configures One-Time Password (OTP) for SSH access    ║
# ║  Method 1: Interactive User Selection                             ║
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
  print_section "Timezone Configuration"

  local current_tz=$(timedatectl show --property=Timezone --value)
  print_info "Current timezone: ${BOLD}$current_tz${NC}"

  if confirm "Do you want to change the timezone?"; then
    print_info "Listing available timezones..."

    echo -e -n "${CYAN}Enter your continent (default: Europe): ${NC}"
    read continent
    continent=${continent:-Europe}

    echo -e -n "${CYAN}Enter your capital (default: Paris): ${NC}"
    read capital
    capital=${capital:-Paris}

    local new_timezone="${continent}/${capital}"

    if timedatectl list-timezones | grep -q "^${new_timezone}$"; then
      print_info "Setting timezone to $new_timezone"
      timedatectl set-timezone "$new_timezone"
      print_success "Timezone updated successfully"
    else
      print_error "Invalid timezone: $new_timezone"
      print_info "Keeping current timezone: $current_tz"
    fi
  else
    print_info "Keeping current timezone: $current_tz"
  fi

  # Ensure system time is synchronized
  print_info "Synchronizing system time..."
  timedatectl set-ntp true
  systemctl enable systemd-timesyncd
  systemctl start systemd-timesyncd
  print_success "Time synchronization enabled and started"
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Function to install Google Authenticator                         │
# └─────────────────────────────────────────────────────────────────┘
install_google_authenticator() {
  print_section "Google Authenticator Installation"

  if command -v google-authenticator &>/dev/null; then
    print_info "Google Authenticator is already installed."
    return 0
  fi

  print_info "Installing Google Authenticator..."

  if command -v pacman &>/dev/null; then
    # Arch Linux
    pacman -Sy --noconfirm libpam-google-authenticator
  elif command -v apt &>/dev/null; then
    # Debian/Ubuntu
    apt update && apt install -y libpam-google-authenticator
  elif command -v yum &>/dev/null; then
    # RHEL/CentOS
    yum install -y google-authenticator
  else
    print_error "Unsupported package manager. Please install Google Authenticator manually."
    exit 1
  fi

  if command -v google-authenticator &>/dev/null; then
    print_success "Google Authenticator installed successfully."
  else
    print_error "Failed to install Google Authenticator."
    exit 1
  fi
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ User Management Functions                                        │
# └─────────────────────────────────────────────────────────────────┘

# Function to get all regular users (non-system users)
get_regular_users() {
  # Get users with UID >= 1000 and < 65534 (regular users)
  getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' | sort
}

# Function to display user selection menu
display_user_menu() {
  local users=($(get_regular_users))

  if [[ ${#users[@]} -eq 0 ]]; then
    print_error "No regular users found on the system"
    return 1
  fi

  print_section "Available Users for 2FA Configuration"

  echo -e "${CYAN}${BOLD}Select users to configure 2FA:${NC}"
  echo

  for i in "${!users[@]}"; do
    local user="${users[i]}"
    local home_dir=$(getent passwd "$user" | cut -d: -f6)
    local has_2fa=""

    # Check if user already has 2FA configured
    if [[ -f "$home_dir/.google_authenticator" ]]; then
      has_2fa="${GREEN}[2FA CONFIGURED]${NC}"
    else
      has_2fa="${RED}[NO 2FA]${NC}"
    fi

    echo -e "  ${YELLOW}$((i + 1)))${NC} ${BOLD}$user${NC} $has_2fa"
  done

  echo -e "  ${YELLOW}0)${NC} ${BOLD}Configure for ALL users${NC}"
  echo -e "  ${YELLOW}q)${NC} ${BOLD}Skip 2FA configuration${NC}"
  echo
}

# Function to setup OTP for a specific user
setup_user_otp() {
  local target_user="$1"

  print_info "Configuring 2FA for user: ${BOLD}$target_user${NC}"

  # Verify user exists
  if ! id "$target_user" &>/dev/null; then
    print_error "User $target_user does not exist"
    return 1
  fi

  # Get user's home directory
  local user_home=$(getent passwd "$target_user" | cut -d: -f6)

  if [[ ! -d "$user_home" ]]; then
    print_error "Home directory for user $target_user not found"
    return 1
  fi

  # Check if 2FA is already configured
  if [[ -f "$user_home/.google_authenticator" ]]; then
    print_warning "2FA already configured for user: $target_user"
    if confirm "Do you want to reconfigure 2FA for $target_user?"; then
      sudo -u "$target_user" rm -f "$user_home/.google_authenticator"
    else
      print_info "Skipping user: $target_user"
      return 0
    fi
  fi

  echo
  print_info "Launching Google Authenticator setup for user: ${BOLD}$target_user${NC}"
  print_warning "The user will need to scan the QR code with their authenticator app"
  echo -e "${MAGENTA}${BOLD}┌─────────────────────────────────────────────────────────────┐${NC}"
  echo -e "${MAGENTA}${BOLD}│ IMPORTANT: Save the emergency scratch codes in a safe place │${NC}"
  echo -e "${MAGENTA}${BOLD}└─────────────────────────────────────────────────────────────┘${NC}"
  echo

  # Run google-authenticator as the target user
  if sudo -u "$target_user" bash -c "
        cd '$user_home'
        echo -e '${GREEN}${BOLD}Setting up 2FA for: $target_user${NC}'
        echo -e '${YELLOW}Please scan the QR code with Google Authenticator or similar app${NC}'
        echo
        google-authenticator -t -d -f -r 3 -R 30 -W
    "; then
    print_success "2FA configured successfully for user: $target_user"
    echo
    return 0
  else
    print_error "Failed to configure 2FA for user: $target_user"
    return 1
  fi
}

# Function to handle user selection and configuration
configure_user_otp_interactive() {
  print_section "Two-Factor Authentication Setup"

  # Check if google-authenticator is installed
  if ! command -v google-authenticator &>/dev/null; then
    print_error "Google Authenticator is not installed"
    return 1
  fi

  local users=($(get_regular_users))
  local configured_users=()

  while true; do
    display_user_menu

    echo -e -n "${CYAN}Enter your selection: ${NC}"
    read selection

    case $selection in
    0) # Configure for all users
      print_info "Configuring 2FA for all users..."
      local success_count=0
      local total_count=${#users[@]}

      for user in "${users[@]}"; do
        echo
        echo -e "${BLUE}${BOLD}┌─ Configuring user $((success_count + 1))/$total_count: $user ─┐${NC}"
        if setup_user_otp "$user"; then
          ((success_count++))
          configured_users+=("$user")
        fi
        echo -e "${BLUE}${BOLD}└─────────────────────────────────────────────────────────────┘${NC}"

        # Pause between users for readability
        if [[ $success_count -lt $total_count ]]; then
          echo -e "${YELLOW}Press Enter to continue to next user...${NC}"
          read
        fi
      done

      print_success "2FA configuration completed for $success_count/$total_count users"
      break
      ;;
    [1-9]*) # Specific user selection
      if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#users[@]} ]]; then
        local selected_user="${users[$((selection - 1))]}"
        if setup_user_otp "$selected_user"; then
          configured_users+=("$selected_user")
        fi

        if confirm "Configure 2FA for another user?"; then
          continue
        else
          break
        fi
      else
        print_error "Invalid selection. Please choose a number between 1 and ${#users[@]}"
      fi
      ;;
    q | Q) # Skip
      print_warning "Skipping 2FA configuration"
      break
      ;;
    *) # Invalid input
      print_error "Invalid selection. Please try again."
      ;;
    esac
  done

  # Summary of configured users
  if [[ ${#configured_users[@]} -gt 0 ]]; then
    echo
    print_section "2FA Configuration Summary"
    print_success "2FA configured for the following users:"
    for user in "${configured_users[@]}"; do
      echo -e "  ${GREEN}✓${NC} $user"
    done
  fi
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Function to configure PAM for SSH                                │
# └─────────────────────────────────────────────────────────────────┘
configure_pam_sshd() {
  print_section "PAM SSH Configuration"

  local pam_sshd_file="/etc/pam.d/sshd"

  if [[ ! -f "$pam_sshd_file" ]]; then
    print_error "PAM SSH configuration file not found: $pam_sshd_file"
    return 1
  fi

  backup_file "$pam_sshd_file"

  # Check if Google Authenticator PAM module is already configured
  if grep -q "pam_google_authenticator.so" "$pam_sshd_file"; then
    print_info "Google Authenticator PAM module already configured."
  else
    print_info "Adding Google Authenticator PAM module to SSH configuration..."

    # Add the PAM module after the @include common-auth line
    sed -i '/^@include common-auth/a auth required pam_google_authenticator.so' "$pam_sshd_file"

    print_success "Google Authenticator PAM module added to SSH configuration."
  fi

  # Ensure the PAM module line is present
  if grep -q "auth required pam_google_authenticator.so" "$pam_sshd_file"; then
    print_success "PAM SSH configuration complete."
  else
    print_error "Failed to configure PAM SSH. Manual intervention may be required."
    return 1
  fi
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Function to configure SSH daemon                                 │
# └─────────────────────────────────────────────────────────────────┘
configure_sshd() {
  print_section "SSH Daemon Configuration"

  local sshd_config="/etc/ssh/sshd_config"

  if [[ ! -f "$sshd_config" ]]; then
    print_error "SSH configuration file not found: $sshd_config"
    return 1
  fi

  backup_file "$sshd_config"

  print_info "Configuring SSH daemon for 2FA..."

  # Configure ChallengeResponseAuthentication
  if grep -q "^ChallengeResponseAuthentication" "$sshd_config"; then
    sed -i 's/^ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' "$sshd_config"
  else
    echo "ChallengeResponseAuthentication yes" >>"$sshd_config"
  fi

  # Configure AuthenticationMethods (require both publickey and keyboard-interactive)
  if grep -q "^AuthenticationMethods" "$sshd_config"; then
    sed -i 's/^AuthenticationMethods.*/AuthenticationMethods publickey,keyboard-interactive/' "$sshd_config"
  else
    echo "AuthenticationMethods publickey,keyboard-interactive" >>"$sshd_config"
  fi

  # Additional security hardening
  print_info "Applying additional SSH security hardening..."

  # Disable password authentication
  if grep -q "^PasswordAuthentication" "$sshd_config"; then
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
  else
    echo "PasswordAuthentication no" >>"$sshd_config"
  fi

  # Disable root login
  if grep -q "^PermitRootLogin" "$sshd_config"; then
    sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' "$sshd_config"
  else
    echo "PermitRootLogin no" >>"$sshd_config"
  fi

  # Enable public key authentication
  if grep -q "^PubkeyAuthentication" "$sshd_config"; then
    sed -i 's/^PubkeyAuthentication.*/PubkeyAuthentication yes/' "$sshd_config"
  else
    echo "PubkeyAuthentication yes" >>"$sshd_config"
  fi

  # Configure UsePAM
  if grep -q "^UsePAM" "$sshd_config"; then
    sed -i 's/^UsePAM.*/UsePAM yes/' "$sshd_config"
  else
    echo "UsePAM yes" >>"$sshd_config"
  fi

  print_success "SSH daemon configuration complete."
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Function to apply SSH configuration                              │
# └─────────────────────────────────────────────────────────────────┘
apply_ssh_config() {
  print_section "Applying SSH Configuration"

  print_info "Testing SSH configuration..."

  # Test the SSH configuration
  if sshd -t; then
    print_success "SSH configuration test passed."
  else
    print_error "SSH configuration test failed. Please check your configuration."
    return 1
  fi

  print_info "Restarting SSH service..."

  # Restart SSH service
  if systemctl restart sshd; then
    print_success "SSH service restarted successfully."
  else
    print_error "Failed to restart SSH service."
    return 1
  fi

  # Enable SSH service if not already enabled
  if systemctl is-enabled sshd &>/dev/null; then
    print_info "SSH service is already enabled."
  else
    print_info "Enabling SSH service..."
    systemctl enable sshd
    print_success "SSH service enabled."
  fi
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Main function                                                    │
# └─────────────────────────────────────────────────────────────────┘
main() {
  # Display banner
  echo -e "${BRIGHT_BLUE}${BOLD}"
  cat <<"EOF"
   ██████╗ ████████╗██████╗     ██╗  ██╗ █████╗ ██████╗ ██████╗ ███████╗███╗   ██╗██╗███╗   ██╗ ██████╗ 
  ██╔═══██╗╚══██╔══╝██╔══██╗    ██║  ██║██╔══██╗██╔══██╗██╔══██╗██╔════╝████╗  ██║██║████╗  ██║██╔════╝ 
  ██║   ██║   ██║   ██████╔╝    ███████║███████║██████╔╝██║  ██║█████╗  ██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
  ██║   ██║   ██║   ██╔═══╝     ██╔══██║██╔══██║██╔══██╗██║  ██║██╔══╝  ██║╚██╗██║██║██║╚██╗██║██║   ██║
  ╚██████╔╝   ██║   ██║         ██║  ██║██║  ██║██║  ██║██████╔╝███████╗██║ ╚████║██║██║ ╚████║╚██████╔╝
   ╚═════╝    ╚═╝   ╚═╝         ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝ 
                                                                                                          
                     █████╗ ██████╗  ██████╗██╗  ██╗    ██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗         
                    ██╔══██╗██╔══██╗██╔════╝██║  ██║    ██║     ██║████╗  ██║██║   ██║╚██╗██╔╝         
                    ███████║██████╔╝██║     ███████║    ██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝          
                    ██╔══██║██╔══██╗██║     ██╔══██║    ██║     ██║██║╚██╗██║██║   ██║ ██╔██╗          
                    ██║  ██║██║  ██║╚██████╗██║  ██║    ███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗         
                    ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝    ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝         
EOF
  echo -e "${NC}"

  check_sudo
  check_and_set_timezone
  install_google_authenticator
  configure_user_otp_interactive
  configure_pam_sshd
  configure_sshd
  apply_ssh_config

  print_section "Configuration Summary"

  echo -e "${GREEN}${BOLD}┌─────────────────────────────────────────────────────────────────┐${NC}"
  echo -e "${GREEN}${BOLD}│ OTP Configuration Completed Successfully                        │${NC}"
  echo -e "${GREEN}${BOLD}└─────────────────────────────────────────────────────────────────┘${NC}"

  echo -e "  ${GREEN}✓${NC} Google Authenticator installed and configured for selected users"
  echo -e "  ${GREEN}✓${NC} PAM configured for SSH authentication"
  echo -e "  ${GREEN}✓${NC} SSH hardened with secure configuration"
  echo -e "  ${GREEN}✓${NC} Time-based One-Time Password (TOTP) enabled"
  echo
  echo -e "${YELLOW}${BOLD}┌─────────────────────────────────────────────────────────────────┐${NC}"
  echo -e "${YELLOW}${BOLD}│ Important Security Notes                                        │${NC}"
  echo -e "${YELLOW}${BOLD}└─────────────────────────────────────────────────────────────────┘${NC}"
  echo -e "  ${YELLOW}!${NC} Keep your recovery codes in a secure location"
  echo -e "  ${YELLOW}!${NC} Users can now log in using SSH key + OTP token"
  echo -e "  ${YELLOW}!${NC} Root login is disabled - use configured user accounts"
  echo -e "  ${YELLOW}!${NC} Test authentication before closing this session"
  echo -e "  ${YELLOW}!${NC} Each user must have their SSH public key installed"

  echo
  echo -e "${MAGENTA}${BOLD}Testing Command:${NC}"
  echo -e "  ${CYAN}ssh -i ~/.ssh/your_key username@your_server${NC}"
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
