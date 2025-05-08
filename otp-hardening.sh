#!/bin/bash

# Script to configure OTP (One-Time Password) authentication for SSH on Arch Linux
# Created for educational purposes in cybersecurity

# Function to check if the script is run with sudo privileges
check_sudo() {
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root or with sudo privileges."
    exit 1
  fi
}

# Function to backup a file before modifying it
backup_file() {
  local file=$1
  local backup_file="${file}.bak.$(date +%Y%m%d%H%M%S)"

  echo "Creating backup of $file to $backup_file"
  cp "$file" "$backup_file"

  if [[ $? -ne 0 ]]; then
    echo "Failed to create backup of $file. Exiting."
    exit 1
  fi
}

# Function to check and set timezone
check_and_set_timezone() {
  echo "Current date and time:"
  date

  read -p "Is the date and time correct? (y/n): " date_correct

  if [[ "$date_correct" != "y" && "$date_correct" != "Y" ]]; then
    read -p "Enter your continent (default: Europe): " continent
    read -p "Enter your capital (default: Paris): " capital

    continent=${continent:-Europe}
    capital=${capital:-Paris}

    echo "Setting timezone to $continent/$capital"
    timedatectl set-timezone "$continent/$capital"

    if [[ $? -ne 0 ]]; then
      echo "Failed to set timezone. Please check if the continent and capital are valid."
      exit 1
    fi

    echo "Updated date and time:"
    date
  fi
}

# Function to get the user for OTP configuration
get_user_for_otp() {
  # If the script is run with sudo, default to the sudo user
  if [[ -n "$SUDO_USER" ]]; then
    default_user="$SUDO_USER"
  else
    default_user="$(whoami)"
  fi

  read -p "Enter the username for OTP configuration (default: $default_user): " username
  username=${username:-$default_user}

  # Check if user exists
  if ! id "$username" &>/dev/null; then
    echo "User $username does not exist. Exiting."
    exit 1
  fi

  echo "OTP will be configured for user: $username"
  return 0
}

# Function to install google-authenticator if not installed
install_google_authenticator() {
  if ! pacman -Q libpam-google-authenticator &>/dev/null && ! pacman -Q google-authenticator &>/dev/null && ! pacman -Q google-authenticator-libpam &>/dev/null; then
    echo "Google Authenticator is not installed. Installing..."
    pacman -S --noconfirm libpam-google-authenticator || pacman -S --noconfirm google-authenticator || pacman -S --noconfirm google-authenticator-libpam

    if [[ $? -ne 0 ]]; then
      echo "Failed to install Google Authenticator. Exiting."
      exit 1
    fi
  else
    echo "Google Authenticator is already installed."
  fi

  # Install qrencode if not already installed (for QR code generation)
  if ! pacman -Q qrencode &>/dev/null; then
    echo "Installing qrencode for QR code generation..."
    pacman -S --noconfirm qrencode

    if [[ $? -ne 0 ]]; then
      echo "Failed to install qrencode. QR code saving might not work."
    fi
  fi
}

# Function to create OTP directory for the user
create_otp_directory() {
  local user_home
  user_home=$(eval echo ~"$username")
  otp_dir="$user_home/.otp"

  echo "Creating OTP directory at $otp_dir"

  # Create the directory if it doesn't exist
  if [[ ! -d "$otp_dir" ]]; then
    mkdir -p "$otp_dir"
    if [[ $? -ne 0 ]]; then
      echo "Failed to create OTP directory. Exiting."
      exit 1
    fi
  fi

  # Set proper ownership and permissions
  chown "$username":"$username" "$otp_dir"
  chmod 700 "$otp_dir"

  echo "OTP directory created and secured."
}

# Function to configure Google Authenticator
configure_google_authenticator() {
  echo "Configuring Google Authenticator for user $username..."
  echo "Please follow the instructions to set up your OTP."
  echo "It is recommended to answer 'y' to all questions for secure setup."
  echo "------------------------------------------------------"

  # Create temporary file to capture the output
  temp_file=$(mktemp)

  # Run Google Authenticator setup for the specified user and capture output
  su - "$username" -c "script -q -c 'google-authenticator' $temp_file"

  if [[ $? -ne 0 ]]; then
    echo "Failed to configure Google Authenticator. Exiting."
    rm -f "$temp_file"
    exit 1
  fi

  echo "Google Authenticator configuration completed."

  # Extract the otpauth URL from the temporary file
  otpauth_url=$(grep -o 'otpauth://[^[:space:]]*' "$temp_file")

  if [[ -n "$otpauth_url" ]]; then
    # Generate QR code and save it to user's .otp directory
    qr_code_file="$otp_dir/qr_code.png"
    echo "Generating QR code and saving to $qr_code_file"

    qrencode -s 8 -o "$qr_code_file" "$otpauth_url"

    if [[ $? -eq 0 ]]; then
      # Set proper ownership and permissions
      chown "$username":"$username" "$qr_code_file"
      chmod 600 "$qr_code_file"

      echo "QR code saved successfully to $qr_code_file"

      # Also save the URL in a text file
      echo "$otpauth_url" >"$otp_dir/otpauth_url.txt"
      chown "$username":"$username" "$otp_dir/otpauth_url.txt"
      chmod 600 "$otp_dir/otpauth_url.txt"
    else
      echo "Failed to generate QR code. Please use the secret key manually."
    fi
  else
    echo "Could not extract OTP URL. QR code generation skipped."
  fi

  # Clean up
  rm -f "$temp_file"
}

# Function to modify PAM configuration for SSH
configure_pam_sshd() {
  local pam_file="/etc/pam.d/sshd"

  echo "Configuring PAM for SSH..."
  backup_file "$pam_file"

  # Check if the line is already there
  if ! grep -q "auth required pam_google_authenticator.so" "$pam_file"; then
    # Find the line with #%PAM-1.0 and add our line after it
    sed -i '/#%PAM-1.0/a auth required pam_google_authenticator.so' "$pam_file"

    if [[ $? -ne 0 ]]; then
      echo "Failed to modify $pam_file. Exiting."
      exit 1
    fi

    echo "Added Google Authenticator to PAM configuration."
  else
    echo "Google Authenticator is already configured in PAM."
  fi
}

# Function to modify SSH daemon configuration
configure_sshd() {
  local sshd_config="/etc/ssh/sshd_config"
  local archlinux_conf="/etc/ssh/sshd_config.d/99-archlinux.conf"

  echo "Configuring SSH daemon..."
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
    else
      # Setting doesn't exist, add it
      echo "${key} ${value}" >>"$sshd_config"
    fi
  done

  echo "SSH daemon configuration updated."

  # Comment out all lines in 99-archlinux.conf if it exists
  if [[ -f "$archlinux_conf" ]]; then
    backup_file "$archlinux_conf"

    echo "Commenting out all lines in $archlinux_conf"
    sed -i 's/^/#/' "$archlinux_conf"

    if [[ $? -ne 0 ]]; then
      echo "Failed to modify $archlinux_conf. Exiting."
      exit 1
    fi
  else
    echo "$archlinux_conf does not exist. Skipping."
  fi
}

# Function to apply SSH configuration changes
apply_ssh_config() {
  echo "Testing SSH configuration..."
  sshd -t

  if [[ $? -ne 0 ]]; then
    echo "SSH configuration test failed. Please check your configuration."
    exit 1
  fi

  echo "Restarting SSH daemon..."
  systemctl restart sshd

  if [[ $? -ne 0 ]]; then
    echo "Failed to restart SSH daemon. Exiting."
    exit 1
  fi

  echo "SSH daemon restarted successfully."
}

# Main function
main() {
  echo "======================================"
  echo "OTP Configuration Script for Arch Linux"
  echo "======================================"

  check_sudo
  check_and_set_timezone
  get_user_for_otp
  install_google_authenticator
  create_otp_directory
  configure_google_authenticator
  configure_pam_sshd
  configure_sshd
  apply_ssh_config

  echo "======================================"
  echo "OTP configuration completed successfully!"
  echo "Make sure to keep your recovery codes in a safe place."
  echo "You can now log in using your SSH key and OTP token."
  echo "A QR code for your OTP has been saved to: $qr_code_file"
  echo "======================================"
}

# Execute main function
main
