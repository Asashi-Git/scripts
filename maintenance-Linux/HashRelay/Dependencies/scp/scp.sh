#!/usr/bin/env bash
# This script is used to export to the server the modified backups.
#
# TODO:
# It can import backup from the server too either by dowloading all actual backup that
# are actually onto the server or X last number of backups of the same file.
#
# Author: Decarnelle Samuel

# Ensure the script is luched as sudo
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "this script must be run as root (use sudo)." >&2
  exit 1
fi

# Verify the status of the server
if /usr/local/bin/HashRelay/prob-viewer/prob-viewer.sh; then
  echo "Server is up"
  IS_UP=true
else
  echo "Server is down"
  IS_UP=false
fi

DRY_RUN=false

# usage(): print help text:
usage() {
  cat <<'USAGE'
  scp.sh
  Options:
    --dry-run                 Show command; don't execute
    -h|--help                 This help
  Environement:
    This script is used to scp the baclups to the server.
  Behavior:
    Only the agent call this script. You don't need to.
USAGE
}

# Parse CLI arguments in a loop until all are consumed
while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run)
    DRY_RUN=true # Show command don't execute.
    shift
    ;;
  *)
    echo "[!] Unknow arg: $1"
    usage
    exit 1
    ;;
  esac
done

# Variable for the main config file
CONFIG="/usr/local/bin/HashRelay/agent.conf"

# Get the Ip address of the server inside the config file
get_existing() {
  [[ -f "$CONFIG" ]] || {
    echo ""
    return
  }

  local line
  # Find lines like: SERVER_IP = 1.2.3.4
  line="$(grep -E '^[[:space:]]*SERVER_IP[[:space:]]*=' "$CONFIG" | tail -n1 || true)"
  [[ -z "$line" ]] && {
    echo ""
    return
  }

  # Extract the right-hand side of '='
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

# Get the name of the client if onto the client machine
get_existing_name() {
  [[ -f "$CONFIG" ]] || {
    echo ""
    return
  }

  local line
  line="$(grep -E '^[[:space:]]*NAME[[:space:]]*=' "$CONFIG" | tail -n1 || true)"
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

get_existing_port() {
  [[ -f "$CONFIG" ]] || {
    echo ""
    return
  }

  local line
  line="$(grep -E '^[[:space:]]*SERVER_PORT[[:space:]]*=' "$CONFIG" | tail -n1 || true)"
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

NEEDED_BACKUPS="/usr/local/bin/HashRelay/hash-printer/hash/$(get_existing_name)/hash-to-add.conf"
SERVER_PATH="/home/HashRelay/$(get_existing_name)/backups" #TODO: change it to HashRelay user
IP_ADD=$(get_existing)
PORT=$(get_existing_port)

# Making a variable to get each path for each different hash backup
# between the client and the server
send_backups_path() {
  echo "Reading: $NEEDED_BACKUPS"
  echo "Sending files to: HashRelay@$IP_ADD:$SERVER_PATH"
  echo "--------------------------------------------"

  while IFS= read -r line; do

    # Skip comments
    [[ "$line" =~ ^# ]] && continue

    # Skip empty lines
    [[ -z "$line" ]] && continue

    # Avoid path traversal like ../ etc.
    if [[ "$line" =~ \.\. ]]; then
      echo "Blocked suspicious path: $line"
      continue
    fi

    # Check if path exists
    if [[ ! -e "$line" ]]; then
      echo "Path not found: $line"
      continue
    fi

    echo "Sending: $line"

    if [[ "$DRY_RUN" == false ]]; then
      #scp -r "$line" "sam@$IP_ADD:$SERVER_PATH"
      scp -r -i /usr/local/bin/scp/HashRelay_rsa -p "$PORT" "$line" "HashRelay@$IP_ADD:$SERVER_PATH"
    else
      echo "scp -r -i /usr/local/bin/HashRelay/scp/HashRelay_rsa -p $PORT $line HashRelay@$IP_ADD:$SERVER_PATH"
    fi

    # Check return code
    if [[ $? -ne 0 ]]; then
      echo "ERROR: Failed to send $line"
    fi

  done <"$NEEDED_BACKUPS"
}

# Check if there is an configured IP_ADD inside the config file
if [[ -n "$IP_ADD" ]]; then
  echo "Actual configured IP: $IP_ADD"

  if [[ -n "$PORT" ]]; then
    echo "Actual configured Port: $PORT"

    # Verify that the server is IP before sending anything
    if [[ "$IS_UP" == true ]]; then
      # Can start to send via scp each backups file to the server.
      echo "The server is up"
      # Send the backups to the server
      send_backups_path
    else
      # Try to send the backups next time if the server is up
      echo "The server is Down"
    fi

  else
    echo "ERROR: Port not configured"
  fi

else
  echo "ERROR: Ip address not configured !"
fi
