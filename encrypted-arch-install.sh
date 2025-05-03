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
print_info "Creating partition table..."
(
  echo g     # Create a new empty GPT partition table
  echo n     # Add new partition (EFI)
  echo 1     # Partition number 1
  echo       # Default first sector
  echo +512M # Size 512MB
  echo t     # Change partition type
  echo 1     # EFI System
  echo n     # Add new partition (Main)
  echo 2     # Partition number 2
  echo       # Default first sector
  echo       # Default last sector (rest of disk)
  echo w     # Write changes and exit
) | fdisk $disk_path

check_success "Partitions created successfully." "Failed to create partitions."

# Format EFI partition
print_info "Formatting EFI partition..."
mkfs.fat -F32 ${disk_path}1
check_success "EFI partition formatted successfully." "Failed to format EFI partition."

# Setup encryption
print_section "Setting up Encryption"
print_warning "You will be asked to enter an encryption passphrase. DO NOT FORGET THIS PASSPHRASE!"

cryptsetup luksFormat --type luks2 ${disk_path}2
check_success "Encrypted container created successfully." "Failed to create encrypted container."

print_info "Opening encrypted container..."
cryptsetup open ${disk_path}2 cryptlvm
check_success "Encrypted container opened successfully." "Failed to open encrypted container."

# Setup LVM
print_section "Setting up LVM"
print_info "Creating physical volume..."
pvcreate /dev/mapper/cryptlvm
check_success "Physical volume created successfully." "Failed to create physical volume."

print_info "Creating volume group..."
vgcreate vg0 /dev/mapper/cryptlvm
check_success "Volume group created successfully." "Failed to create volume group."

# Create logical volumes
print_info "Creating logical volumes..."
lvcreate -L 8G vg0 -n swap
lvcreate -L 50G vg0 -n root
lvcreate -l 100%FREE vg0 -n home
check_success "Logical volumes created successfully." "Failed to create logical volumes."

# Format logical volumes
print_section "Formatting Logical Volumes"
print_info "Formatting root partition..."
mkfs.ext4 /dev/vg0/root
check_success "Root partition formatted successfully." "Failed to format root partition."

print_info "Formatting home partition..."
mkfs.ext4 /dev/vg0/home
check_success "Home partition formatted successfully." "Failed to format home partition."

print_info "Formatting swap partition..."
mkswap /dev/vg0/swap
check_success "Swap partition formatted successfully." "Failed to format swap partition."

# Mount partitions
print_section "Mounting Partitions"
print_info "Mounting partitions..."
mount /dev/vg0/root /mnt
mkdir -p /mnt/home
mount /dev/vg0/home /mnt/home
mkdir -p /mnt/boot
mount ${disk_path}1 /mnt/boot
swapon /dev/vg0/swap
check_success "Partitions mounted successfully." "Failed to mount partitions."

# Install base packages
print_section "Installing Base System"

# Get additional packages from user
read -p "Enter additional packages to install (space-separated): " additional_packages
base_packages="base base-devel nano vim networkmanager lvm2 cryptsetup grub efibootmgr linux linux-firmware sof-firmware $additional_packages"

print_info "Installing base packages: $base_packages"
pacstrap /mnt $base_packages

check_success "Base system installed successfully." "Failed to install base system."

# Generate fstab
print_section "Generating fstab"
print_info "Generating fstab..."
genfstab -U /mnt >/mnt/etc/fstab.new

# Show fstab to user
echo -e "\n${YELLOW}Generated fstab:${NC}"
cat /mnt/etc/fstab.new
echo

# Confirm fstab looks good
if confirm "Does the fstab look correct?"; then
  mv /mnt/etc/fstab.new /mnt/etc/fstab
  print_info "fstab saved."
else
  print_info "You can edit the fstab manually after installation."
  exit 1
fi

# Chroot configuration
print_section "Configuring System"

# Create a script to run inside the chroot environment
cat >/mnt/root/chroot_setup.sh <<'EOL'
#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print info messages
print_info() {
    echo -e "${GREEN}INFO:${NC} $1"
}

# Configure mkinitcpio
print_info "Configuring mkinitcpio..."
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems fsck usr)/' /etc/mkinitcpio.conf
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
echo "LANG=en_EN.UTF-8" > /etc/locale.conf

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
encrypted_uuid=$(blkid -o value -s UUID /dev/vda2)
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
        print_warning "Using default SSH port 22 (not recommended for security)"
    fi
    
    # Configure SSH
    print_info "Configuring SSH with enhanced security..."
    
    # Backup original config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    # Update SSH configuration with security settings
    sed -i "s/^#Port .*/Port $ssh_port/" /etc/ssh/sshd_config
    sed -i 's/^#PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/^#LoginGraceTime .*/LoginGraceTime 20/' /etc/ssh/sshd_config
    sed -i 's/^#MaxAuthTries .*/MaxAuthTries 3/' /etc/ssh/sshd_config
    sed -i 's/^#MaxSessions .*/MaxSessions 5/' /etc/ssh/sshd_config
    sed -i 's/^#ClientAliveInterval .*/ClientAliveInterval 60/' /etc/ssh/sshd_config
    sed -i 's/^#ClientAliveCountMax .*/ClientAliveCountMax 3/' /etc/ssh/sshd_config
    sed -i 's/^X11Forwarding .*/X11Forwarding no/' /etc/ssh/sshd_config
    sed -i 's/^#AllowAgentForwarding .*/AllowAgentForwarding no/' /etc/ssh/sshd_config
    sed -i 's/^#AllowTcpForwarding .*/AllowTcpForwarding no/' /etc/ssh/sshd_config
    sed -i 's/^#PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#KbdInteractiveAuthentication .*/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#UsePAM .*/UsePAM yes/' /etc/ssh/sshd_config
    sed -i 's/^#ChallengeResponseAuthentication .*/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config
    
    # Add Authentication Methods
    if ! grep -q "AuthenticationMethods" /etc/ssh/sshd_config; then
        echo "AuthenticationMethods publickey,keyboard-interactive" >> /etc/ssh/sshd_config
    else
        sed -i 's/^#AuthenticationMethods .*/AuthenticationMethods publickey,keyboard-interactive/' /etc/ssh/sshd_config
    fi
    
    # Comment out content in the Arch-specific config
    if [ -f "/etc/ssh/sshd_config.d/99-archlinux.conf" ]; then
        sed -i 's/^/#/' /etc/ssh/sshd_config.d/99-archlinux.conf
    fi
    
    # Generate SSH key for the current user
    print_info "Generating SSH key..."
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
    
    # Set up authorized_keys
    cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    
    # Configure AuthorizedKeysFile
    sed -i 's/^#AuthorizedKeysFile .*/AuthorizedKeysFile .ssh\/authorized_keys/' /etc/ssh/sshd_config
    
    # Configure Google Authenticator for 2FA
    if confirm "Would you like to set up Google Authenticator 2FA for SSH?"; then
        print_info "Setting up Google Authenticator..."
        
        # Configure PAM
        echo "auth required pam_google_authenticator.so" >> /etc/pam.d/sshd
        
        # Run google-authenticator setup
        print_info "Please follow the prompts to set up Google Authenticator:"
        sudo -u $(logname) google-authenticator
        
        print_info "Google Authenticator setup complete!"
    fi
    
    # Restart SSH to apply changes
    systemctl restart sshd
    
    print_info "SSH configuration complete. Use 'ssh -p $ssh_port username@hostname' to connect."
fi

# Kernel hardening via sysctl
print_info "Applying kernel hardening via sysctl..."

# Network security
cat > /etc/sysctl.d/90-network-security.conf <<'EOF'
# Reverse Path Filtering (Prevent Spoofing Attacks)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
# Block SYN attacks
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_synack_retries = 3
# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
# Disable Source Packet Routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0 
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
# Disable Packet Forwarding (unless server is functioning as router or VPN)
net.ipv4.ip_forward = 0
net.ipv4.conf.all.forwarding = 0
net.ipv6.conf.all.forwarding = 0
net.ipv4.conf.default.forwarding = 0
net.ipv6.conf.default.forwarding = 0
# Protect TCP Connections (TIME-WAIT State)
net.ipv4.tcp_rfc1337 = 1
# Additional UFW compatible settings
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.icmp_echo_ignore_all = 0
net.ipv4.conf.all.log_martians = 0
net.ipv4.conf.default.log_martians = 0
EOF

# Kernel hardening
cat > /etc/sysctl.d/91-kernel-hardening.conf <<'EOF'
# Harden the BPF JIT Compiler
net.core.bpf_jit_harden = 2
kernel.unprivileged_bpf_disabled = 1 
# Disable Magic Keys
kernel.sysrq = 0
# Restrict Access to Kernel Logs
kernel.dmesg_restrict = 1
# Restrict ptrace Access
kernel.yama.ptrace_scope = 3
# Restrict User Namespaces
kernel.unprivileged_userns_clone = 0
# Address Space Layout Randomization (ASLR)
kernel.randomize_va_space = 2
# Additional kernel hardening 
kernel.kexec_load_disabled = 1
kernel.perf_event_paranoid = 3
EOF

# Filesystem and memory protection
cat > /etc/sysctl.d/92-fs-memory-protection.conf <<'EOF'
# Restrict Core Dumps
kernel.core_pattern = |/bin/false
fs.suid_dumpable = 0
# File Creation Restrictions
fs.protected_regular = 2
fs.protected_fifos = 2
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
# Control Swapping
vm.swappiness = 1
EOF

# Apply sysctl changes
print_info "Applying sysctl changes..."
sysctl --system

# Configure UFW Firewall
if confirm "Would you like to set up UFW firewall?"; then
    print_info "Installing and configuring UFW firewall..."
    pacman -S --noconfirm ufw
    
    # Configure UFW to use our sysctl settings
    sed -i 's|^IPT_SYSCTL=.*|IPT_SYSCTL=/etc/sysctl.conf|' /etc/default/ufw
    
    # If SSH was configured, allow the chosen port
    if [ -n "$ssh_port" ]; then
        ufw allow "$ssh_port/tcp"
        ufw limit "$ssh_port"
        print_info "Added UFW rule for SSH on port $ssh_port"
    fi
    
    # Configure additional security rules in UFW
    print_info "Adding additional security rules to UFW..."
    
    # Add rules to block invalid packets
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
print_info "Unmounting partitions..."
umount -a

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
