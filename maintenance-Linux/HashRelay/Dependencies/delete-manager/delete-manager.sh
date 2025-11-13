#!/usr/bin/env bash
# delete-manager.sh - Backup rotation and age management
#
# This script manages backup retention by:
# 1. Tracking backup ages in AGE_CONF
# 2. Deleting backups older than CHAIN_BACKUPS_NUMBER
# 3. Maintaining proper age ordering by timestamp
#
# Author: Decarnelle Samuel

set -Eeuo pipefail
IFS=$'\n\t'

# =================== CONFIGURATION ===================

# Ensure we are root
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

# Main variables
BACKUP_CONF="/usr/local/bin/HashRelay/backups-manager/backups.conf"
NEXT="/usr/local/bin/HashRelay/hashrelay-client/hashrelay-client.sh"
CONFIG_FILE="/usr/local/bin/HashRelay/agent.conf"
AGE_CONF="/usr/local/bin/HashRelay/delete-manager/age.conf"

# Logging
LOG_DIR="/var/log/HashRelay"
LOG_FILE="${LOG_DIR}/delete.log"

# Flags
NUMBER=false
VERBOSE=false

# =================== HELPER FUNCTIONS ===================

usage() {
  cat <<'USAGE'
delete-manager.sh - Backup Rotation Management

Options:
  --number          Configure CHAIN_BACKUPS_NUMBER in agent.conf
  --verbose         Enable detailed logging
  -h|--help         Show this help

Environment:
  CONFIG_FILE       Main configuration file
  AGE_CONF          Backup age tracking file
  BACKUP_DIR        Directory containing backups (derived from NAME)

Behavior:
  - Without flags: Manages backup rotation based on CHAIN_BACKUPS_NUMBER
  - With --number: Interactive configuration mode (chains to next script)

Example:
  sudo ./delete-manager.sh --verbose
  sudo ./delete-manager.sh --number
USAGE
}

# Small wrapper for gum
confirm() { gum confirm "$1"; }

# =================== CONFIGURATION EXTRACTION ===================

# Extract NAME from CONFIG_FILE
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
  line="${line#"${line%%[![:space:]]*}"}" # ltrim
  line="${line%"${line##*[![:space:]]}"}" # rtrim
  line="${line%\"}"
  line="${line#\"}"
  line="${line%\'}"
  line="${line#\'}"

  echo "$line"
}

# Extract CHAIN_BACKUPS_NUMBER from CONFIG_FILE
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
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  line="${line%\"}"
  line="${line#\"}"
  line="${line%\'}"
  line="${line#\'}"

  echo "$line"
}

# Validate number: 1-100
valid_num() {
  local n=$1
  [[ "$n" =~ ^[0-9]+$ ]] || return 1
  ((n >= 1 && n <= 100)) || return 1
  return 0
}

# Persist CHAIN_BACKUPS_NUMBER to CONFIG_FILE
set_num() {
  local number="$1"

  sudo mkdir -p "$(dirname -- "$CONFIG_FILE")"

  if [[ -f "$CONFIG_FILE" ]] && grep -qE '^[[:space:]]*CHAIN_BACKUPS_NUMBER[[:space:]]*=' "$CONFIG_FILE"; then
    # Backup and update existing
    sudo cp -a -- "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%s)"
    sudo sed -i -E "s|^[[:space:]]*CHAIN_BACKUPS_NUMBER[[:space:]]*=.*$|CHAIN_BACKUPS_NUMBER=$number|" "$CONFIG_FILE"
  else
    # Append new
    printf "CHAIN_BACKUPS_NUMBER=%s\n" "$number" | sudo tee -a "$CONFIG_FILE" >/dev/null
  fi
}

# =================== PARSE ARGUMENTS ===================

while [[ $# -gt 0 ]]; do
  case "$1" in
  --number)
    NUMBER=true
    shift
    ;;
  --verbose)
    VERBOSE=true
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "[!] Unknown argument: $1" >&2
    usage
    exit 1
    ;;
  esac
done

# =================== INTERACTIVE CONFIGURATION MODE ===================

if [[ "$NUMBER" == true ]]; then
  title="Chain Backups Number Configurator"

  # Welcome banner
  gum style --border double --margin "1 2" --padding "1 2" --border-foreground 212 \
    "Welcome to $title"

  # Check config file exists
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[!] Configuration file not found: $CONFIG_FILE" >&2
    exit 1
  fi

  [[ "$VERBOSE" == true ]] && echo "[i] Configuration file exists: $CONFIG_FILE"

  # Get existing number
  existing_number="$(get_existing_number)"

  # If exists, ask if user wants to modify
  if [[ -n "$existing_number" ]]; then
    gum style --foreground 212 "Current CHAIN_BACKUPS_NUMBER: $existing_number"

    if ! confirm "Do you want to modify this number?"; then
      echo "[i] Keeping existing number: $existing_number"
      [[ -f "$NEXT" ]] && exec sudo bash "$NEXT"
      exit 0
    fi
  fi

  # Prompt for new number
  while :; do
    number="$(gum input --placeholder 'Enter number (1-100), e.g. 3' \
      ${existing_number:+--value="$existing_number"})"

    [[ -z "${number:-}" ]] && {
      echo "[!] No input provided. Exiting."
      exit 0
    }

    if ! valid_num "$number"; then
      gum style --foreground 196 "❌ Invalid! Enter a number between 1 and 100"
      continue
    fi

    break
  done

  # Save and confirm
  set_num "$number"
  gum style --foreground 82 "✓ CHAIN_BACKUPS_NUMBER set to: $number"

  # Chain to next script
  [[ -f "$NEXT" ]] && exec sudo bash "$NEXT"
  exit 0
fi

# =================== AUTOMATED MODE - SETUP LOGGING ===================

umask 027
mkdir -p -- "$LOG_DIR"
touch -- "$LOG_FILE"
chmod 640 -- "$LOG_FILE"
chmod 750 -- "$LOG_DIR"

# Redirect all output to log with timestamps
exec > >(awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush(); }' | tee -a "$LOG_FILE") 2>&1

echo "╔════════════════════════════════════════╗"
echo "║   DELETE-MANAGER - Backup Rotation    ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "Config file:      $CONFIG_FILE"
echo "Age tracking:     $AGE_CONF"
echo "Log file:         $LOG_FILE"

# =================== DERIVE BACKUP_DIR ===================

USER_PATH_NAME=$(get_existing_name)

if [[ -z "$USER_PATH_NAME" ]]; then
  echo "[!] ERROR: NAME not found in $CONFIG_FILE" >&2
  echo "[!] Cannot determine BACKUP_DIR. Exiting." >&2
  exit 1
fi

BACKUP_DIR="/home/sam/backups/$USER_PATH_NAME"
echo "Backup directory: $BACKUP_DIR"

if [[ ! -d "$BACKUP_DIR" ]]; then
  echo "[!] WARNING: BACKUP_DIR does not exist: $BACKUP_DIR" >&2
  echo "[i] Creating directory..."
  mkdir -p -- "$BACKUP_DIR"
fi

# =================== GET CHAIN_BACKUPS_NUMBER ===================

BACKUP_NUMBER="$(get_existing_number)"

if [[ -z "$BACKUP_NUMBER" ]]; then
  echo "[!] ERROR: CHAIN_BACKUPS_NUMBER not found in $CONFIG_FILE" >&2
  echo "[!] Run with --number to configure it first." >&2
  exit 1
fi

if ! valid_num "$BACKUP_NUMBER"; then
  echo "[!] ERROR: Invalid CHAIN_BACKUPS_NUMBER: $BACKUP_NUMBER" >&2
  exit 1
fi

echo "Retention policy:  Keep last $BACKUP_NUMBER backup(s) per item"
echo ""

# =================== BACKUP PARSING ===================

# Parse filename: backup-<name>-YYYY-MM-DD-HH-MM-SS.tar.gz
# Returns: "<name>\t<timestamp>" or fails with return 1
parse_backup_basename() {
  local base="$1"
  if [[ "$base" =~ ^backup-(.+)-([0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2})\.tar\.gz$ ]]; then
    printf "%s\t%s\n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

# Convert timestamp to Unix epoch for sorting
# Format: YYYY-MM-DD-HH-MM-SS -> epoch seconds
ts_to_epoch() {
  local ts="$1"
  # Convert YYYY-MM-DD-HH-MM-SS to "YYYY-MM-DD HH:MM:SS"
  local dt="${ts:0:10} ${ts:11:2}:${ts:14:2}:${ts:17:2}"
  date -d "$dt" +%s 2>/dev/null || echo "0"
}

# =================== AGE_CONF MANAGEMENT ===================

# Ensure AGE_CONF file exists
ensure_age_conf() {
  mkdir -p -- "$(dirname -- "$AGE_CONF")"
  if [[ ! -f "$AGE_CONF" ]]; then
    echo "# Backup age tracking - Generated by delete-manager.sh" >"$AGE_CONF"
    [[ "$VERBOSE" == true ]] && echo "[i] Created AGE_CONF: $AGE_CONF"
  fi
}

# Check if section "-<name>:" exists
has_section() {
  local name="$1"
  grep -q -E "^-${name}:$" "$AGE_CONF" 2>/dev/null
}

# Check if backup entry exists in section
entry_exists_in_section() {
  local name="$1" base="$2"
  awk -v sec="-$name:" -v base="$base" '
    $0 == sec { insec=1; next }
    insec && /^-.*:$/ { insec=0 }
    insec && $1 == base { found=1; exit }
    END { exit !found }
  ' "$AGE_CONF" 2>/dev/null
}

# =================== 1) GET_ACTUAL_BACKUPS ===================

# Scan BACKUP_DIR and emit TSV: name<TAB>timestamp<TAB>epoch<TAB>fullpath<TAB>basename
get_actual_backups() {
  [[ -d "$BACKUP_DIR" ]] || {
    [[ "$VERBOSE" == true ]] && echo "[i] BACKUP_DIR does not exist yet: $BACKUP_DIR"
    return 0
  }

  shopt -s nullglob
  local full base parsed name ts epoch

  for full in "$BACKUP_DIR"/backup-*.tar.gz; do
    [[ -e "$full" ]] || break

    base="$(basename -- "$full")"

    if parsed="$(parse_backup_basename "$base")"; then
      name="${parsed%%$'\t'*}"
      ts="${parsed##*$'\t'}"
      epoch="$(ts_to_epoch "$ts")"

      printf "%s\t%s\t%s\t%s\t%s\n" "$name" "$ts" "$epoch" "$full" "$base"
    else
      [[ "$VERBOSE" == true ]] && echo "[skip] Non-conforming filename: $base"
    fi
  done

  shopt -u nullglob
}

# =================== 2) CREATE_BACKUPS_NAME ===================

# Ensure section "-<name>:" exists in AGE_CONF
create_backups_name() {
  local name="$1"

  if ! has_section "$name"; then
    echo "-${name}:" >>"$AGE_CONF"
    [[ "$VERBOSE" == true ]] && echo "[+] Created section: -${name}:"
  fi
}

# =================== 3) APPEND_NEW_BACKUPS ===================

# Add new backup entries to AGE_CONF under their sections
append_new_backups() {
  ensure_age_conf

  local name ts epoch full base
  local sections_created=0 entries_added=0

  # Process all backups
  while IFS=$'\t' read -r name ts epoch full base; do
    # Ensure section exists
    if ! has_section "$name"; then
      create_backups_name "$name"
      ((sections_created++))
    fi

    # Add entry if not exists
    if ! entry_exists_in_section "$name" "$base"; then
      # Append under section (before next section or EOF)
      awk -v sec="-$name:" -v entry="$base -> AGE=?" '
        BEGIN { done=0 }
        $0 == sec { print; insec=1; next }
        insec && /^-.*:$/ && !done { print entry; done=1; insec=0 }
        { print }
        END { if (insec && !done) print entry }
      ' "$AGE_CONF" >"$AGE_CONF.tmp"

      mv -f -- "$AGE_CONF.tmp" "$AGE_CONF"
      ((entries_added++))
      [[ "$VERBOSE" == true ]] && echo "[+] Added: $base under -${name}:"
    fi
  done < <(get_actual_backups)

  echo "[i] Sections created: $sections_created, Entries added: $entries_added"
}

# =================== 4) MAKE_AGE ===================

# Recompute ages based on timestamps (newest = AGE=0)
make_age() {
  ensure_age_conf

  local tmp
  tmp="$(mktemp)"

  {
    echo "# Backup age tracking - Updated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    # Get all unique backup names
    mapfile -t all_names < <(get_actual_backups | cut -f1 | sort -u)

    local name
    for name in "${all_names[@]}"; do
      [[ -z "$name" ]] && continue

      # Get all backups for this name, sorted by epoch DESC (newest first)
      mapfile -t rows < <(
        get_actual_backups |
          awk -F'\t' -v n="$name" '$1 == n' |
          sort -t$'\t' -k3,3rn
      )

      if ((${#rows[@]} == 0)); then
        [[ "$VERBOSE" == true ]] && echo "[i] No backups found for: $name"
        continue
      fi

      # Write section header
      printf -- "-%s:\n" "$name"

      # Assign ages
      local age=0 row base
      for row in "${rows[@]}"; do
        base="$(echo "$row" | cut -f5)"
        printf "%s -> AGE=%d\n" "$base" "$age"
        ((age++))
      done

      echo "" # Blank line between sections
    done
  } >"$tmp"

  mv -f -- "$tmp" "$AGE_CONF"
  [[ "$VERBOSE" == true ]] && echo "[i] Ages recomputed and written to $AGE_CONF"
}

# =================== 5) DELETE_OLD ===================

# Delete backups with AGE >= BACKUP_NUMBER
delete_old() {
  ensure_age_conf

  local deleted=0 failed=0 missing=0

  # Extract entries to delete: AGE >= BACKUP_NUMBER
  mapfile -t to_delete < <(
    awk -v keep="$BACKUP_NUMBER" '
      /^-.*:$/ { next }
      /^[#[:space:]]*$/ { next }
      {
        # Match: "filename -> AGE=N"
        if (match($0, /^([^[:space:]]+)[[:space:]]*->[[:space:]]*AGE=([0-9]+)/, arr)) {
          if (arr[2] >= keep) {
            print arr[1]
          }
        }
      }
    ' "$AGE_CONF"
  )

  if ((${#to_delete[@]} == 0)); then
    echo "[i] No backups to delete (all within retention policy)"
    return 0
  fi

  echo "[i] Found ${#to_delete[@]} backup(s) exceeding retention policy"

  # Delete each file
  local base full
  for base in "${to_delete[@]}"; do
    full="$BACKUP_DIR/$base"

    if [[ ! -e "$full" ]]; then
      [[ "$VERBOSE" == true ]] && echo "[warn] Already deleted: $base"
      ((missing++))
      continue
    fi

    if rm -f -- "$full"; then
      echo "[-] Deleted: $base"
      ((deleted++))
    else
      echo "[!] Failed to delete: $base" >&2
      ((failed++))
    fi
  done

  # Rebuild AGE_CONF to remove deleted entries
  echo "[i] Rebuilding age tracking..."
  make_age

  echo ""
  echo "Deletion summary:"
  echo "  ✓ Deleted:    $deleted"
  echo "  ✗ Failed:     $failed"
  echo "  ⚠ Missing:    $missing"
}

# =================== MAIN EXECUTION ===================

echo "Starting backup rotation process..."
echo ""

# Step 1: Discover current backups
echo "[1/4] Scanning backup directory..."
backup_count=$(get_actual_backups | wc -l)
echo "      Found $backup_count backup file(s)"

# Step 2: Update AGE_CONF with new backups
echo "[2/4] Updating age tracking file..."
append_new_backups

# Step 3: Recalculate ages
echo "[3/4] Recalculating backup ages..."
make_age

# Step 4: Delete old backups
echo "[4/4] Applying retention policy..."
delete_old

echo ""
echo "╔════════════════════════════════════════╗"
echo "║     Backup Rotation Complete ✓         ║"
echo "╚════════════════════════════════════════╝"
echo ""

exit 0
