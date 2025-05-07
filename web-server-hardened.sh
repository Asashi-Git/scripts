#!/bin/bash

# LUKS-Encrypted HTTP Partition Setup Script for Arch Linux
# This script:
# 1. Creates an encrypted logical volume for HTTP data
# 2. Sets up mount scripts and automation
# 3. Configures Nginx to work with the encrypted partition
# 4. Sets up appropriate permissions and ownership
# 5. Implements a maintenance page fallback
# 6. Fetches website content from GitHub repository

# Check if running as root
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root"
	exit 1
fi

# Default settings
BACKUP_DIR="/root/httpencrypt_backup"
VOLUME_GROUP="vg0"
LOGICAL_VOLUME="httpdata"
CRYPT_NAME="crypthttp"
HTTP_MOUNT_PATH="/data/http"
HTTP_DATA_SIZE="5G"
ADMIN_USER="localadm"
NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_HTML_DIR="/usr/share/nginx/html"
NGINX_MAINTENANCE="${NGINX_HTML_DIR}/maintenance.html"
MAINTENANCE_URL="https://raw.githubusercontent.com/Asashi-Git/scripts/main/maintenance.html"
MOUNT_SCRIPT="/usr/local/bin/mount-httpdata.sh"
WEBSITE_REPO="https://github.com/Asashi-Git/encrypted-arch-linux.git"
WEBSITE_PATH="${HTTP_MOUNT_PATH}/encrypted-arch-linux"

# Create backup directory
mkdir -p $BACKUP_DIR

echo "===== LUKS-Encrypted HTTP Partition Setup ====="

# Function to create necessary directories
create_dirs() {
	mkdir -p $HTTP_MOUNT_PATH
	mkdir -p $NGINX_HTML_DIR
	echo "✓ Created necessary directories"
}

# Function to check if volume exists
check_volume() {
	if lvdisplay ${VOLUME_GROUP}/${LOGICAL_VOLUME} &>/dev/null; then
		echo "Volume ${VOLUME_GROUP}/${LOGICAL_VOLUME} already exists."
		return 0
	else
		return 1
	fi
}

# Function to check if a volume group exists
check_vg() {
	local vg=$1
	if vgdisplay $vg &>/dev/null; then
		return 0
	else
		return 1
	fi
}

# Function to check if a package is installed
check_package() {
	local pkg=$1
	if pacman -Q $pkg &>/dev/null; then
		return 0
	else
		return 1
	fi
}

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

# Step 1: Check prerequisites
echo -e "\n[1/8] Checking prerequisites..."

# Check if we're running from installation media or regular system
if [ -f /etc/arch-release ] && [ ! -f /etc/hostname ]; then
	IN_INSTALLER=true
	echo "✓ Running from Arch Linux installation media"
else
	IN_INSTALLER=false
	echo "⚠️ Not running from installation media. Some operations might fail."
	echo "   It's recommended to perform these steps from Arch installation media."

	read -p "Continue anyway? (y/n): " choice
	if [[ ! "$choice" =~ ^[Yy]$ ]]; then
		echo "Exiting as requested."
		exit 1
	fi
fi

# Check for required packages
required_pkgs=("lvm2" "cryptsetup" "nginx" "git" "curl")
missing_pkgs=()

for pkg in "${required_pkgs[@]}"; do
	if ! check_package $pkg; then
		missing_pkgs+=($pkg)
	fi
done

if [ ${#missing_pkgs[@]} -gt 0 ]; then
	echo "Installing missing packages: ${missing_pkgs[*]}"
	pacman -Syu --noconfirm
	pacman -S --noconfirm ${missing_pkgs[*]}
fi

# Check if volume group exists
if ! check_vg $VOLUME_GROUP; then
	echo "❌ Volume group $VOLUME_GROUP does not exist."
	echo "Please create it first with vgcreate or specify a different volume group."
	exit 1
fi

# Step 2: Create encrypted logical volume
echo -e "\n[2/8] Setting up encrypted logical volume..."

# Check if logical volume already exists
if check_volume; then
	read -p "Logical volume ${LOGICAL_VOLUME} already exists. Overwrite? (y/n): " choice
	if [[ "$choice" =~ ^[Yy]$ ]]; then
		echo "Removing existing logical volume..."

		# First check if it's mounted
		if grep -qs "/dev/mapper/${CRYPT_NAME}" /proc/mounts; then
			umount /dev/mapper/${CRYPT_NAME} 2>/dev/null
			cryptsetup close ${CRYPT_NAME} 2>/dev/null
		fi

		lvremove -f ${VOLUME_GROUP}/${LOGICAL_VOLUME}
	else
		echo "Skipping logical volume creation."
		SKIP_LV_CREATE=true
	fi
fi

if [ "$SKIP_LV_CREATE" != "true" ]; then
	echo "Creating logical volume..."
	if ! lvcreate -L ${HTTP_DATA_SIZE} ${VOLUME_GROUP} -n ${LOGICAL_VOLUME}; then
		echo "❌ Failed to create logical volume."
		exit 1
	fi
	echo "✓ Logical volume created successfully."

	echo "Encrypting volume with LUKS..."
	echo -n "Enter passphrase for LUKS encryption: "
	read -s LUKS_PASSPHRASE
	echo

	echo -n "Confirm passphrase: "
	read -s LUKS_PASSPHRASE_CONFIRM
	echo

	if [ "$LUKS_PASSPHRASE" != "$LUKS_PASSPHRASE_CONFIRM" ]; then
		echo "❌ Passphrases don't match."
		exit 1
	fi

	# Use a here-string to provide the passphrase
	echo "$LUKS_PASSPHRASE" | cryptsetup luksFormat /dev/${VOLUME_GROUP}/${LOGICAL_VOLUME} -

	if [ $? -ne 0 ]; then
		echo "❌ Failed to encrypt volume."
		exit 1
	fi
	echo "✓ Volume encrypted successfully."

	# Open the encrypted volume
	echo "Opening encrypted volume..."
	echo "$LUKS_PASSPHRASE" | cryptsetup open /dev/${VOLUME_GROUP}/${LOGICAL_VOLUME} ${CRYPT_NAME} -

	if [ $? -ne 0 ]; then
		echo "❌ Failed to open encrypted volume."
		exit 1
	fi
	echo "✓ Encrypted volume opened successfully."

	# Format the new partition
	echo "Formatting encrypted volume with ext4..."
	if ! mkfs.ext4 /dev/mapper/${CRYPT_NAME}; then
		echo "❌ Failed to format encrypted volume."
		exit 1
	fi
	echo "✓ Volume formatted successfully."
fi

# Step 3: Create necessary directories
echo -e "\n[3/8] Creating mount points and directories..."
create_dirs

# Mount the encrypted volume if not already mounted
if ! grep -qs "/dev/mapper/${CRYPT_NAME}" /proc/mounts; then
	echo "Mounting encrypted volume..."
	if ! mount /dev/mapper/${CRYPT_NAME} ${HTTP_MOUNT_PATH}; then
		echo "❌ Failed to mount encrypted volume."
		exit 1
	fi
	echo "✓ Encrypted volume mounted successfully."
else
	echo "✓ Encrypted volume is already mounted."
fi

# Step 4: Create mount helper script
echo -e "\n[4/8] Creating mount helper script..."

cat >${MOUNT_SCRIPT} <<'EOF'
#!/bin/bash

# Mount script for HTTP encrypted data partition

# Variables
VOLUME_GROUP="vg0"
LOGICAL_VOLUME="httpdata"
CRYPT_NAME="crypthttp"
HTTP_MOUNT_PATH="/data/http"
ADMIN_USER="localadm"

# Check if already mounted
if mountpoint -q ${HTTP_MOUNT_PATH}; then
    echo "HTTP data partition is already mounted."
    exit 0
fi

# Try to unlock and mount
echo "Unlocking HTTP data partition..."
if cryptsetup open /dev/${VOLUME_GROUP}/${LOGICAL_VOLUME} ${CRYPT_NAME}; then
    echo "Mounting HTTP data partition..."
    mount /dev/mapper/${CRYPT_NAME} ${HTTP_MOUNT_PATH}
    echo "HTTP data partition mounted successfully."
    
    # Set proper ownership and permissions
    chown ${ADMIN_USER}:http ${HTTP_MOUNT_PATH}
    chmod 750 ${HTTP_MOUNT_PATH}
    
    # Restart web server if needed
    if systemctl is-active --quiet nginx; then
        systemctl restart nginx
        echo "Nginx restarted."
    else
        echo "Nginx is not running. No restart needed."
    fi
else
    echo "Failed to unlock HTTP data partition."
    exit 1
fi
EOF

# Replace variables in the script
sed -i "s/VOLUME_GROUP=\"vg0\"/VOLUME_GROUP=\"${VOLUME_GROUP}\"/g" ${MOUNT_SCRIPT}
sed -i "s/LOGICAL_VOLUME=\"httpdata\"/LOGICAL_VOLUME=\"${LOGICAL_VOLUME}\"/g" ${MOUNT_SCRIPT}
sed -i "s/CRYPT_NAME=\"crypthttp\"/CRYPT_NAME=\"${CRYPT_NAME}\"/g" ${MOUNT_SCRIPT}
sed -i "s|HTTP_MOUNT_PATH=\"/data/http\"|HTTP_MOUNT_PATH=\"${HTTP_MOUNT_PATH}\"|g" ${MOUNT_SCRIPT}
sed -i "s/ADMIN_USER=\"localadm\"/ADMIN_USER=\"${ADMIN_USER}\"/g" ${MOUNT_SCRIPT}

# Make script executable
chmod +x ${MOUNT_SCRIPT}
echo "✓ Mount helper script created at ${MOUNT_SCRIPT}"

# Step 5: Configure auto-mount on user login
echo -e "\n[5/8] Configuring auto-mount on user login..."

# Check if user localadm exists
if id "$ADMIN_USER" &>/dev/null; then
	ADMIN_HOME=$(eval echo ~${ADMIN_USER})

	# Backup .bash_profile if it exists
	if [ -f "${ADMIN_HOME}/.bash_profile" ]; then
		backup_file "${ADMIN_HOME}/.bash_profile"
	fi

	# Add the mount check to bash_profile
	cat >>"${ADMIN_HOME}/.bash_profile" <<'EOF'

# Check if HTTP partition is mounted
if ! mountpoint -q /data/http; then
    echo "HTTP data partition is not mounted."
    read -p "Would you like to mount it now? (y/n): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        sudo /usr/local/bin/mount-httpdata.sh
    fi
fi
EOF

	# Update path in bash_profile
	sed -i "s|/data/http|${HTTP_MOUNT_PATH}|g" "${ADMIN_HOME}/.bash_profile"
	sed -i "s|/usr/local/bin/mount-httpdata.sh|${MOUNT_SCRIPT}|g" "${ADMIN_HOME}/.bash_profile"

	# Set proper ownership
	chown ${ADMIN_USER}:${ADMIN_USER} "${ADMIN_HOME}/.bash_profile"

	echo "✓ Auto-mount configured in user's bash profile"
else
	echo "⚠️ User ${ADMIN_USER} does not exist. Skipping bash_profile configuration."
	echo "   You'll need to manually configure auto-mount for your admin user."
fi

# Step 6: Download maintenance page and website content
echo -e "\n[6/8] Downloading maintenance page and website content..."

# Download maintenance page
echo "Downloading maintenance page..."
if curl -s -o "${NGINX_MAINTENANCE}" "${MAINTENANCE_URL}"; then
	echo "✓ Maintenance page downloaded to ${NGINX_MAINTENANCE}"
else
	echo "❌ Failed to download maintenance page"
	# Create a basic maintenance page as fallback
	cat >"${NGINX_MAINTENANCE}" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Site Maintenance</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #333; }
        p { color: #666; }
    </style>
</head>
<body>
    <h1>Site Under Maintenance</h1>
    <p>Sorry for the inconvenience. We're performing scheduled maintenance at the moment.</p>
    <p>Please check back soon.</p>
</body>
</html>
EOF
	echo "✓ Created basic maintenance page as fallback"
fi

# Clone website repository
echo "Cloning website repository..."
if [ -d "${WEBSITE_PATH}" ]; then
	echo "Website directory already exists. Updating..."
	cd "${WEBSITE_PATH}" && git pull
	echo "✓ Website content updated"
else
	if git clone "${WEBSITE_REPO}" "${WEBSITE_PATH}"; then
		echo "✓ Website content cloned successfully to ${WEBSITE_PATH}"
	else
		echo "❌ Failed to clone website content"
		# Create a basic index file as fallback
		mkdir -p "${WEBSITE_PATH}"
		cat >"${WEBSITE_PATH}/encrypted-arch-linux.html" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Encrypted Arch Linux</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #1793d1; }
        p { color: #333; }
    </style>
</head>
<body>
    <h1>Encrypted Arch Linux</h1>
    <p>This is a placeholder page for the encrypted HTTP partition.</p>
    <p>If you're seeing this page, the encryption setup was successful!</p>
</body>
</html>
EOF
		echo "✓ Created basic index file as fallback"
	fi
fi

# Set proper ownership and permissions for website content
chown -R ${ADMIN_USER}:http "${WEBSITE_PATH}"
chmod -R 750 "${WEBSITE_PATH}"

# Step 7: Configure Nginx
echo -e "\n[7/8] Configuring Nginx..."

# Backup nginx.conf if it exists
backup_file "${NGINX_CONF}"

# Create http group if it doesn't exist
if ! getent group http >/dev/null; then
	echo "Creating http group..."
	groupadd http
fi

# Add admin user to http group
usermod -a -G http ${ADMIN_USER}

# Configure Nginx
cat >${NGINX_CONF} <<'EOF'
user http;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
    # multi_accept on;
}

http {
    # Basic settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging settings
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;

    # Gzip settings
    gzip on;
    
    # Virtual Host Configs
    server {
        listen 80;
        server_name www.manual-arch-install.local;
        
        root /data/http/encrypted-arch-linux;
        index encrypted-arch-linux.html;
        
        #Maintenance page logic
        error_page 403 404 /maintenance.html;
        location = /maintenance.html {
            root /usr/share/nginx/html;
            internal;
        }
        
        access_log /var/log/nginx/access.log;
        error_log  /var/log/nginx/error.log warn;
        
        location / {
            try_files $uri $uri/ =404;
        }
    }
}
EOF

# Update paths in nginx.conf
sed -i "s|/data/http/encrypted-arch-linux|${WEBSITE_PATH}|g" ${NGINX_CONF}
sed -i "s|/usr/share/nginx/html|${NGINX_HTML_DIR}|g" ${NGINX_CONF}

echo "✓ Nginx configured with maintenance page fallback"

# Step 8: Enable and start services
echo -e "\n[8/8] Enabling and starting services..."

# Create required directories and set permissions for nginx
mkdir -p /var/log/nginx
chown -R http:http /var/log/nginx

# Enable and start nginx service
systemctl enable nginx
systemctl restart nginx

echo "✓ Nginx service enabled and started"

# Final output
echo -e "\n===== LUKS-Encrypted HTTP Partition Setup Complete! ====="
echo "Your encrypted HTTP partition is set up and ready to use."
echo -e "\nImportant information:"
echo "- Encrypted partition: /dev/${VOLUME_GROUP}/${LOGICAL_VOLUME}"
echo "- Mount point: ${HTTP_MOUNT_PATH}"
echo "- Mount script: ${MOUNT_SCRIPT}"
echo "- Website content: ${WEBSITE_PATH}"
echo "- Nginx maintenance page: ${NGINX_MAINTENANCE}"
echo -e "\nThe encrypted HTTP partition will be mounted automatically when ${ADMIN_USER} logs in."
echo "To manually mount the partition, run: sudo ${MOUNT_SCRIPT}"
echo "To test Nginx, visit: http://www.manual-arch-install.local or http://localhost"
echo -e "\nDon't forget to add the hostname to your /etc/hosts file if needed:"
echo "127.0.0.1 www.manual-arch-install.local"
echo -e "\nCongratulations! Your Arch Linux web server with encrypted HTTP partition is now complete."
