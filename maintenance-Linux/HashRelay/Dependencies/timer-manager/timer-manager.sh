#!/usr/bin/env bash
# Configure TIMER in /usr/local/bin/HashRelay/agent.conf
# This script:
#   - Reads the existing TIMER from the config (if present)
#   - Shows it and asks if you want to modify it
#   - Validates that any new input is an interger time in minutes (1-44640)
#   - Replaces or appends TIMER in the config safely (with a timestamped backup)
#   - Chains to the HashRelay client script !!! TEMPORARY
#
# Author: Decarnelle Samuel

# Exit on:
#   - any command error (-e)
#   - use of an unset variable (-u)
#   - a failure anywhere in a pipeline (-o pipefail)
set -euo pipefail

# Ensure we are root
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

# Main variables
title="Timer Configurator"
CONFIG="/usr/local/bin/HashRelay/agent.conf"
NEXT="/usr/local/bin/HashRelay/hashrelay-client/hashrelay-client.sh"
TIMER_CALL=false
VERBOSE=false

# usage(): print help text:
usage() {
  cat <<'USAGE'
  timer-manager.sh
  Options:
    --timer                   Put/change the timer inside the file agent.conf
    --verbose                 Extra logging
    -h|--help                 This help
  Environement:
    This script is used to get the TIMER 
  Behavior:
    Only the configuration manager and the agent call this script. You don't need to.
USAGE
}

# Small wrapper for gum to keep calls short and readable
confirm() { gum confirm "$1"; }

# Parse CLI arguments in a loop until all are consumed
while [[ $# -gt 0 ]]; do
  case "$1" in
  --timer)
    TIMER_CALL=true # Ask for the TIMER
    shift
    ;;
  --verbose)
    VERBOSE=true # Extra logging
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "[!] Unknow arg: $1"
    usage
    exit 1
    ;;
  esac
done

# See if we are onto a client or a server configuration
CLIENT_OR_SERVER=$(/usr/local/bin/HashRelay/agent-detector/agent-detector.sh)
# Let's print the result:
if [[ "$CLIENT_OR_SERVER" == "true" ]]; then
  IS_CLIENT=true
  printf 'Client is considered: %s\n' "$IS_CLIENT"
else
  IS_SERVER=true
  printf 'Server is considered: %s\n' "$IS_SERVER"
fi

# Read the last TIMER entry from CONFIG (if file exists)
# - Greps for a line starting with TIMER=
# - Takes the last occurrence (tail -n1) to handle multiple entries
# - Trims spaces and strips quotes around the value
get_existing_timer() {
  [[ -f "$CONFIG" ]] || {
    echo ""
    return
  }

  local line
  line="$(grep -E '^[[:space:]]*TIMER[[:space:]]*=' "$CONFIG" | tail -n1 || true)"
  [[ -z "$line" ]] && {
    echo ""
    return
  }

  line="${line#*=}"

  # Trim leading/trailing whitespace
  line="${line#"${line%%[![:space:]]*}"}" # ltrim
  line="${line%"${line##*[![:space:]]}"}" # rtrim

  # Remove surrounding single/double quotes, if any
  line="${line%\"}"
  line="${line#\"}"
  line="${line%\'}"
  line="${line#\'}"

  echo "$line"
}

CONFIGURED_TIMER=$(get_existing_timer)

# Only if --timer is invoked
if [[ "$TIMER_CALL" == true ]]; then
  if [[ "$CONFIG" == true ]]; then
    if [[ "$VERBOSE" == true ]]; then
      echo "The configuration file exist !"
    else
      echo "COnfiguration file not found !"
    fi
  fi

  # Strict timer validator: integer 1–44640
  valid_timer() {
    local t="$1"
    [[ "$t" =~ ^[0-9]+$ ]] || return 1
    ((t >= 1 && t <= 44640)) || return 1
    return 0
  }

  # Persist TIMER into CONFIG:
  # - Ensures directory exists (with sudo, since path is under /usr/local/bin)
  # - If TIMER= exists, make a timestamped backup and replace it in-place
  # - Otherwise, append a new TIMER line
  set_timer() {
    local timer="$1"

    sudo mkdir -p "$(dirname -- "$CONFIG")"

    if [[ -f "$CONFIG" ]] && grep -qE '^[[:space:]]*TIMER[[:space:]]*=' "$CONFIG"; then
      sudo cp -a -- "$CONFIG" "$CONFIG.bak.$(date -Iseconds)"
      sudo sed -i -E "s|^[[:space:]]*TIMER[[:space:]]*=.*$|TIMER=$timer|" "$CONFIG"
    else
      printf "TIMER=%s\n" "$timer" | sudo tee -a "$CONFIG" >/dev/null
    fi
  }

  # Nice welcome banner
  gum style --border double --margin "1 2" --padding "1 2" --border-foreground 212 \
    "Welcome to $title"

  # Try to read the existing TIMER from the config
  existing_timer="$(get_existing_timer)"

  # If we already have a value, show it and ask whether to modify it
  if [[ -n "$existing_timer" ]]; then
    gum style --foreground 212 "Current TIMER: $existing_timer"

    if ! confirm "Do you want to modify the TIMER?"; then
      echo "Keeping existing TIMER: $existing_timer"
      exec sudo bash "$NEXT"
    fi
  fi

  # Prompt loop until we get a valid timer (or user exits)
  while :; do
    # Pre-fill with existing value if we had one
    timer="$(gum input --placeholder 'e.g. 60(in minutes)' \
      ${existing_timer:+--value "$existing_timer"})"

    # If user pressed Enter on an empty input, exit gracefully
    [[ -z "${timer:-}" ]] && {
      echo "No input provided. Exiting."
      exit 0
    }

    if ! valid_timer "$timer"; then
      gum style --foreground 196 "Invalid timer. Enter an integer between 1 and 44640 (e.g., 60)."
      continue
    fi

    TIMER="$timer"
    break
  done

  # Persist the chosen port into the config
  set_timer "$TIMER"
  echo "Your timer is set to: $TIMER"

  # Finally, chain to the client script; exec replaces the current process
  exec sudo bash "$NEXT"
fi

# Stating the true timer section that create a timer via the timer set inside the CONFIG file
# and using systemd timer.
# If the timer already exist, change the timer, change the timer inside the systemd
# and reload the demon with sudo systemctl daemon-reload.
# If the timer did not exist, create the timer with the service file too.
# We already have a variable named CONFIGURED_TIMER that have the timer that the user set
# in it.
#
# What's the workflow of my agent:
#   01- The installation via hashrelay-installer.sh
#   02- The configuration via hashrelay-client/hashrelay-server.sh server or client
#      *  If on the client:
#           03- The configurator lunch the ssh-configuration-manager.sh
#           04- The ssh-configuration-manager.sh lunch the ufw-configuration-manager.sh
#           05- The ufw-configuration-manager.sh lunch the timer-manager.sh
#           06- This script create a timer that lunch backup-manager.sh every X minutes
#           07- The backups-manager.sh lunch the delete-manager.sh script
#           08- The delete-manager.sh lunch the hash-printer.sh
#           09- The hash-printer.sh lunch the prob-viewer.sh
#           10- The prob-viewer.sh verrify the server is up if up, lunch the sender.sh
#           11- The sender.sh send/retreve the hash.file lunch the scp.sh
#           12- Then scp.sh send the backups to the server
#      *  If on the server:
#           03- The configurator lunch the ssh-configuration-manager.sh
#           04- The ssh-configuration-manager.sh lunch:
#               |>if web=yes in the conf file it lunch the web-server.sh
#               |>else it lunch the ufw-configuration-manager.sh
#           05- The ufw-configuration-manager.sh lunch the timer-manager.sh
#           06- This script create a timer that lunch delete-manager.sh every X minutes
#           07- The delete-manager.sh lunch the hash-printer.sh
#           08- The hash-printer.sh lunch the receiver.sh
#           09- The receiver.sh process the data in the hash.file and put it in a
#               directory so the client can process the server output.
#
# So in this script we need to create server/timer for two different script:
#      *  If on the client:
#           - backups-manager.sh (With a timer of X set in the configuration)
#      *  If on the server:
#           - delete-manager.sh (With a timer of X set in the configuration)
#           - receiver.sh (With like a static timer of 20/40 secondes)
#

# Variables for backups-manager.sh
BACKUP_SERVICE_PATH="/etc/systemd/system/hashrelay-backups.service"
BACKUP_TIMER_PATH="/etc/systemd/system/hashrelay-backups.timer"
BACKUP_MANAGER_PATH="/usr/local/bin/HashRelay/backups-manager/backups-manager.sh"

# Variables for delete-manager.sh
DELETE_SERVICE_PATH="/etc/systemd/system/hashrelay-delete.service"
DELETE_TIMER_PATH="/etc/systemd/system/hashrelay-delete.timer"
DELETE_MANAGER_PATH="/usr/local/bin/HashRelay/delete-manager/delete-manager.sh"

# Variables for receiver.sh
RECEIVER_SERVICE_PATH="/etc/systemd/system/hashrelay-receiver.service"
RECEIVER_TIMER_PATH="/etc/systemd/system/hashrelay-receiver.timer"
RECEIVER_PATH="/usr/local/bin/HashRelay/receiver/receiver.sh"

# Logging
LOG_DIR="/var/log/HashRelay"
LOG_FILE="${LOG_DIR}/timer-manager.log"
umask 027
mkdir -p -- "$LOG_DIR" "$BACKUP_DIR"
# Ensure log file exists with restrictive perms
touch -- "$LOG_FILE"
chmod 655 -- "$LOG_FILE" "$LOG_DIR"

# Route all stdout/stderr to both console and the log file, with timestamps
# Uses gawk to prefix lines with a timestamp.
exec > >(awk '{ print strftime("[%Y-%m-%d %H:%M:%S%z]"), $0; fflush(); }' | tee -a "$LOG_FILE") 2>&1

echo "=== START Timer Run ==="
echo "Using config: $BACKUP_CONF"
echo "Destination:  $BACKUP_DIR"
echo "Log file:     $LOG_FILE"

# Checking if there is a TIMER=ChosenTimerNumber
if [[ -n "$CONFIGURED_TIMER" ]]; then
  echo "Timer exist and is set to $CONFIGURED_TIMER minutes"
else
  printf 'Then timer is not configured. Configure the timer'
  printf 'via the command hashrelay --config'
  exit 1
fi

#

echo "=== END Backup Run ==="
