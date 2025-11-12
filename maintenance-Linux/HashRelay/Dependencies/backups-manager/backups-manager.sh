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

# Logging
LOG_DIR="/var/log/HashRelay"
LOG_FILE="${LOG_DIR}/backup.log"
umask 027
mkdir -p -- "$LOG_DIR" "$BACKUP_DIR"
# Ensure log file exists with restrictive perms
touch -- "$LOG_FILE"
chmod 650 -- "$LOG_FILE" "$LOG_DIR"

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
