#!/bin/bash

# ╔═══════════════════════════════════════════════════════════════════╗
# ║  Web Server Hardening Script for Arch Linux                       ║
# ║  This script configures an encrypted web server with NGINX        ║
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
	echo -e "${CYAN}${BOLD}[INFO]${NC} $1"
}

# Function to print step information (numbered steps)
print_step() {
	local step_num="$1"
	local total_steps="$2"
	local description="$3"
	echo -e "${GREEN}${BOLD}[STEP ${step_num}/${total_steps}]${NC} ${description}"
}

# Function to print warnings
print_warning() {
	echo -e "${YELLOW}${BOLD}[WARNING]${NC} $1"
}

# Function to print errors
print_error() {
	echo -e "${RED}${BOLD}[ERROR]${NC} $1"
	exit 1
}

# Function to print success messages
print_success() {
	echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"
}

# Function to get user confirmation
confirm() {
	local prompt="$1"
	local answer

	echo -ne "${CYAN}${prompt} (y/n): ${NC}"
	read answer

	if [[ "$answer" =~ ^[Yy]$ ]]; then
		return 0
	else
		return 1
	fi
}

# Function to handle errors
handle_error() {
	print_error "$1"
	exit 1
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Check if script is run as root                                   │
# └─────────────────────────────────────────────────────────────────┘
check_root() {
	if [ "$EUID" -ne 0 ]; then
		print_error "This script must be run as root"
		exit 1
	fi
}

# ┌─────────────────────────────────────────────────────────────────┐
# │ Main script                                                      │
# └─────────────────────────────────────────────────────────────────┘
main() {
	# Display header
	clear
	echo
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

	echo -e "${CYAN}${BOLD}┌───────────────────────────────────────────────────────────────┐${NC}"
	echo -e "${CYAN}${BOLD}│ Encrypted Web Server Setup for Arch Linux                     │${NC}"
	echo -e "${CYAN}${BOLD}└───────────────────────────────────────────────────────────────┘${NC}"
	echo -e "  ${GREEN}▶${NC} Creates a secure encrypted partition for web content"
	echo -e "  ${GREEN}▶${NC} Configures NGINX with hardened settings"
	echo -e "  ${GREEN}▶${NC} Sets up user-prompted mount for enhanced security"
	echo -e "  ${GREEN}▶${NC} Implements proper ownership and permissions"
	echo -e "  ${GREEN}▶${NC} Provides maintenance and fallback pages"
	echo

	TOTAL_STEPS=10

	# Check if running as root
	check_root

	# Ask for the username
	print_section "User Configuration"
	echo -ne "${CYAN}Enter the username for which to configure the auto-mount prompt (e.g., localadm): ${NC}"
	read username

	# Validate that the user exists
	if ! id "$username" &>/dev/null; then
		print_warning "User '$username' does not exist."
		if confirm "Would you like to create this user?"; then
			useradd -m "$username" || handle_error "Failed to create user"
			print_info "Setting password for new user '$username'"
			passwd "$username" || handle_error "Failed to set password"
			print_success "User '$username' created successfully"
		else
			handle_error "User does not exist. Please specify a valid username."
		fi
	else
		print_success "User '$username' exists"
	fi

	# Get the home directory of the user
	user_home=$(eval echo ~$username)
	if [ ! -d "$user_home" ]; then
		handle_error "Home directory for user '$username' not found"
	fi

	print_info "Using home directory: ${BOLD}$user_home${NC}"

	# Step 1: Create the logical volume
	print_section "Logical Volume Setup"
	print_step 1 $TOTAL_STEPS "Creating logical volume 'httpdata'..."
	lvcreate -L 5G vg0 -n httpdata || handle_error "Failed to create logical volume"
	print_success "Logical volume created"

	# Step 2: Encrypt the logical volume
	print_step 2 $TOTAL_STEPS "Encrypting the volume (you will be prompted for a passphrase)..."
	print_warning "This will overwrite any data on /dev/vg0/httpdata."
	if ! confirm "Are you sure you want to continue?"; then
		echo -e "${YELLOW}Operation cancelled by user${NC}"
		exit 0
	fi

	cryptsetup luksFormat /dev/vg0/httpdata || handle_error "Failed to encrypt volume"
	print_success "Volume encrypted successfully"

	# Step 3: Open the encrypted volume
	print_step 3 $TOTAL_STEPS "Opening the encrypted volume..."
	print_info "Please enter the encryption passphrase when prompted"
	cryptsetup open /dev/vg0/httpdata crypthttp || handle_error "Failed to open encrypted volume"
	print_success "Encrypted volume opened"

	# Step 4: Format the partition
	print_step 4 $TOTAL_STEPS "Formatting the partition..."
	mkfs.ext4 /dev/mapper/crypthttp || handle_error "Failed to format partition"
	print_success "Partition formatted with ext4"

	# Step 5: Create mount points
	print_step 5 $TOTAL_STEPS "Creating mount points..."
	mkdir -p /data/http || handle_error "Failed to create mount points"
	print_success "Mount points created"

	# Step 6: Mount the partition
	print_step 6 $TOTAL_STEPS "Mounting the partition..."
	mount /dev/mapper/crypthttp /data/http || handle_error "Failed to mount partition"
	print_success "Partition mounted at /data/http"

	# Step 7: Create script to mount encrypted partition
	print_step 7 $TOTAL_STEPS "Creating mount script..."
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
	print_success "Mount script created: /usr/local/bin/mount-httpdata.sh"

	# Step 8: Update user profile to prompt for mounting
	print_step 8 $TOTAL_STEPS "Setting up autostart for user $username..."
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

	chown $username:$username "$user_home/.bash_profile" || handle_error "Failed to set ownership for bash_profile"
	print_success "Login prompt configured for user $username"

	# Step 9: Install and configure Nginx
	print_section "Web Server Configuration"
	print_step 9 $TOTAL_STEPS "Installing and configuring Nginx..."
	print_info "Updating system..."
	pacman -Syu --noconfirm || handle_error "Failed to update system"

	print_info "Installing Nginx and Git..."
	pacman -S --noconfirm nginx git || handle_error "Failed to install required packages"

	# Create http group if it doesn't exist
	groupadd -f http

	# Ensure user is in the http group
	usermod -a -G http $username
	print_success "Added user $username to the http group"

	# Download maintenance page
	print_info "Setting up maintenance page..."
	mkdir -p /usr/share/nginx/html
	curl -o /usr/share/nginx/html/maintenance.html https://raw.githubusercontent.com/Asashi-Git/scripts/main/maintenance.html 2>/dev/null

	# If curl fails, create a basic maintenance page
	if [ ! -f /usr/share/nginx/html/maintenance.html ]; then
		print_warning "Failed to download maintenance page, creating a basic one"
		cat >/usr/share/nginx/html/maintenance.html <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Site Under Maintenance</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #444; }
        p { color: #666; }
    </style>
</head>
<body>
    <h1>We'll be back soon!</h1>
    <p>Sorry for the inconvenience. We're performing some maintenance at the moment.</p>
</body>
</html>
EOF
	fi

	# Configure Nginx
	print_info "Configuring Nginx..."
	cat >/etc/nginx/nginx.conf <<'EOF'
#user http;
worker_processes 1;

#error_log  logs/error.log;
#error_log  logs/error.log  notice;
#error_log  logs/error.log  info;

#pid        logs/nginx.pid;

# Load all installed modules
include modules.d/*.conf;

events {
    worker_connections 1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    #log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
    #                  '$status $body_bytes_sent "$http_referer" '
    #                  '"$http_user_agent" "$http_x_forwarded_for"';

    #access_log  logs/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    #keepalive_timeout  0;
    keepalive_timeout  65;

    #gzip  on;

    server {
        listen       80;
        server_name  localhost;

        #charset koi8-r;

        #access_log  logs/host.access.log  main;
        root /data/http/encrypted-arch-linux;
        index encrypted-arch-linux.html;

        #location / {
        #    root   /usr/share/nginx/html;
        #    index  index.html index.htm;
        #}

        #error_page  404              /404.html;

        # redirect server error pages to the static page /50x.html
        #
        error_page 403 404 /maintenance.html;
        location = /maintenance.html {
            root   /usr/share/nginx/html;
            internal;
        }

        access_log /var/log/nginx/access.log;
        error_log /var/log/nginx/error.log warn;

        # proxy the PHP scripts to Apache listening on 127.0.0.1:80
        #
        #location ~ \.php$ {
        #    proxy_pass   http://127.0.0.1;
        #}

        # pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000
        #
        #location ~ \.php$ {
        #    root           html;
        #    fastcgi_pass   127.0.0.1:9000;
        #    fastcgi_index  index.php;
        #    fastcgi_param  SCRIPT_FILENAME  /scripts$fastcgi_script_name;
        #    include        fastcgi_params;
        #}

        # deny access to .htaccess files, if Apache's document root
        # concurs with nginx's one
        #
        #location ~ /\.ht {
        #    deny  all;
        #}
    }


    # another virtual host using mix of IP-, name-, and port-based configuration
    #
    #server {
    #    listen       8000;
    #    listen       somename:8080;
    #    server_name  somename  alias  another.alias;

    #    location / {
    #        root   html;
    #        index  index.html index.htm;
    #    }
    #}


    # HTTPS server
    #
    #server {
    #    listen       443 ssl;
    #    server_name  localhost;

    #    ssl_certificate      cert.pem;
    #    ssl_certificate_key  cert.key;

    #    ssl_session_cache    shared:SSL:1m;
    #    ssl_session_timeout  5m;

    #    ssl_ciphers  HIGH:!aNULL:!MD5;
    #    ssl_prefer_server_ciphers  on;

    #    location / {
    #        root   html;
    #        index  index.html index.htm;
    #    }
    #}

}
EOF
	print_success "Nginx configured"

	# Step 10: Set up website content
	print_step 10 $TOTAL_STEPS "Setting up website content..."
	pushd /tmp >/dev/null

	# Try to clone the repository
	print_info "Attempting to clone website content..."
	git clone https://github.com/Asashi-Git/encrypted-arch-linux.git 2>/dev/null
	if [ -d encrypted-arch-linux ]; then
		# If clone succeeded
		print_success "Content downloaded successfully"
		mv encrypted-arch-linux /data/http/ || handle_error "Failed to move website files"
	else
		# Create placeholder content if git clone fails
		print_warning "Could not download content, creating placeholder"
		mkdir -p /data/http/encrypted-arch-linux
		cat >/data/http/encrypted-arch-linux/encrypted-arch-linux.html <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Encrypted Arch Linux</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
        h1 { color: #3498db; }
        .container { max-width: 800px; margin: 0 auto; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to Encrypted Arch Linux</h1>
        <p>This is a placeholder page for the encrypted HTTP partition setup.</p>
        <p>Your encrypted partition is working correctly!</p>
    </div>
</body>
</html>
EOF
	fi

	popd >/dev/null

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
}

# Execute main function
main
