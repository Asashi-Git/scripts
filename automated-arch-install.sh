#!/bin/bash

# Arch Linux Automated Installer Script
# This script automates the installation of Arch Linux with encryption and LVM
# Created for educational purposes

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display section headers
section() {
	echo -e "\n${BLUE}==>${NC} ${GREEN}$1${NC}"
	sleep 1
}

# Function for user prompts
prompt() {
	echo -e "\n${YELLOW}$1${NC}"
}

# Function to display success messages
success() {
	echo -e "\n${GREEN}✓ $1${NC}"
	sleep 1
}

# Function to display warning messages
warning() {
	echo -e "\n${RED}! WARNING: $1${NC}"
}

# Function to display info messages
info() {
	echo -e "\n${CYAN}ℹ $1${NC}"
}

# Function to check command success
check_success() {
	if [ $? -eq 0 ]; then
		success "$1"
	else
		echo -e "\n${RED}✗ Error: $1 failed${NC}"
		exit 1
	fi
}

# Function to get user confirmation
confirm() {
	while true; do
		prompt "$1 [y/n]"
		read -r response
		case $response in
		[yY]*) return 0 ;;
		[nN]*) return 1 ;;
		*) echo "Please answer yes (y) or no (n)." ;;
		esac
	done
}

# Check if script is running as root
if [ "$(id -u)" -ne 0 ]; then
	echo -e "${RED}This script must be run as root${NC}"
	exit 1
fi

# Welcome message
clear
echo -e "${MAGENTA}========================================${NC}"
echo -e "${MAGENTA}   Arch Linux Automated Installer      ${NC}"
echo -e "${MAGENTA}========================================${NC}"
echo -e "\nThis script will guide you through installing Arch Linux with encryption and LVM."
echo -e "Make sure you have backed up any important data before proceeding.\n"

if ! confirm "Do you want to continue with the installation?"; then
	echo "Installation aborted."
	exit 0
fi

# Step 1: Check internet connection
section "Checking internet connection"
if ping -c 1 archlinux.org >/dev/null 2>&1; then
	success "Internet connection is available"
else
	echo -e "${RED}No internet connection. Please check your network settings.${NC}"
	exit 1
fi

# Step 2: Update system clock
section "Updating system clock"
timedatectl set-ntp true
check_success "System clock updated"

# Step 3: Disk selection and partitioning
section "Disk Selection"
echo "Available disks:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep disk
prompt "Enter the disk to use (e.g. vda, sda, nvme0n1):"
read disk_name
disk_path="/dev/${disk_name}"

if [ ! -b "$disk_path" ]; then
	echo -e "${RED}Error: $disk_path is not a valid block device.${NC}"
	exit 1
fi

warning "All data on $disk_path will be erased!"
if ! confirm "Are you sure you want to continue?"; then
	echo "Installation aborted."
	exit 0
fi

# Step 4: Create partitions
section "Creating partitions"

# Create partition table
echo -e "\nCreating GPT partition table on $disk_path"
parted -s "$disk_path" mklabel gpt

# Create boot partition (512MB)
echo "Creating boot partition (512MB)"
parted -s "$disk_path" mkpart "EFI system partition" fat32 1MiB 513MiB
parted -s "$disk_path" set 1 esp on

# Create encrypted partition (rest of disk)
echo "Creating encrypted partition (rest of disk)"
parted -s "$disk_path" mkpart "encrypted" 513MiB 100%

# Set boot partition variable
if [[ "$disk_name" =~ nvme ]]; then
	boot_part="${disk_path}p1"
	crypt_part="${disk_path}p2"
else
	boot_part="${disk_path}1"
	crypt_part="${disk_path}2"
fi

check_success "Partitions created"

# Step 5: Format boot partition
section "Formatting boot partition"
mkfs.fat -F32 "$boot_part"
check_success "Boot partition formatted"

# Step 6: Setup encryption
section "Setting up encryption"
prompt "Enter a passphrase for disk encryption (will not be shown):"
read -s cryptpass
echo
prompt "Confirm passphrase (will not be shown):"
read -s cryptpass_confirm
echo

if [ "$cryptpass" != "$cryptpass_confirm" ]; then
	echo -e "${RED}Error: Passphrases do not match.${NC}"
	exit 1
fi

echo -n "$cryptpass" | cryptsetup luksFormat --type luks2 "$crypt_part" -
check_success "Encryption setup"

echo -n "$cryptpass" | cryptsetup open "$crypt_part" cryptlvm -
check_success "Encrypted partition opened"

# Step 7: Setup LVM
section "Setting up Logical Volume Manager (LVM)"

# Create physical volume
pvcreate /dev/mapper/cryptlvm
check_success "Physical volume created"

# Create volume group
prompt "Enter a name for the volume group (default: vg0):"
read vg_name
vg_name=${vg_name:-vg0}
vgcreate "$vg_name" /dev/mapper/cryptlvm
check_success "Volume group created"

# Create logical volumes
# Get total available space
total_space=$(vgs --noheadings --units g -o vg_size "$vg_name" | tr -d ' ' | cut -d'.' -f1)
info "Total available space: ${total_space}GB"

# Ask if user wants swap
if confirm "Do you want to create a swap partition?"; then
	prompt "Enter swap size in GB (recommended: 4-8GB):"
	read swap_size
	lvcreate -L "${swap_size}G" "$vg_name" -n swap
	check_success "Swap logical volume created"
	total_space=$((total_space - swap_size))
	info "Remaining space: ${total_space}GB"
fi

# Root partition
prompt "Enter root partition size in GB (recommended: 20-30GB):"
read root_size
lvcreate -L "${root_size}G" "$vg_name" -n root
check_success "Root logical volume created"
total_space=$((total_space - root_size))
info "Remaining space: ${total_space}GB"

# Ask if user wants separate home partition
if confirm "Do you want to create a separate home partition?"; then
	prompt "Enter home partition size in GB (default: remaining space):"
	read home_size
	if [ -z "$home_size" ]; then
		home_size=$((total_space / 2))
	fi
	lvcreate -L "${home_size}G" "$vg_name" -n home
	check_success "Home logical volume created"
	total_space=$((total_space - home_size))
	info "Remaining space: ${total_space}GB"
fi

# Ask if user wants separate var partition
if confirm "Do you want to create a separate var partition?"; then
	prompt "Enter var partition size in GB (recommended: 10-15GB):"
	read var_size
	lvcreate -L "${var_size}G" "$vg_name" -n var
	check_success "Var logical volume created"
	total_space=$((total_space - var_size))
	info "Remaining space: ${total_space}GB"
fi

# Ask if user wants separate usr partition
if confirm "Do you want to create a separate usr partition?"; then
	prompt "Enter usr partition size in GB (recommended: 10-15GB):"
	read usr_size
	lvcreate -L "${usr_size}G" "$vg_name" -n usr
	check_success "Usr logical volume created"
	total_space=$((total_space - usr_size))
	info "Remaining space: ${total_space}GB"
fi

# Ask if user wants a data partition for the remaining space
if [ "$total_space" -gt 0 ]; then
	if confirm "Do you want to create a data partition with the remaining ${total_space}GB?"; then
		lvcreate -l 100%FREE "$vg_name" -n data
		check_success "Data logical volume created"
	fi
fi

# Step 8: Format logical volumes
section "Formatting logical volumes"

mkfs.ext4 "/dev/$vg_name/root"
check_success "Root partition formatted"

# Format other partitions if they exist
if lvs | grep -q "$vg_name-home"; then
	mkfs.ext4 "/dev/$vg_name/home"
	check_success "Home partition formatted"
fi

if lvs | grep -q "$vg_name-var"; then
	mkfs.ext4 "/dev/$vg_name/var"
	check_success "Var partition formatted"
fi

if lvs | grep -q "$vg_name-usr"; then
	mkfs.ext4 "/dev/$vg_name/usr"
	check_success "Usr partition formatted"
fi

if lvs | grep -q "$vg_name-data"; then
	mkfs.ext4 "/dev/$vg_name/data"
	check_success "Data partition formatted"
fi

# Create swap if it exists
if lvs | grep -q "$vg_name-swap"; then
	mkswap "/dev/$vg_name/swap"
	check_success "Swap partition formatted"
fi

# Step 9: Mount the file systems
section "Mounting file systems"

mount "/dev/$vg_name/root" /mnt
check_success "Root partition mounted"

# Create necessary directories
mkdir -p /mnt/{boot,home,var,usr,data}
check_success "Mount point directories created"

# Mount boot partition
mount "$boot_part" /mnt/boot
check_success "Boot partition mounted"

# Mount other partitions if they exist with hardening options
if lvs | grep -q "$vg_name-home"; then
	if confirm "Do you want to mount home with hardening options (nosuid,nodev,noexec)?"; then
		mount "/dev/$vg_name/home" /mnt/home -o nosuid,nodev,noexec
	else
		mount "/dev/$vg_name/home" /mnt/home
	fi
	check_success "Home partition mounted"
fi

if lvs | grep -q "$vg_name-var"; then
	if confirm "Do you want to mount var with hardening options (nosuid,nodev,noexec)?"; then
		mount "/dev/$vg_name/var" /mnt/var -o nosuid,nodev,noexec
	else
		mount "/dev/$vg_name/var" /mnt/var
	fi
	check_success "Var partition mounted"
fi

if lvs | grep -q "$vg_name-usr"; then
	if confirm "Do you want to mount usr with hardening options (nodev)?"; then
		mount "/dev/$vg_name/usr" /mnt/usr -o nodev
	else
		mount "/dev/$vg_name/usr" /mnt/usr
	fi
	check_success "Usr partition mounted"
fi

if lvs | grep -q "$vg_name-data"; then
	mount "/dev/$vg_name/data" /mnt/data
	check_success "Data partition mounted"
fi

# Enable swap if it exists
if lvs | grep -q "$vg_name-swap"; then
	swapon "/dev/$vg_name/swap"
	check_success "Swap enabled"
fi

# Step 10: Install essential packages
section "Installing base packages"

prompt "Do you want to install additional packages? (Enter space-separated list, or press Enter for defaults):"
read -r additional_packages

# Base packages that are always installed
base_packages="base base-devel nano vim networkmanager lvm2 cryptsetup grub efibootmgr linux linux-firmware sof-firmware"

# Combine base and additional packages
packages="$base_packages $additional_packages"

pacstrap /mnt $packages
check_success "Base packages installed"

# Step 11: Generate fstab
section "Generating fstab"

genfstab -U /mnt >/mnt/etc/fstab
check_success "fstab generated"

# Display generated fstab
echo "Generated fstab:"
cat /mnt/etc/fstab

# Step 12: Prepare for chroot
section "Preparing for chroot"

# Create a post-installation script to be executed inside the chroot
cat >/mnt/post_install.sh <<EOF
#!/bin/bash

# Set time zone
echo "Setting time zone..."
prompt "Enter your timezone (e.g. Europe/Paris):"
read timezone
ln -sf "/usr/share/zoneinfo/\$timezone" /etc/localtime
hwclock --systohc

# Localization
echo "Setting locale..."
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Network configuration
echo "Setting hostname..."
prompt "Enter hostname:"
read hostname
echo "\$hostname" > /etc/hostname
echo "127.0.0.1 localhost" > /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 \$hostname.localdomain \$hostname" >> /etc/hosts

# Configure initramfs
echo "Configuring mkinitcpio.conf..."
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems fsck usr)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Set root password
echo "Setting root password..."
passwd

# Create a user
echo "Creating user..."
prompt "Enter username:"
read username
useradd -m -G wheel -s /bin/bash \$username
passwd \$username

# Enable wheel group for sudo
echo "Enabling sudo for wheel group..."
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel

# Configure GRUB
echo "Configuring GRUB..."
VG_NAME=\$(lvs --noheadings -o vg_name | tr -d ' ' | head -n1)
CRYPT_UUID=\$(blkid -s UUID -o value \$(findmnt -no source /boot | sed 's/p\?1\$/p\?2/'))

sed -i "s#^GRUB_CMDLINE_LINUX=.*#GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\$CRYPT_UUID:cryptlvm root=/dev/\$VG_NAME/root\"#" /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
echo "Enabling NetworkManager service..."
systemctl enable NetworkManager

echo "Post-installation completed successfully!"
EOF

chmod +x /mnt/post_install.sh

# Step 13: Enter chroot and execute post-installation script
section "Entering chroot to execute post-installation"

arch-chroot /mnt /post_install.sh
check_success "Post-installation completed"

# Remove the post-installation script
rm /mnt/post_install.sh

# Step 14: Ask about web server configuration
if confirm "Do you want to set up a web server with encrypted HTTP partition?"; then
	section "Setting up encrypted HTTP partition"

	# Create HTTP data partition
	prompt "Enter the size for HTTP data partition in GB:"
	read http_size
	lvcreate -L "${http_size}G" "$vg_name" -n httpdata
	check_success "HTTP data logical volume created"

	# Encrypt HTTP partition
	prompt "Enter a passphrase for HTTP data encryption (will not be shown):"
	read -s http_cryptpass
	echo
	prompt "Confirm passphrase (will not be shown):"
	read -s http_cryptpass_confirm
	echo

	if [ "$http_cryptpass" != "$http_cryptpass_confirm" ]; then
		echo -e "${RED}Error: Passphrases do not match.${NC}"
		exit 1
	fi

	echo -n "$http_cryptpass" | cryptsetup luksFormat "/dev/$vg_name/httpdata" -
	check_success "HTTP partition encryption setup"

	echo -n "$http_cryptpass" | cryptsetup open "/dev/$vg_name/httpdata" crypthttp -
	check_success "HTTP encrypted partition opened"

	# Format HTTP partition
	mkfs.ext4 /dev/mapper/crypthttp
	check_success "HTTP partition formatted"

	# Mount HTTP partition
	mkdir -p /mnt/data/http
	mount /dev/mapper/crypthttp /mnt/data/http
	check_success "HTTP partition mounted"

	# Create script to mount HTTP data on login
	cat >/mnt/usr/local/bin/mount-httpdata.sh <<EOF
#!/bin/bash

# Check if already mounted
if mountpoint -q /data/http; then
    echo "HTTP data partition is already mounted."
    exit 0
fi

# Try to unlock and mount
echo "Unlocking HTTP data partition..."
if cryptsetup open /dev/$vg_name/httpdata crypthttp; then
    echo "Mounting HTTP data partition..."
    mount /dev/mapper/crypthttp /data/http
    echo "HTTP data partition mounted successfully."
    
    # Set proper ownership and permissions
    chown localadm:http /data/http
    chmod 750 /data/http
    
    # Restart web server if needed
    systemctl restart nginx
else
    echo "Failed to unlock HTTP data partition."
    exit 1
fi
EOF

	chmod +x /mnt/usr/local/bin/mount-httpdata.sh
	check_success "HTTP mount script created"

	# Create localadm user if it doesn't exist
	arch-chroot /mnt useradd -m -G wheel -s /bin/bash localadm
	arch-chroot /mnt passwd localadm

	# Add to .bash_profile
	cat >>/mnt/home/localadm/.bash_profile <<EOF

# Check if HTTP partition is mounted
if ! mountpoint -q /data/http; then
    echo "HTTP data partition is not mounted."
    read -p "Would you like to mount it now? (y/n): " response
    if [[ "\$response" =~ ^[Yy]$ ]]; then
        sudo /usr/local/bin/mount-httpdata.sh
    fi
fi
EOF

	# Install nginx
	arch-chroot /mnt pacman -S --noconfirm nginx
	check_success "Nginx installed"

	# Create maintenance page
	mkdir -p /mnt/usr/share/nginx/html
	cat >/mnt/usr/share/nginx/html/maintenance.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Maintenance</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 40px; background-color: #585a59; color: #FFF }
        h1 { color: #FFF; }
        .container { max-width: 600px; margin: 0 auto; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Site Under Maintenance</h1>
        <p>The website is currently undergoing maintenance. Please check back later.</p>
    </div>
</body>
</html>
EOF

	# Configure Nginx
	cat >/mnt/etc/nginx/nginx.conf <<EOF
worker_processes 1;
events {
    worker_connections 1024;
}

http {
    include mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;

    server {
        listen 80;
        server_name www.manual-arch-install.local;
        
        root /data/http/encrypted-arch-linux;
        index encrypted-arch-linux.html;
        
        error_page 403 404 /maintenance.html;
        location = /maintenance.html {
            root /usr/share/nginx/html;
            internal;
        }
        
        access_log /var/log/nginx/access.log;
        error_log /var/log/nginx/error.log warn;
    }
}
EOF

	# Enable Nginx
	arch-chroot /mnt systemctl enable nginx
	check_success "Nginx configured and enabled"

	# Create HTTP group for nginx
	arch-chroot /mnt groupadd http
	arch-chroot /mnt usermod -aG http localadm

	# Clone sample website
	arch-chroot /mnt pacman -S --noconfirm git
	arch-chroot /mnt git clone https://github.com/Asashi-Git/encrypted-arch-linux.git /tmp/website
	mkdir -p /mnt/data/http/encrypted-arch-linux
	cp -r /mnt/tmp/website/* /mnt/data/http/encrypted-arch-linux/
	check_success "Sample website cloned"
fi

# Step 15: Unmount all partitions
section "Finishing installation"

umount -R /mnt
check_success "Partitions unmounted"

# Step 16: Finalize installation
section "Installation completed"
echo -e "${GREEN}Arch Linux has been successfully installed!${NC}"
echo -e "You can now reboot into your new system."
if confirm "Do you want to reboot now?"; then
	reboot
else
	echo "Please reboot when you're ready."
fi
