#!/bin/bash

# Arch Linux Hardening Script
# This script implements security best practices for Arch Linux systems
# Author: CyberSec Student
# Version: 1.0

# Ensure the script is run with root privileges
if [ "$EUID" -ne 0 ]; then
	echo "Please run this script as root or with sudo"
	exit 1
fi

echo "=========================================================="
echo "        Arch Linux Security Hardening Script"
echo "=========================================================="
echo ""

# Function to create backup of files before modification
backup_file() {
	if [ -f "$1" ]; then
		cp "$1" "$1.bak.$(date +%Y%m%d%H%M%S)"
		echo "Backup created: $1.bak.$(date +%Y%m%d%H%M%S)"
	fi
}

# Configure sudo logging
echo "[+] Configuring sudo logging..."
backup_file /etc/sudoers
if ! grep -q "^Defaults logfile=/var/log/sudo.log" /etc/sudoers; then
	echo "Defaults logfile=/var/log/sudo.log" >>/etc/sudoers
	echo "  - Sudo logging enabled to /var/log/sudo.log"
else
	echo "  - Sudo logging already configured"
fi

# Secure the root account
echo "[+] Securing the root account..."
backup_file /etc/passwd
backup_file /etc/shadow

# Change root shell to nologin
sed -i 's|^root:.*:|root:x:0:0:root:/root:/usr/sbin/nologin|' /etc/passwd
echo "  - Root shell changed to /usr/sbin/nologin"

# Lock the root password
sed -i 's|^root:\*:|root:!:|' /etc/shadow
sed -i 's|^root:\$:|root:!:|' /etc/shadow
echo "  - Root password locked"

# Harden filesystem mounts
echo "[+] Hardening filesystem mounts..."
backup_file /etc/fstab

# Add secure /proc and /tmp mounts if they don't already exist
if ! grep -q "^proc.*hidepid=2" /etc/fstab; then
	echo "proc           /proc            proc            hidepid=2 0 0" >>/etc/fstab
	echo "  - Added secure /proc mount"
else
	echo "  - Secure /proc mount already configured"
fi

if ! grep -q "^tmpfs.*nosuid,nodev,noexec" /etc/fstab; then
	echo "tmpfs          /tmp             tmpfs           nosuid,nodev,noexec 0 0" >>/etc/fstab
	echo "  - Added secure /tmp mount"
else
	echo "  - Secure /tmp mount already configured"
fi

# SSH hardening
echo "[+] Setting up SSH security..."

# Ask if the user wants to install 2FA
read -p "Do you want to set up SSH with 2FA? (y/n): " setup_2fa
if [[ "$setup_2fa" =~ ^[Yy]$ ]]; then
	# Install required packages
	echo "  - Installing required packages..."
	pacman -S --noconfirm openssh libpam-google-authenticator qrencode

	# Enable SSH service
	systemctl enable sshd
	systemctl start sshd

	# Configure SSH port
	backup_file /etc/ssh/sshd_config
	read -p "Enter the SSH port number you want to use (default is 22): " ssh_port
	ssh_port=${ssh_port:-22}

	# Update SSH port in config
	sed -i "/^#Port /c\Port $ssh_port" /etc/ssh/sshd_config
	sed -i "/^Port /c\Port $ssh_port" /etc/ssh/sshd_config
	echo "  - SSH port set to $ssh_port"

	# Disable root login
	sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
	sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
	echo "  - Root login via SSH disabled"

	# Create SSH key if it doesn't exist
	if [ ! -f "$HOME/.ssh/id_rsa" ]; then
		echo "  - Generating SSH key..."
		mkdir -p "$HOME/.ssh"
		chmod 700 "$HOME/.ssh"
		ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N ""
	else
		echo "  - SSH key already exists"
	fi

	# Setup authorized keys
	mkdir -p "$HOME/.ssh"
	touch "$HOME/.ssh/authorized_keys"
	cat "$HOME/.ssh/id_rsa.pub" >>"$HOME/.ssh/authorized_keys"
	chmod 600 "$HOME/.ssh/authorized_keys"
	echo "  - SSH key added to authorized_keys"

	# Update authorized keys file location
	sed -i 's/^#AuthorizedKeysFile.*/AuthorizedKeysFile .ssh\/authorized_keys/' /etc/ssh/sshd_config
	echo "  - AuthorizedKeysFile path configured"

	# Set up Google Authenticator
	echo "  - Setting up Google Authenticator 2FA..."
	echo "  - Please scan the QR code with your authenticator app and save the emergency codes"
	google-authenticator

	# Configure PAM for SSH
	backup_file /etc/pam.d/sshd
	if ! grep -q "auth required pam_google_authenticator.so" /etc/pam.d/sshd; then
		echo "auth required pam_google_authenticator.so" >>/etc/pam.d/sshd
		echo "  - PAM module for Google Authenticator added"
	else
		echo "  - PAM module already configured"
	fi

	# Update SSH config for 2FA
	cat >/etc/ssh/sshd_config.d/hardening.conf <<EOF
PasswordAuthentication no
KbdInteractiveAuthentication yes
UsePAM yes
ChallengeResponseAuthentication yes
AuthenticationMethods publickey,keyboard-interactive
LoginGraceTime 20
MaxAuthTries 3
MaxSessions 5
ClientAliveInterval 60
ClientAliveCountMax 3
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
EOF
	echo "  - SSH hardening options configured"

	# Comment out all configurations in Arch's default SSH config file
	backup_file /etc/ssh/sshd_config.d/99-archlinux.conf
	if [ -f "/etc/ssh/sshd_config.d/99-archlinux.conf" ]; then
		sed -i 's/^[^#]/#&/' /etc/ssh/sshd_config.d/99-archlinux.conf
		echo "  - Disabled default Arch SSH configurations"
	fi

	# Verify SSH configuration
	echo "  - Verifying SSH configuration..."
	sshd -t
	if [ $? -eq 0 ]; then
		systemctl restart sshd
		echo "  - SSH configuration verified and service restarted"
	else
		echo "  - Error in SSH configuration, please check manually"
	fi
else
	echo "  - Skipping SSH 2FA setup"
fi

# Kernel and network hardening
echo "[+] Applying kernel and network security settings..."

# Network security
backup_file /etc/sysctl.d/90-network-security.conf
cat >/etc/sysctl.d/90-network-security.conf <<EOF
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
# Additional UFW settings
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.icmp_echo_ignore_all = 0
net.ipv4.conf.all.log_martians = 0
net.ipv4.conf.default.log_martians = 0
EOF
echo "  - Network security parameters configured"

# Kernel hardening
backup_file /etc/sysctl.d/91-kernel-hardening.conf
cat >/etc/sysctl.d/91-kernel-hardening.conf <<EOF
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
echo "  - Kernel hardening parameters configured"

# Filesystem and memory protection
backup_file /etc/sysctl.d/92-fs-memory-protection.conf
cat >/etc/sysctl.d/92-fs-memory-protection.conf <<EOF
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
echo "  - Filesystem and memory protection parameters configured"

# Apply sysctl settings
echo "  - Applying sysctl settings..."
sysctl --system
echo "  - Sysctl settings applied"

# Verify sysctl settings
echo "  - Verifying sysctl settings..."
if sysctl -a | grep -q "net.ipv4.conf.all.rp_filter = 1"; then
	echo "  - Sysctl settings successfully verified"
else
	echo "  - Some sysctl settings might not be applied correctly, check manually"
fi

# Setup UFW firewall
echo "[+] Setting up UFW firewall..."
pacman -S --noconfirm ufw

# Configure UFW to use our sysctl settings
backup_file /etc/default/ufw
sed -i 's|^IPT_SYSCTL=.*|IPT_SYSCTL=/etc/sysctl.conf|' /etc/default/ufw
echo "  - UFW configured to use system sysctl settings"

# Set up UFW rules
if [ -n "$ssh_port" ]; then
	ufw allow "$ssh_port"/tcp
	ufw limit "$ssh_port"/tcp
	echo "  - UFW configured to allow and limit SSH on port $ssh_port"
else
	ufw allow 22/tcp
	ufw limit 22/tcp
	echo "  - UFW configured to allow and limit SSH on port 22"
fi

# Configure UFW for invalid packet protection
backup_file /etc/ufw/before.rules
if ! grep -q "ufw-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j DROP" /etc/ufw/before.rules; then
	# Find the *filter line
	filter_line=$(grep -n "^*filter" /etc/ufw/before.rules | cut -d: -f1)
	if [ -n "$filter_line" ]; then
		# Insert the new rules after the ufw-before-input chain definition
		insert_line=$((filter_line + 3))
		sed -i "${insert_line}a\\-A ufw-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j ufw-logging-deny\\n-A ufw-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j DROP" /etc/ufw/before.rules
		echo "  - Added invalid packet protection to before.rules"
	else
		echo "  - Could not find *filter line in before.rules"
	fi
fi

backup_file /etc/ufw/before6.rules
if ! grep -q "ufw6-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j DROP" /etc/ufw/before6.rules; then
	# Find the *filter line
	filter_line=$(grep -n "^*filter" /etc/ufw/before6.rules | cut -d: -f1)
	if [ -n "$filter_line" ]; then
		# Insert the new rules after the ufw6-before-input chain definition
		insert_line=$((filter_line + 3))
		sed -i "${insert_line}a\\-A ufw6-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j ufw6-logging-deny\\n-A ufw6-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j DROP" /etc/ufw/before6.rules
		echo "  - Added invalid packet protection to before6.rules"
	else
		echo "  - Could not find *filter line in before6.rules"
	fi
fi

# Enable and start UFW
echo "  - Enabling UFW firewall..."
ufw --force enable
echo "  - UFW firewall enabled"
ufw status verbose

# Setup Fail2ban
echo "[+] Setting up Fail2ban..."
pacman -S --noconfirm fail2ban

# Configure Fail2ban
backup_file /etc/fail2ban/jail.conf
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
backup_file /etc/fail2ban/fail2ban.conf
cp /etc/fail2ban/fail2ban.conf /etc/fail2ban/fail2ban.local

# Update Fail2ban settings
sed -i 's/^maxretry = .*/maxretry = 2/' /etc/fail2ban/jail.local
sed -i 's/^bantime  = .*/bantime = 30m/' /etc/fail2ban/jail.local
sed -i 's/^findtime  = .*/findtime = 30m/' /etc/fail2ban/jail.local

# Configure SSH jail
if [ -n "$ssh_port" ]; then
	sed -i "/^

$$
sshd
$$

$/,/^

$$
/ s/^#enabled.*/enabled = true/" /etc/fail2ban/jail.local
	sed -i "/^\[sshd
$$

$/,/^

$$
/ s/^port.*/port = $ssh_port/" /etc/fail2ban/jail.local
	echo "  - Fail2ban configured to protect SSH on port $ssh_port"
else
	sed -i "/^\[sshd
$$

$/,/^\[/ s/^#enabled.*/enabled = true/" /etc/fail2ban/jail.local
	echo "  - Fail2ban configured to protect SSH on default port"
fi

# Enable and start Fail2ban
systemctl enable fail2ban
systemctl start fail2ban
echo "  - Fail2ban service enabled and started"

# Display Fail2ban status
fail2ban-client status

echo ""
echo "=========================================================="
echo "   Arch Linux Security Hardening Completed Successfully"
echo "=========================================================="
echo ""
echo "Security measures implemented:"
echo "  - Sudo logging configured"
echo "  - Root account secured"
echo "  - Filesystem mounts hardened"
if [[ "$setup_2fa" =~ ^[Yy]$ ]]; then
	echo "  - SSH with 2FA authentication configured"
fi
echo "  - Kernel and network security parameters applied"
echo "  - UFW firewall enabled and configured"
echo "  - Fail2ban intrusion prevention enabled"
echo ""
echo "NOTE: A system reboot is recommended to apply all changes."
echo "Would you like to reboot now? (y/n)"
read reboot_choice
if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
	echo "Rebooting system..."
	sleep 3
	reboot
else
	echo "Please reboot your system manually when convenient."
fi
