#!/usr/bin/env bash
# The pupose of this script is to look into the backup.conf file
# in the /usr/local/bin/HashRelay/backups-manager/backups.conf and
# fetch all the path of all the files the user have choosen to backup
# to get the hash of eatch file and place the hash into the hash.conf
# in /usr/local/bin/HashRelay/hash-printer/hash.conf
#
# This script must look if we have an actual cache of the backups inside the server
# to avoid contacting the server every time.
# if a new backup have a different hash then the cache, that mean the backup have
# been modified and must be backed up !
# else do nothing.
# ssh user@remote-ip 'bash /path/to/remote_script.sh --flag'
#
# Author: Decarnelle Samuel

# Ensure we are root
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

CONFIG_FILE="/usr/local/bin/HashRelay/agent.conf"
HASH_CONF="/usr/local/bin/HashRelay/hash-printer/hash.conf"
HASH_PATH="/usr/local/bin/HashRelay/hash-printer/hash"
BACKUP_PATH="/home/sam/backups" # Must be changed to HashRelay

# Get the name of the client if onto the client machine
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

# Generate hash for each client inside /home/HashRelay/backups/
# Generate a file containing the hashs inside:
# /usr/local/bin/HashRelay/hash-printer/hash/<CLIENT_NAME>/hash.conf
generate_hashes() {

  local backup_root="$BACKUP_PATH"
  local output_root="$HASH_PATH"

  # Loop through each client directory
  for client_dir in "$backup_root"/*; do

    # Skip if not a directory
    [[ -d "$client_dir" ]] || continue

    client_name=$(basename "$client_dir")
    client_output_dir="$output_root/$client_name"

    mkdir -p "$client_output_dir"

    hash_file="$client_output_dir/hash.conf"

    echo "# This is all of the hash of $client_name:" >"$hash_file"

    # Now go through each backup file of the client
    for backup_file in "$client_dir"/*; do
      [[ -f "$backup_file" ]] || continue

      backup_name=$(basename "$backup_file")

      echo "-$backup_name:" >>"$hash_file"

      sha256sum "$backup_file" | awk '{print $1}' >>"$hash_file"
      echo "" >>"$hash_file"
    done
  done
}
generate_hashes
