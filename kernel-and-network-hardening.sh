#!/bin/bash

# ╔═══════════════════════════════════════════════════════════════════╗
# ║  Kernel and Network Hardening Script for Arch Linux               ║
# ║  This script configures system security parameters                ║
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
# │ Default settings                                                 │
# └─────────────────────────────────────────────────────────────────┘
BACKUP_DIR="/root/sysctl_backup"
NETWORK_CONF="/etc/sysctl.d/90-network-security.conf"
KERNEL_CONF="/etc/sysctl.d/91-kernel-hardening.conf"
FS_MEM_CONF="/etc/sysctl.d/92-fs-memory-protection.conf"
SYSCTL_CONF="/etc/sysctl.conf"

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

# Function to print success messages
print_success() {
  echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"
}

# Function to backup a file before modifying
backup_file() {
  local file=$1
  local backup="${BACKUP_DIR}/$(basename ${file}).bak.$(date +%Y%m%d%H%M%S)"

  # Only backup if file exists
  if [ -f "$file" ]; then
    cp "$file" "$backup"
    print_info "Backed up $file to $backup"
  fi
}

# Function to verify a sysctl parameter
verify_sysctl() {
  local param=$1
  local expected_value=$2
  local actual_value=$(sysctl -n "$param" 2>/dev/null)

  if [ -z "$actual_value" ]; then
    print_warning "Parameter $param does not exist or couldn't be read."
    return 1
  elif [ "$actual_value" != "$expected_value" ]; then
    print_warning "Parameter $param has value '$actual_value' (expected '$expected_value')"
    return 1
  else
    print_success "$param = $actual_value"
    return 0
  fi
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Check if running as root                                         │
# └─────────────────────────────────────────────────────────────────┘
if [[ $EUID -ne 0 ]]; then
  print_error "This script must be run as root"
  exit 1
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ Create backup directory                                          │
# └─────────────────────────────────────────────────────────────────┘
mkdir -p $BACKUP_DIR

# ┌─────────────────────────────────────────────────────────────────┐
# │ Welcome message                                                  │
# └─────────────────────────────────────────────────────────────────┘
clear
echo
echo -e "${BRIGHT_BLUE}${BOLD}"
cat <<"EOF"
  ██╗  ██╗███████╗██████╗ ███╗   ██╗███████╗██╗         ███████╗███████╗ ██████╗██╗   ██╗██████╗ ██╗████████╗██╗   ██╗
  ██║ ██╔╝██╔════╝██╔══██╗████╗  ██║██╔════╝██║         ██╔════╝██╔════╝██╔════╝██║   ██║██╔══██╗██║╚══██╔══╝╚██╗ ██╔╝
  █████╔╝ █████╗  ██████╔╝██╔██╗ ██║█████╗  ██║         ███████╗█████╗  ██║     ██║   ██║██████╔╝██║   ██║    ╚████╔╝ 
  ██╔═██╗ ██╔══╝  ██╔══██╗██║╚██╗██║██╔══╝  ██║         ╚════██║██╔══╝  ██║     ██║   ██║██╔══██╗██║   ██║     ╚██╔╝  
  ██║  ██╗███████╗██║  ██║██║ ╚████║███████╗███████╗    ███████║███████╗╚██████╗╚██████╔╝██║  ██║██║   ██║      ██║   
  ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝    ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝   ╚═╝      ╚═╝   
EOF
echo -e "${NC}"
echo
echo -e "${MAGENTA}${BOLD}"
cat <<"EOF"
  ███╗   ██╗███████╗████████╗██╗    ██╗ ██████╗ ██████╗ ██╗  ██╗    ██╗  ██╗ █████╗ ██████╗ ██████╗ ███████╗███╗   ██╗██╗███╗   ██╗ ██████╗ 
  ████╗  ██║██╔════╝╚══██╔══╝██║    ██║██╔═══██╗██╔══██╗██║ ██╔╝    ██║  ██║██╔══██╗██╔══██╗██╔══██╗██╔════╝████╗  ██║██║████╗  ██║██╔════╝ 
  ██╔██╗ ██║█████╗     ██║   ██║ █╗ ██║██║   ██║██████╔╝█████╔╝     ███████║███████║██████╔╝██║  ██║█████╗  ██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
  ██║╚██╗██║██╔══╝     ██║   ██║███╗██║██║   ██║██╔══██╗██╔═██╗     ██╔══██║██╔══██║██╔══██╗██║  ██║██╔══╝  ██║╚██╗██║██║██║╚██╗██║██║   ██║
  ██║ ╚████║███████╗   ██║   ╚███╔███╔╝╚██████╔╝██║  ██║██║  ██╗    ██║  ██║██║  ██║██║  ██║██████╔╝███████╗██║ ╚████║██║██║ ╚████║╚██████╔╝
  ╚═╝  ╚═══╝╚══════╝   ╚═╝    ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝    ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝ 
EOF
echo -e "${NC}"

# ┌─────────────────────────────────────────────────────────────────┐
# │ Configure Network Security Settings                              │
# └─────────────────────────────────────────────────────────────────┘
print_section "Network Security Configuration"

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

print_success "Network security parameters configured."

# ┌─────────────────────────────────────────────────────────────────┐
# │ Configure Kernel Hardening Settings                              │
# └─────────────────────────────────────────────────────────────────┘
print_section "Kernel Hardening Configuration"

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

print_success "Kernel hardening parameters configured."

# ┌─────────────────────────────────────────────────────────────────┐
# │ Configure File System and Memory Protection                      │
# └─────────────────────────────────────────────────────────────────┘
print_section "File System and Memory Protection"

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

print_success "File system and memory protection parameters configured."

# ┌─────────────────────────────────────────────────────────────────┐
# │ Set up UFW Compatibility                                         │
# └─────────────────────────────────────────────────────────────────┘
print_section "UFW Compatibility Configuration"

# Check if /etc/sysctl.conf exists, if so backup and remove
if [ -f "$SYSCTL_CONF" ]; then
  if [ -L "$SYSCTL_CONF" ]; then
    print_info "Existing symbolic link detected at $SYSCTL_CONF"
    backup_file "$SYSCTL_CONF"
    rm "$SYSCTL_CONF"
    print_info "Removed existing symbolic link"
  else
    print_info "Existing file detected at $SYSCTL_CONF"
    backup_file "$SYSCTL_CONF"
    rm "$SYSCTL_CONF"
    print_info "Backed up and removed the existing file"
  fi
fi

# Create symbolic link for UFW compatibility
ln -s "$NETWORK_CONF" "$SYSCTL_CONF"
print_success "Created symbolic link from $NETWORK_CONF to $SYSCTL_CONF for UFW compatibility"

# If UFW is installed, check its configuration
if command -v ufw >/dev/null 2>&1; then
  print_info "UFW is installed. Checking configuration..."

  if [ -f "/etc/default/ufw" ]; then
    # Check if IPT_SYSCTL is already set to /etc/sysctl.conf
    if grep -q "^IPT_SYSCTL=/etc/sysctl.conf" "/etc/default/ufw"; then
      print_success "UFW is already configured to use /etc/sysctl.conf"
    else
      # Backup UFW config
      backup_file "/etc/default/ufw"

      # Update IPT_SYSCTL in UFW config
      sed -i 's|^IPT_SYSCTL=.*|IPT_SYSCTL=/etc/sysctl.conf|' "/etc/default/ufw"
      print_success "Updated UFW configuration to use /etc/sysctl.conf"
    fi
  else
    print_warning "UFW is installed but the config file was not found at /etc/default/ufw"
  fi
else
  print_info "UFW is not installed. No UFW configuration needed."
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ Apply and Verify Settings                                        │
# └─────────────────────────────────────────────────────────────────┘
print_section "Applying and Verifying Settings"

# Apply all sysctl settings
print_info "Applying sysctl settings..."
sysctl --system

if [ $? -ne 0 ]; then
  print_error "Failed to apply sysctl settings. Check the output above for errors."
  exit 1
else
  print_success "Successfully applied all sysctl settings."
fi

# Verify critical settings to ensure they were applied correctly
print_section "Verifying Critical Settings"

# Network security verification
print_info "Verifying network security settings..."
verify_sysctl "net.ipv4.conf.all.rp_filter" "1"
verify_sysctl "net.ipv4.tcp_syncookies" "1"
verify_sysctl "net.ipv4.conf.all.accept_redirects" "0"
verify_sysctl "net.ipv4.conf.all.accept_source_route" "0"
verify_sysctl "net.ipv4.ip_forward" "0"

# Kernel hardening verification
print_info "Verifying kernel hardening settings..."
verify_sysctl "kernel.dmesg_restrict" "1"
verify_sysctl "kernel.randomize_va_space" "2"
verify_sysctl "kernel.yama.ptrace_scope" "3"

# File system and memory protection verification
print_info "Verifying file system and memory protection settings..."
verify_sysctl "fs.suid_dumpable" "0"
verify_sysctl "fs.protected_symlinks" "1"
verify_sysctl "vm.swappiness" "1"

# Check if systemd-sysctl service is running
print_section "SystemD Service Status"
echo -e "${CYAN}systemctl status systemd-sysctl${NC}"
systemctl status systemd-sysctl --no-pager

# Verify symbolic link for UFW compatibility
print_section "UFW Compatibility Status"
if [ -L "$SYSCTL_CONF" ] && [ "$(readlink -f "$SYSCTL_CONF")" = "$NETWORK_CONF" ]; then
  print_success "Symbolic link is correctly set up from $SYSCTL_CONF to $NETWORK_CONF"
else
  print_warning "Symbolic link verification failed"
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ Summary                                                          │
# └─────────────────────────────────────────────────────────────────┘
print_section "Summary"

echo -e "${GREEN}${BOLD}┌───────────────────────────────────────────────────────────────┐${NC}"
echo -e "${GREEN}${BOLD}│ Configuration Files Created                                   │${NC}"
echo -e "${GREEN}${BOLD}└───────────────────────────────────────────────────────────────┘${NC}"
echo -e "  ${BOLD}Network Security:${NC} $NETWORK_CONF"
echo -e "  ${BOLD}Kernel Hardening:${NC} $KERNEL_CONF"
echo -e "  ${BOLD}File System & Memory:${NC} $FS_MEM_CONF"
echo -e "  ${BOLD}Symbolic Link:${NC} $SYSCTL_CONF → $NETWORK_CONF"
echo -e "  ${BOLD}Backup Directory:${NC} $BACKUP_DIR"

echo -e "${BLUE}${BOLD}┌───────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}${BOLD}│ Verification Commands                                         │${NC}"
echo -e "${BLUE}${BOLD}└───────────────────────────────────────────────────────────────┘${NC}"
echo -e "  ${CYAN}sudo sysctl --system${NC}           - Apply all sysctl settings"
echo -e "  ${CYAN}sysctl -a | grep \"parameter_name\"${NC} - Check specific parameters"

print_warning "Some kernel parameters may require a system reboot to take full effect."

echo
echo -e "${BRIGHT_BLUE}${BOLD}"
cat <<"EOF"
  ███████╗███████╗ ██████╗██╗   ██╗██████╗ ██╗████████╗██╗   ██╗    ███████╗███╗   ██╗██╗  ██╗ █████╗ ███╗   ██╗ ██████╗███████╗██████╗ 
  ██╔════╝██╔════╝██╔════╝██║   ██║██╔══██╗██║╚══██╔══╝╚██╗ ██╔╝    ██╔════╝████╗  ██║██║  ██║██╔══██╗████╗  ██║██╔════╝██╔════╝██╔══██╗
  ███████╗█████╗  ██║     ██║   ██║██████╔╝██║   ██║    ╚████╔╝     █████╗  ██╔██╗ ██║███████║███████║██╔██╗ ██║██║     █████╗  ██║  ██║
  ╚════██║██╔══╝  ██║     ██║   ██║██╔══██╗██║   ██║     ╚██╔╝      ██╔══╝  ██║╚██╗██║██╔══██║██╔══██║██║╚██╗██║██║     ██╔══╝  ██║  ██║
  ███████║███████╗╚██████╗╚██████╔╝██║  ██║██║   ██║      ██║       ███████╗██║ ╚████║██║  ██║██║  ██║██║ ╚████║╚██████╗███████╗██████╔╝
  ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝   ╚═╝      ╚═╝       ╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝╚══════╝╚═════╝ 
EOF
echo -e "${NC}"

exit 0
