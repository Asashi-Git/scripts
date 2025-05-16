#!/bin/bash

# Network Configuration Script using nmcli
# For educational purposes in cybersecurity

# Text formatting
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BOLD}Network Configuration Utility${NC}\n"

# Function to validate IP address format
validate_ip() {
  local ip=$1
  # Split the IP address into octets
  IFS='.' read -r o1 o2 o3 o4 <<<"$ip"

  # Check if we got exactly 4 octets
  if [ -z "$o1" ] || [ -z "$o2" ] || [ -z "$o3" ] || [ -z "$o4" ]; then
    return 1
  fi

  # Check if each octet is a valid number between 0-255
  for octet in "$o1" "$o2" "$o3" "$o4"; do
    # Check if octet is a number
    if ! [[ "$octet" =~ ^[0-9]+$ ]]; then
      return 1
    fi

    # Check if octet is between 0-255
    if [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
      return 1
    fi
  done

  return 0
}

# Function to validate CIDR notation (mask)
validate_cidr() {
  local cidr=$1
  # Check if input is a number
  if ! [[ "$cidr" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  # Check if number is between 0-32
  if [ "$cidr" -lt 0 ] || [ "$cidr" -gt 32 ]; then
    return 1
  fi

  return 0
}

# Function to display the current configuration for a connection
display_connection_details() {
  local conn_name=$1

  echo -e "${BOLD}Connection Details for: ${YELLOW}$conn_name${NC}"

  # Check if the connection exists
  if ! nmcli -g NAME con show | grep -q "^$conn_name$"; then
    echo -e "${RED}Error: Connection '$conn_name' not found.${NC}"
    return 1
  fi

  # Get connection type (DHCP or STATIC)
  local method=$(nmcli -g ipv4.method con show "$conn_name")

  if [[ "$method" == "auto" ]]; then
    echo -e "IP Configuration: ${GREEN}DHCP (Automatic)${NC}"
  else
    echo -e "IP Configuration: ${GREEN}Static IP${NC}"
  fi

  # Get interface name
  local interface=$(nmcli -g GENERAL.DEVICES con show "$conn_name" 2>/dev/null)
  if [[ -z "$interface" ]]; then
    interface=$(nmcli -g connection.interface-name con show "$conn_name" 2>/dev/null)
  fi

  if [[ -n "$interface" ]]; then
    echo -e "Interface: ${GREEN}$interface${NC}"

    # Check if the interface is active
    local state=$(nmcli -g GENERAL.STATE con show "$conn_name" 2>/dev/null)
    if [[ -n "$state" ]]; then
      echo -e "Connection State: ${GREEN}$state${NC}"
    else
      # Check if connection is active
      if nmcli -t -f NAME,DEVICE con show --active | grep -q "^$conn_name:"; then
        echo -e "Connection State: ${GREEN}Active${NC}"
      else
        echo -e "Connection State: ${RED}Inactive${NC}"
      fi
    fi

    # Display IP address
    local ip_address=$(nmcli -g ipv4.addresses con show "$conn_name")
    if [[ -n "$ip_address" ]]; then
      echo -e "IP Address: ${GREEN}$ip_address${NC}"
    else
      # Try to get IP from the interface if it's active
      local current_ip=$(ip addr show $interface 2>/dev/null | grep -w "inet" | awk '{print $2}')
      if [[ -n "$current_ip" ]]; then
        echo -e "Current IP Address: ${GREEN}$current_ip${NC} (dynamically assigned)"
      else
        echo -e "IP Address: ${RED}Not assigned${NC}"
      fi
    fi

    # Display Gateway
    local gateway=$(nmcli -g ipv4.gateway con show "$conn_name")
    if [[ -n "$gateway" ]]; then
      echo -e "Gateway: ${GREEN}$gateway${NC}"
    else
      local current_gateway=$(ip route | grep default | grep $interface | awk '{print $3}' | head -1)
      if [[ -n "$current_gateway" ]]; then
        echo -e "Current Gateway: ${GREEN}$current_gateway${NC}"
      else
        echo -e "Gateway: ${RED}Not assigned${NC}"
      fi
    fi
  else
    echo -e "Interface: ${RED}Not assigned${NC}"
    echo -e "Connection State: ${RED}Inactive${NC}"

    # Display IP address if configured
    local ip_address=$(nmcli -g ipv4.addresses con show "$conn_name")
    if [[ -n "$ip_address" ]]; then
      echo -e "Configured IP Address: ${GREEN}$ip_address${NC}"
    else
      echo -e "IP Address: ${RED}Not configured${NC}"
    fi

    # Display Gateway if configured
    local gateway=$(nmcli -g ipv4.gateway con show "$conn_name")
    if [[ -n "$gateway" ]]; then
      echo -e "Configured Gateway: ${GREEN}$gateway${NC}"
    else
      echo -e "Gateway: ${RED}Not configured${NC}"
    fi
  fi

  # Display DNS
  local dns_servers=$(nmcli -g ipv4.dns con show "$conn_name")
  if [[ -n "$dns_servers" ]]; then
    echo -e "DNS Servers: ${GREEN}$dns_servers${NC}"
  else
    local current_dns=$(grep nameserver /etc/resolv.conf | awk '{print $2}')
    if [[ -n "$current_dns" ]]; then
      echo -e "Current DNS Servers: ${GREEN}$current_dns${NC}"
    else
      echo -e "DNS Servers: ${RED}Not assigned${NC}"
    fi
  fi

  # Display connection type
  local conn_type=$(nmcli -g connection.type con show "$conn_name")
  if [[ -n "$conn_type" ]]; then
    echo -e "Connection Type: ${GREEN}$conn_type${NC}"
  fi
}

# Create a temporary file to store connection names
tmp_file=$(mktemp)

# Store connection names and their indices
echo -e "${YELLOW}Available network connections:${NC}"
nmcli -t -f NAME con show >"$tmp_file"
i=1
while IFS= read -r conn_name; do
  echo "$i. $conn_name"
  i=$((i + 1))
done <"$tmp_file"
echo ""

# Get the connection to configure
read -p "Enter the number of the connection you want to configure: " conn_num

# Get the total number of connections
total_connections=$(wc -l <"$tmp_file")

# Validate connection number
if ! [[ "$conn_num" =~ ^[0-9]+$ ]] || [ "$conn_num" -lt 1 ] || [ "$conn_num" -gt "$total_connections" ]; then
  echo -e "${RED}Error: Invalid connection number.${NC}"
  rm "$tmp_file"
  exit 1
fi

# Get the connection name based on the number
selected_con=$(sed "${conn_num}q;d" "$tmp_file")

# Clean up temporary file
rm "$tmp_file"

# Display current configuration
echo -e "\n${BLUE}Current Network Configuration:${NC}"
display_connection_details "$selected_con"

if [ $? -ne 0 ]; then
  echo -e "${RED}Could not retrieve connection details. Exiting.${NC}"
  exit 1
fi

# Ask if user wants to change the configuration
echo ""
read -p "Do you want to change this network configuration? (y/n): " change_config

if [[ ! "$change_config" =~ ^[Yy]$ ]]; then
  echo -e "\n${GREEN}Configuration unchanged. Exiting.${NC}"
  exit 0
fi

# Ask for IP configuration type
echo ""
echo "Select IP configuration type:"
echo "1. DHCP (Automatic IP assignment)"
echo "2. Static IP"
read -p "Enter your choice (1 or 2): " ip_choice

if [[ "$ip_choice" == "1" ]]; then
  # Configure DHCP
  echo -e "${YELLOW}Configuring DHCP...${NC}"
  nmcli con mod "$selected_con" ipv4.method auto

  # Remove any static IP configuration
  nmcli con mod "$selected_con" ipv4.addresses "" ipv4.gateway "" ipv4.dns ""

  echo -e "${GREEN}DHCP configuration applied.${NC}"
elif [[ "$ip_choice" == "2" ]]; then
  # Configure Static IP
  echo -e "${YELLOW}Configuring Static IP...${NC}"

  # Get IP address
  while true; do
    read -p "Enter IP address (e.g., 192.168.1.100): " ip_address
    if validate_ip "$ip_address"; then
      break
    else
      echo -e "${RED}Invalid IP address format. Please use format like 192.168.1.100${NC}"
    fi
  done

  # Get subnet mask
  while true; do
    read -p "Enter subnet mask in CIDR notation (e.g., 24 for 255.255.255.0): " subnet_mask
    if validate_cidr "$subnet_mask"; then
      break
    else
      echo -e "${RED}Invalid subnet mask. Please enter a number between 0 and 32.${NC}"
    fi
  done

  # Get gateway
  while true; do
    read -p "Enter gateway IP address (e.g., 192.168.1.1): " gateway
    if validate_ip "$gateway"; then
      break
    else
      echo -e "${RED}Invalid gateway address format. Please use format like 192.168.1.1${NC}"
    fi
  done

  # Get DNS
  while true; do
    read -p "Enter primary DNS server (e.g., 8.8.8.8) or leave empty for default: " dns1
    if [[ -z "$dns1" ]] || validate_ip "$dns1"; then
      break
    else
      echo -e "${RED}Invalid DNS address format. Please use format like 8.8.8.8${NC}"
    fi
  done

  # Get secondary DNS (optional)
  dns2=""
  read -p "Enter secondary DNS server (optional): " dns2
  if [[ -n "$dns2" ]]; then
    if ! validate_ip "$dns2"; then
      echo -e "${RED}Invalid DNS address format. Secondary DNS will not be set.${NC}"
      dns2=""
    fi
  fi

  # Apply static IP configuration
  echo -e "${YELLOW}Applying static IP configuration...${NC}"

  # Set method to manual
  nmcli con mod "$selected_con" ipv4.method manual

  # Set IP and gateway
  nmcli con mod "$selected_con" ipv4.addresses "$ip_address/$subnet_mask" ipv4.gateway "$gateway"

  # Set DNS servers
  if [[ -n "$dns1" ]] && [[ -n "$dns2" ]]; then
    nmcli con mod "$selected_con" ipv4.dns "$dns1 $dns2"
  elif [[ -n "$dns1" ]]; then
    nmcli con mod "$selected_con" ipv4.dns "$dns1"
  fi

  echo -e "${GREEN}Static IP configuration applied.${NC}"
else
  echo -e "${RED}Invalid choice. Exiting without making changes.${NC}"
  exit 1
fi

# Restart the connection to apply changes
echo -e "\n${YELLOW}Restarting network connection to apply changes...${NC}"
nmcli con down "$selected_con" && nmcli con up "$selected_con"

# Display new configuration
echo -e "\n${BLUE}New Network Configuration:${NC}"
display_connection_details "$selected_con"

# Test connectivity
echo -e "\n${YELLOW}Testing internet connectivity...${NC}"
if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
  echo -e "${GREEN}Network configuration successful! Internet connection is working.${NC}"
else
  echo -e "${RED}Warning: Internet connection may not be working.${NC}"
  echo "Please verify your network settings."
fi

echo -e "\n${BOLD}Configuration complete!${NC}"
