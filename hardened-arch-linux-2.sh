#!/bin/bash

#############################################################
# Hardened Arch Linux by Samuel Decarnelle
#############################################################

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function for printing messages
print_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
  echo -e "${RED}[ERROR]${NC}  $ 1"
}

# Function to run commands with sudo
run_sudo() {
  print_info "Executing: sudo  $ *"
  sudo "$@"
  if [ $? -eq 0 ]; then
    print_success "Command executed successfully"
  else
    print_error "Command failed with exit code $?"
  fi
}

# Function to confirm action
confirm_action() {
  echo -e "${YELLOW}$1 ${NC}(y/n): "
  read choice
  case "$choice" in
  y | Y) return 0 ;;
  n | N) return 1 ;;
  *)
    print_error "Invalid choice"
    confirm_action "$1"
    ;;
  esac
}

# Verify connectivity
check_connectivity() {
  print_info "Checking internet connectivity..."
  if ping -c 1 archlinux.org &>/dev/null; then
    print_success "Internet connectivity confirmed"
  else
    print_error "No internet connection detected"
    exit 1
  fi
}

# Main script starts here
clear
echo "=================================================="
echo "   Hardened Arch Linux by Samuel Decarnelle"
echo "=================================================="
echo ""

# Check connectivity
check_connectivity

# Ask server type
echo "What type of server are you setting up?"
echo "1) Web Server"
echo "2) Reverse-Proxy Server"
echo "3) Proxy Server"
echo "4) Reverse-Proxy and Proxy Server"
echo "5) Desktop"
read -p "Select an option [1-5]: " server_type

# Store server type for later use
case $server_type in
1) SERVER_TYPE="Web Server" ;;
2) SERVER_TYPE="Reverse-Proxy Server" ;;
3) SERVER_TYPE="Proxy Server" ;;
4) SERVER_TYPE="Reverse-Proxy and Proxy Server" ;;
5) SERVER_TYPE="Desktop" ;;
*)
  print_error "Invalid option"
  exit 1
  ;;
esac

print_info "Configuring system as $SERVER_TYPE"

# Get SSH port
read -p "Enter SSH port to use (default: 22): " ssh_port
ssh_port=${ssh_port:-22}
print_info "SSH will be configured on port $ssh_port"

# Basic system update
if confirm_action "Would you like to update the system first?"; then
  print_info "Updating system packages..."
  run_sudo pacman -Syu --noconfirm
fi

# Basic security packages
if confirm_action "Install basic security packages?"; then
  print_info "Installing security packages..."
  run_sudo pacman -S --needed --noconfirm ufw fail2ban cronie rkhunter lynis arch-audit
fi

# SSH hardening
if confirm_action "Harden SSH configuration?"; then
  print_info "Configuring SSH..."

  # Backup existing config
  run_sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

  # Apply hardened configuration
  print_info "Applying hardened SSH configuration..."
  run_sudo bash -c "cat > /etc/ssh/sshd_config << EOL
Port $ssh_port
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
UsePrivilegeSeparation yes
KeyRegenerationInterval 3600
ServerKeyBits 1024
SyslogFacility AUTH
LogLevel INFO
LoginGraceTime 30
PermitRootLogin no
StrictModes yes
RSAAuthentication yes
PubkeyAuthentication yes
IgnoreRhosts yes
RhostsRSAAuthentication no
HostbasedAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
PasswordAuthentication yes
X11Forwarding no
X11DisplayOffset 10
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/ssh/sftp-server
UsePAM yes
AllowGroups wheel
MaxAuthTries 3
MaxSessions 2
ClientAliveInterval 300
ClientAliveCountMax 2
EOL"

  # Restart SSH
  run_sudo systemctl restart sshd
  print_info "SSH configuration has been hardened"
fi

# UFW configuration
if confirm_action "Configure UFW firewall?"; then
  print_info "Setting up UFW firewall..."

  # Reset UFW
  run_sudo ufw reset

  # Default policies
  run_sudo ufw default deny incoming
  run_sudo ufw default allow outgoing

  # Allow SSH
  run_sudo ufw allow $ssh_port/tcp comment "SSH"

  # Server-specific rules
  case $server_type in
  1) # Web Server
    run_sudo ufw allow 80/tcp comment "HTTP"
    run_sudo ufw allow 443/tcp comment "HTTPS"
    ;;
  2) # Reverse-Proxy Server
    run_sudo ufw allow 80/tcp comment "HTTP"
    run_sudo ufw allow 443/tcp comment "HTTPS"
    ;;
  3) # Proxy Server
    run_sudo ufw allow 8080/tcp comment "Proxy"
    ;;
  4) # Reverse-Proxy and Proxy Server
    run_sudo ufw allow 80/tcp comment "HTTP"
    run_sudo ufw allow 443/tcp comment "HTTPS"
    run_sudo ufw allow 8080/tcp comment "Proxy"
    ;;
  5) # Desktop
    # No special ports needed for desktop
    ;;
  esac

  # Enable UFW
  run_sudo ufw enable
  run_sudo systemctl enable ufw

  print_success "UFW configured and enabled"
fi

# Fail2Ban configuration
if confirm_action "Configure Fail2Ban?"; then
  print_info "Setting up Fail2Ban..."

  # Create fail2ban configuration
  run_sudo cp /etc/fail2ban/fail2ban.conf /etc/fail2ban/fail2ban.local

  # Configure jail.local
  run_sudo bash -c "cat > /etc/fail2ban/jail.local << EOL
[DEFAULT]
# Ban hosts for 30 minutes
bantime = 30m
# A host is banned if it has generated maxretry during the last findtime
findtime = 30m
maxretry = 2

# Override /etc/fail2ban/jail.d/00-firewalld.conf
banaction = iptables-multiport

[sshd]
enabled = true
port    = $ssh_port
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOL"

  # Start and enable fail2ban
  run_sudo systemctl start fail2ban
  run_sudo systemctl enable fail2ban

  # Check status
  run_sudo fail2ban-client status

  print_success "Fail2Ban configured and enabled"
fi

# System hardening (with individual sudo calls)
if confirm_action "Apply system hardening?"; then
  print_info "Applying system hardening..."

  # Kernel parameters for security
  run_sudo bash -c "cat > /etc/sysctl.d/99-security.conf << EOL
# IP Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP broadcast requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0 
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Block SYN attacks
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Log Martians
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Ignore Directed pings
net.ipv4.icmp_echo_ignore_all = 1

# Disable IPv6 if not used
# net.ipv6.conf.all.disable_ipv6 = 1
# net.ipv6.conf.default.disable_ipv6 = 1
# net.ipv6.conf.lo.disable_ipv6 = 1
EOL"

  # Apply sysctl settings
  run_sudo sysctl -p /etc/sysctl.d/99-security.conf

  # Secure shared memory
  run_sudo bash -c "echo 'tmpfs     /run/shm     tmpfs     defaults,noexec,nosuid     0     0' >> /etc/fstab"

  # Set up daily updates for security
  run_sudo bash -c "cat > /etc/cron.daily/pacman-security-updates << EOL
#!/bin/bash
/usr/bin/pacman -Sy arch-audit --noconfirm
/usr/bin/arch-audit
/usr/bin/pacman -Syu --noconfirm
EOL"
  run_sudo chmod +x /etc/cron.daily/pacman-security-updates

  # Enable and start cronie for scheduled tasks
  run_sudo systemctl enable cronie
  run_sudo systemctl start cronie

  print_success "System hardening applied successfully"
fi

# Create a security audit script
if confirm_action "Create security audit script?"; then
  print_info "Creating security audit script..."

  run_sudo bash -c "cat > /usr/local/bin/security-audit << EOL
#!/bin/bash
echo \"==== System Security Audit ====\"
echo \"Running on \$(date)\"
echo \"\"

echo \"=== System Updates ===\"
pacman -Qu

echo \"=== Security Vulnerabilities ===\"
arch-audit

echo \"=== Listening Ports ===\"
ss -tulpn

echo \"=== Active Services ===\"
systemctl --type=service --state=running

echo \"=== Failed Login Attempts ===\"
journalctl -u sshd | grep 'Failed'

echo \"=== Fail2Ban Status ===\"
fail2ban-client status

echo \"=== Last Logins ===\"
last -n 10

echo \"=== Disk Usage ===\"
df -h

echo \"=== System Load ===\"
uptime

echo \"Done! For a more comprehensive scan, run 'lynis audit system'\";
EOL"

  run_sudo chmod +x /usr/local/bin/security-audit

  print_success "Security audit script created at /usr/local/bin/security-audit"
fi

print_success "Hardening complete for $SERVER_TYPE! Please reboot your system to apply all changes."
echo ""
echo "==================== Summary ====================="
echo "Server type: $SERVER_TYPE"
echo "SSH port: $ssh_port"
echo "Firewall: Enabled (UFW)"
echo "Fail2Ban: Enabled"
echo ""
echo "To run a security audit: sudo /usr/local/bin/security-audit"
echo "===================================================="

exit 0
