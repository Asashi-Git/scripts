#!/usr/bin/env bash
# This script is used to backup the file/directory that are put
# inside backup.conf by the agent and compress them with tar then
# put the backups inside the directory BACKUP_DIR
#
# Author: Decarnelle Samuel

set -Eeuo pipefail
IFS=$'\n\t'

# Ensure we are root
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

# Your variables
BACKUP_CONF="/usr/local/bin/HashRelay/backups-manager/backups.conf"
BACKUP_DIR="/home/sam/backups"
BACKUP_NAME="" # set per-line from the config
BACKUP_PATH="" # set per-line from the config
NOW=""         # set per-backup with seconds, minutes, hours, year, month, date

NEXT=/usr/local/bin/HashRelay/hashrelay-client/hashrelay-client.sh
VERBOSE=false                                     # Extra logging
NAME=false                                        # if true, ask the name of the actual client machine
CONFIG_FILE="/usr/local/bin/HashRelay/agent.conf" # The main config file (where we need to add the CLIENT_NAME)

# usage(): print help text:
usage() {
  cat <<'USAGE'
  backups-manager.sh
  Options:
    --name                    Put/change the name of the client inside the file agent.conf
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
  --name)
    NAME=true # Ask for the client name
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

# Only if --name is invoked
if [[ "$NAME" == true ]]; then
  if [[ -f "$CONFIG_FILE" ]]; then
    if [[ "$VERBOSE" == true ]]; then
      echo "The configuration file exist !"
    else
      echo "Configuration file not found !"
    fi
  fi

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

  # Strict char validator: a-zA-Z0-9_-
  valid_char() {
    local s=$1
    [[ $s =~ ^[A-Za-z0-9_.-]+$ ]] || return 1
    return 0
  }

  # Persist NAME into CONFIG_FILE:
  # - Ensure directory exists (With sudo, since path is under /usr/local/bin/)
  # - If NAME= exists, make a timestamped backup and replace it in-place
  # - Otherwise, append a new NAME line
  set_name() {
    local name="$1"

    sudo mkdir -p "$(dirname -- "$CONFIG_FILE")"

    if [[ -f "$CONFIG_FILE" ]] && grep -qE '^[[:space:]]*NAME[[:space:]]*=' "$CONFIG_FILE"; then
      sudo cp -a -- "$CONFIG_FILE" "CONFIG_FILE.bak.$(date -Iseconds)"
      sudo sed -i -E "s|^[[:space:]]*NAME[[:space:]]*=.*$|NAME=$name|" "$CONFIG_FILE"
    else
      printf "NAME=%s\n" "$name" | sudo tee -a "$CONFIG_FILE" >/dev/null
    fi
  }

  title="Name Configurator"
  # Nice welcome banner
  gum style --border double --margin "1 2" --padding "1 2" --border-foreground 212 \
    "Welcome to $title"

  # Try to read the exixting NAME from the config
  existing_name="$(get_existing_name)"

  # If we already have a value, show it and ask whether to modify it
  if [[ -n "$existing_name" ]]; then
    gum style --foreground 212 "Current NAME: $existing_name"

    if ! confirm "Do you want to modify the NAME?"; then
      echo "Keeping existing NAME: $existing_name"
      exec sudo bash "$NEXT"
    fi
  fi

  # Prompt loop until we get a valid User (or User exist)
  while :; do
    # Pre-fill with existing value if we had one
    name="$(gum input --placeholder 'e.g. sam' \
      ${existing_name:+--value= "$existing_name"})"

    # If user pressed Enter on an empty input, exit gracefully
    [[ -z "${name:-}" ]] && {
      echo "No input provided. Exiting."
      exit 0
    }

    if ! valid_char "$name"; then
      gum style --foreground 196 "Invalid name. Enter a name with only these characteres A-Za-z0-9_.-"
      continue
    fi

    NAME="$name"
    break
  done

  # Persist the chosen name into the config
  set_name "$NAME"
  echo "Your name is set to: $NAME"

  # Finally, chain to the client script: exec replace the current process
  exec sudo bash "$NEXT"
fi

# Logging
LOG_DIR="/var/log/HashRelay"
LOG_FILE="${LOG_DIR}/backup.log"
umask 027
mkdir -p -- "$LOG_DIR" "$BACKUP_DIR"
# Ensure log file exists with restrictive perms
touch -- "$LOG_FILE"
chmod 655 -- "$LOG_FILE" "$LOG_DIR"

# Route all stdout/stderr to both console and the log file, with timestamps
# Uses gawk to prefix lines with a timestamp.
exec > >(awk '{ print strftime("[%Y-%m-%d %H:%M:%S%z]"), $0; fflush(); }' | tee -a "$LOG_FILE") 2>&1

echo "=== START backup run ==="
echo "Using config: $BACKUP_CONF"
echo "Destination:  $BACKUP_DIR"
echo "Log file:     $LOG_FILE"

# Helper to trim whitespace
trim() {
  local s="$*"
  s="${s#"${s%%[![:space:]]*}"}" # ltrim
  s="${s%"${s##*[![:space:]]}"}" # rtrim
  printf '%s' "$s"
}

# Optional: make BACKUP_NAME safe for filenames (keeps alnum . _ -)
sanitize_name() {
  printf '%s' "$1" | tr ' /' '__' | tr -cd '[:alnum:]._-' || true
}

# Read lines "BACKUP_NAME=BACKUP_PATH", skipping blanks and comments
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

  # Split at first '=' only
  BACKUP_NAME="$(trim "${line%%=*}")"
  BACKUP_PATH="$(trim "${line#*=}")"

  if [[ -z "$BACKUP_NAME" || -z "$BACKUP_PATH" ]]; then
    echo "WARN: Invalid line (need BACKUP_NAME=BACKUP_PATH): $line"
    continue
  fi

  if [[ ! -e "$BACKUP_PATH" ]]; then
    echo "WARN: Skipping missing path for $BACKUP_NAME: $BACKUP_PATH"
    continue
  fi

  # Timestamp: Second-Minutes-Hour-Year-Month-Date
  NOW="$(date +%S-%M-%H-%Y-%m-%d)"

  # Build archive path
  SAFE_BACKUP_NAME="$(sanitize_name "$BACKUP_NAME")"
  ARCHIVE="${BACKUP_DIR}/backup-${SAFE_BACKUP_NAME}-${NOW}.tar.gz"

  echo "INFO: Creating $ARCHIVE from $BACKUP_PATH (name: $BACKUP_NAME)"
  if tar -czf "$ARCHIVE" \
    --absolute-names \
    --exclude-vcs \
    --ignore-failed-read \
    --warning=no-file-changed \
    "$BACKUP_PATH"; then
    echo "OK: $ARCHIVE <= $BACKUP_PATH (name: $BACKUP_NAME)"
    # Optional integrity file:
    # sha256sum "$ARCHIVE" > "${ARCHIVE}.sha256"
  else
    echo "ERROR: Failed to back up $BACKUP_PATH (name: $BACKUP_NAME)."
  fi
done < <(grep -Ev '^\s*(#|$)' "$BACKUP_CONF")

echo "=== END backup run ==="
