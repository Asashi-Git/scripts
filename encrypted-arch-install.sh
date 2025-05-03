#!/bin/bash

# Arch Linux Installation Script with Hardening
# Based on the Arch Linux Manual Install and Hardening documentation

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to print section headers
print_section() {
	echo -e "\n${BLUE}${BOLD}=== $1 ===${NC}\n"
}

# Function to print information
print_info() {
	echo -e "${GREEN}INFO:${NC} $1"
}

# Function to print warnings
print_warning() {
	echo -e "${YELLOW}WARNING:${NC} $1"
}

# Function to print errors
print_error() {
	echo -e "${RED}ERROR:${NC} $1"
}

# Function to get user confirmation
confirm() {
	local prompt="$1"
	local response

	while true; do
		read -p "$prompt [y/n]: " response
		case $response in
		[Yy]*) return 0 ;;
		[Nn]*) return 1 ;;
		*) echo "Please enter y or n." ;;
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

# Welcome message
clear
echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}    Arch Linux Installation Script with Hardening     ${NC}"
echo -e "${BOLD}======================================================${NC}"
echo
print_info "This script will guide you through installing Arch Linux with encryption and security hardening."
print_warning "This script will erase all data on the target disk. Make sure you have backups!"
echo

# Confirm before proceeding
if ! confirm "Do you want to continue?"; then
	echo "Installation aborted by user."
	exit 0
fi

# Display available disks
print_section "Storage Configuration"
echo "Available disks:"
lsblk -d -o NAME,SIZE,MODEL
echo

# Get disk selection
read -p "Enter the disk to install Arch Linux on (e.g., vda, sda): " disk
disk_path="/dev/${disk}"

if [ ! -b "$disk_path" ]; then
	print_error "The specified disk $disk_path does not exist."
	exit 1
fi

print_warning "All data on $disk_path will be erased!"
if ! confirm "Are you sure you want to continue?"; then
	echo "Installation aborted by user."
	exit 0
fi

# Display current partition layout
print_info "Current partition layout:"
lsblk $disk_path

# Create partitions
print_section "Creating Partitions"
print_info "Creating EFI partition (512MB) and main partition for encryption"

# Using fdisk instead of cfdisk for automation
print_info "Creating a new partition table..."
(
	echo g     # Create a new empty GPT partition table
	echo n     # Add a new partition
	echo 1     # Partition number 1
	echo       # First sector (default)
	echo +512M # Last sector (512MB boot partition)
	echo t     # Change partition type
	echo 1     # EFI System
	echo n     # Add a new partition
	echo 2     # Partition number 2
	echo       # First sector (default)
	echo       # Last sector (default, remaining space)
	echo w     # Write changes
) | fdisk $disk_path

# Check if partitioning was successful
if [ ! -b "${disk_path}1" ] || [ ! -b "${disk_path}2" ]; then
	print_error "Failed to create partitions. Check 'fdisk -l $disk_path' for details."
	exit 1
fi

print_info "Partitioning completed successfully."
print_info "Formatting EFI partition..."
mkfs.fat -F32 ${disk_path}1
check_success "EFI partition formatted successfully." "Failed to format EFI partition."

# Setup encryption
print_section "Setting up Encryption"
print_warning "You will be asked to enter an encryption passphrase. DO NOT FORGET THIS PASSPHRASE!"

# Make sure the partition exists before attempting to encrypt it
if [ ! -b "${disk_path}2" ]; then
	print_error "Partition ${disk_path}2 does not exist. Partitioning may have failed."
	lsblk ${disk_path}
	exit 1
fi

print_info "Creating encrypted LUKS container on ${disk_path}2..."
if ! cryptsetup luksFormat --type luks2 ${disk_path}2; then
	print_error "Failed to create encrypted container."
	exit 1
fi
print_info "Encrypted container created successfully."

print_info "Opening encrypted container..."
if ! cryptsetup open ${disk_path}2 cryptlvm; then
	print_error "Failed to open encrypted container."
	exit 1
fi
print_info "Encrypted container opened successfully at /dev/mapper/cryptlvm"

# Verify the encrypted container was created
if [ ! -e "/dev/mapper/cryptlvm" ]; then
	print_error "Encrypted container /dev/mapper/cryptlvm does not exist after opening."
	exit 1
fi

# Setup LVM
print_section "Setting up LVM"
print_info "Creating physical volume on /dev/mapper/cryptlvm..."
if ! pvcreate /dev/mapper/cryptlvm; then
	print_error "Failed to create physical volume."
	cryptsetup close cryptlvm
	exit 1
fi
print_info "Physical volume created successfully."

print_info "Creating volume group 'vg0'..."
if ! vgcreate vg0 /dev/mapper/cryptlvm; then
	print_error "Failed to create volume group."
	cryptsetup close cryptlvm
	exit 1
fi
print_info "Volume group created successfully."

# Display created volume group for verification
vgdisplay vg0

# Create logical volumes
print_info "Creating logical volumes..."
if ! lvcreate -L 8G vg0 -n swap; then
	print_error "Failed to create swap logical volume."
	vgremove vg0
	cryptsetup close cryptlvm
	exit 1
fi
print_info "Swap volume created successfully."

if ! lvcreate -L 50G vg0 -n root; then
	print_error "Failed to create root logical volume."
	lvremove /dev/vg0/swap
	vgremove vg0
	cryptsetup close cryptlvm
	exit 1
fi
print_info "Root volume created successfully."

if ! lvcreate -l 100%FREE vg0 -n home; then
	print_error "Failed to create home logical volume."
	lvremove /dev/vg0/swap
	lvremove /dev/vg0/root
	vgremove vg0
	cryptsetup close cryptlvm
	exit 1
fi
print_info "Home volume created successfully."

# Display created logical volumes for verification
lvs

# Format partitions
print_section "Formatting Partitions"
print_info "Formatting partitions..."
mkfs.ext4 /dev/vg0/root
check_success "Root partition formatted successfully." "Failed to format root partition."

mkfs.ext4 /dev/vg0/home
check_success "Home partition formatted successfully." "Failed to format home partition."

mkswap /dev/vg0/swap
check_success "Swap partition formatted successfully." "Failed to format swap partition."

# Mount partitions
print_section "Mounting Partitions"
print_info "Mounting partitions..."

# Create mount point if it doesn't exist
if [ ! -d /mnt ]; then
	mkdir -p /mnt
	print_info "Created mount point directory at /mnt"
fi

# Mount root partition with proper error handling
if ! mount /dev/vg0/root /mnt; then
	print_error "Failed to mount root partition. Check if volume group and logical volume were created correctly."
	print_info "Trying to list available logical volumes:"
	lvs
	exit 1
fi
print_info "Root partition mounted successfully."

# Create and mount home directory
print_info "Creating /home mount point..."
if [ ! -d /mnt/home ]; then
	mkdir -p /mnt/home
fi
if ! mount /dev/vg0/home /mnt/home; then
	print_error "Failed to mount home partition."
	umount /mnt
	exit 1
fi
print_info "Home partition mounted successfully."

# Create and mount boot directory
print_info "Creating /boot mount point..."
if [ ! -d /mnt/boot ]; then
	mkdir -p /mnt/boot
fi
if ! mount ${disk_path}1 /mnt/boot; then
	print_error "Failed to mount boot partition."
	umount /mnt/home
	umount /mnt
	exit 1
fi
print_info "Boot partition mounted successfully."

# Activate swap
print_info "Activating swap..."
if ! swapon /dev/vg0/swap; then
	print_warning "Failed to activate swap. Continuing anyway, but you may encounter issues."
else
	print_info "Swap activated successfully."
fi

# Verify mounts
print_info "Verifying mounted partitions:"
lsblk ${disk_path}
df -h | grep -E "/mnt|/boot"

# Install essential packages
print_section "Installing Base System"
print_info "Installing essential packages..."
pacstrap /mnt base base-devel linux linux-firmware lvm2 \
	vim nano grub efibootmgr networkmanager \
	dhcpcd wpa_supplicant cryptsetup
check_success "Base packages installed successfully." "Failed to install base packages."

# Generate fstab
print_section "Configuring System"
print_info "Generating fstab..."
genfstab -U /mnt >>/mnt/etc/fstab
check_success "fstab generated successfully." "Failed to generate fstab."

# Create chroot setup script
print_info "Creating configuration script..."
cat >/mnt/root/chroot_setup.sh <<'EOL'
#!/bin/bash

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print information
print_info() {
    echo -e "${GREEN}INFO:${NC} $1"
}

# Function to print warnings
print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

# Function to print errors
print_error() {
    echo -e "${RED}ERROR:${NC} $1"
}

# Configure crypttab
print_info "Configuring crypttab..."
echo "cryptlvm    UUID=$(blkid -s UUID -o value /dev/$(lsblk -no pkname /dev/mapper/cryptlvm))    none    luks" >> /etc/crypttab

# Configure mkinitcpio
print_info "Configuring mkinitcpio hooks..."
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap consolefont modconf block encrypt lvm2 filesystems fsck usr)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Set timezone
print_info "Setting timezone to Europe/Paris..."
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc
date

# Configure locale
print_info "Configuring locale..."
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
read -p "Enter hostname for this system: " hostname
echo "$hostname" > /etc/hostname

# Set root password
print_info "Setting root password..."
passwd

# Create user
read -p "Enter username for new user: " username
useradd -m -G wheel -s /bin/bash "$username"
print_info "Setting password for $username..."
passwd "$username"

# Configure sudo
print_info "Configuring sudo..."
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
echo "$username ALL=(ALL:ALL) ALL" >> /etc/sudoers.d/$username

# Configure GRUB
print_info "Installing GRUB bootloader..."
grub-install --efi-directory=/boot --bootloader-id=GRUB

# Get UUID for encrypted device
encrypted_uuid=$(blkid -s UUID -o value /dev/$(lsblk -no pkname /dev/mapper/cryptlvm))
print_info "Found encrypted device UUID: $encrypted_uuid"

# Configure GRUB for encrypted boot
sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet cryptdevice=UUID=${encrypted_uuid}:cryptlvm root=\/dev\/vg0\/root\"/" /etc/default/grub

# Generate GRUB config
grub-mkconfig -o /boot/grub/grub.cfg

# Enable NetworkManager
print_info "Enabling NetworkManager..."
systemctl enable NetworkManager

# Configure sudo logging
print_info "Configuring sudo logging..."
echo "Defaults logfile=/var/log/sudo.log" >> /etc/sudoers.d/logging

# Final message
print_info "Chroot setup complete!"
EOL

# Make the script executable
chmod +x /mnt/root/chroot_setup.sh

# Execute the script inside chroot
print_info "Running configuration script inside chroot..."
arch-chroot /mnt /root/chroot_setup.sh

# Clean up the script after execution
rm /mnt/root/chroot_setup.sh

# Security Hardening Section
print_section "Security Hardening"
print_info "Setting up post-installation security hardening..."

# Create a post-install security script
cat >/mnt/root/security_hardening.sh <<'EOL'
#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print info messages
print_info() {
    echo -e "${GREEN}INFO:${NC} $1"
}

# Function to print warning messages
print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

# Function to get user confirmation
confirm() {
    local prompt="$1"
    local response
    
    while true; do
        read -p "$prompt [y/n]: " response
        case $response in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please enter y or n.";;
        esac
    done
}

print_info "Beginning security hardening process..."

# Configure sudo logging
print_info "Configuring sudo logging..."
if ! grep -q "logfile=/var/log/sudo.log" /etc/sudoers; then
    echo "Defaults logfile=/var/log/sudo.log" >> /etc/sudoers.d/logging
    chmod 440 /etc/sudoers.d/logging
fi

# Disable root login
print_info "Disabling root login shell..."
sed -i 's|^root:.*:|root:x:0:0:root:/root:/usr/sbin/nologin|' /etc/passwd

# Lock the root password
print_info "Locking root password..."
passwd -l root

# Enhance /etc/fstab with security options
print_info "Enhancing filesystem security in fstab..."
if ! grep -q "hidepid=2" /etc/fstab; then
    echo "# Process hiding for /proc" >> /etc/fstab
    echo "proc           /proc            proc            hidepid=2       0 0" >> /etc/fstab
fi

if ! grep -q "nosuid,nodev,noexec.*\/tmp" /etc/fstab; then
    echo "# Secure /tmp mount" >> /etc/fstab
    echo "tmpfs          /tmp             tmpfs           nosuid,nodev,noexec 0 0" >> /etc/fstab
fi

# Ask about SSH and 2FA
if confirm "Would you like to set up SSH with hardened security?"; then
    # Install required packages
    print_info "Installing SSH and 2FA packages..."
    pacman -S --noconfirm openssh libpam-google-authenticator qrencode
    
    # Enable SSH service
    systemctl enable sshd
    
    # Configure custom SSH port
    read -p "Enter a custom SSH port (recommended: use a port between 1024-65535): " ssh_port
    
    # Default to 22 if no port specified
    if [ -z "$ssh_port" ]; then
        ssh_port=22
        print_warning "Using default SSH port 22 (not recommended)"
    fi
    
    # Configure SSH
    print_info "Configuring SSH with hardened settings..."
    cat > /etc/ssh/sshd_config <<EOF
# Hardened SSH Configuration
Port $ssh_port
Protocol 2
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key

# Ciphers and keying
KexAlgorithms curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

# Authentication
LoginGraceTime 30s
PermitRootLogin no
StrictModes yes
MaxAuthTries 3
MaxSessions 5
PubkeyAuthentication yes
PasswordAuthentication yes   # Change to 'no' after setting up key-based authentication
PermitEmptyPasswords no
ChallengeResponseAuthentication yes
UsePAM yes

# Features
X11Forwarding no
PrintMotd no
Banner /etc/issue

# Allow only specific users
AllowUsers $USER

# Security
AllowAgentForwarding no
AllowTcpForwarding no
PermitUserEnvironment no
PermitTunnel no
DebianBanner no
EOF

    # Set up Google Authenticator
    if confirm "Would you like to set up Google Authenticator 2FA for SSH?"; then
        print_info "Setting up Google Authenticator..."
        
        # Configure PAM for SSH with 2FA
        cat > /etc/pam.d/sshd <<EOF
#%PAM-1.0
auth required pam_google_authenticator.so
auth include system-remote-login
account include system-remote-login
password include system-remote-login
session include system-remote-login
EOF

        # Update SSH config for 2FA
        sed -i 's/ChallengeResponseAuthentication yes/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config
        sed -i 's/AuthenticationMethods .*/AuthenticationMethods publickey,keyboard-interactive/' /etc/ssh/sshd_config

        print_info "Google Authenticator PAM configuration complete!"
        print_info "After rebooting, run 'google-authenticator' as your user to set up 2FA."
    fi
    
    print_info "SSH configuration complete! Service will start on next boot."
fi

# Harden the kernel with sysctl settings
if confirm "Would you like to apply kernel hardening settings?"; then
    print_info "Applying kernel hardening settings..."
    
    cat > /etc/sysctl.d/99-security.conf <<EOF
# Kernel hardening
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
kernel.printk=3 3 3 3
kernel.unprivileged_bpf_disabled=1
net.core.bpf_jit_harden=2
dev.tty.ldisc_autoload=0
vm.unprivileged_userfaultfd=0
kernel.kexec_load_disabled=1
kernel.sysrq=0
kernel.unprivileged_userns_clone=0
kernel.perf_event_paranoid=3

# Network security
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.secure_redirects=0
net.ipv4.conf.default.secure_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
net.ipv6.conf.all.accept_source_route=0
net.ipv6.conf.default.accept_source_route=0
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_rfc1337=1
net.ipv4.tcp_timestamps=0
net.ipv4.tcp_sack=0
net.ipv4.conf.all.log_martians=1
net.ipv4.conf.default.log_martians=1

# ASLR for memory protection
kernel.randomize_va_space=2
EOF

    # Apply settings
    sysctl --system
    
    print_info "Kernel hardening settings applied!"
fi

# Set up UFW firewall
if confirm "Would you like to set up UFW firewall?"; then
    print_info "Installing and configuring UFW..."
    pacman -S --noconfirm ufw
    
    # Reset UFW to default state
    ufw --force reset
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH if configured
    if [ -n "$ssh_port" ]; then
        print_info "Opening firewall port for SSH ($ssh_port)..."
        ufw allow "$ssh_port/tcp" comment "SSH"
    fi
    
    # Add extra security rules to UFW
    cat >> /etc/ufw/before.rules <<'EOF'

# Block invalid packets
-A ufw-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j ufw-logging-deny
-A ufw-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j DROP
EOF

    # Add similar rules for IPv6
    cat >> /etc/ufw/before6.rules <<'EOF'

# Block invalid packets
-A ufw6-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j ufw6-logging-deny
-A ufw6-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j DROP
EOF

    # Enable UFW
    print_info "Enabling UFW..."
    ufw --force enable
    
    print_info "UFW configuration complete!"
fi

# Configure Fail2Ban
if confirm "Would you like to set up Fail2Ban for intrusion prevention?"; then
    print_info "Installing and configuring Fail2Ban..."
    pacman -S --noconfirm fail2ban
    
    # Create copies of the configuration files
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    cp /etc/fail2ban/fail2ban.conf /etc/fail2ban/fail2ban.local
    
    # Configure jail.local
    sed -i 's/^maxretry = .*/maxretry = 2/' /etc/fail2ban/jail.local
    sed -i 's/^bantime = .*/bantime = 30m/' /etc/fail2ban/jail.local
    sed -i 's/^findtime = .*/findtime = 30m/' /etc/fail2ban/jail.local
    
    # Configure SSH jail if SSH was set up
    if [ -n "$ssh_port" ]; then
        cat > /etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
port = $ssh_port
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOF
    fi
    
    # Enable and start Fail2Ban
    systemctl enable fail2ban
    systemctl start fail2ban
    
    print_info "Fail2Ban configuration complete!"
fi

print_info "Security hardening complete!"
print_warning "Remember: Security is an ongoing process, not a one-time setup."
print_info "Regular updates and security audits are essential for maintaining system security."
EOL

# Make the security script executable
chmod +x /mnt/root/security_hardening.sh

# Ask if user wants to run security hardening now
if confirm "Would you like to apply security hardening configurations now?"; then
	print_info "Running security hardening script inside chroot..."
	arch-chroot /mnt /root/security_hardening.sh

	# Remove the script after execution
	rm /mnt/root/security_hardening.sh
else
	print_info "Security hardening script saved to /root/security_hardening.sh in your new system."
	print_info "You can run it after the first boot by executing 'sudo /root/security_hardening.sh'"
fi

# Finish installation
print_section "Completing Installation"

# Before unmounting, check if anyone is using the mount points
print_info "Checking for processes using mounted filesystems..."
fuser -vm /mnt 2>&1 || true

print_info "Unmounting partitions..."
# Unmount in reverse order
umount -R /mnt || {
	print_error "Failed to unmount partitions. Trying to identify and kill processes using mounts..."
	lsof | grep '/mnt' || true
	sleep 5
	umount -R /mnt || {
		print_error "Still unable to unmount. You may need to unmount manually before reboot."
		if confirm "Would you like to force unmount with lazy option (umount -l)?"; then
			umount -l -R /mnt
		fi
	}
}

print_section "Installation Complete"
print_info "Arch Linux has been installed with encryption and hardening."
print_info "You can now reboot your system and remove the installation media."
print_info "After reboot, you'll need to enter the disk encryption password."

if confirm "Would you like to reboot now?"; then
	print_info "Rebooting..."
	reboot
else
	print_info "You can reboot manually when ready."
fi
