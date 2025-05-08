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

# Function to install google-authenticator if not installed
install_google_authenticator() {
	if ! pacman -Q libpam-google-authenticator &>/dev/null && ! pacman -Q google-authenticator &>/dev/null; then
		echo "Google Authenticator is not installed. Installing..."
		pacman -S --noconfirm libpam-google-authenticator || pacman -S --noconfirm google-authenticator

		if [[ $? -ne 0 ]]; then
			echo "Failed to install Google Authenticator. Exiting."
			exit 1
		fi
	else
		echo "Google Authenticator is already installed."
	fi
}

# Function to configure Google Authenticator
configure_google_authenticator() {
	echo "Configuring Google Authenticator..."
	echo "Please follow the instructions to set up your OTP."
	echo "It is recommended to answer 'y' to all questions for secure setup."
	echo "------------------------------------------------------"

	# Run Google Authenticator setup for the current user
	sudo -u $SUDO_USER google-authenticator

	if [[ $? -ne 0 ]]; then
		echo "Failed to configure Google Authenticator. Exiting."
		exit 1
	fi

	echo "Google Authenticator configuration completed."
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
	install_google_authenticator
	configure_google_authenticator
	configure_pam_sshd
	configure_sshd
	apply_ssh_config

	echo "======================================"
	echo "OTP configuration completed successfully!"
	echo "Make sure to keep your recovery codes in a safe place."
	echo "You can now log in using your SSH key and OTP token."
	echo "======================================"
}

# Execute main function
main
