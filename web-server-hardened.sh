#!/bin/bash

# ╔═══════════════════════════════════════════════════════════════════╗
# ║  Encrypted Web Server Configuration                               ║
# ║  Sets up an encrypted partition for web server data               ║
# ╚═══════════════════════════════════════════════════════════════════╝

# ┌─────────────────────────────────────────────────────────────────┐
# │ Colors for output formatting                                     │
# └─────────────────────────────────────────────────────────────────┘
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BRIGHT_BLUE='\033[1;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ┌─────────────────────────────────────────────────────────────────┐
# │ Utility functions                                                │
# └─────────────────────────────────────────────────────────────────┘
print_section() {
  echo -e "\n${BLUE}${BOLD}╔════════════ $1 ════════════╗${NC}\n"
}

print_info() {
  echo -e "${CYAN}${BOLD}[INFO]${NC} $1"
}

print_step() {
  echo -e "${MAGENTA}${BOLD}[STEP $1/10]${NC} $2"
}

print_success() {
  echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"
}

print_error() {
  echo -e "${RED}${BOLD}[ERROR]${NC} $1"
  exit 1
}

print_warning() {
  echo -e "${YELLOW}${BOLD}[WARNING]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  print_error "Please run as root"
fi

# Function to handle errors
handle_error() {
  print_error "$1"
}

# Display banner
echo -e "${BRIGHT_BLUE}${BOLD}"
cat <<"EOF"
  ███████╗███╗   ██╗ ██████╗██████╗ ██╗   ██╗██████╗ ████████╗███████╗██████╗ 
  ██╔════╝████╗  ██║██╔════╝██╔══██╗╚██╗ ██╔╝██╔══██╗╚══██╔══╝██╔════╝██╔══██╗
  █████╗  ██╔██╗ ██║██║     ██████╔╝ ╚████╔╝ ██████╔╝   ██║   █████╗  ██║  ██║
  ██╔══╝  ██║╚██╗██║██║     ██╔══██╗  ╚██╔╝  ██╔═══╝    ██║   ██╔══╝  ██║  ██║
  ███████╗██║ ╚████║╚██████╗██║  ██║   ██║   ██║        ██║   ███████╗██████╔╝
  ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚═╝  ╚═╝   ╚═╝   ╚═╝        ╚═╝   ╚══════╝╚═════╝  
  ██╗    ██╗███████╗██████╗     ███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗ 
  ██║    ██║██╔════╝██╔══██╗    ██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗
  ██║ █╗ ██║█████╗  ██████╔╝    ███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝
  ██║███╗██║██╔══╝  ██╔══██╗    ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗
  ╚███╔███╔╝███████╗██████╔╝    ███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║
   ╚══╝╚══╝ ╚══════╝╚═════╝     ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝
EOF
echo -e "${NC}"

echo -e "${ORANGE}${BOLD}"
cat <<"EOF"
  ██████╗ ██╗   ██╗    ██████╗ ███████╗ ██████╗ █████╗ ██████╗ ███╗   ██╗███████╗██╗     ██╗     ███████╗    ███████╗ █████╗ ███╗   ███╗██╗   ██╗███████╗██╗     
  ██╔══██╗╚██╗ ██╔╝    ██╔══██╗██╔════╝██╔════╝██╔══██╗██╔══██╗████╗  ██║██╔════╝██║     ██║     ██╔════╝    ██╔════╝██╔══██╗████╗ ████║██║   ██║██╔════╝██║     
  ██████╔╝ ╚████╔╝     ██║  ██║█████╗  ██║     ███████║██████╔╝██╔██╗ ██║█████╗  ██║     ██║     █████╗      ███████╗███████║██╔████╔██║██║   ██║█████╗  ██║     
  ██╔══██╗  ╚██╔╝      ██║  ██║██╔══╝  ██║     ██╔══██║██╔══██╗██║╚██╗██║██╔══╝  ██║     ██║     ██╔══╝      ╚════██║██╔══██║██║╚██╔╝██║██║   ██║██╔══╝  ██║     
  ██████╔╝   ██║       ██████╔╝███████╗╚██████╗██║  ██║██║  ██║██║ ╚████║███████╗███████╗███████╗███████╗    ███████║██║  ██║██║ ╚═╝ ██║╚██████╔╝███████╗███████╗
  ╚═════╝    ╚═╝       ╚═════╝ ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝╚══════╝╚══════╝    ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚══════╝
EOF
echo -e "${NC}"

print_section "Creating and Setting Up Encrypted HTTP Partition"

# Ask for the username
echo -n "Enter the username for which to configure the auto-mount prompt (e.g., localadm): "
read username

# Validate that the user exists
if ! id "$username" &>/dev/null; then
  print_warning "User '$username' does not exist"
  echo "Would you like to create this user? (y/n)"
  read create_user
  if [[ "$create_user" =~ ^[Yy]$ ]]; then
    useradd -m "$username" || handle_error "Failed to create user"
    echo "Setting password for new user '$username'"
    passwd "$username" || handle_error "Failed to set password"
    print_success "User created successfully"
  else
    handle_error "User does not exist. Please specify a valid username."
  fi
fi

# Get the home directory of the user
user_home=$(eval echo ~$username)
if [ ! -d "$user_home" ]; then
  handle_error "Home directory for user '$username' not found"
fi

print_info "Using home directory: $user_home"

# Step 1: Create the logical volume
print_step "1" "Creating logical volume 'httpdata'..."
lvcreate -L 5G vg0 -n httpdata || handle_error "Failed to create logical volume"

# Step 2: Encrypt the logical volume
print_step "2" "Encrypting the volume (you will be prompted for a passphrase)..."
echo "This will overwrite any data on /dev/vg0/httpdata. Are you sure? (y/n)"
read confirmation
if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
  echo "Operation cancelled"
  exit 0
fi

cryptsetup luksFormat /dev/vg0/httpdata || handle_error "Failed to encrypt volume"

# Step 3: Open the encrypted volume
print_step "3" "Opening the encrypted volume (please enter the passphrase)..."
cryptsetup open /dev/vg0/httpdata crypthttp || handle_error "Failed to open encrypted volume"

# Step 4: Format the partition
print_step "4" "Formatting the partition..."
mkfs.ext4 /dev/mapper/crypthttp || handle_error "Failed to format partition"

# Step 5: Create mount points
print_step "5" "Creating mount points..."
mkdir -p /data/http || handle_error "Failed to create mount points"

# Step 6: Mount the partition
print_step "6" "Mounting the partition..."
mount /dev/mapper/crypthttp /data/http || handle_error "Failed to mount partition"

# Step 7: Create script to mount encrypted partition
print_step "7" "Creating mount script..."
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
    chown USERNAME:http /data/http #Here we use http group for nginx on arch linux
    chmod 750 /data/http
    
    # Restart web server if needed
    systemctl restart nginx
else
    echo "Failed to unlock HTTP data partition."
    exit 1
fi
EOF

# Replace USERNAME placeholder with the actual username
sed -i "s/USERNAME/$username/g" /usr/local/bin/mount-httpdata.sh

chmod +x /usr/local/bin/mount-httpdata.sh || handle_error "Failed to make script executable"

# Step 8: Update user profile to prompt for mounting
print_step "8" "Setting up autostart for user $username..."
if [ -f "$user_home/.bash_profile" ]; then
  grep -q "mount-httpdata.sh" "$user_home/.bash_profile" || cat >>"$user_home/.bash_profile" <<'EOF'

# Check if HTTP partition is mounted
if ! mountpoint -q /data/http; then
    echo "HTTP data partition is not mounted."
    read -p "Would you like to mount it now? (y/n): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        sudo /usr/local/bin/mount-httpdata.sh
    fi
fi
EOF
else
  cat >"$user_home/.bash_profile" <<'EOF'
# Check if HTTP partition is mounted
if ! mountpoint -q /data/http; then
    echo "HTTP data partition is not mounted."
    read -p "Would you like to mount it now? (y/n): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        sudo /usr/local/bin/mount-httpdata.sh
    fi
fi
EOF
fi

# Step 9: Check if Nginx is installed and install if needed
print_step "9" "Checking for Nginx..."
if ! pacman -Q nginx &>/dev/null; then
  print_warning "Nginx is not installed"
  echo "Would you like to install Nginx now? (y/n)"
  read install_nginx
  if [[ "$install_nginx" =~ ^[Yy]$ ]]; then
    pacman -Sy --noconfirm nginx || handle_error "Failed to install Nginx"
    print_success "Nginx installed successfully"
  else
    print_warning "Skipping Nginx installation. You will need to install it later."
  fi
fi

# Step 10: Create a sample website in the mounted directory
print_step "10" "Setting up sample website..."
mkdir -p /data/http/encrypted-arch-linux
if [ -d "/data/http/encrypted-arch-linux" ]; then
  cat >/data/http/encrypted-arch-linux/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Encrypted Arch Linux Server</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 0;
            background: #f4f4f4;
            color: #333;
        }
        .container {
            width: 80%;
            margin: 0 auto;
            overflow: hidden;
            padding: 20px;
        }
        header {
            background: #0088cc;
            color: white;
            padding: 20px;
            text-align: center;
        }
        .content {
            background: white;
            padding: 20px;
            margin-top: 20px;
            border-radius: 5px;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
        }
        .success {
            color: #0088cc;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <header>
        <h1>Encrypted Arch Linux Web Server</h1>
    </header>
    <div class="container">
        <div class="content">
            <h2>Configuration Successful!</h2>
            <p>Your encrypted web server is now properly configured and working.</p>
            <p class="success">This website is being served from an encrypted partition that is only accessible when unlocked!</p>
            <h3>Next Steps:</h3>
            <ul>
                <li>Replace this file with your actual website content</li>
                <li>Configure additional Nginx settings as needed</li>
                <li>Set up SSL certificates for secure HTTPS connections</li>
            </ul>
            <p>The encrypted partition will be mounted at login when the user chooses to unlock it.</p>
            <h3>Security Features:</h3>
            <ul>
                <li>Full disk encryption for web content</li>
                <li>Content is only accessible when explicitly unlocked</li>
                <li>User-based access control via sudo permissions</li>
            </ul>
        </div>
    </div>
</body>
</html>
EOF

  # Configure Nginx to serve the website
  if [ -d "/etc/nginx/sites-available" ]; then
    nginx_conf_dir="/etc/nginx/sites-available"
    nginx_enabled_dir="/etc/nginx/sites-enabled"
    mkdir -p "$nginx_enabled_dir" 2>/dev/null
  else
    nginx_conf_dir="/etc/nginx/conf.d"
    nginx_enabled_dir=""
    mkdir -p "$nginx_conf_dir" 2>/dev/null
  fi

  cat >"$nginx_conf_dir/encrypted-site.conf" <<EOF
server {
    listen 80;
    server_name localhost;

    root /data/http/encrypted-arch-linux;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

  # Enable the site if using sites-enabled
  if [ -n "$nginx_enabled_dir" ] && [ ! -L "$nginx_enabled_dir/encrypted-site.conf" ]; then
    ln -s "$nginx_conf_dir/encrypted-site.conf" "$nginx_enabled_dir/encrypted-site.conf"
  fi

  print_success "Sample website created at /data/http/encrypted-arch-linux"
else
  print_warning "Could not create sample website. Directory /data/http/encrypted-arch-linux is not available."
fi

# Set proper permissions
print_info "Setting correct permissions..."
chown -R $username:http /data/http
chmod -R 750 /data/http

# Enable and start Nginx
print_info "Enabling and starting Nginx..."
systemctl enable nginx
systemctl restart nginx

# Configure sudo permissions for mount script
print_info "Configuring sudo permissions for mount script..."
if ! grep -q "mount-httpdata.sh" /etc/sudoers.d/*; then
  echo "$username ALL=(ALL) NOPASSWD: /usr/local/bin/mount-httpdata.sh" >"/etc/sudoers.d/$username" || handle_error "Failed to update sudoers"
  chmod 440 "/etc/sudoers.d/$username"
  print_success "Sudo permissions configured"
else
  print_info "Sudo permissions already configured"
fi

# Final summary
print_section "Setup Complete"

echo -e "${GREEN}${BOLD}┌───────────────────────────────────────────────────────────────┐${NC}"
echo -e "${GREEN}${BOLD}│ Encrypted Web Server Configuration Complete                   │${NC}"
echo -e "${GREEN}${BOLD}└───────────────────────────────────────────────────────────────┘${NC}"
echo -e
echo -e "  ${GREEN}✓${NC} Encrypted HTTP partition has been created and configured"
echo -e "  ${GREEN}✓${NC} User '$username' will be prompted to mount the partition at login"
echo -e "  ${GREEN}✓${NC} Nginx has been configured to serve content from /data/http/encrypted-arch-linux"
echo -e "  ${GREEN}✓${NC} Mount script is available at: /usr/local/bin/mount-httpdata.sh"
echo

# Let user know if partition will be unmounted at reboot
if ! grep -q "crypthttp" /etc/crypttab; then
  echo -e "${YELLOW}${BOLD}┌───────────────────────────────────────────────────────────────┐${NC}"
  echo -e "${YELLOW}${BOLD}│ Important Notes                                                │${NC}"
  echo -e "${YELLOW}${BOLD}└───────────────────────────────────────────────────────────────┘${NC}"
  echo -e "  ${YELLOW}!${NC} The encrypted partition will not be automatically unlocked at boot"
  echo -e "  ${YELLOW}!${NC} To make it persistent across reboots, add entries to:"
  echo -e "     - /etc/crypttab"
  echo -e "     - /etc/fstab"
  echo
fi

# Final check if everything is working
if mountpoint -q /data/http && systemctl is-active --quiet nginx; then
  echo -e "${GREEN}${BOLD}┌───────────────────────────────────────────────────────────────┐${NC}"
  echo -e "${GREEN}${BOLD}│ Status: All services are running correctly!                    │${NC}"
  echo -e "${GREEN}${BOLD}└───────────────────────────────────────────────────────────────┘${NC}"
else
  echo -e "${YELLOW}${BOLD}┌───────────────────────────────────────────────────────────────┐${NC}"
  echo -e "${YELLOW}${BOLD}│ Warning: There may be issues with the setup                    │${NC}"
  echo -e "${YELLOW}${BOLD}└───────────────────────────────────────────────────────────────┘${NC}"
  echo -e "  ${YELLOW}!${NC} Please check the logs for more information:"
  echo -e "     - Nginx logs: /var/log/nginx/error.log"
  echo -e "     - System logs: journalctl -xe"
fi

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
