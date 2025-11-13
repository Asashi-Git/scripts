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

# This is the part of the script where I need help:
# This is how the AGE_CONF file should look like with an BACKUP_NUMBER of 3:
#
# # Contain the age of each backups file # This is how the AGE_CONF file look like actually he just have this comment.
# -nginx.conf: <- this is a "BACKUP_NAME" BACKUP_NAME always have this format "-$BACKUP_NAME:\n"
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

# So to make it work we need to make all theses steps in order:
#
# 1- get_actual_backups():
# Create a function that look at the BACKUP_DIR to store all of the actual backups
#
# 2- create_backups_name():
# Create a function that look at the AGE_CONF file to see if the BACKUP_NAME already
# exist inside the file. We can easily spot if because all BACKUP_NAME have a "-BACKUP_NAME:"
# format inside the AGE_CONF file. If there is no BACKUP_NAME match it create the BACKUP_NAME.
#
# 3- append_new_backups():
# Create a function that look at the AGE_CONF file to see if the backups inside BACKUP_DIR have
# already been reported throug the file. If there is no BACKUP_NAME match it call the precedent
# function to create it. If there already a BACKUP_NAME it add the new backups under the
# BACKUP_NAME.
#
# 4- make_age():
# Create a function that look at the AGE_CONF and via the date of the backup, determine
# the age of the backups inside the AGE_CONF file. The most recent file get an age of 0.
# the second most recent get age++ etc... The age must be print inside the AGE_CONF file
# to the left of each baskup like showed in the example AGE_CONF file.
#
# 5- delete_old():
# Create a function that look at the AGE_CONF file and for each BACKUP_NAME go through the
# age of all the backup. If a backup have an age >= of the BACKUP_NUMBER he got deleted
# and his line inside the AGE_CONF got deleted too.
# This function should do that for all children of BACKUP_NAME.
#

# =================== Helpers ===================

# Parse backup basename into: "<name>\t<timestamp>", return 0 on success
# Expected: backup-<name>-YYYY-MM-DD-HH-MM-SS.tar.gz
parse_backup_basename() {
  local base="$1"
  if [[ "$base" =~ ^backup-(.+)-([0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2})\.tar\.gz$ ]]; then
    printf "%s\t%s\n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

# Ensure AGE_CONF exists
ensure_age_conf() {
  mkdir -p -- "$(dirname -- "$AGE_CONF")"
  [[ -f "$AGE_CONF" ]] || echo "# Contain the age of each backups file" >"$AGE_CONF"
}

# Return 0 if a section "-<name>:" exists
has_section() {
  ensure_age_conf
  local name="$1"
  grep -q -E "^-${name}:" "$AGE_CONF"
}

# Return 0 if a given "basename -> " entry is inside section "-<name>:"
entry_exists_in_section() {
  ensure_age_conf
  local name="$1" base="$2"
  awk -v sec="-$name:" -v base="$base" '
    $0==sec {insec=1; next}
    insec && /^-/ {insec=0}
    insec && index($0, base" -> ")==1 {found=1; exit}
    END {exit !found}
  ' "$AGE_CONF"
}

# Append a line to a specific section, creating the section if missing
append_line_to_section() {
  ensure_age_conf
  local name="$1" line="$2"
  if ! has_section "$name"; then
    echo "-${name}:" >>"$AGE_CONF"
    echo "$line" >>"$AGE_CONF"
    return 0
  fi

  # Insert inside the section, just before the next section header or EOF
  local tmp
  tmp="$(mktemp)"
  awk -v sec="-$name:" -v ins="$line" '
    BEGIN{insec=0; done=0}
    $0==sec {print; insec=1; next}
    insec && /^-/ && !done {print ins; done=1; insec=0}
    {print}
    END { if (insec && !done) print ins }
  ' "$AGE_CONF" >"$tmp"
  cp -f -- "$tmp" "$AGE_CONF"
  rm -f -- "$tmp"
}

# =================== 1) get_actual_backups ===================
# Emit TSV: name <TAB> ts <TAB> fullpath <TAB> basename
get_actual_backups() {
  [[ -d "$BACKUP_DIR" ]] || {
    [[ "$VERBOSE" == true ]] && echo "[i] No BACKUP_DIR: $BACKUP_DIR"
    return 0
  }
  shopt -s nullglob
  local full base parsed
  for full in "$BACKUP_DIR"/backup-*.tar.gz; do
    [[ -e "$full" ]] || break
    base="$(basename -- "$full")"
    if parsed="$(parse_backup_basename "$base")"; then
      # parsed = "<name>\t<timestamp>"
      printf "%s\t%s\t%s\t%s\n" "${parsed%%$'\t'*}" "${parsed##*$'\t'}" "$full" "$base"
    else
      [[ "$VERBOSE" == true ]] && echo "[skip] Non-conforming: $base"
    fi
  done
  shopt -u nullglob
}

# =================== 2) create_backups_name ===================
# Ensure "-<BACKUP_NAME>:" section exists
create_backups_name() {
  local name="$1"
  ensure_age_conf
  if ! has_section "$name"; then
    [[ "$VERBOSE" == true ]] && echo "[sec] Creating section: -$name:"
    echo "-${name}:" >>"$AGE_CONF"
  fi
}

# =================== 3) append_new_backups ===================
# Add any missing file lines under their section as "basename -> AGE=?"
append_new_backups() {
  ensure_age_conf
  local name _ts full base
  local sections_added=0 appended=0

  # First pass: ensure sections
  while IFS=$'\t' read -r name _ts full base; do
    if ! has_section "$name"; then
      create_backups_name "$name"
      ((sections_added++))
    fi
  done < <(get_actual_backups)

  # Second pass: append entries that are not yet recorded
  while IFS=$'\t' read -r name _ts full base; do
    if ! entry_exists_in_section "$name" "$base"; then
      [[ "$VERBOSE" == true ]] && echo "[add] $base -> AGE=? under -$name:"
      append_line_to_section "$name" "$base -> AGE=?"
      ((appended++))
    fi
  done < <(get_actual_backups)

  [[ "$VERBOSE" == true ]] && echo "[i] Sections added: $sections_added, New entries appended: $appended"
}

# =================== 4) make_age ===================
# Recompute ages from timestamps, newest AGE=0
make_age() {
  ensure_age_conf
  local tmp
  tmp="$(mktemp)"
  {
    echo "# Contain the age of each backups file"

    # Collect names present in conf and directory
    mapfile -t _conf_names < <(grep -E '^-.*:$' "$AGE_CONF" | sed -E 's/^-([^:]+):$/\1/' | sort -u)
    mapfile -t _dir_names < <(get_actual_backups | cut -f1 | sort -u)
    mapfile -t _all_names < <(printf "%s\n" "${_conf_names[@]}" "${_dir_names[@]}" | awk 'NF' | sort -u)

    local name
    for name in "${_all_names[@]}"; do
      # rows: name<TAB>ts<TAB>full<TAB>base — sort by ts desc
      mapfile -t _rows < <(get_actual_backups | awk -v n="$name" -F'\t' '$1==n' | sort -t $'\t' -k2,2r)
      ((${#_rows[@]})) || {
        [[ "$VERBOSE" == true ]] && echo "[i] Section -$name: empty, skipping" >&2
        continue
      }

      printf -- "-%s:\n" "$name"
      local age=0 row base _name _ts _full
      for row in "${_rows[@]}"; do
        IFS=$'\t' read -r _name _ts _full base <<<"$row"
        printf "%s -> AGE=%d\n" "$base" "$age"
        ((age++))
      done
    done
  } >"$tmp"

  cp -f -- "$tmp" "$AGE_CONF"
  rm -f -- "$tmp"
  [[ "$VERBOSE" == true ]] && echo "[i] AGE recomputed and $AGE_CONF rewritten."
}

# =================== 5) delete_old ===================
# Delete files with AGE >= BACKUP_NUMBER and remove their lines from AGE_CONF, then re-pack ages.
delete_old() {
  ensure_age_conf

  # Build deletion list from current AGE_CONF
  mapfile -t _to_del < <(
    awk -v keep="$BACKUP_NUMBER" '
      /^-.*:$/ { next }
      /^[#[:space:]]*$/ { next }
      {
        if (match($0,/^([^[:space:]]+)[[:space:]]*->[[:space:]]*AGE=([0-9]+)/,a)) {
          if (a[2] >= keep) print a[1];
        }
      }
    ' "$AGE_CONF"
  )

  local base full deleted=0 failed=0
  for base in "${_to_del[@]}"; do
    full="$BACKUP_DIR/$base"
    if [[ -e "$full" ]]; then
      if rm -f -- "$full"; then
        ((deleted++))
        [[ "$VERBOSE" == true ]] && echo "[del] $full (AGE >= $BACKUP_NUMBER)"
      else
        ((failed++))
        echo "[!] Failed to delete $full" >&2
      fi
    else
      [[ "$VERBOSE" == true ]] && echo "[warn] Already missing: $full"
    fi
  done

  # Recompute and rewrite AGE_CONF after deletions
  make_age
  [[ "$VERBOSE" == true ]] && echo "[i] Deleted: $deleted, Failed: $failed"
}

# =================== Orchestrate ===================
# Validate BACKUP_NUMBER using your variables
if ! [[ "${BACKUP_NUMBER:-}" =~ ^[0-9]+$ ]]; then
  echo "[!] Invalid or missing BACKUP_NUMBER from $CONFIG_FILE" >&2
  exit 1
fi

# Pipeline (call in this order)
get_actual_backups >/dev/null # probe / warm-up; output ignored
append_new_backups
make_age
delete_old
