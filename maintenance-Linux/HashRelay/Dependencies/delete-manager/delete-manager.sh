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
BACKUP_DIR="/home/sam/backups/$USER_PATH_NAME" # will be changed in the release from sam to HashRelay

# Only if --number is invoked
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
      sudo sed -i -E "s|^[[:space:]]*CHAIN_BACKUPS_NUMBER[[:space:]]*=.*$|CHAIN_BACKUPS_NUMBER=$number|" "$CONFIG_FILE"
    else
      printf "CHAIN_BACKUPS_NUMBER=%s\n" "$number" | sudo tee -a "$CONFIG_FILE" >/dev/null
    fi
  }

  title="Chain Backups Number Configurator"
  # Nice welcome banner
  gum style --border double --margin "1 2" --padding "1 2" --border-foreground 212 \
    "Welcome to $title"

  # Try to read the exixting CHAIN_BACKUPS_NUMBER from the config
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
  echo "Your number is set to: $NUMBER"

  # Finally, chain to the client script: exec replace the current process
  exec sudo bash "$NEXT"
fi

# Logging
LOG_DIR="/var/log/HashRelay"
LOG_FILE="${LOG_DIR}/delete.log"
umask 027
mkdir -p -- "$LOG_DIR"
# Ensure log file exist with restrictive perms
touch -- "$LOG_FILE"
chmod 655 -- "$LOG_FILE" "$LOG_DIR"

# Route all stdout/stderr to both console and the log file, with timestamps
# Use gawk to prefix line with a timestamps.
exec > >(awk '{ print strftime("[%Y-%m-%d %H:%M:%S%z]"), $0; fflush(); }' | tee -a "$LOG_FILE") 2>&1

echo "=== START delete run ==="
echo "Using config: $BACKUP_CONF"
echo "Using config: $CONFIG_FILE"
echo "Destination:  $BACKUP_DIR"
echo "Log file:     $LOG_FILE"

# Get the number that the user choose during it's configuration inside the CONFIG_FILE
choosen_number() {
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

# Placing the backup number inside a variable
BACKUP_NUMBER="$(choosen_number)"
AGE_CONF="/usr/local/bin/HashRelay/delete-manager/age.conf"

# Printing the choosen_number
if [[ "$VERBOSE" == true ]]; then
  echo "Inside the configuration, the user choose to backup $BACKUP_NUMBER iteration of the same file"
fi

# Read the AGE_CONF file to see the age of each backup
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! MUST BE DONE

# Add the backup file inside the AGE_CONF if it's a new backup file
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! MUST BE DONE

# If the name of the backup already exist, append to the backup name section
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! MUST BE DONE

# This is how the AGE_CONF file should look like with an BACKUP_NUMBER of 3:
#
# # Contain the age of each backups file # This is how the AGE_CONF file look like actually he just have this comment.
# -nginx.conf:
# backup-nginx.conf-2025-11-12-23-09-05.tar.gz -> AGE=0 (This is for year 2025 November(11) the 12 day at 23 hours 09 minutes and 05 seconds. This is the newest backup, he got juste backed up.
# backup-nginx.conf-2025-11-12-22-34-22.tar.gz -> AGE=1
# backup-nginx.conf-2025-11-11-15-23-18.tar.gz -> AGE=2
# backup-nginx.conf-2025-11-05-12-26-52.tar.gz -> AGE=3 (This backup should be deleted be cause he just got an age of 3 and the BACKUP_NUMBER is = 3)
# -nginx: (Here that's not the nginx.conf but directory that's been backup)
# backup-nginx-2025-11-10-12-14-42.tar.gz -> AGE=0
# backup-nginx-2025-11-04-05-37-13.tar.gz -> AGE=1
# -HashRelay:
# backup-HashRelay-2025-11-04-15-51-18.tar.gz -> AGE=0
# backup-HashRelay-2025-10-15-20-32-47.tar.gz -> AGE=1
# backup-HashRelay-2024-12-24-23-59-59.tar.gz -> AGE=2
#
# So in this example of AGE_CONF the nginx.conf backup with an age of 3 because BACKUP_NUMBER
# been configured to 3 inside the CONFIG_FILE should be deleted.
# The next time the user do an backup of nginx.conf, the backup with the age of 2
# should get an age of 3 and then should be deleted too. They should be deleted
# from the AGE_CONF and inside the BACKUP_DIR. What's good with this method is
# that is easy for us to delete the real backup file inside the BACKUP_DIR because
# we already have the exact name of the file and his directory with the BACKUP_DIR variable.
# I don't want to use another file then the AGE_CONF file because with one file it's
# more readable and more easy for me to centralize all inside one file.

# ===== Manage AGE_CONF, compute ages, and delete old backups =====

# Sanity checks
if [[ -z "${BACKUP_NUMBER:-}" ]]; then
  echo "[!] CHAIN_BACKUPS_NUMBER not found in $CONFIG_FILE; aborting." >&2
  exit 1
fi

if ! [[ "$BACKUP_NUMBER" =~ ^[0-9]+$ ]] || ((BACKUP_NUMBER < 1 || BACKUP_NUMBER > 100)); then
  echo "[!] Invalid BACKUP_NUMBER='$BACKUP_NUMBER' (must be 1..100)." >&2
  exit 1
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
  echo "[i] Backup directory '$BACKUP_DIR' does not exist yet. Nothing to do."
  # Ensure AGE_CONF still exists with header for future runs
  sudo mkdir -p -- "$(dirname -- "$AGE_CONF")"
  if [[ ! -f "$AGE_CONF" ]]; then
    printf "# Contain the age of each backups file\n" | sudo tee "$AGE_CONF" >/dev/null
  fi
  exit 0
fi

# Ensure AGE_CONF path exists
sudo mkdir -p -- "$(dirname -- "$AGE_CONF")"

# We will rebuild AGE_CONF from scratch based on actual files:
tmp_age="$(mktemp)"
trap 'rm -f -- "$tmp_age"' EXIT

# Write header
printf "# Contain the age of each backups file\n" >"$tmp_age"

shopt -s nullglob
declare -A groups # key: name, value: newline-separated "timestamp|fullpath|basename"
# Scan backups
for fullpath in "$BACKUP_DIR"/backup-*.tar.gz; do
  # Handle no matches
  [[ -e "$fullpath" ]] || break

  base="$(basename -- "$fullpath")"
  # Expect: backup-<name>-YYYY-MM-DD-HH-MM-SS.tar.gz
  if [[ "$base" =~ ^backup-(.+)-([0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2})\.tar\.gz$ ]]; then
    name="${BASH_REMATCH[1]}"
    ts="${BASH_REMATCH[2]}"
    groups["$name"]+="${ts}|${fullpath}|${base}"$'\n'
  else
    # Skip unexpected filenames but log them
    echo "[!] Skipping non-conforming file name: $base" >&2
  fi
done
shopt -u nullglob

# If no groups (no backups), still ensure AGE_CONF exists and exit
if ((${#groups[@]} == 0)); then
  if [[ "$VERBOSE" == true ]]; then
    echo "[i] No backup-*.tar.gz files found under $BACKUP_DIR"
  fi
  sudo cp -f -- "$tmp_age" "$AGE_CONF"
  exit 0
fi

# Process each group
deleted_total=0
kept_total=0

for name in "${!groups[@]}"; do
  # Print section header like "-nginx.conf:" or "-HashRelay:"
  printf -- "-%s:\n" "$name" >>"$tmp_age"

  # Sort entries by timestamp (descending: newest first).
  # Timestamps are lexicographically sortable in the provided format.
  mapfile -t lines < <(printf "%s" "${groups[$name]}" | sed '/^$/d' | sort -r)

  age=0
  for line in "${lines[@]}"; do
    ts="${line%%|*}"
    rest="${line#*|}" # fullpath|basename
    fullpath="${rest%%|*}"
    base="${rest##*|}"

    if ((age < BACKUP_NUMBER)); then
      # Keep this one; record in AGE_CONF
      printf "%s -> AGE=%d\n" "$base" "$age" >>"$tmp_age"
      ((kept_total++))
    else
      # Delete from disk and do not add to AGE_CONF
      if rm -f -- "$fullpath"; then
        ((deleted_total++))
        [[ "$VERBOSE" == true ]] && echo "[del] Removed: $fullpath (AGE=$age >= $BACKUP_NUMBER)"
      else
        echo "[!] Failed to delete: $fullpath" >&2
      fi
    fi
    ((age++))
  done

done

# Atomically replace AGE_CONF
if sudo cp -f -- "$tmp_age" "$AGE_CONF"; then
  :
else
  echo "[!] Failed to write $AGE_CONF" >&2
  exit 1
fi

echo "[i] AGE_CONF updated at $AGE_CONF"
echo "[i] Kept: $kept_total, Deleted: $deleted_total"
# ===== End AGE_CONF management =====
