#!/bin/bash

# arch-setup.sh - Automated setup script for Arch Linux
# Created for educational purposes

# Print colored output for better readability
print_status() {
	echo -e "\e[1;34m[*]\e[0m $1"
}

print_success() {
	echo -e "\e[1;32m[+]\e[0m $1"
}

print_error() {
	echo -e "\e[1;31m[!]\e[0m $1"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
	print_error "Please do not run this script as root or with sudo"
	exit 1
fi

# Check virtualization environment
print_status "Checking virtualization environment..."
if systemd-detect-virt -q; then
	virt_type=$(systemd-detect-virt)
	print_status "Running in a $virt_type virtual machine"
	is_vm=true
else
	print_status "Running on physical hardware"
	is_vm=false
fi

# Make sure system is up to date first
print_status "Updating system packages..."
sudo pacman -Syu --noconfirm || {
	print_error "Failed to update system"
	exit 1
}
print_success "System updated successfully"

# Install required packages
print_status "Installing Hyprland and related packages..."
sudo pacman -S --needed --noconfirm \
	hyprland \
	ly \
	xdg-desktop-portal-hyprland \
	waybar \
	mako \
	kitty \
	wofi \
	rofi \
	grim \
	slurp \
	swappy \
	mesa \
	nemo \
	libva-mesa-driver \
	mesa-vdpau \
	vulkan-radeon \
	vulkan-intel \
	vulkan-mesa-layers \
	git \
	zsh \
	curl \
	chromium \
	hyprlock \
	hyprpaper \
	neofetch \
	swaylock \
	wl-clipboard \
	net-tools \
	sof-firmware \
	vim \
	neovim \
	nano \
	rofi-wayland \
	ttf-dejavu \
	noto-fonts \
	noto-fonts-cjk \
	noto-fonts-emoji \
	ttf-liberation \
	ttf-jetbrains-mono \
	ttf-fira-code \
	ttf-cascadia-code \
	ttf-roboto \
	ttf-ubuntu-font-family \
	ttf-opensans \
	font-manager \
	pipewire \
	pipewire-pulse \
	pipewire-alsa \
	pipewire-jack \
	wireplumber \
	pipewire-audio \
	pavucontrol \
	jq \
	blueman \
	bluez \
	bluez-utils \
	base-devel || {
	print_error "Failed to install some packages"
	exit 1
}
print_success "Packages installed successfully"

print_status "Enable Audio Drivers"
systemctl --user enable --now pipewire.service
systemctl --user enable --now pipewire-pulse.service
systemctl --user enable --now wireplumber.service
sudo systemctl start bluetooth.service
sudo systemctl enable bluetooth.service
print_success "Driver Audio Installed"

# Install yay AUR helper
print_status "Installing yay AUR helper..."
if command -v yay &>/dev/null; then
	print_status "yay is already installed!"
else
	print_status "Cleaning any existing yay build directories..."
	rm -rf /tmp/yay 2>/dev/null

	print_status "Cloning yay repository..."
	git clone https://aur.archlinux.org/yay.git /tmp/yay || {
		print_error "Failed to clone yay repository"
		exit 1
	}

	print_status "Building and installing yay..."
	cd /tmp/yay || exit 1
	makepkg -si --noconfirm || {
		print_error "Failed to install yay"
		exit 1
	}
	cd - || exit 1
	print_success "yay installed successfully"
fi

print_status "Try to install SwayNc"
yay -S swaync
systemctl --user stop dunst
systemctl --user disable dunst
systemctl --user enable --now swaync
notify-send "Test Notification" "This should appear in SwayNC!"
print_success "SwayNc Installed!"

print_status "Try to install hyprshot"
yay -S hyprshot-git
print_success "Hyprshot Installed!"

# Install hyprshot from AUR
print_status "Installing hyprshot from AUR..."
if command -v hyprshot &>/dev/null; then
	print_status "hyprshot is already installed!"
else
	# Clean any existing build directories first
	rm -rf "$HOME/.cache/yay/hyprshot" 2>/dev/null

	# Install using yay
	yay -S --needed --noconfirm hyprshot || {
		print_error "Failed to install hyprshot through yay"

		# Alternative manual installation method if yay fails
		print_status "Attempting manual installation of hyprshot..."
		temp_dir=$(mktemp -d)
		git clone https://github.com/Gustash/hyprshot.git "$temp_dir" || {
			print_error "Failed to clone hyprshot repository"
			print_status "Continuing without hyprshot..."
		}

		if [ -d "$temp_dir" ]; then
			cd "$temp_dir" || exit 1
			sudo make install || print_error "Failed to install hyprshot manually"
			cd - || exit 1
			rm -rf "$temp_dir"
			print_success "Manually installed hyprshot"
		fi
	}
fi

# Create basic directories if they don't exist
print_status "Creating configuration directories..."
mkdir -p ~/.config/hypr
mkdir -p ~/.config/waybar
mkdir -p ~/.config/mako
mkdir -p ~/.config/wofi
mkdir -p ~/.config/kitty
mkdir -p ~/.config/wlogout
print_success "Directories created"

# Enable LY display manager
print_status "Enabling LY display manager..."
sudo systemctl enable ly.service
print_success "LY display manager enabled"

# Fetch dotfiles from GitHub
print_status "Fetching dotfiles from GitHub..."
dotfiles_repo="https://github.com/Asashi-Git/dotfiles.git"
dotfiles_dir="$HOME/.dotfiles"

if [ -d "$dotfiles_dir" ]; then
	print_status "Dotfiles directory already exists. Updating..."
	cd "$dotfiles_dir" && git pull || {
		print_error "Failed to update dotfiles repository"
		exit 1
	}
else
	print_status "Cloning dotfiles repository..."
	git clone "$dotfiles_repo" "$dotfiles_dir" || {
		print_error "Failed to clone dotfiles repository"
		exit 1
	}
fi

# Set up dotfiles (using direct copy)
print_status "Setting up dotfiles..."
dotfiles_source="$dotfiles_dir/dotfiles"

# Copy each configuration directory
for dir in hypr hyprshot nvim rofi swaylock waybar wlogout; do
	if [ -d "$dotfiles_source/$dir" ]; then
		print_status "Copying $dir configuration..."
		cp -r "$dotfiles_source/$dir" "$HOME/.config/" || {
			print_error "Failed to copy $dir configuration"
		}
	fi
done

print_success "Dotfiles have been set up successfully"

print_success "Setup complete! You can now start Hyprland"
if [ "$is_vm" = true ]; then
	print_status "System has been configured for VM environment"
	print_status "Restart your system and select 'Hyprland (VM Optimized)' in LY"
	print_status "If you encounter issues, you can still start Hyprland manually by typing 'Hyprland'"
else
	print_status "Restart your system to use the LY display manager"
	print_status "Or type 'Hyprland' to start your new desktop environment manually"
fi

# Final instructions for new tools
print_status "Additional usage information:"
if command -v wlogout &>/dev/null; then
	print_status "- To use wlogout: press Super + Escape or run 'wlogout' in a terminal"
else
	print_status "- wlogout not detected. You'll need to install it manually later."
fi

if command -v hyprshot &>/dev/null; then
	print_status "- To take screenshots with hyprshot:"
	print_status "  • Super + Print: Full screen screenshot"
	print_status "  • Super + Shift + Print: Region screenshot"
	print_status "  • Super + Ctrl + Print: Window screenshot"
else
	print_status "- hyprshot not detected. You'll need to install it manually later."
fi

print_status "Installing Ohmyzsh"
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
