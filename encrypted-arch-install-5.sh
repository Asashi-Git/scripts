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
loadkeys $kb_layout
print_info "Keyboard layout set to $kb_layout"

# Timezone selection
print_section "Timezone Configuration"
echo "Common timezones:"
echo "1) America/New_York"
echo "2) America/Chicago"
echo "3) America/Denver"
echo "4) America/Los_Angeles"
echo "5) Europe/London"
echo "6) Europe/Paris"
echo "7) Europe/Berlin"
echo "8) Asia/Tokyo"
echo "9) Australia/Sydney"
echo "10) Other (select from full list)"

read -p "Select your timezone [1-10]: " tz_choice

case $tz_choice in
1) timezone="America/New_York" ;;
2) timezone="America/Chicago" ;;
3) timezone="America/Denver" ;;
4) timezone="America/Los_Angeles" ;;
5) timezone="Europe/London" ;;
6) timezone="Europe/Paris" ;;
7) timezone="Europe/Berlin" ;;
8) timezone="Asia/Tokyo" ;;
9) timezone="Australia/Sydney" ;;
10)
  # Show timezone list
  timedatectl list-timezones
  read -p "Enter your timezone from the list above: " timezone
  ;;
*)
  echo "Invalid choice. Defaulting to UTC."
  timezone="UTC"
  ;;
esac

print_info "Timezone set to $timezone"

# Locale selection
print_section "Locale Configuration"
echo "Common locales:"
echo "1) en_US.UTF-8 - US English (default)"
echo "2) en_GB.UTF-8 - British English"
echo "3) de_DE.UTF-8 - German"
echo "4) fr_FR.UTF-8 - French"
echo "5) es_ES.UTF-8 - Spanish"
echo "6) it_IT.UTF-8 - Italian"
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
  cat /etc/locale.gen | grep -v "#" | grep UTF-8
  read -p "Enter locale from the list above: " locale
  ;;
*)
  echo "Invalid choice. Defaulting to en_US.UTF-8."
  locale="en_US.UTF-8"
  ;;
esac

print_info "Locale set to $locale"

# Desktop Environment Selection
print_section "Desktop Environment Selection"
echo "Available desktop environments:"
echo "1) None (CLI only)"
echo "2) GNOME"
echo "3) KDE Plasma"
echo "4) Xfce"
echo "5) Cinnamon"
echo "6) MATE"

read -p "Select desktop environment [1-6]: " de_choice

case $de_choice in
1)
  desktop_env="none"
  de_packages=""
  de_service=""
  ;;
2)
  desktop_env="GNOME"
  de_packages="gnome gnome-extra gdm"
  de_service="gdm.service"
  ;;
3)
  desktop_env="KDE Plasma"
  de_packages="plasma kde-applications sddm"
  de_service="sddm.service"
  ;;
4)
  desktop_env="Xfce"
  de_packages="xfce4 xfce4-goodies lightdm lightdm-gtk-greeter"
  de_service="lightdm.service"
  ;;
5)
  desktop_env="Cinnamon"
  de_packages="cinnamon lightdm lightdm-gtk-greeter"
  de_service="lightdm.service"
  ;;
6)
  desktop_env="MATE"
  de_packages="mate mate-extra lightdm lightdm-gtk-greeter"
  de_service="lightdm.service"
  ;;
*)
  echo "Invalid choice. Defaulting to CLI only."
  desktop_env="none"
  de_packages=""
  de_service=""
  ;;
esac

if [ "$desktop_env" != "none" ]; then
  print_info "Desktop environment set to $desktop_env"
else
  print_info "No desktop environment selected (CLI only)"
fi

# Check network connectivity
print_section "Checking Network Connection"
if ping -c 1 archlinux.org &>/dev/null; then
  print_info "Network is working."
else
  print_error "No network connection. Please configure your network and try again."
  exit 1
fi

# Update system clock
print_section "Setting up System Clock"
timedatectl set-ntp true
check_success "System clock synchronized." "Failed to synchronize system clock."

# Select disk
print_section "Disk Selection"
print_info "Available disks:"
lsblk -o NAME,SIZE,TYPE,MODEL | grep -v loop | grep disk
echo

read -p "Enter the disk to install Arch Linux on (e.g., sda, nvme0n1): " disk_name

# Validate disk exists
if [ ! -b "/dev/${disk_name}" ] && [ ! -b "/dev/${disk_name}" ]; then
  print_error "Disk /dev/${disk_name} does not exist."
  exit 1
fi

# Format disk path depending on device type
if [[ $disk_name == nvme* ]]; then
  disk="/dev/${disk_name}"
  boot_part="/dev/${disk_name}p1"
  root_part="/dev/${disk_name}p2"
else
  disk="/dev/${disk_name}"
  boot_part="/dev/${disk_name}1"
  root_part="/dev/${disk_name}2"
fi

print_info "Selected disk: $disk"
print_warning "ALL DATA ON $disk WILL BE ERASED!"
if ! confirm "Are you sure you want to continue?"; then
  echo "Installation aborted by user."
  exit 0
fi

# Partition sizes
print_section "Configuring Partition Sizes"

# Calculate default root partition size based on available disk space
disk_size_kb=$(blockdev --getsize64 $disk)
disk_size_gb=$(echo "scale=2; $disk_size_kb / (1024*1024*1024)" | bc)
print_info "Disk size: ${disk_size_gb}GB"

# Set default sizes
default_boot_size="500M"
mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
mem_total_gb=$(echo "scale=2; $mem_total_kb / (1024*1024)" | bc)
default_swap_size="${mem_total_gb}G" # Match RAM size

# Calculate remaining space after boot for LVM partitioning
remaining_space_gb=$(echo "$disk_size_gb - 0.5" | bc) # Subtract boot partition

# Default LVM sizes
default_root_size="20G"
default_var_size="10G"
default_usr_size="10G"
default_data_size="10G"
default_home_size="remaining" # Will be calculated to use remaining space

print_info "Suggested partition sizes:"
echo "  - Boot: ${default_boot_size}"
echo "  - Swap: ${default_swap_size} (matches your RAM)"
echo "  - Root: ${default_root_size}"
echo "  - Var: ${default_var_size}"
echo "  - Usr: ${default_usr_size}"
echo "  - Data: ${default_data_size}"
echo "  - Home: remaining space"

if confirm "Would you like to use these default sizes?"; then
  boot_size=$default_boot_size
  swap_size=$default_swap_size
  root_size=$default_root_size
  var_size=$default_var_size
  usr_size=$default_usr_size
  data_size=$default_data_size
  home_size=$default_home_size
else
  read -p "Enter Boot partition size [${default_boot_size}]: " boot_size
  boot_size=${boot_size:-$default_boot_size}

  read -p "Enter Swap partition size [${default_swap_size}]: " swap_size
  swap_size=${swap_size:-$default_swap_size}

  read -p "Enter Root partition size [${default_root_size}]: " root_size
  root_size=${root_size:-$default_root_size}

  read -p "Enter Var partition size [${default_var_size}]: " var_size
  var_size=${var_size:-$default_var_size}

  read -p "Enter Usr partition size [${default_usr_size}]: " usr_size
  usr_size=${usr_size:-$default_usr_size}

  read -p "Enter Data partition size [${default_data_size}]: " data_size
  data_size=${data_size:-$default_data_size}

  print_info "Home partition will use remaining space"
  home_size="remaining"
fi

# Partition the drive
print_section "Partitioning Disk"
print_info "Creating partition table..."
parted -s $disk mklabel gpt
check_success "GPT partition table created." "Failed to create GPT partition table."

print_info "Creating boot partition..."
parted -s $disk mkpart "EFI" fat32 1MiB $boot_size
parted -s $disk set 1 esp on
check_success "Boot partition created." "Failed to create boot partition."

print_info "Creating root partition..."
parted -s $disk mkpart "cryptlvm" ext4 $boot_size 100%
check_success "Root partition created." "Failed to create root partition."

print_info "Partitioning completed. Disk layout:"
parted -s $disk print
fdisk -l $disk

# Format the boot partition
print_section "Formatting Boot Partition"
print_info "Creating FAT32 filesystem on boot partition..."
mkfs.fat -F32 $boot_part
check_success "Boot partition formatted." "Failed to format boot partition."

# Setup encryption
print_section "Setting up Disk Encryption"
print_info "Initializing LUKS encryption on root partition..."
print_warning "You will be prompted to enter and confirm a passphrase for disk encryption."
print_warning "REMEMBER THIS PASSPHRASE! You will need it to boot your system."
echo

# Create LUKS container
cryptsetup luksFormat --type luks2 $root_part
check_success "LUKS encryption initialized." "Failed to initialize LUKS encryption."

# Open the LUKS container
print_info "Opening LUKS container..."
cryptsetup open $root_part cryptlvm
check_success "LUKS container opened." "Failed to open LUKS container."

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

# Format the logical volumes
print_section "Formatting Logical Volumes"

print_info "Formatting root partition..."
mkfs.ext4 /dev/vg0/root
check_success "Root partition formatted." "Failed to format root partition."

print_info "Formatting home partition..."
mkfs.ext4 /dev/vg0/home
check_success "Home partition formatted." "Failed to format home partition."

print_info "Formatting var partition..."
mkfs.ext4 /dev/vg0/var
check_success "Var partition formatted." "Failed to format var partition."

print_info "Formatting usr partition..."
mkfs.ext4 /dev/vg0/usr
check_success "Usr partition formatted." "Failed to format usr partition."

print_info "Formatting data partition..."
mkfs.ext4 /dev/vg0/data
check_success "Data partition formatted." "Failed to format data partition."

print_info "Creating swap..."
mkswap /dev/vg0/swap
check_success "Swap created." "Failed to create swap."

# Mount filesystems
print_section "Mounting Filesystems"

print_info "Mounting root partition..."
mount /dev/vg0/root /mnt
check_success "Root partition mounted." "Failed to mount root partition."

print_info "Creating directory structure..."
mkdir -p /mnt/{boot,home,var,usr,data}
check_success "Directory structure created." "Failed to create directory structure."

print_info "Mounting other partitions..."
mount $boot_part /mnt/boot
mount /dev/vg0/home /mnt/home
mount /dev/vg0/var /mnt/var
mount /dev/vg0/usr /mnt/usr
mount /dev/vg0/data /mnt/data
swapon /dev/vg0/swap
check_success "All partitions mounted." "Failed to mount some partitions."

# Install base packages
print_section "Installing Base System"

if [ "$desktop_env" != "none" ]; then
  print_info "Installing base packages with desktop environment ($desktop_env)..."
  pacstrap /mnt base linux linux-firmware base-devel lvm2 networkmanager grub efibootmgr vim nano mkinitcpio sudo $de_packages
else
  print_info "Installing base packages (CLI only)..."
  pacstrap /mnt base linux linux-firmware base-devel lvm2 networkmanager grub efibootmgr vim nano mkinitcpio sudo
fi

check_success "Base system installed." "Failed to install base system."

# Generate fstab
print_section "Generating fstab"
genfstab -U /mnt >>/mnt/etc/fstab
check_success "fstab generated." "Failed to generate fstab."

# Configure system
print_section "Configuring System"

# Create chroot script
cat >/mnt/root/chroot_setup.sh <<EOF
#!/bin/bash
set -e  # Exit on error

# Variables passed from main script
ROOT_PARTITION="$root_part"

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

# Get UUID for encrypted device
LUKS_UUID=\$(blkid -s UUID -o value \$ROOT_PARTITION)
echo "Found LUKS UUID: \$LUKS_UUID"

# Setup GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
# Use the correct UUID in GRUB configuration
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\$LUKS_UUID:cryptlvm root=/dev/vg0/root\"|" /etc/default/grub

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
