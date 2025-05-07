#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Function to handle errors
handle_error() {
  echo "ERROR: $1"
  exit 1
}

echo "========== Creating and Setting Up Encrypted HTTP Partition =========="

# Step 1: Create the logical volume
echo "[1/10] Creating logical volume 'httpdata'..."
lvcreate -L 5G vg0 -n httpdata || handle_error "Failed to create logical volume"

# Step 2: Encrypt the logical volume
echo "[2/10] Encrypting the volume (you will be prompted for a passphrase)..."
echo "This will overwrite any data on /dev/vg0/httpdata. Are you sure? (y/n)"
read confirmation
if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
  echo "Operation cancelled"
  exit 0
fi

cryptsetup luksFormat /dev/vg0/httpdata || handle_error "Failed to encrypt volume"

# Step 3: Open the encrypted volume
echo "[3/10] Opening the encrypted volume (please enter the passphrase)..."
cryptsetup open /dev/vg0/httpdata crypthttp || handle_error "Failed to open encrypted volume"

# Step 4: Format the partition
echo "[4/10] Formatting the partition..."
mkfs.ext4 /dev/mapper/crypthttp || handle_error "Failed to format partition"

# Step 5: Create mount points
echo "[5/10] Creating mount points..."
mkdir -p /data/http || handle_error "Failed to create mount points"

# Step 6: Mount the partition
echo "[6/10] Mounting the partition..."
mount /dev/mapper/crypthttp /data/http || handle_error "Failed to mount partition"

# Step 7: Create script to mount encrypted partition
echo "[7/10] Creating mount script..."
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
    chown localadm:http /data/http #Here we use http group for nginx on arch linux
    chmod 750 /data/http
    
    # Restart web server if needed
    systemctl restart nginx
else
    echo "Failed to unlock HTTP data partition."
    exit 1
fi
EOF

chmod +x /usr/local/bin/mount-httpdata.sh || handle_error "Failed to make script executable"

# Step 8: Update user profile to prompt for mounting
echo "[8/10] Setting up autostart for localadm user..."
if [ -f /home/localadm/.bash_profile ]; then
  grep -q "mount-httpdata.sh" /home/localadm/.bash_profile || cat >>/home/localadm/.bash_profile <<'EOF'

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
  cat >/home/localadm/.bash_profile <<'EOF'
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

chown localadm:localadm /home/localadm/.bash_profile || handle_error "Failed to set ownership for bash_profile"

# Step 9: Install and configure Nginx
echo "[9/10] Installing and configuring Nginx..."
pacman -Syu --noconfirm || handle_error "Failed to update system"
pacman -S --noconfirm nginx git || handle_error "Failed to install required packages"

# Create http group if it doesn't exist
groupadd -f http

# Ensure localadm user is in the http group
usermod -a -G http localadm

# Download maintenance page
mkdir -p /usr/share/nginx/html
curl -o /usr/share/nginx/html/maintenance.html https://raw.githubusercontent.com/Asashi-Git/scripts/main/maintenance.html 2>/dev/null

# If curl fails, create a basic maintenance page
if [ ! -f /usr/share/nginx/html/maintenance.html ]; then
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

# Step 10: Set up website content
echo "[10/10] Setting up website content..."
pushd /tmp >/dev/null

# Try to clone the repository
git clone https://github.com/Asashi-Git/encrypted-arch-linux.git 2>/dev/null
if [ -d encrypted-arch-linux ]; then
  # If clone succeeded
  mv encrypted-arch-linux /data/http/ || handle_error "Failed to move website files"
else
  # Create placeholder content if git clone fails
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
chown -R localadm:http /data/http
chmod -R 750 /data/http

# Enable and start Nginx
systemctl enable nginx
systemctl restart nginx

# Final message
echo ""
echo "========== Setup Complete =========="
echo "Encrypted HTTP partition has been created and configured."
echo "When localadm logs in, they will be prompted to mount the encrypted partition."
echo "To manually mount the partition, run: sudo /usr/local/bin/mount-httpdata.sh"
echo ""
echo "Nginx has been configured to serve content from /data/http/encrypted-arch-linux"
echo ""

# Let user know if partition will be unmounted at reboot
if ! grep -q "crypthttp" /etc/crypttab; then
  echo "NOTE: The encrypted partition will not be automatically unlocked at boot."
  echo "To make it persistent across reboots, add an entry to /etc/crypttab and /etc/fstab."
  echo ""
fi

# Final check if everything is working
if mountpoint -q /data/http && systemctl is-active --quiet nginx; then
  echo "All services are running correctly!"
else
  echo "WARNING: There may be issues with the setup. Please check the logs."
fi

exit 0
