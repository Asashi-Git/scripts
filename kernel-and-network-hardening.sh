#!/bin/bash

# Kernel and Network Hardening Script for Arch Linux
# This script:
# 1. Sets up network security parameters
# 2. Implements kernel hardening
# 3. Configures file system and memory protection
# 4. Creates symbolic link for UFW compatibility
# 5. Verifies all settings have been applied

# Check if script is run with root privileges
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi

# Default settings
BACKUP_DIR="/root/sysctl_backup"
NETWORK_CONF="/etc/sysctl.d/90-network-security.conf"
KERNEL_CONF="/etc/sysctl.d/91-kernel-hardening.conf"
FS_MEM_CONF="/etc/sysctl.d/92-fs-memory-protection.conf"
SYSCTL_CONF="/etc/sysctl.conf"

# Create backup directory
mkdir -p $BACKUP_DIR

echo "===== Kernel and Network Hardening ====="

# Function to backup a file before modifying
backup_file() {
  local file=$1
  local backup="${BACKUP_DIR}/$(basename ${file}).bak.$(date +%Y%m%d%H%M%S)"

  # Only backup if file exists
  if [ -f "$file" ]; then
    cp "$file" "$backup"
    echo "✓ Backed up $file to $backup"
  fi
}

# Step 1: Configure Network Security Settings
echo -e "\n[1/5] Setting up network security parameters..."

# Backup existing config if it exists
backup_file "$NETWORK_CONF"

# Create/overwrite network security configuration
cat >"$NETWORK_CONF" <<'EOF'
# Network Security Settings
# Created by kernel hardening script on $(date)

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
EOF

echo "✓ Network security parameters configured."

# Step 2: Configure Kernel Hardening Settings
echo -e "\n[2/5] Implementing kernel hardening..."

# Backup existing config if it exists
backup_file "$KERNEL_CONF"

# Create/overwrite kernel hardening configuration
cat >"$KERNEL_CONF" <<'EOF'
# Kernel Hardening Settings
# Created by kernel hardening script on $(date)

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

echo "✓ Kernel hardening parameters configured."

# Step 3: Configure File System and Memory Protection
echo -e "\n[3/5] Setting up file system and memory protection..."

# Backup existing config if it exists
backup_file "$FS_MEM_CONF"

# Create/overwrite file system and memory protection configuration
cat >"$FS_MEM_CONF" <<'EOF'
# File System and Memory Protection Settings
# Created by kernel hardening script on $(date)

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

echo "✓ File system and memory protection parameters configured."

# Step 4: Create symbolic link for UFW compatibility
echo -e "\n[4/5] Setting up UFW compatibility..."

# Check if /etc/sysctl.conf exists, if so backup and remove
if [ -f "$SYSCTL_CONF" ]; then
  if [ -L "$SYSCTL_CONF" ]; then
    echo "Existing symbolic link detected at $SYSCTL_CONF"
    backup_file "$SYSCTL_CONF"
    rm "$SYSCTL_CONF"
    echo "✓ Removed existing symbolic link"
  else
    echo "Existing file detected at $SYSCTL_CONF"
    backup_file "$SYSCTL_CONF"
    rm "$SYSCTL_CONF"
    echo "✓ Backed up and removed the existing file"
  fi
fi

# Create symbolic link for UFW compatibility
ln -s "$NETWORK_CONF" "$SYSCTL_CONF"
echo "✓ Created symbolic link from $NETWORK_CONF to $SYSCTL_CONF for UFW compatibility"

# If UFW is installed, check its configuration
if command -v ufw >/dev/null 2>&1; then
  echo "UFW is installed. Checking configuration..."

  if [ -f "/etc/default/ufw" ]; then
    # Check if IPT_SYSCTL is already set to /etc/sysctl.conf
    if grep -q "^IPT_SYSCTL=/etc/sysctl.conf" "/etc/default/ufw"; then
      echo "✓ UFW is already configured to use /etc/sysctl.conf"
    else
      # Backup UFW config
      backup_file "/etc/default/ufw"

      # Update IPT_SYSCTL in UFW config
      sed -i 's|^IPT_SYSCTL=.*|IPT_SYSCTL=/etc/sysctl.conf|' "/etc/default/ufw"
      echo "✓ Updated UFW configuration to use /etc/sysctl.conf"
    fi
  else
    echo "⚠ UFW is installed but the config file was not found at /etc/default/ufw"
  fi
else
  echo "ℹ UFW is not installed. No UFW configuration needed."
fi

# Step 5: Apply and Verify Settings
echo -e "\n[5/5] Applying and verifying settings..."

# Apply all sysctl settings
echo "Applying sysctl settings..."
sysctl --system

if [ $? -ne 0 ]; then
  echo "⚠ Failed to apply sysctl settings. Check the output above for errors."
  exit 1
else
  echo "✓ Successfully applied all sysctl settings."
fi

# Verify critical settings to ensure they were applied correctly
echo -e "\nVerifying critical settings:"

# Function to verify a sysctl parameter
verify_sysctl() {
  local param=$1
  local expected_value=$2
  local actual_value=$(sysctl -n "$param" 2>/dev/null)

  if [ -z "$actual_value" ]; then
    echo "⚠ Parameter $param does not exist or couldn't be read."
    return 1
  elif [ "$actual_value" != "$expected_value" ]; then
    echo "⚠ Parameter $param has value '$actual_value' (expected '$expected_value')"
    return 1
  else
    echo "✓ $param = $actual_value"
    return 0
  fi
}

# Network security verification
verify_sysctl "net.ipv4.conf.all.rp_filter" "1"
verify_sysctl "net.ipv4.tcp_syncookies" "1"
verify_sysctl "net.ipv4.conf.all.accept_redirects" "0"
verify_sysctl "net.ipv4.conf.all.accept_source_route" "0"
verify_sysctl "net.ipv4.ip_forward" "0"

# Kernel hardening verification
verify_sysctl "kernel.dmesg_restrict" "1"
verify_sysctl "kernel.randomize_va_space" "2"
verify_sysctl "kernel.yama.ptrace_scope" "3"

# File system and memory protection verification
verify_sysctl "fs.suid_dumpable" "0"
verify_sysctl "fs.protected_symlinks" "1"
verify_sysctl "vm.swappiness" "1"

# Check if systemd-sysctl service is running
echo -e "\nChecking systemd-sysctl service status:"
systemctl status systemd-sysctl --no-pager

# Verify symbolic link for UFW compatibility
echo -e "\nVerifying UFW compatibility setup:"
if [ -L "$SYSCTL_CONF" ] && [ "$(readlink -f "$SYSCTL_CONF")" = "$NETWORK_CONF" ]; then
  echo "✓ Symbolic link is correctly set up from $SYSCTL_CONF to $NETWORK_CONF"
else
  echo "⚠ Symbolic link verification failed"
fi

echo -e "\n===== Kernel and Network Hardening Complete =====\n"
echo "Configuration files created:"
echo "  - $NETWORK_CONF"
echo "  - $KERNEL_CONF"
echo "  - $FS_MEM_CONF"
echo "  - $SYSCTL_CONF (symbolic link to $NETWORK_CONF for UFW compatibility)"
echo -e "\nTo verify all configured parameters manually, use:"
echo "  sudo sysctl --system"
echo "  sysctl -a | grep \"parameter_name\""
echo -e "\nBackups of original configurations are stored in: $BACKUP_DIR"
echo -e "\nNOTE: Some kernel parameters may require a system reboot to take full effect."

exit 0
