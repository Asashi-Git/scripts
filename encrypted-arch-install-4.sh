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
echo -e "${BOLD}==========================================================================${NC}"
echo -e "${BOLD}    Arch Linux Installation Script with Hardening By Samuel Decarnelle    ${NC}"
echo -e "${BOLD}==========================================================================${NC}"
echo
print_info "This script will guide you through installing Arch Linux with encryption and security hardening."
print_warning "This script will erase all data on the target disk. Make sure you have backups!"
echo

# Confirm before proceeding
if ! confirm "Do you want to continue?"; then
  echo "Installation aborted by user."
  exit 0
fi

# Keyboard layout selection
print_section "Keyboard Layout Configuration"
echo "Available keyboard layouts:"
echo "1) us - US English (default)"
echo "2) uk - United Kingdom"
echo "3) de - German"
echo "4) fr - French"
echo "5) es - Spanish"
echo "6) it - Italian"
echo "7) Other (specify manually)"

read -p "Select your keyboard layout [1-7]: " kb_choice

case $kb_choice in
1) kb_layout="us" ;;
2) kb_layout="uk" ;;
3) kb_layout="de" ;;
4) kb_layout="fr" ;;
5) kb_layout="es" ;;
6) kb_layout="it" ;;
7)
  # List available layouts
  localectl list-keymaps | grep -v ".gz"
  read -p "Enter keyboard layout from the list above: " kb_layout
  ;;
*)
  echo "Invalid choice. Defaulting to US layout."
  kb_layout="us"
  ;;
esac

# Set keyboard layout
print_info "Setting keyboard layout to $kb_layout..."
loadkeys $kb_layout

# Timezone selection
print_section "Timezone Configuration"
echo "Available regions:"
ls -l /usr/share/zoneinfo/ | grep '^d' | awk '{print NR ") " $9}'
read -p "Select region number: " region_num
region=$(ls -l /usr/share/zoneinfo/ | grep '^d' | awk '{print $9}' | sed -n "${region_num}p")

echo "Available cities in $region:"
ls -l /usr/share/zoneinfo/$region/ | grep -v '^d' | awk '{print NR ") " $9}'
read -p "Select city number: " city_num
city=$(ls -l /usr/share/zoneinfo/$region/ | grep -v '^d' | awk '{print $9}' | sed -n "${city_num}p")

timezone="$region/$city"
print_info "Selected timezone: $timezone"

# Verify network connection
print_section "Network Connection"
if ping -c 1 archlinux.org >/dev/null 2>&1; then
  print_info "Network connection is working."
else
  print_error "No network connection. Please check your connection and try again."
  exit 1
fi

# Language/locale selection
print_section "Language Configuration"
echo "Select your language/locale:"
echo "1) en_US.UTF-8 (US English)"
echo "2) en_GB.UTF-8 (British English)"
echo "3) de_DE.UTF-8 (German)"
echo "4) fr_FR.UTF-8 (French)"
echo "5) es_ES.UTF-8 (Spanish)"
echo "6) it_IT.UTF-8 (Italian)"
echo "7) Other (specify manually)"

read -p "Select your locale [1-7]: " locale_choice

case $locale_choice in
1) locale="en_US.UTF-8" ;;
2) locale="en_GB.UTF-8" ;;
3) locale="de_DE.UTF-8" ;;
4) locale="fr_FR.UTF-8" ;;
5) locale="es_ES.UTF-8" ;;
6) locale="it_IT.UTF-8" ;;
7)
  echo "Available locales:"
  grep -v '^#' /etc/locale.gen | grep UTF-8 | less
  read -p "Enter your desired locale (e.g., en_US.UTF-8): " locale
  ;;
*)
  echo "Invalid choice. Defaulting to en_US.UTF-8."
  locale="en_US.UTF-8"
  ;;
esac

print_info "Selected locale: $locale"

# Update system clock
print_section "System Clock"
print_info "Updating system clock..."
timedatectl set-ntp true

# Disk selection
print_section "Disk Selection"
echo "Available disks:"
lsblk -d -p -n -l -o NAME,SIZE,MODEL | grep -E "^/dev/(sd|nvme|vd)"
echo
read -p "Enter the full disk path to install Arch Linux (e.g., /dev/sda): " disk_path
if [ ! -b "$disk_path" ]; then
  print_error "$disk_path is not a valid disk path. Exiting."
  exit 1
fi

print_info "Selected disk: $disk_path"
print_warning "All data on $disk_path will be erased."
if ! confirm "Are you sure you want to continue?"; then
  echo "Installation aborted by user."
  exit 0
fi

# Desktop Environment selection
print_section "Desktop Environment"
echo "Select a desktop environment to install:"
echo "1) None (CLI only)"
echo "2) GNOME"
echo "3) KDE Plasma"
echo "4) Xfce"
echo "5) MATE"
echo "6) Cinnamon"
echo "7) i3-wm"

read -p "Select desktop environment [1-7]: " de_choice

case $de_choice in
1)
  desktop_env="none"
  de_packages=""
  de_service=""
  ;;
2)
  desktop_env="gnome"
  de_packages="gnome gnome-extra"
  de_service="gdm"
  ;;
3)
  desktop_env="kde"
  de_packages="plasma kde-applications"
  de_service="sddm"
  ;;
4)
  desktop_env="xfce"
  de_packages="xfce4 xfce4-goodies lightdm lightdm-gtk-greeter"
  de_service="lightdm"
  ;;
5)
  desktop_env="mate"
  de_packages="mate mate-extra lightdm lightdm-gtk-greeter"
  de_service="lightdm"
  ;;
6)
  desktop_env="cinnamon"
  de_packages="cinnamon lightdm lightdm-gtk-greeter"
  de_service="lightdm"
  ;;
7)
  desktop_env="i3"
  de_packages="i3-wm i3status i3blocks i3lock dmenu lightdm lightdm-gtk-greeter xorg-server xorg-apps xorg-xinit rxvt-unicode"
  de_service="lightdm"
  ;;
*)
  desktop_env="none"
  de_packages=""
  de_service=""
  print_info "Invalid choice. No desktop environment will be installed."
  ;;
esac

if [ "$desktop_env" != "none" ]; then
  print_info "Selected desktop environment: $desktop_env"
else
  print_info "No desktop environment will be installed (CLI only)."
fi

# Partition disk and setup encryption
print_section "Disk Partitioning"

# Calculate default partition sizes
print_info "Calculating default partition sizes..."

# Get total disk size in GB
total_disk_size_kb=$(blockdev --getsize64 $disk_path)
total_disk_size=$(echo "scale=2; $total_disk_size_kb / 1024 / 1024 / 1024" | bc)
print_info "Total disk size: ${total_disk_size}GB"

# Get system memory for swap
mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
swap_size=$(echo "scale=2; $mem_kb / 1024 / 1024" | bc)
print_info "RAM size (for swap): ${swap_size}GB"

# Calculate available space after EFI (512MB)
available_space=$(echo "scale=2; $total_disk_size - 0.5 - $swap_size" | bc)
print_info "Available space for LVM: ${available_space}GB"

# Calculate sizes based on percentages
root_size=$(echo "scale=2; $available_space * 0.20" | bc)
home_size=$(echo "scale=2; $available_space * 0.35" | bc)
var_size=$(echo "scale=2; $available_space * 0.15" | bc)
usr_size=$(echo "scale=2; $available_space * 0.20" | bc)
data_size=$(echo "scale=2; $available_space * 0.10" | bc)

echo "Default partition sizes:"
echo "  - EFI:  512MB (fixed)"
echo "  - SWAP: ${swap_size}GB (equals RAM size)"
echo "  - ROOT: ${root_size}GB (20%)"
echo "  - HOME: ${home_size}GB (35%)"
echo "  - VAR:  ${var_size}GB (15%)"
echo "  - USR:  ${usr_size}GB (20%)"
echo "  - DATA: ${data_size}GB (10%)"

# Format sizes for lvcreate
root_size="${root_size}G"
home_size="${home_size}G"
var_size="${var_size}G"
usr_size="${usr_size}G"
data_size="${data_size}G"
swap_size="${swap_size}G"

if ! confirm "Use these default sizes?"; then
  read -p "Enter ROOT size (in GB, e.g., 20G): " root_size
  read -p "Enter HOME size (in GB, e.g., 40G): " home_size
  read -p "Enter VAR size (in GB, e.g., 15G): " var_size
  read -p "Enter USR size (in GB, e.g., 20G): " usr_size
  read -p "Enter DATA size (in GB, e.g., 10G): " data_size
  read -p "Enter SWAP size (in GB, e.g., 8G): " swap_size

  # Append 'G' if not present
  [[ $root_size == *G ]] || root_size="${root_size}G"
  [[ $home_size == *G ]] || home_size="${home_size}G"
  [[ $var_size == *G ]] || var_size="${var_size}G"
  [[ $usr_size == *G ]] || usr_size="${usr_size}G"
  [[ $data_size == *G ]] || data_size="${data_size}G"
  [[ $swap_size == *G ]] || swap_size="${swap_size}G"
fi

# Wipe disk
print_info "Wiping disk signature on $disk_path..."
wipefs --all $disk_path
check_success "Disk wiped successfully." "Failed to wipe disk."

# Create partitions
print_info "Creating partitions..."
parted -s $disk_path mklabel gpt
parted -s $disk_path mkpart ESP fat32 1MiB 513MiB
parted -s $disk_path set 1 boot on
parted -s $disk_path mkpart primary 513MiB 100%
check_success "Partitions created successfully." "Failed to create partitions."

# Determine partition names (handles nvme, sd*, vd* devices correctly)
if [[ $disk_path =~ ^/dev/nvme ]]; then
  boot_part="${disk_path}p1"
  root_part="${disk_path}p2"
else
  boot_part="${disk_path}1"
  root_part="${disk_path}2"
fi

print_info "Boot partition: $boot_part"
print_info "Root partition: $root_part"

# Set up encryption
print_section "Disk Encryption"

# Set up encryption and LVM
read -s -p "Enter disk encryption password: " password
echo
read -s -p "Confirm disk encryption password: " password_confirm
echo

if [ "$password" != "$password_confirm" ]; then
  print_error "Passwords do not match. Exiting."
  exit 1
fi

# Create encrypted container
print_info "Setting up disk encryption..."
echo -n "$password" | cryptsetup luksFormat --type luks2 -q $root_part -
check_success "Encrypted container created successfully." "Failed to create encrypted container."

# Open the container
print_info "Opening encrypted container..."
echo -n "$password" | cryptsetup open $root_part cryptlvm -
check_success "Encrypted container opened successfully." "Failed to open encrypted container."

# Setup LVM
print_section "Setting up LVM"
print_info "Creating physical volume..."
pvcreate /dev/mapper/cryptlvm
check_success "Physical volume created successfully." "Failed to create physical volume."

print_info "Creating volume group..."
vgcreate vg0 /dev/mapper/cryptlvm
check_success "Volume group created successfully." "Failed to create volume group."

# Get total volume group size in GB
vg_size=$(vgs --noheading --units g -o vg_size vg0 | sed 's/ //g' | sed 's/g//')
print_info "Volume group size: ${vg_size}GB"

# Calculate logical volume sizes
# Remove decimal point for lvcreate command
root_size_int=$(echo "$root_size" | sed 's/G$//')
var_size_int=$(echo "$var_size" | sed 's/G$//')
usr_size_int=$(echo "$usr_size" | sed 's/G$//')
data_size_int=$(echo "$data_size" | sed 's/G$//')
home_size_int=$(echo "$home_size" | sed 's/G$//')
swap_size_int=$(echo "$swap_size" | sed 's/G$//')

print_info "Creating logical volumes with specified sizes..."
print_info "  - ROOT: ${root_size_int}G"
lvcreate -L ${root_size_int}G vg0 -n root || {
  print_error "Failed to create root LV"
  exit 1
}

print_info "  - VAR: ${var_size_int}G"
lvcreate -L ${var_size_int}G vg0 -n var || {
  print_error "Failed to create var LV"
  exit 1
}

print_info "  - USR: ${usr_size_int}G"
lvcreate -L ${usr_size_int}G vg0 -n usr || {
  print_error "Failed to create usr LV"
  exit 1
}

print_info "  - DATA: ${data_size_int}G"
lvcreate -L ${data_size_int}G vg0 -n data || {
  print_error "Failed to create data LV"
  exit 1
}

print_info "  - SWAP: ${swap_size_int}G"
lvcreate -L ${swap_size_int}G vg0 -n swap || {
  print_error "Failed to create swap LV"
  exit 1
}

# Create home with remaining space
print_info "  - HOME: remaining space"
lvcreate -l 100%FREE vg0 -n home || {
  print_error "Failed to create home LV"
  exit 1
}

check_success "Logical volumes created successfully." "Failed to create all logical volumes."

# Format filesystems
print_section "Creating Filesystems"

print_info "Formatting EFI partition..."
mkfs.fat -F32 $boot_part
check_success "EFI partition formatted successfully." "Failed to format EFI partition."

print_info "Formatting root partition..."
mkfs.ext4 /dev/vg0/root
check_success "Root partition formatted successfully." "Failed to format root partition."

print_info "Formatting home partition..."
mkfs.ext4 /dev/vg0/home
check_success "Home partition formatted successfully." "Failed to format home partition."

print_info "Formatting var partition..."
mkfs.ext4 /dev/vg0/var
check_success "Var partition formatted successfully." "Failed to format var partition."

print_info "Formatting usr partition..."
mkfs.ext4 /dev/vg0/usr
check_success "Usr partition formatted successfully." "Failed to format usr partition."

print_info "Formatting data partition..."
mkfs.ext4 /dev/vg0/data
check_success "Data partition formatted successfully." "Failed to format data partition."

print_info "Setting up swap..."
mkswap /dev/vg0/swap
swapon /dev/vg0/swap
check_success "Swap setup completed." "Failed to setup swap."

# Mount filesystems
print_section "Mounting Filesystems"
print_info "Mounting partitions..."

mount /dev/vg0/root /mnt
mkdir -p /mnt/{boot,home,var,usr,data}
mount $boot_part /mnt/boot
mount /dev/vg0/home /mnt/home
mount /dev/vg0/var /mnt/var
mount /dev/vg0/usr /mnt/usr
mount /dev/vg0/data /mnt/data
check_success "Partitions mounted successfully." "Failed to mount partitions."

# Install essential packages
print_section "Installing Base System"
print_info "Installing essential packages... This may take a while."
pacstrap /mnt base base-devel linux linux-firmware \
  lvm2 grub efibootmgr networkmanager \
  vim nano sudo cryptsetup

if [ "$desktop_env" != "none" ] && [ -n "$de_packages" ]; then
  print_info "Installing desktop environment: $desktop_env"
  pacstrap /mnt $de_packages xorg
  check_success "Desktop environment installed successfully." "Failed to install desktop environment."
fi

check_success "Base system installed successfully." "Failed to install base system."

# Generate fstab
print_section "Generating fstab"
genfstab -U /mnt >>/mnt/etc/fstab
check_success "fstab generated successfully." "Failed to generate fstab."

# Configure system
print_section "Configuring System"

# Create chroot script
cat >/mnt/root/chroot_setup.sh <<EOF
#!/bin/bash
set -e  # Exit on error

# Set timezone
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

# Set locale
echo "$locale UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$locale" > /etc/locale.conf

# Set keyboard layout
echo "KEYMAP=$kb_layout" > /etc/vconsole.conf

# Set hostname
read -p "Enter hostname for this system: " hostname
echo "\$hostname" > /etc/hostname

# Set up hosts file
cat > /etc/hosts << END
127.0.0.1    localhost
::1          localhost
127.0.1.1    \$hostname.localdomain    \$hostname
END

# Configure mkinitcpio
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect keyboard sd-vconsole modconf block sd-encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Set root password
echo "Set root password:"
passwd

# Create user
read -p "Enter username for new user: " username
useradd -m -G wheel -s /bin/bash "\$username"
echo "Set password for \$username:"
passwd "\$username"

# Configure sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Setup GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="cryptdevice=UUID=$(blkid -s UUID -o value $root_part):cryptlvm root=\/dev\/vg0\/root"/' /etc/default/grub

# Generate GRUB config
grub-mkconfig -o /boot/grub/grub.cfg

# Enable NetworkManager
systemctl enable NetworkManager

# Enable display manager if a desktop environment was selected
if [ -n "$de_service" ]; then
    echo "Enabling display manager $de_service..."
    systemctl enable $de_service
fi

# Final message
echo "Chroot setup complete!"
EOF

# Make the script executable
chmod +x /mnt/root/chroot_setup.sh

# Execute the script inside chroot
print_info "Running configuration script inside chroot..."
arch-chroot /mnt /root/chroot_setup.sh

# Clean up the script after execution
rm /mnt/root/chroot_setup.sh

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
