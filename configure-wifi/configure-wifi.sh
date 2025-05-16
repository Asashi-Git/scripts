#!/bin/bash

# WiFi Connection Manager
# A script to simplify WiFi connections using basic nmcli commands

function scan_networks() {
	echo "Scanning for WiFi networks..."
	nmcli device wifi rescan
	sleep 2
	nmcli device wifi list
}

function connect_to_network() {
	local ssid="$1"
	local password="$2"

	echo "Attempting to connect to $ssid..."

	# Basic connection command - nmcli handles security type automatically
	if [ -z "$password" ]; then
		# Connect without password if no password is provided
		nmcli device wifi connect "$ssid"
	else
		# Connect with password
		nmcli device wifi connect "$ssid" password "$password"
	fi

	# Check if connection was successful
	if [ $? -eq 0 ]; then
		echo "Successfully connected to $ssid"
		# Save the network details to our connection history
		echo "$ssid:$password" >>~/.wifi_connections
	else
		echo "Failed to connect to $ssid"
		return 1
	fi
}

function show_saved_networks() {
	if [ -f ~/.wifi_connections ]; then
		echo "Saved networks:"
		cat ~/.wifi_connections | cut -d':' -f1
	else
		echo "No saved networks found."
	fi
}

function reconnect_to_saved() {
	local ssid="$1"
	if [ -f ~/.wifi_connections ]; then
		saved=$(grep "^${ssid}:" ~/.wifi_connections)
		if [ -n "$saved" ]; then
			password=$(echo "$saved" | cut -d':' -f2)
			connect_to_network "$ssid" "$password"
		else
			echo "Network $ssid not found in saved connections."
		fi
	else
		echo "No saved networks found."
	fi
}

function show_current_connection() {
	echo "Current connection status:"
	nmcli device status | grep wifi
	echo ""
	nmcli connection show --active
	echo ""
	nmcli device wifi show
}

# Main menu
while true; do
	echo ""
	echo "===== WiFi Connection Manager ====="
	echo "1. Scan for networks"
	echo "2. Connect to a network"
	echo "3. View saved networks"
	echo "4. Reconnect to a saved network"
	echo "5. Show current connection"
	echo "6. Exit"
	echo ""
	read -p "Select an option: " choice

	case $choice in
	1) scan_networks ;;
	2)
		read -p "Enter SSID: " ssid
		read -s -p "Enter password (leave empty for open networks): " password
		echo ""
		connect_to_network "$ssid" "$password"
		;;
	3) show_saved_networks ;;
	4)
		read -p "Enter SSID to reconnect: " ssid
		reconnect_to_saved "$ssid"
		;;
	5) show_current_connection ;;
	6)
		echo "Exiting."
		exit 0
		;;
	*) echo "Invalid option. Please try again." ;;
	esac
done
