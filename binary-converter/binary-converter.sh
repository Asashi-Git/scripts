#!/bin/bash
# binary_ip_converter.sh - A converter that supports dotted notation for both binary and decimal IP

# ANSI color codes
CYAN="\033[0;36m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
WHITE="\033[1;37m"
YELLOW="\033[1;33m"
RESET="\033[0m"

# Initialize variables
binary="00000000.00000000.00000000.00000000"
decimal="0"
ip_notation="0.0.0.0"
mode="binary" # Default mode is binary to decimal

# Function to convert dotted decimal IP to binary
ip_to_binary() {
	local ip="$1"
	local binary_result=""

	# Split IP address into octets
	IFS='.' read -r -a octets <<<"$ip"

	# Ensure we have 4 octets
	if [[ ${#octets[@]} -ne 4 ]]; then
		return 1
	fi

	# Convert each octet to binary and concatenate
	for octet in "${octets[@]}"; do
		# Validate each octet is a number between 0-255
		if ! [[ "$octet" =~ ^[0-9]+$ ]] || [ "$octet" -gt 255 ]; then
			return 1
		fi

		# Convert to 8-bit binary
		local binary_octet=$(echo "obase=2; $octet" | bc)
		binary_octet=$(printf "%08d" "$binary_octet")

		if [ -z "$binary_result" ]; then
			binary_result="$binary_octet"
		else
			binary_result="${binary_result}.${binary_octet}"
		fi
	done

	echo "$binary_result"
	return 0
}

# Function to convert dotted binary to single binary string
dotted_binary_to_full() {
	echo "$1" | tr -d '.'
}

# Function to convert binary string to dotted notation
full_binary_to_dotted() {
	local bin="$1"
	# Ensure it's 32 bits by padding
	bin=$(printf "%032s" "$bin" | tr ' ' '0')
	echo "${bin:0:8}.${bin:8:8}.${bin:16:8}.${bin:24:8}"
}

# Function to validate dotted binary input
validate_dotted_binary() {
	local input="$1"

	# Check format: 8 bits, dot, 8 bits, dot, 8 bits, dot, 8 bits
	if ! [[ "$input" =~ ^[01]{1,8}\.[01]{1,8}\.[01]{1,8}\.[01]{1,8}$ ]]; then
		return 1
	fi

	# Split by dots
	IFS='.' read -r -a parts <<<"$input"

	# Pad each part to 8 bits if needed (for inputs like 1.1.1.1)
	for i in {0..3}; do
		parts[$i]=$(printf "%08d" "${parts[$i]}")
	done

	# Join back with dots
	echo "${parts[0]}.${parts[1]}.${parts[2]}.${parts[3]}"
	return 0
}

# Function to convert binary to dotted decimal IP
binary_to_ip() {
	local binary_input=$(dotted_binary_to_full "$1")
	local part1=${binary_input:0:8}
	local part2=${binary_input:8:8}
	local part3=${binary_input:16:8}
	local part4=${binary_input:24:8}

	local octet1=$(echo "ibase=2; $part1" | bc)
	local octet2=$(echo "ibase=2; $part2" | bc)
	local octet3=$(echo "ibase=2; $part3" | bc)
	local octet4=$(echo "ibase=2; $part4" | bc)

	echo "$octet1.$octet2.$octet3.$octet4"
}

# Function to validate IP format
validate_ip() {
	local ip="$1"
	local ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

	if ! [[ $ip =~ $ip_regex ]]; then
		return 1 # Not IP format
	fi

	# Check each octet is <= 255
	IFS='.' read -r -a octets <<<"$ip"
	for octet in "${octets[@]}"; do
		if [ "$octet" -gt 255 ]; then
			return 1 # Invalid octet value
		fi
	done

	return 0 # Valid IP
}

# Function to draw the converter
draw_converter() {
	local bin_input="$1"
	local dec_input="$2"
	local ip_input="$3"
	local current_mode="$4"

	# Split the binary input into octets (already in dotted format)
	IFS='.' read -r -a binary_parts <<<"$bin_input"

	# Full binary without dots (for calculation)
	local full_binary=$(dotted_binary_to_full "$bin_input")

	# Convert each octet to decimal for display
	local octet1=$(echo "ibase=2; ${binary_parts[0]}" | bc)
	local octet2=$(echo "ibase=2; ${binary_parts[1]}" | bc)
	local octet3=$(echo "ibase=2; ${binary_parts[2]}" | bc)
	local octet4=$(echo "ibase=2; ${binary_parts[3]}" | bc)

	# Calculate hex value
	local hex_value=$(echo "ibase=2; obase=16; $full_binary" | bc)

	# Clear screen
	clear

	echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════════╗"
	echo -e "║                   ${WHITE}BINARY ↔ DECIMAL CONVERTER${YELLOW}                       ║"
	echo -e "╠════════════════════════════════════════════════════════════════════╣"
	echo -e "║                                                                    ║"

	# Mode selection
	if [[ "$current_mode" == "binary" ]]; then
		echo -e "║  ${GREEN}[B] Binary to Decimal${RESET}    ${WHITE}[D] Decimal to Binary${YELLOW}                    ║"
	else
		echo -e "║  ${WHITE}[B] Binary to Decimal${RESET}    ${GREEN}[D] Decimal to Binary${YELLOW}                 ║"
	fi
	echo -e "║                                                                    ║"

	# Binary section
	echo -e "║  ${CYAN}BINARY:${YELLOW}                                                           ║"
	echo -e "║  ${CYAN}┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐${YELLOW}                       ║"
	echo -e "║  ${CYAN}│${WHITE}${binary_parts[0]}${CYAN}│.│${WHITE}${binary_parts[1]}${CYAN}│.│${WHITE}${binary_parts[2]}${CYAN}│.│${WHITE}${binary_parts[3]}${CYAN}│${YELLOW}                       ║"
	echo -e "║  ${CYAN}└────────┘ └────────┘ └────────┘ └────────┘${YELLOW}                       ║"

	# Decimal section
	echo -e "║                                                                    ║"
	echo -e "║  ${CYAN}IP ADDRESS:${YELLOW}                                                       ║"
	echo -e "║  ${CYAN}┌────┐ ┌────┐ ┌────┐ ┌────┐${YELLOW}                                       ║"
	echo -e "║  ${CYAN}│${WHITE}$(printf "%3d" "$octet1")${CYAN} │.│${WHITE}$(printf "%3d" "$octet2")${CYAN} │.│${WHITE}$(printf "%3d" "$octet3")${CYAN} │.│${WHITE}$(printf "%3d" "$octet4")${CYAN} │${YELLOW}                                       ║"
	echo -e "║  ${CYAN}└────┘ └────┘ └────┘ └────┘${YELLOW}                                       ║"

	# Power Values
	echo -e "║                                                                    ║"
	echo -e "║  ${CYAN}Power Values:${YELLOW}                                                     ║"
	echo -e "║  ${CYAN}┌───┬───┬───┬───┬───┬───┬───┬───┐${YELLOW}                                 ║"
	echo -e "║  ${CYAN}│${WHITE}128${CYAN}│${WHITE} 64${CYAN}│${WHITE} 32${CYAN}│${WHITE} 16${CYAN}│${WHITE}  8${CYAN}│${WHITE}  4${CYAN}│${WHITE}  2${CYAN}│${WHITE}  1${CYAN}│  ${WHITE}← Values per position${YELLOW}          ║"
	echo -e "║  ${CYAN}└───┴───┴───┴───┴───┴───┴───┴───┘${YELLOW}                                 ║"

	# Full decimal and hex
	echo -e "║                                                                    ║"
	echo -e "║  ${CYAN}Full decimal value: ${WHITE}$dec_input${YELLOW}                                             ║"
	echo -e "║  ${CYAN}Hexadecimal: ${WHITE}0x$hex_value${YELLOW}                                                  ║"

	# Notes section
	echo -e "║                                                                    ║"
	echo -e "║  ${CYAN}NOTES:${YELLOW}                                                            ║"
	echo -e "║  ${WHITE}- Each octet (8 bits) ranges from 0 to 255${YELLOW}                        ║"
	echo -e "║  ${WHITE}- Enter binary in format: 10101010.10101010.10101010.10101010${YELLOW}     ║"
	echo -e "║  ${WHITE}- Enter IP in format: 192.168.1.1 (in decimal mode)${YELLOW}               ║"
	echo -e "║  ${WHITE}- Type 'b' or 'd' to switch conversion modes${YELLOW}                      ║"
	echo -e "║  ${WHITE}- Type 'q' to quit${YELLOW}                                                ║"
	echo -e "║                                                                    ║"
	echo -e "╚════════════════════════════════════════════════════════════════════╝${RESET}"

	# Show appropriate prompt based on mode
	if [[ "$current_mode" == "binary" ]]; then
		echo -e "Enter binary with dots (e.g., 11111111.00000000.00000000.00000001), 'b'/'d' to switch, or 'q' to quit: "
	else
		echo -e "Enter IP address (e.g., 192.168.1.1), 'b'/'d' to switch mode, or 'q' to quit: "
	fi
}

# Main loop
while true; do
	draw_converter "$binary" "$decimal" "$ip_notation" "$mode"

	# Get user input
	read -r input

	# Check for mode switch or quit
	case "$input" in
	q | Q | quit)
		clear
		echo -e "${GREEN}Thanks for using the Binary/Decimal Converter!${RESET}"
		exit 0
		;;
	b | B)
		mode="binary"
		continue
		;;
	d | D)
		mode="decimal"
		continue
		;;
	esac

	# Process input based on mode
	if [[ "$mode" == "binary" ]]; then
		# Validate and normalize dotted binary input
		normalized=$(validate_dotted_binary "$input")
		if [ $? -eq 0 ]; then
			# Store the normalized binary
			binary="$normalized"

			# Calculate decimal and IP from full binary
			full_binary=$(dotted_binary_to_full "$binary")
			decimal=$(echo "ibase=2; $full_binary" | bc)
			ip_notation=$(binary_to_ip "$binary")
		else
			echo -e "${CYAN}Invalid binary format. Use format: 11111111.00000000.00000000.00000001"
			echo -e "${CYAN}(8 bits per octet, separated by dots). Press Enter to try again...${RESET}"
			read
		fi
	else # decimal mode (IP format)
		if validate_ip "$input"; then
			# Store IP notation
			ip_notation="$input"

			# Convert IP to binary
			binary_result=$(ip_to_binary "$input")
			if [ $? -eq 0 ]; then
				binary="$binary_result"
				# Calculate full decimal from binary
				full_binary=$(dotted_binary_to_full "$binary")
				decimal=$(echo "ibase=2; $full_binary" | bc)
			else
				echo -e "${CYAN}Invalid IP format. Press Enter to try again...${RESET}"
				read
			fi
		else
			echo -e "${CYAN}Invalid IP format (use w.x.y.z where each value is 0-255). Press Enter to try again...${RESET}"
			read
		fi
	fi
done
