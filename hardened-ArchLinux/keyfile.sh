#!/bin/bash
# setup_sda2_keyfile.sh - Auto unlock encrypted sda2

set -e

ENCRYPTED_DEVICE="/dev/sda2"
KEYFILE_PATH="/etc/luks-keys/root.key"
CRYPT_NAME="cryptlvm" # Adjust if your mapping name is different

echo "=== Setting up keyfile for encrypted /dev/sda2 ==="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root"
  exit 1
fi

# Create keyfile directory
echo "Creating keyfile directory..."
mkdir -p /etc/luks-keys

# Generate keyfile
echo "Generating random keyfile..."
dd if=/dev/urandom of="$KEYFILE_PATH" bs=512 count=1
chmod 600 "$KEYFILE_PATH"
chown root:root "$KEYFILE_PATH"
echo "✓ Keyfile created: $KEYFILE_PATH"

# Add keyfile to LUKS
echo "Adding keyfile to LUKS partition $ENCRYPTED_DEVICE"
echo "You will be prompted for your current LUKS passphrase:"
if cryptsetup luksAddKey "$ENCRYPTED_DEVICE" "$KEYFILE_PATH"; then
  echo "✓ Keyfile added to LUKS"
else
  echo "✗ Failed to add keyfile to LUKS"
  exit 1
fi

# Backup original mkinitcpio.conf
cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.backup

# Configure mkinitcpio
echo "Configuring mkinitcpio..."
if grep -q "^FILES=" /etc/mkinitcpio.conf; then
  # FILES line exists, modify it
  if grep -q "FILES=.*$KEYFILE_PATH" /etc/mkinitcpio.conf; then
    echo "! Keyfile already in mkinitcpio.conf"
  else
    sed -i "s|^FILES=(|FILES=($KEYFILE_PATH |" /etc/mkinitcpio.conf
    echo "✓ Added keyfile to FILES in mkinitcpio.conf"
  fi
else
  # Add FILES line
  echo "FILES=($KEYFILE_PATH)" >>/etc/mkinitcpio.conf
  echo "✓ Added FILES line with keyfile to mkinitcpio.conf"
fi

# Rebuild initramfs
echo "Rebuilding initramfs..."
mkinitcpio -p linux
echo "✓ initramfs rebuilt"

# Backup original GRUB config
cp /etc/default/grub /etc/default/grub.backup

# Configure GRUB
echo "Configuring GRUB..."
CRYPTKEY_PARAM="cryptkey=rootfs:$KEYFILE_PATH"

if grep -q "cryptkey=" /etc/default/grub; then
  echo "! cryptkey already configured in GRUB"
else
  # Add cryptkey parameter
  sed -i "s|GRUB_CMDLINE_LINUX=\"|GRUB_CMDLINE_LINUX=\"$CRYPTKEY_PARAM |" /etc/default/grub
  echo "✓ Added cryptkey parameter to GRUB"
fi

# Update GRUB
echo "Updating GRUB configuration..."
grub-mkconfig -o /boot/grub/grub.cfg
echo "✓ GRUB configuration updated"

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "Your system should now unlock /dev/sda2 automatically on boot."
echo ""
echo "What was done:"
echo "  1. Created keyfile: $KEYFILE_PATH"
echo "  2. Added keyfile to LUKS keyslot on $ENCRYPTED_DEVICE"
echo "  3. Embedded keyfile in initramfs"
echo "  4. Added cryptkey parameter to GRUB"
echo ""
echo "IMPORTANT NOTES:"
echo "  - Your original passphrase still works (keep it as backup!)"
echo "  - Reboot to test the automatic unlock"
echo "  - If something goes wrong, you can still unlock with your passphrase"
echo ""
echo "To verify setup:"
echo "  cryptsetup luksDump $ENCRYPTED_DEVICE"
echo ""
echo "Backup files created:"
echo "  /etc/mkinitcpio.conf.backup"
echo "  /etc/default/grub.backup"
