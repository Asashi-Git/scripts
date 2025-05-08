#!/bin/bash

# ╔═══════════════════════════════════════════════════════════════════╗
# ║  Arch Linux Installation Script with Hardening                    ║
# ║  Based on the Arch Linux Manual Install and Hardening docs        ║
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
    read -p "${CYAN}${prompt} [y/n]:${NC} " response
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
# │ Welcome message                                                  │
# └─────────────────────────────────────────────────────────────────┘
clear
echo
echo -e "${BRIGHT_BLUE}${BOLD} █████╗ ██████╗  ██████╗██╗  ██╗    ██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗${NC}"
echo -e "${BRIGHT_BLUE}${BOLD}██╔══██╗██╔══██╗██╔════╝██║  ██║    ██║     ██║████╗  ██║██║   ██║╚██╗██╔╝${NC}"
echo -e "${BRIGHT_BLUE}${BOLD}███████║██████╔╝██║     ███████║    ██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝ ${NC}"
echo -e "${BRIGHT_BLUE}${BOLD}██╔══██║██╔══██╗██║     ██╔══██║    ██║     ██║██║╚██╗██║██║   ██║ ██╔██╗ ${NC}"
echo -e "${BRIGHT_BLUE}${BOLD}██║  ██║██║  ██║╚██████╗██║  ██║    ███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗${NC}"
echo -e "${BRIGHT_BLUE}${BOLD}╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝    ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝${NC}"
echo
echo -e "${MAGENTA}"
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

echo
print_info "This script will guide you through installing Arch Linux with encryption and security hardening."
print_warning "This script will erase all data on the target disk. Make sure you have backups!"
echo -e "${YELLOW}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# ┌─────────────────────────────────────────────────────────────────┐
# │ Confirm before proceeding                                        │
# └─────────────────────────────────────────────────────────────────┘
if ! confirm "Do you want to continue?"; then
  echo -e "${RED}${BOLD}Installation aborted by user.${NC}"
  exit 0
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ Keyboard layout selection                                        │
# └─────────────────────────────────────────────────────────────────┘
print_section "Keyboard Layout Configuration"
echo -e "${CYAN}Available keyboard layouts:${NC}"
echo -e "${CYAN}┌───────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC} 1) us - US English (default)"
echo -e "${CYAN}│${NC} 2) uk - United Kingdom"
echo -e "${CYAN}│${NC} 3) de - German"
echo -e "${CYAN}│${NC} 4) fr - French"
echo -e "${CYAN}│${NC} 5) es - Spanish"
echo -e "${CYAN}│${NC} 6) it - Italian"
echo -e "${CYAN}│${NC} 7) Other (specify manually)"
echo -e "${CYAN}└───────────────────────────────────────┘${NC}"

read -p "$(echo -e ${CYAN}"Select your keyboard layout [1-7]: "${NC})" kb_choice

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
  read -p "$(echo -e ${CYAN}"Enter keyboard layout from the list above: "${NC})" kb_layout
  ;;
*)
  echo -e "${YELLOW}Invalid choice. Defaulting to US layout.${NC}"
  kb_layout="us"
  ;;
esac

print_info "Setting keyboard layout to ${kb_layout}..."
loadkeys $kb_layout

# ┌─────────────────────────────────────────────────────────────────┐
# │ Display available disks                                          │
# └─────────────────────────────────────────────────────────────────┘
print_section "Storage Configuration"
echo -e "${CYAN}Available disks:${NC}"
echo -e "${CYAN}┌──────────────────────────────────────────────────────────┐${NC}"
lsblk -d -o NAME,SIZE,MODEL
echo -e "${CYAN}└──────────────────────────────────────────────────────────┘${NC}"
echo

# ┌─────────────────────────────────────────────────────────────────┐
# │ Get disk selection                                               │
# └─────────────────────────────────────────────────────────────────┘
read -p "$(echo -e ${CYAN}"Enter the disk to install Arch Linux on (e.g., vda, sda): "${NC})" disk
disk_path="/dev/${disk}"

if [ ! -b "$disk_path" ]; then
  print_error "The specified disk $disk_path does not exist."
  exit 1
fi

print_warning "All data on $disk_path will be erased!"
if ! confirm "Are you sure you want to continue?"; then
  echo -e "${RED}${BOLD}Installation aborted by user.${NC}"
  exit 0
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ Display current partition layout                                 │
# └─────────────────────────────────────────────────────────────────┘
print_info "Current partition layout:"
echo -e "${CYAN}┌──────────────────────────────────────────────────────────┐${NC}"
lsblk $disk_path
echo -e "${CYAN}└──────────────────────────────────────────────────────────┘${NC}"

# ┌─────────────────────────────────────────────────────────────────┐
# │ Create partitions                                                │
# └─────────────────────────────────────────────────────────────────┘
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

# ┌─────────────────────────────────────────────────────────────────┐
# │ Setup encryption                                                 │
# └─────────────────────────────────────────────────────────────────┘
print_section "Setting up Encryption"
print_warning "You will be asked to enter an encryption passphrase. DO NOT FORGET THIS PASSPHRASE!"
echo -e "${YELLOW}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

cryptsetup luksFormat --type luks2 ${disk_path}2
check_success "Encrypted container created successfully." "Failed to create encrypted container."

print_info "Opening encrypted container..."
cryptsetup open ${disk_path}2 cryptlvm
check_success "Encrypted container opened successfully." "Failed to open encrypted container."

# ┌─────────────────────────────────────────────────────────────────┐
# │ Setup LVM                                                        │
# └─────────────────────────────────────────────────────────────────┘
print_section "Setting up LVM"
print_info "Creating physical volume..."
pvcreate /dev/mapper/cryptlvm
check_success "Physical volume created successfully." "Failed to create physical volume."

print_info "Creating volume group..."
vgcreate vg0 /dev/mapper/cryptlvm
check_success "Volume group created successfully." "Failed to create volume group."

# ┌─────────────────────────────────────────────────────────────────┐
# │ Get partition sizes from user                                    │
# └─────────────────────────────────────────────────────────────────┘
print_info "Setting up logical volumes. Please specify sizes for each partition."
echo -e "${CYAN}┌──────────────────────────────────────────────────────────┐${NC}"
read -p "$(echo -e ${CYAN}"Size for ROOT partition (e.g., 20G): "${NC})" root_size
read -p "$(echo -e ${CYAN}"Size for VAR partition (e.g., 15G): "${NC})" var_size
read -p "$(echo -e ${CYAN}"Size for USR partition (e.g., 20G): "${NC})" usr_size
read -p "$(echo -e ${CYAN}"Size for DATA partition (e.g., 10G): "${NC})" data_size
read -p "$(echo -e ${CYAN}"Size for HOME partition (e.g., 30G): "${NC})" home_size
read -p "$(echo -e ${CYAN}"Size for SWAP partition (e.g., 8G): "${NC})" swap_size
echo -e "${CYAN}└──────────────────────────────────────────────────────────┘${NC}"

print_info "Creating logical volumes with specified sizes..."
lvcreate -L $root_size vg0 -n root
lvcreate -L $var_size vg0 -n var
lvcreate -L $usr_size vg0 -n usr
lvcreate -L $data_size vg0 -n data
lvcreate -L $home_size vg0 -n home
lvcreate -L $swap_size vg0 -n swap

check_success "Logical volumes created successfully." "Failed to create logical volumes."

# ┌─────────────────────────────────────────────────────────────────┐
# │ Get mount options from user                                      │
# └─────────────────────────────────────────────────────────────────┘
print_info "Choose mount options for each partition"
echo -e "${CYAN}┌──────────────────────────────────────────────────────────┐${NC}"
read -p "$(echo -e ${CYAN}"Mount options for /boot (default: nosuid,nodev,noexec): "${NC})" boot_options
boot_options=${boot_options:-nosuid,nodev,noexec}

read -p "$(echo -e ${CYAN}"Mount options for /home (default: nosuid,nodev,noexec): "${NC})" home_options
home_options=${home_options:-nosuid,nodev,noexec}

read -p "$(echo -e ${CYAN}"Mount options for /var (default: nosuid,nodev,noexec): "${NC})" var_options
var_options=${var_options:-nosuid,nodev,noexec}

read -p "$(echo -e ${CYAN}"Mount options for /usr (default: nodev): "${NC})" usr_options
usr_options=${usr_options:-nodev}

read -p "$(echo -e ${CYAN}"Mount options for /data (default: defaults): "${NC})" data_options
data_options=${data_options:-defaults}
echo -e "${CYAN}└──────────────────────────────────────────────────────────┘${NC}"

# ┌─────────────────────────────────────────────────────────────────┐
# │ Format partitions                                                │
# └─────────────────────────────────────────────────────────────────┘
print_info "Formatting partitions..."
mkfs.ext4 /dev/vg0/root
mkfs.ext4 /dev/vg0/var
mkfs.ext4 /dev/vg0/usr
mkfs.ext4 /dev/vg0/data
mkfs.ext4 /dev/vg0/home
mkswap /dev/vg0/swap

check_success "Partitions formatted successfully." "Failed to format partitions."

# ┌─────────────────────────────────────────────────────────────────┐
# │ Mount partitions                                                 │
# └─────────────────────────────────────────────────────────────────┘
print_section "Mounting Partitions"
print_info "Mounting partitions with specified options..."

mount /dev/vg0/root /mnt
mkdir -p /mnt/{boot,home,var,usr,data}
mount ${disk_path}1 /mnt/boot -o $boot_options
mount /dev/vg0/home /mnt/home -o $home_options
mount /dev/vg0/var /mnt/var -o $var_options
mount /dev/vg0/usr /mnt/usr -o $usr_options
mount /dev/vg0/data /mnt/data -o $data_options
swapon /dev/vg0/swap

check_success "Partitions mounted successfully." "Failed to mount partitions."

# ┌─────────────────────────────────────────────────────────────────┐
# │ Install base packages                                            │
# └─────────────────────────────────────────────────────────────────┘
print_section "Installing Base System"

# Get additional packages from user
read -p "$(echo -e ${CYAN}"Enter additional packages to install (space-separated): "${NC})" additional_packages
base_packages="base base-devel nano vim networkmanager lvm2 cryptsetup grub efibootmgr linux linux-firmware sof-firmware $additional_packages"

# ┌─────────────────────────────────────────────────────────────────┐
# │ Desktop Environment Selection                                    │
# └─────────────────────────────────────────────────────────────────┘
print_section "Desktop Environment"
echo -e "${CYAN}Would you like to install a desktop environment?${NC}"
echo -e "${CYAN}┌───────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC} 1) None (console only)"
echo -e "${CYAN}│${NC} 2) GNOME"
echo -e "${CYAN}│${NC} 3) KDE Plasma"
echo -e "${CYAN}│${NC} 4) Xfce"
echo -e "${CYAN}│${NC} 5) MATE"
echo -e "${CYAN}│${NC} 6) i3 (minimal window manager)"
echo -e "${CYAN}└───────────────────────────────────────┘${NC}"

read -p "$(echo -e ${CYAN}"Select a desktop environment [1-6]: "${NC})" de_choice

case $de_choice in
1) de_packages="" ;;
2)
  de_packages="gnome gnome-extra gdm"
  de_service="gdm"
  ;;
3)
  de_packages="plasma kde-applications sddm"
  de_service="sddm"
  ;;
4)
  de_packages="xfce4 xfce4-goodies lightdm lightdm-gtk-greeter"
  de_service="lightdm"
  ;;
5)
  de_packages="mate mate-extra lightdm lightdm-gtk-greeter"
  de_service="lightdm"
  ;;
6)
  de_packages="i3-wm i3status i3lock dmenu lightdm lightdm-gtk-greeter xorg-server xorg-xinit"
  de_service="lightdm"
  ;;
*)
  de_packages=""
  de_service=""
  ;;
esac

if [ -n "$de_packages" ]; then
  print_info "Adding desktop environment packages: $de_packages"
  base_packages="$base_packages $de_packages"
fi

print_info "Installing base packages: $base_packages"
pacstrap /mnt $base_packages

check_success "Base system installed successfully." "Failed to install base system."

# ┌─────────────────────────────────────────────────────────────────┐
# │ Generate fstab                                                   │
# └─────────────────────────────────────────────────────────────────┘
print_section "Generating fstab"
print_info "Generating fstab..."
genfstab -U /mnt >/mnt/etc/fstab.new

# Show fstab to user
echo -e "\n${YELLOW}Generated fstab:${NC}"
echo -e "${CYAN}┌──────────────────────────────────────────────────────────┐${NC}"
cat /mnt/etc/fstab.new
echo -e "${CYAN}└──────────────────────────────────────────────────────────┘${NC}"
echo

# Confirm fstab looks good
if confirm "Does the fstab look correct?"; then
  mv /mnt/etc/fstab.new /mnt/etc/fstab
  print_info "fstab saved."
else
  print_info "You can edit the fstab manually after installation."
  exit 1
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ Chroot configuration                                             │
# └─────────────────────────────────────────────────────────────────┘
print_section "Configuring System"

# ┌─────────────────────────────────────────────────────────────────┐
# │ Create a script to run inside the chroot environment             │
# └─────────────────────────────────────────────────────────────────┘
# Pass the disk variable and keyboard layout to the chroot
cat >/mnt/root/chroot_setup.sh <<EOF
#!/bin/bash

# ┌─────────────────────────────────────────────────────────────────┐
# │ Pass the variables to the chroot                                 │
# └─────────────────────────────────────────────────────────────────┘
disk="${disk}"
disk_path="/dev/\${disk}"
de_service="${de_service}"
kb_layout="${kb_layout}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to print section headers
print_section() {
    echo -e "\n\${BLUE}\${BOLD}╔════════════ \$1 ════════════╗\${NC}\n"
}

# Function to print info messages
print_info() {
    echo -e "\${GREEN}\${BOLD}[INFO]\${NC} \$1"
}

# Function to print warnings
print_warning() {
    echo -e "\${YELLOW}\${BOLD}[WARNING]\${NC} \$1"
}

# Configure keyboard layout
print_info "Setting system keyboard layout to \${kb_layout}..."
echo "KEYMAP=\${kb_layout}" > /etc/vconsole.conf

# Configure mkinitcpio
print_info "Configuring mkinitcpio..."
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems fsck usr)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Timezone selection
print_info "Setting timezone..."
# List available regions
echo "Available regions:"
ls -1 /usr/share/zoneinfo | grep -v posix | grep -v right
read -p "Enter your region: " region

if [ -d "/usr/share/zoneinfo/\$region" ]; then
    echo "Cities in \$region:"
    ls -1 /usr/share/zoneinfo/\$region
    read -p "Enter your city: " city
    
    if [ -f "/usr/share/zoneinfo/\$region/\$city" ]; then
        ln -sf /usr/share/zoneinfo/\$region/\$city /etc/localtime
        echo "Timezone set to \$region/\$city"
    else
        echo "Invalid city. Setting default timezone (UTC)."
        ln -sf /usr/share/zoneinfo/UTC /etc/localtime
    fi
else
    echo "Invalid region. Setting default timezone (UTC)."
    ln -sf /usr/share/zoneinfo/UTC /etc/localtime
fi

hwclock --systohc

# Language selection
print_info "Configuring locale..."
echo "Available locales (abbreviated list):"
echo "1) en_US.UTF-8 - English (US)"
echo "2) fr_FR.UTF-8 - French"
echo "3) de_DE.UTF-8 - German"
echo "4) es_ES.UTF-8 - Spanish"
echo "5) it_IT.UTF-8 - Italian"
echo "6) ja_JP.UTF-8 - Japanese"
echo "7) Other (specify manually)"

read -p "Select your preferred locale [1-7]: " locale_choice

case \$locale_choice in
    1) locale="en_US.UTF-8" ;;
    2) locale="fr_FR.UTF-8" ;;
    3) locale="de_DE.UTF-8" ;;
    4) locale="es_ES.UTF-8" ;;
    5) locale="it_IT.UTF-8" ;;
    6) locale="ja_JP.UTF-8" ;;
    7) 
        read -p "Enter locale (format: xx_XX.UTF-8): " locale
        ;;
    *) 
        echo "Invalid choice. Defaulting to en_US.UTF-8"
        locale="en_US.UTF-8"
        ;;
esac

echo "\$locale UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=\$locale" > /etc/locale.conf

# Set hostname
read -p "Enter hostname for this system: " hostname
echo "\$hostname" > /etc/hostname

# Set root password
print_info "Setting root password..."
passwd

# Create user
read -p "Enter username for new user: " username
useradd -m -G wheel -s /bin/bash "\$username"
print_info "Setting password for \$username..."
passwd "\$username"

# Configure sudo
print_info "Configuring sudo..."
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
echo "\$username ALL=(ALL:ALL) ALL" >> /etc/sudoers.d/\$username

# Configure sudo logging
print_info "Configuring sudo logging..."
echo "Defaults logfile=/var/log/sudo.log" >> /etc/sudoers.d/logging

# Configure GRUB
print_info "Installing GRUB bootloader..."
grub-install --efi-directory=/boot --bootloader-id=GRUB

# Get UUID for encrypted device - now using the dynamic disk path
encrypted_uuid=\$(blkid -o value -s UUID \${disk_path}2)
print_info "Found encrypted device UUID: \${encrypted_uuid}"

# Configure GRUB for encrypted boot
sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet cryptdevice=UUID=\${encrypted_uuid}:cryptlvm root=\/dev\/vg0\/root\"/" /etc/default/grub

# Generate GRUB config
grub-mkconfig -o /boot/grub/grub.cfg

# Enable NetworkManager
print_info "Enabling NetworkManager..."
systemctl enable NetworkManager

# Enable display manager if a desktop environment was selected
if [ -n "\$de_service" ]; then
    print_info "Enabling display manager \$de_service..."
    systemctl enable \$de_service
fi

# Final message
print_info "Chroot setup complete!"
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
echo
cat <<"EOF"

   █████╗ ██████╗  ██████╗██╗  ██╗    ██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗
  ██╔══██╗██╔══██╗██╔════╝██║  ██║    ██║     ██║████╗  ██║██║   ██║╚██╗██╔╝
  ███████║██████╔╝██║     ███████║    ██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝ 
  ██╔══██║██╔══██╗██║     ██╔══██║    ██║     ██║██║╚██╗██║██║   ██║ ██╔██╗ 
  ██║  ██║██║  ██║╚██████╗██║  ██║    ███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗
  ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝    ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝
                                                                            
    ██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗     ███████╗██████╗   
    ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     ██╔════╝██╔══██╗  
    ██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║     █████╗  ██████╔╝  
    ██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     ██╔══╝  ██╔══██╗  
    ██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗███████╗██║  ██║  
    ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝  

EOF
echo
cat <<"EOF"
$(tput setaf 5)
    ██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗      █████╗ ████████╗██╗ ██████╗ ███╗   ██╗
    ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     ██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║
    ██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║     ███████║   ██║   ██║██║   ██║██╔██╗ ██║
    ██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     ██╔══██║   ██║   ██║██║   ██║██║╚██╗██║
    ██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║
    ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝
                                                                                                  
     ██████╗ ██████╗ ███╗   ███╗██████╗ ██╗     ███████╗████████╗███████╗    ██╗                 
    ██╔════╝██╔═══██╗████╗ ████║██╔══██╗██║     ██╔════╝╚══██╔══╝██╔════╝    ██║                 
    ██║     ██║   ██║██╔████╔██║██████╔╝██║     █████╗     ██║   █████╗      ██║                 
    ██║     ██║   ██║██║╚██╔╝██║██╔═══╝ ██║     ██╔══╝     ██║   ██╔══╝      ╚═╝                 
    ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║     ███████╗███████╗   ██║   ███████╗    ██╗                 
     ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚══════╝╚══════╝   ╚═╝   ╚══════╝    ╚═╝                 
$(tput sgr0)
EOF
echo
print_info "Arch Linux has been installed with encryption and hardening."
print_info "You can now reboot your system and remove the installation media."
print_info "After reboot, you'll need to enter the disk encryption password."

if confirm "Would you like to reboot now?"; then
  print_info "Rebooting..."
  reboot
else
  print_info "You can reboot manually when ready."
fi
