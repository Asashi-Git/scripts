#!/bin/bash

#############################################################
# Hardened Arch Linux by Samuel Decarnelle
#############################################################

# ANSI color codes for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print section headers
print_section() {
	echo -e "\n${BLUE}===================================================================${NC}"
	echo -e "${MAGENTA}$1${NC}"
	echo -e "${BLUE}===================================================================${NC}\n"
}

# Function to print success messages
print_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to print error messages
print_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

# Function to print info messages
print_info() {
	echo -e "${CYAN}[INFO]${NC} $1"
}

# Function to print warning messages
print_warning() {
	echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if running as root
check_root() {
	if [[ $EUID -ne 0 ]]; then
		print_error "This script must be run as root"
		exit 1
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

# Function to get SSH port
get_ssh_port() {
	read -p "Enter SSH port (default 22): " ssh_port
	if [[ -z "$ssh_port" ]]; then
		ssh_port=22
	fi

	# Validate port number
	if ! [[ "$ssh_port" =~ ^[0-9]+$ ]] || [ "$ssh_port" -lt 1 ] || [ "$ssh_port" -gt 65535 ]; then
		print_error "Invalid port number. Please enter a value between 1-65535."
		get_ssh_port
	else
		print_success "SSH port set to $ssh_port"
	fi
}

# Function to configure HTTP encrypted partition
configure_http_partition() {
	print_section "Configuring Encrypted HTTP Partition"

	if confirm_action "Do you want to create an encrypted HTTP partition?"; then
		print_info "Creating and setting up encrypted HTTP partition..."

		# Create logical volume
		lvcreate -L 5G vg0 -n httpdata || {
			print_error "Failed to create logical volume"
			return 1
		}

		# Encrypt it
		cryptsetup luksFormat /dev/vg0/httpdata || {
			print_error "Failed to encrypt volume"
			return 1
		}

		# Open encrypted volume
		cryptsetup open /dev/vg0/httpdata crypthttp || {
			print_error "Failed to open encrypted volume"
			return 1
		}

		# Format as ext4
		mkfs.ext4 /dev/mapper/crypthttp || {
			print_error "Failed to format volume"
			return 1
		}

		# Create mount point
		mkdir -p /mnt/data/http || {
			print_error "Failed to create mount point"
			return 1
		}

		# Mount
		mount /dev/mapper/crypthttp /mnt/data/http || {
			print_error "Failed to mount volume"
			return 1
		}

		# Create mount script
		cat >/usr/local/bin/mount-httpdata.sh <<'EOF'
#!/bin/bash

# Check if already mounted
if mountpoint -q /data/http; then
    echo "HTTP data partition is already mounted."
    exit 0
fi

# Try to unlock and mount
echo "Unlocking HTTP data partition..."
if cryptsetup open /dev/vg0/httpdata crypthttp; then
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

		chmod +x /usr/local/bin/mount-httpdata.sh

		# Add to user profile
		cat >>/home/localadm/.bash_profile <<'EOF'

# Check if HTTP partition is mounted
if ! mountpoint -q /data/http; then
    echo "HTTP data partition is not mounted."
    read -p "Would you like to mount it now? (y/n): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        sudo /usr/local/bin/mount-httpdata.sh
    fi
fi
EOF

		print_success "HTTP encrypted partition configured successfully"
	else
		print_info "Skipping HTTP encrypted partition configuration"
	fi
}

# Function to configure sudo logging
configure_sudo_logging() {
	print_section "Configuring Sudo Logging"

	if grep -q "^Defaults logfile=/var/log/sudo.log" /etc/sudoers; then
		print_info "Sudo logging already configured"
	else
		echo "Defaults logfile=/var/log/sudo.log" | EDITOR='tee -a' visudo
		print_success "Sudo logging configured"
	fi
}

# Function to secure root account
secure_root_account() {
	print_section "Securing Root Account"

	# Disable root login shell
	sed -i 's|^root:.*:|root:x:0:0:root:/root:/usr/sbin/nologin|' /etc/passwd
	print_success "Root login shell disabled"

	# Lock root password
	sed -i 's|^root:[^:]*:|root:!:|' /etc/shadow
	print_success "Root password locked"
}

# Function to harden filesystem
harden_filesystem() {
	print_section "Hardening Filesystem Configuration"

	# Check if entries already exist
	if ! grep -q "^proc.*hidepid=2" /etc/fstab; then
		echo "proc           /proc            proc            hidepid=2 0 0" >>/etc/fstab
		print_success "Added hidepid=2 to /proc mount"
	else
		print_info "/proc mount already hardened"
	fi

	if ! grep -q "^tmpfs.*nosuid,nodev,noexec" /etc/fstab; then
		echo "tmpfs          /tmp             tmpfs           nosuid,nodev,noexec 0 0" >>/etc/fstab
		print_success "Added nosuid,nodev,noexec to /tmp mount"
	else
		print_info "/tmp mount already hardened"
	fi

	print_warning "You may need to reboot for filesystem changes to take effect"
}

# Function to configure and secure SSH
configure_ssh() {
	print_section "Configuring and Securing SSH"

	# Install required packages
	print_info "Installing OpenSSH, Google Authenticator and qrencode..."
	pacman -S --noconfirm openssh libpam-google-authenticator qrencode || {
		print_error "Failed to install required packages"
		return 1
	}

	# Enable and start SSH service
	systemctl enable sshd
	systemctl start sshd
	print_success "SSH service enabled and started"

	# Get SSH port
	get_ssh_port

	# Configure sshd_config
	print_info "Configuring SSH daemon..."

	# Make backup of configs
	cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

	# Update port
	sed -i "s/^#Port 22/Port $ssh_port/" /etc/ssh/sshd_config

	# Disable root login
	sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

	# Set up SSH key authentication
	if confirm_action "Do you want to set up SSH key authentication?"; then
		print_info "Generating SSH key..."
		ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
		mkdir -p ~/.ssh
		cat ~/.ssh/id_rsa.pub >>~/.ssh/authorized_keys
		chmod 700 ~/.ssh
		chmod 600 ~/.ssh/authorized_keys

		# Update AuthorizedKeysFile
		sed -i 's/^#AuthorizedKeysFile.*/AuthorizedKeysFile .ssh\/authorized_keys/' /etc/ssh/sshd_config
		print_success "SSH key authentication configured"
	fi

	# Set up Google Authenticator (2FA)
	if confirm_action "Do you want to set up 2FA with Google Authenticator?"; then
		print_info "Running Google Authenticator setup..."
		google-authenticator -t -d -f -r 3 -R 30 -w 3

		# Save QR code to file
		username=$(whoami)
		qrencode -t PNG -o ~/qrcode_user_$username.png "$(grep -oP '(?<=otpauth:\/\/).*' ~/.google_authenticator)"
		print_success "QR code saved to ~/qrcode_user_$username.png"

		# Configure PAM
		echo "auth required pam_google_authenticator.so" >>/etc/pam.d/sshd

		# Configure SSH for 2FA
		sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
		sed -i 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config
		sed -i 's/^#\?UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config
		sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config

		# Add AuthenticationMethods
		if ! grep -q "^AuthenticationMethods" /etc/ssh/sshd_config; then
			echo "AuthenticationMethods publickey,keyboard-interactive" >>/etc/ssh/sshd_config
		else
			sed -i 's/^AuthenticationMethods.*/AuthenticationMethods publickey,keyboard-interactive/' /etc/ssh/sshd_config
		fi

		print_success "2FA configured for SSH"
	fi

	# Comment out Arch Linux specific settings
	if [ -f /etc/ssh/sshd_config.d/99-archlinux.conf ]; then
		sed -i 's/^/#/' /etc/ssh/sshd_config.d/99-archlinux.conf
		print_success "Commented out Arch Linux specific SSH settings"
	fi

	# Configure additional hardening
	print_info "Applying additional SSH hardening..."

	# Update SSH settings
	sed -i 's/^#\?LoginGraceTime.*/LoginGraceTime 20/' /etc/ssh/sshd_config
	sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
	sed -i 's/^#\?MaxSessions.*/MaxSessions 5/' /etc/ssh/sshd_config
	sed -i 's/^#\?ClientAliveInterval.*/ClientAliveInterval 60/' /etc/ssh/sshd_config
	sed -i 's/^#\?ClientAliveCountMax.*/ClientAliveCountMax 3/' /etc/ssh/sshd_config
	sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
	sed -i 's/^#\?AllowAgentForwarding.*/AllowAgentForwarding no/' /etc/ssh/sshd_config
	sed -i 's/^#\?AllowTcpForwarding.*/AllowTcpForwarding no/' /etc/ssh/sshd_config

	# Test SSH configuration
	sshd -t
	if [ $? -eq 0 ]; then
		systemctl restart sshd
		print_success "SSH configured successfully and restarted"
	else
		print_error "SSH configuration test failed. Please check the configuration"
	fi
}

# Function to configure sysctl settings
configure_sysctl() {
	print_section "Configuring System Kernel Parameters (sysctl)"

	# Create sysctl configuration files
	print_info "Creating network security configuration..."
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
# UFW recommended settings
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.icmp_echo_ignore_all = 0
net.ipv4.conf.all.log_martians = 0
net.ipv4.conf.default.log_martians = 0
EOF

	print_info "Creating kernel hardening configuration..."
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

	print_info "Creating filesystem and memory protection configuration..."
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

	# Apply sysctl settings
	sysctl -p

	print_success "Kernel parameters configured"

	# Verify settings
	if confirm_action "Do you want to verify the sysctl settings?"; then
		sysctl -a | grep "net.ipv4.conf.all.rp_filter"
	fi
}

# Function to configure UFW firewall
configure_ufw() {
	print_section "Configuring UFW Firewall"

	# Install UFW
	print_info "Installing UFW..."
	pacman -S --noconfirm ufw || {
		print_error "Failed to install UFW"
		return 1
	}

	# Update UFW default configuration
	print_info "Configuring UFW defaults..."
	sed -i 's|^IPT_SYSCTL=.*|IPT_SYSCTL=/etc/sysctl.conf|' /etc/default/ufw

	# Configure UFW rules
	print_info "Setting up UFW rules..."

	# Allow SSH
	ufw allow "$ssh_port/tcp"
	ufw limit "$ssh_port"
	print_success "Added SSH rule for port $ssh_port"

	# Ask about additional rules
	if confirm_action "Do you want to add more UFW rules?"; then
		while true; do
			read -p "Enter port number (or q to quit): " port
			if [[ "$port" == "q" ]]; then
				break
			fi

			if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
				print_error "Invalid port number. Try again."
				continue
			fi

			read -p "Protocol (tcp/udp/both): " proto
			case "$proto" in
			tcp | TCP) ufw allow "$port/tcp" ;;
			udp | UDP) ufw allow "$port/udp" ;;
			both | BOTH) ufw allow "$port" ;;
			*)
				print_error "Invalid protocol. Using tcp/udp."
				ufw allow "$port"
				;;
			esac

			print_success "Added rule for port $port ($proto)"
		done
	fi

	# Enable UFW
	print_info "Enabling UFW..."
	ufw --force enable

	# Add additional security rules to before.rules
	print_info "Adding additional security rules..."

	# Add rules to IPv4
	if ! grep -q "ufw-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j DROP" /etc/ufw/before.rules; then
		sed -i '/^# End required lines/a -A ufw-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j ufw-logging-deny\n-A ufw-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j DROP' /etc/ufw/before.rules
	fi

	# Add rules to IPv6
	if ! grep -q "ufw6-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j DROP" /etc/ufw/before6.rules; then
		sed -i '/^# End required lines/a -A ufw6-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j ufw6-logging-deny\n-A ufw6-before-input -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j DROP' /etc/ufw/before6.rules
	fi

	# Reload UFW
	ufw reload

	# Show status
	ufw status verbose

	print_success "UFW firewall configured and enabled"
}

# Function to configure Fail2Ban
configure_fail2ban() {
	print_section "Configuring Fail2Ban"

	# Install Fail2Ban
	print_info "Installing Fail2Ban..."
	pacman -S --noconfirm fail2ban || {
		print_error "Failed to install Fail2Ban"
		return 1
	}

	# Create local config files
	print_info "Creating local configuration files..."
	cp -f /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
	cp -f /etc/fail2ban/fail2ban.conf /etc/fail2ban/fail2ban.local

	# Configure jail.local
	print_info "Configuring jail.local settings..."

	# Update maxretry, bantime, findtime
	sed -i 's/^# *bantime *=.*/bantime = 30m/' /etc/fail2ban/jail.local
	sed -i 's/^# *findtime *=.*/findtime = 30m/' /etc/fail2ban/jail.local
	sed -i 's/^# *maxretry *=.*/maxretry = 2/' /etc/fail2ban/jail.local

	# Enable sshd jail
	sed -i "/^

$$
sshd
$$

/,/^

$$
/ s/^#enabled *=.*/enabled = true/" /etc/fail2ban/jail.local
	sed -i "/^\[sshd
$$

/,/^\[/ s/^#port *=.*/port = $ssh_port/" /etc/fail2ban/jail.local

	# Start and enable Fail2Ban
	systemctl start fail2ban
	systemctl enable fail2ban

	# Show status
	fail2ban-client status

	print_success "Fail2Ban installed and configured"
}

# Main function
main() {
	clear
	echo -e "${GREEN}"
	echo "  ___  __    ____  ___    ____  ____  ____  _  _  ____  ___"
	echo " / __)(  )  (  _ \/ __)  (  _ $   __)/ ___)/ )( \(  __)(__ \\" echo "( (__  )(__  )   /\__ \   ) _ ( ) _) \___  $  \/ ( ) _)  / _/"
	echo " \___)(____)(__)  (___/  (____/(____)(____/\____/(____)(____)   "
	echo ""
	echo "  Hardened Arch Linux by Samuel Decarnelle"
	echo -e "${NC}"

	# Check if running as root
	check_root

	# Determine server type
	print_section "Select Server Type"
	echo "1) Web server"
	echo "2) Reverse proxy server"
	echo "3) Proxy server"
	echo "4) Reverse proxy and proxy server"
	echo "5) Desktop experience"

	read -p "Choose an option (1-5): " server_type

	case "$server_type" in
	1)
		print_info "Web server configuration selected"
		server_mode="web-server"
		;;
	2)
		print_info "Reverse proxy server configuration selected"
		server_mode="reverse-proxy"
		;;
	3)
		print_info "Proxy server configuration selected"
		server_mode="proxy-server"
		;;
	4)
		print_info "Reverse proxy and proxy server configuration selected"
		server_mode="reverse-proxy-and-proxy"
		;;
	5)
		print_info "Desktop experience configuration selected"
		server_mode="desktop"
		;;
	*)
		print_error "Invalid option. Defaulting to web server."
		server_mode="web-server"
		;;
	esac

	# For web server, configure HTTP partition
	if [ "$server_mode" = "web-server" ]; then
		configure_http_partition
	fi

	# Common hardening for all server types
	configure_sudo_logging
	secure_root_account
	harden_filesystem
	configure_ssh
	configure_sysctl
	configure_ufw
	configure_fail2ban

	print_section "Hardening Completed"
	print_success "Your Arch Linux system has been hardened successfully!"

	if confirm_action "Do you want to reboot now to apply all changes?"; then
		print_info "Rebooting system..."
		reboot
	else
		print_info "Remember to reboot your system to apply all changes."
	fi
}

# Run main function
main
