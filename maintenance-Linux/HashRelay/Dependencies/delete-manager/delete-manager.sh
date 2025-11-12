#!/usr/bin/env bash
# This script purpose is to put/get the configuration CHAIN_BACKUPS_NUMBER
# if there is no line CHAIN_BACKUPS_NUMBER the script will put it in the CONFIG_FILE
# if there is one, he look at the number of CHAIN_BACKUPS_NUMBER and delete the older
# backup that present inside the folder BACKUP_DIR.
# In other word, every backup that pass the CHAIN_BACKUPS_NUMBER get deleted.
#
# Example:
# CHAIN_BACKUPS_NUMBER=3
# backup-etc(1).tar.gz
# backup-etc(2).tar.gz
# backup-etc(3).tar.gz
# then, when the backup-manager.sh script add:
# backup-etc(4).tar.gz
# backup-etc(1).tar.gz got automatically deleted.
#
# Author: Decarnelle Samuel

set -Eeuo pipefail
IFS=$'\n\t'

# Ensure we are root
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

# Main variables
BACKUP_CONF="/usr/local/bin/HashRelay/backups-manager/backups.conf"
NEXT=/usr/local/bin/HashRelay/hashrelay-client/hashrelay-client.sh
CONFIG_FILE="/usr/local/bin/HashRelay/agent.conf" # The main config file (where we need to add the CHAIN_BACKUPS_NUMBER)
NUMBER=false
VERBOSE=false

# usage(): print help text:
usage() {
  cat <<'USAGE'
  delete-manager.sh
  Options:
    --number                  Put/change the number of the client inside the file agent.conf
    --verbose                 Extra logging
    -h|--help                 This help
  Environement:
    This script is used to get the CLIENT_NAME for the backups and to
    tar each backups file into the BACKUP_DIR.
  Behavior:
    Only the configuration manager and the agent call this script. You don't need to.
USAGE
}

# Small wrapper for gum to keep calls short and readable
confirm() { gum confirm "$1"; }

# Parse CLI arguments in a loop until all are consumed
while [[ $# -gt 0 ]]; do
  case "$1" in
  --number)
    NUMBER=true # Ask for the client number
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

get_existing_name() {
  [[ -f "$CONFIG_FILE" ]] || {
    echo ""
    return
  }

  local line
  line="$(grep -E '^[[:space:]]*NAME[[:space:]]*=' "$CONFIG_FILE" | tail -n1 || true)"
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

# Get the name for the path of the backup path
USER_PATH_NAME=$(get_existing_name)
BACKUP_DIR="/home/sam/backups/$USER_PATH_NAME" # Need to be changed before release to HashRelay!!!!!

# Only if --number is invoked
# TEMP !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
if [[ "$NUMBER" == true ]]; then
  if [[ -f "$CONFIG_FILE" ]]; then
    if [[ "$VERBOSE" == true ]]; then
      echo "The configuration file exist !"
    else
      echo "Configuration file not found !"
    fi
  fi

  get_existing_number() {
    [[ -f "$CONFIG_FILE" ]] || {
      echo ""
      return
    }

    local line
    line="$(grep -E '^[[:space:]]*CHAIN_BACKUPS_NUMBER[[:space:]]*=' "$CONFIG_FILE" | tail -n1 || true)"
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

  # Strict char validator: a-zA-Z0-9_-
  valid_num() {
    local n=$1
    [[ "$n" =~ ^[0-9]+$ ]] || return 1
    ((n >= 1 && n <= 100)) || return 1 # Can't keep 100 backups of the same file
    return 0
  }

  # Persist NUMBER into CONFIG_FILE:
  # - Ensure directory exists (With sudo, since path is under /usr/local/bin/)
  # - If NUMBER= exists, make a timestamped backup and replace it in-place
  # - Otherwise, append a new NUMBER line
  set_num() {
    local number="$1"

    sudo mkdir -p "$(dirname -- "$CONFIG_FILE")"

    if [[ -f "$CONFIG_FILE" ]] && grep -qE '^[[:space:]]*CHAIN_BACKUPS_NUMBER[[:space:]]*=' "$CONFIG_FILE"; then
      sudo cp -a -- "$CONFIG_FILE" "CONFIG_FILE.bak.$(date -Iseconds)"
      sudo sed -i -E "s|^[[:space:]]*CHAIN_BACKUPS_NUMBER[[:space:]]*=.*$|NAME=$number|" "$CONFIG_FILE"
    else
      printf "NAME=%s\n" "$number" | sudo tee -a "$CONFIG_FILE" >/dev/null
    fi
  }

  title="Chain Backups Number Configurator"
  # Nice welcome banner
  gum style --border double --margin "1 2" --padding "1 2" --border-foreground 212 \
    "Welcome to $title"

  # Try to read the exixting NAME from the config
  existing_number="$(get_existing_number)"

  # If we already have a value, show it and ask whether to modify it
  if [[ -n "$existing_number" ]]; then
    gum style --foreground 212 "Current Number: $existing_number"

    if ! confirm "Do you want to modify the Number?"; then
      echo "Keeping existing Number: $existing_number"
      exec sudo bash "$NEXT"
    fi
  fi

  # Prompt loop until we get a valid Number (or Number exist)
  while :; do
    # Pre-fill with existing value if we had one
    number="$(gum input --placeholder 'e.g. 3' \
      ${existing_number:+--value="$existing_number"})"

    # If user pressed Enter on an empty input, exit gracefully
    [[ -z "${number:-}" ]] && {
      echo "No input provided. Exiting."
      exit 0
    }

    if ! valid_num "$number"; then
      gum style --foreground 196 "Invalid number. Enter a number with only these characteres 0-9"
      continue
    fi

    NUMBER="$number"
    break
  done

  # Persist the chosen number into the config
  set_num "$NUMBER"
  echo "Your name is set to: $NUMBER"

  # Finally, chain to the client script: exec replace the current process
  exec sudo bash "$NEXT"
fi
