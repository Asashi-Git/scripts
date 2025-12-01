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
NEXT_SCRIPT=/usr/local/bin/HashRelay/hash-printer/hash-printer.sh

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

# TODO:
# For the server we need to do a loop for each client name found inside the BACKUP_DIR
# AND
# I need to do the same for the age.conf so every user have is age.conf file.

BACKUP_PATH="/home/sam/backups" # Need to be changed to HashRelay for the release

# Creating a for loop to loop through each <CLIENT_NAME>
for client_dir in "$BACKUP_PATH"/*; do

  # Skip if not a directory
  [[ -d "$client_dir" ]] || continue

  # Get the name of each user
  client_name=$(basename "$client_dir")

  # Get the path for each user
  BACKUP_DIR="$BACKUP_PATH/$client_name"

  echo "=== Delete run for $client_name ==="
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
  # TODO:
  # Need to make AGE_CONF for each user
  # Need to verify if the AGE_CONF exist if not, create it
  BACKUP_NUMBER="$(choosen_number)"
  AGE_CONF="/usr/local/bin/HashRelay/delete-manager/$client_name/age.conf"

  # If the AGE_CONF don't exist, create it
  if [[ ! -f "$AGE_CONF" ]]; then
    echo "The age.conf for the user $client_name do not exist."
    echo "Creating the file..."

    # Create the directoy for the user
    mkdir -p "/usr/local/bin/HashRelay/delete-manager/$client_name"

    # Create the file for the user with the correct template
    printf '# Contain the age of each backups file\n' | sudo tee -a "/usr/local/bin/HashRelay/delete-manager/$client_name/age.conf" >/dev/null

    # Verify that the file is been correctly created
    if [[ ! -f "$AGE_CONF" ]]; then
      echo "Unable to create the age.conf file for the user $client_name"
    else
      echo "The file age.conf created for the user $client_name"
    fi

  else
    echo "the file age.conf already exist for the user $client_name"
  fi

  # Printing the choosen_number
  if [[ "$VERBOSE" == true ]]; then
    echo "Inside the configuration, the user choose to backup $BACKUP_NUMBER iteration of the same file"
  fi

  # Creating a function to get all of the file inside the $BACKUP_DIR
  ACTUAL_FILES=""
  get_actual_files() {
    if [[ "$VERBOSE" == true ]]; then
      echo "Fetching the different backup files inside the $BACKUP_DIR"
    fi
    # Populate ACTUAL_FILES with only regular files in BACKUP_DIR (non-recursive)
    mapfile -d '' -t ACTUAL_FILES < <(
      find "$BACKUP_DIR" -maxdepth 1 -type f -printf '%f\0' | sort -z #-r # Sort in reverse
    )
    printf '%s\n' "${ACTUAL_FILES[@]}"
  }

  # Format the $ACTUAL_FILES to get only the name of the backup
  format_file_name() {
    get_actual_files || return 1

    BACKUP_NAMES=()
    local -A seen=()
    local f base name
    local re='^backup-(.+)-[0-9]{4}(-[0-9]{2}){5}\.tar\.gz$'

    for f in "${ACTUAL_FILES[@]}"; do
      base="${f##*/}"
      if [[ $base =~ $re ]]; then
        name="${BASH_REMATCH[1]}"
        if [[ -z ${seen[$name]+x} ]]; then
          BACKUP_NAMES+=("$name")
          seen[$name]=1
          if [[ "$VERBOSE" == true ]]; then
            printf '%s\n' "$name"
          fi
        fi
      else
        if [[ "$VERBOSE" == true ]]; then
          printf 'warn: skipping non-matching file: %s\n' "$base" >&2
        fi
      fi
    done

    # Only print when not verbose (do not affect exit status)
    if [[ "$VERBOSE" != true ]]; then
      printf '%s\n' "${BACKUP_NAMES[@]}"
    fi

    return 0
  }

  # get_backup_name
  get_backup_name() {
    # Look if the file exist
    if [[ -z ${AGE_CONF:-} ]]; then
      printf 'ERROR: AGE_CONF is not set.\n' >&2
      return 1
    fi

    # Create if missing; ensure writable
    if [[ ! -f $AGE_CONF ]]; then
      ensure_age_conf || {
        printf 'ERROR: cannot creat %s\n' "$AGE_CONF" >&2
        return 1
      }
    fi

    # Check if AGE_CONF is wwritable
    if [[ ! -w $AGE_CONF ]]; then
      printf 'ERROR: AGE_CONF "%s" is not writable.\n' "$AGE_CONF" >&2
      return 1
    fi

    # If all test passed do
    if [[ "$VERBOSE" == true ]]; then
      printf 'Starting to check names against %s\n' "$AGE_CONF"
    fi

    # Do not continue if it's impossible to format the name
    format_file_name || {
      printf 'ERROR: format_file_name failed\n' >&2
      return 1
    }

    local name pattern
    local -i added=0
    for name in "${BACKUP_NAMES[@]}"; do
      pattern="-$name:"
      if grep -qxF -- "$pattern" "$AGE_CONF"; then
        if [[ "$VERBOSE" == true ]]; then
          printf 'Found existing entry: %s\n' "$pattern"
        fi
      else
        printf '%s\n' "$pattern" >>"$AGE_CONF" || {
          printf 'ERROR: failed to append "%s" to %s\n' "$pattern" "$AGE_CONF" >&2
          return 1
        }
        # In bash, the arithmetic command (( expr )) returns exit status 0 if expr ≠ 0, and 1 if expr == 0.
        # With post-increment, (( added++ )) evaluates to the old value, then increments. So when added is 0, the expression evaluates to 0 → exit status 1.
        # If your script uses set -e (errexit), that non-zero status makes the shell abort the current command list/loop, which looks like a “crash.”
        ((added++)) || true # So we need to put || true; else ERROR code 1
        if [[ "$VERBOSE" == true ]]; then
          printf 'Appended missing entry: %s\n' "$pattern"
        fi
      fi
    done

    if [[ "$VERBOSE" == true ]]; then
      printf 'Done. Added %d entr%s.\n' "$added" "$([[ $added -eq 1 ]] && echo "y" || echo "ies")"
    fi
  }

  # append_new_backups is a function that get the output of get_actual_files and
  # if the file name is new append the full name of the backup under it's
  # get_backup_name primary section. It's sorted in reverse so the most recent
  # file should be at the top.
  append_new_backups() {
    if [[ "$VERBOSE" == true ]]; then
      printf 'Starting append_new_backups'
    fi

    # Make sure section headers exist for every BACKUP_NAME we currently have on disk
    get_backup_name || {
      printf 'ERROR: get_backup_name failed\n' >&2
      return 1
    }

    # Populate ACTUAL_FILES (reverse-sorted, newest first)
    get_actual_files || {
      printf 'ERROR: get_actual_files failed\n' >&2
      return 1
    }

    local re='^backup-(.+)-[0-9]{4}(-[0-9]{2}){5}\.tar\.gz$'
    local f base name tmp added=0 skipped=0

    [[ "$VERBOSE" == true ]] && printf 'Starting append_new_backups\n'

    for f in "${ACTUAL_FILES[@]}"; do
      base="${f##*/}"

      # Only consider files that match the expected naming scheme
      if [[ ! $base =~ $re ]]; then
        [[ "$VERBOSE" == true ]] && printf 'warn: skipping non-matching file: %s\n' "$base" >&2
        continue
      fi
      name="${BASH_REMATCH[1]}"

      # If the exact filename is already present anywhere, skip
      if grep -qxF -- "$base" "$AGE_CONF"; then
        ((skipped++)) || true
        [[ "$VERBOSE" == true ]] && printf 'Already present, skip: %s\n' "$base"
        continue
      fi

      # Insert the filename right after its section line "-$name:"
      # Do the change via a temp file to avoid partial writes
      tmp="$(mktemp "${TMPDIR:-/tmp}/ageconf.XXXXXXXX")" || {
        printf 'ERROR: mktemp failed\n' >&2
        return 1
      }
      awk -v section="-"$name":" -v newline="$base" '
      {
        print $0
        if ($0 == section) {
          print newline
        }
      }
    ' "$AGE_CONF" >"$tmp" && mv -- "$tmp" "$AGE_CONF"
      rc=$?
      [[ -f $tmp ]] && rm -f -- "$tmp"
      if ((rc != 0)); then
        printf 'ERROR: failed to insert "%s" under section "%s"\n' "$base" "$name" >&2
        return 1
      fi

      ((added++)) || true
      [[ "$VERBOSE" == true ]] && printf 'Inserted: %s under -%s:\n' "$base" "$name"
    done

    [[ "$VERBOSE" == true ]] && printf 'append_new_backups done. Added %d, skipped %d.\n' "$added" "$skipped"
    return 0
  }
  append_new_backups

  # make_age() is a function that input the age of the backup directly inside the
  # AGE_CONF file, it will be used later to delete the backup based on there age
  # and based on the BACKUP_NUMBER choosen by the user
  make_age() {
    [[ -z ${AGE_CONF:-} ]] && {
      printf 'ERROR: AGE_CONF is not set.\n' >&2
      return 1
    }
    [[ ! -f $AGE_CONF ]] && {
      printf 'ERROR: AGE_CONF does not exist: %s\n' "$AGE_CONF" >&2
      return 1
    }
    [[ ! -w $AGE_CONF ]] && {
      printf 'ERROR: AGE_CONF is not writable: %s\n' "$AGE_CONF" >&2
      return 1
    }

    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/ageconf.rewrite.XXXXXXXX")" || {
      printf 'ERROR: mktemp failed\n' >&2
      return 1
    }

    # Regex in bash= Patterns used to match text using the [[ string=~ regex ]] operator
    # (and tools like grep/sed/awk). Bash use POSIX ERE (Extended Regual Expressions) for =~
    #
    # Collation in bash= how characteres are ordered and compared according to your current
    # locale (LC_COLLATE/LC_ALL). It affect things like sort order, [[a<b]],
    # filename ranges like [a-z], and sometime what a "range" matches.
    local re_backup='^backup-.+-[0-9]{4}(-[0-9]{2}){5}\.tar\.gz$'

    local in_section=0 idx=-1 line key
    declare -A seen # seen["filename"]=1 inside a section

    # Ensure predictable collation/regex behavior
    LC_ALL=C

    # Read age.conf and write the normalized version into $tmp
    # Do this for each children of "-<NAME>:"
    while IFS= read -r line; do
      # Section header like: -HashRelay:
      if [[ $line =~ ^-.*:$ ]]; then
        printf '%s\n' "$line" >>"$tmp"
        in_section=1
        idx=0
        # reset the per-section de-dup map
        # de-dup = deduplication
        # So this for loop delete the duplicate lines
        for k in "${!seen[@]}"; do unset 'seen[$k]'; done
        continue
      fi

      if ((in_section)); then
        # Normalize to pure filename: strip " -> AGE=..."
        key="${line%% -> AGE=*}"

        if [[ $key =~ $re_backup ]]; then
          # De-dup within the section
          if [[ -z ${seen[$key]+x} ]]; then
            printf '%s -> AGE=%d\n' "$key" "$idx" >>"$tmp"
            seen[$key]=1
            ((idx++)) || true # Add to age
          fi
          # Regardless, do not print the original line again
          # to avoid duplicate
          continue
        fi

        # Non-backup lines inside a section (comments/blank)
        # keep the commented line like they are
        printf '%s\n' "$line" >>"$tmp"
        continue
      fi

      # Outside any section (top comments, etc.)
      printf '%s\n' "$line" >>"$tmp"
    done <"$AGE_CONF"

    # Atomically replace
    mv -- "$tmp" "$AGE_CONF" || {
      printf 'ERROR: could not replace %s\n' "$AGE_CONF" >&2
      return 1
    }
    [[ "$VERBOSE" == true ]] && printf 'make_age: ages rewritten in-place based on current order in %s\n' "$AGE_CONF"
  }
  make_age

  # Purge backups whose name is no longer present in BACKUP_CONF.
  # Requires existing helpers:
  #   format_file_name  -> exports BACKUP_NAMES[]
  #   get_actual_files  -> exports ACTUAL_FILES[]
  #   make_age          -> rebuilds AGE indices in AGE_CONF
  # Remove backups for any <name> that is NOT present in BACKUP_CONF.
  remove_unwanted_backups() {
    # Verification steps
    [[ -z ${BACKUP_DIR:-} ]] && {
      printf 'ERROR: BACKUP_DIR not set\n' >&2
      return 1
    }
    [[ -z ${AGE_CONF:-} ]] && {
      printf 'ERROR: AGE_CONF not set\n' >&2
      return 1
    }
    [[ -z ${BACKUP_CONF:-} ]] && {
      printf 'ERROR: BACKUP_CONF not set\n' >&2
      return 1
    }
    [[ ! -d $BACKUP_DIR ]] && {
      printf 'ERROR: BACKUP_DIR not a directory: %s\n' "$BACKUP_DIR" >&2
      return 1
    }
    [[ ! -f $AGE_CONF ]] && {
      printf 'ERROR: AGE_CONF not found: %s\n' "$AGE_CONF" >&2
      return 1
    }
    [[ ! -f $BACKUP_CONF ]] && {
      printf 'ERROR: BACKUP_CONF not found: %s\n' "$BACKUP_CONF" >&2
      return 1
    }
    case "$BACKUP_DIR" in "" | "/")
      printf 'ERROR: BACKUP_DIR unsafe: %q\n' "$BACKUP_DIR" >&2
      return 1
      ;;
    esac

    [[ "$VERBOSE" == true ]] && printf 'remove_unwanted_backups: start (authoritative from BACKUP_CONF)\n'

    # 1) Build ALLOWED from BACKUP_CONF (authoritative)
    #    - ignore comments/blank/whitespace
    #    - take token before '=' as name
    #    - strip spaces and CRLF
    #    CRLF= "carriage return + line feed" => example "\r\n"
    declare -A ALLOWED=()
    local line key
    while IFS= read -r line; do
      # strip CR
      line="${line//$'\r'/}"
      # trim leading/trailing spaces
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      # skip comments/blank
      [[ -z $line || ${line:0:1} == "#" ]] && continue
      # keep only lines containing '='
      [[ $line != *"="* ]] && continue
      key="${line%%=*}"
      # trim again
      key="${key#"${key%%[![:space:]]*}"}"
      key="${key%"${key##*[![:space:]]}"}"
      [[ -n $key ]] && ALLOWED["$key"]=1
    done <"$BACKUP_CONF"

    if [[ "$VERBOSE" == true ]]; then
      printf 'ALLOWED (from BACKUP_CONF):'
      for key in "${!ALLOWED[@]}"; do printf ' %s' "$key"; done
      printf '\n'
    fi

    # 2) Find all names that exist on disk (from filenames) and in AGE_CONF headers
    #    We’ll delete any name that is NOT in ALLOWED.
    local re='^backup-(.+)-[0-9]{4}(-[0-9]{2}){5}\.tar\.gz$'
    local -A NAME_SEEN_ON_DISK=()
    local f base nm
    # We still use your get_actual_files() only to list files; it does not affect ALLOWED.
    get_actual_files || {
      printf 'ERROR: get_actual_files failed\n' >&2
      return 1
    }
    for f in "${ACTUAL_FILES[@]}"; do
      base="${f##*/}"
      if [[ $base =~ $re ]]; then
        nm="${BASH_REMATCH[1]}"
        NAME_SEEN_ON_DISK["$nm"]=1
      fi
    done

    # 3) Parse AGE_CONF and drop sections whose header -<name>: is NOT allowed.
    #    While dropping, collect the filenames in those sections for deletion.
    local tmp_new tmp_del
    tmp_new="$(mktemp)" || return 1
    tmp_del="$(mktemp)" || {
      rm -f "$tmp_new"
      return 1
    }

    local in_section=0 keep_section=0 secname fn
    exec 3<"$AGE_CONF"
    while IFS= read -r line <&3; do
      line="${line//$'\r'/}"
      if [[ $line =~ ^-.*:\ *$ ]]; then
        in_section=1
        secname="${line#-}"
        secname="${secname%:}"
        secname="${secname%%[[:space:]]*}"
        if [[ -n ${ALLOWED[$secname]:-} ]]; then
          keep_section=1
          printf '%s\n' "$line" >>"$tmp_new"
        else
          keep_section=0
          # do not print header for removed section
        fi
        continue
      fi

      if ((in_section)); then
        if ((keep_section)); then
          printf '%s\n' "$line" >>"$tmp_new"
        else
          # section removed: collect filename portion before " -> AGE="
          fn="${line%% -> AGE=*}"
          [[ -n $fn ]] && printf '%s\n' "$fn" >>"$tmp_del"
        fi
        continue
      fi

      # outside any section: copy as-is (comments, headers above first section)
      printf '%s\n' "$line" >>"$tmp_new"
    done
    exec 3<&-

    # Replace AGE_CONF atomically with pruned version
    if ! mv -- "$tmp_new" "$AGE_CONF"; then
      rm -f -- "$tmp_new" "$tmp_del"
      printf 'ERROR: cannot replace %s\n' "$AGE_CONF" >&2
      return 1
    fi

    # 4) Build deletion set:
    #    a) Filenames listed in removed sections (tmp_del)
    #    b) Any on-disk files whose name is NOT ALLOWED (orphans), even if not in AGE_CONF
    declare -A TO_DELETE=()
    while IFS= read -r fn; do
      [[ -n $fn ]] && TO_DELETE["$fn"]=1
    done < <(sed '/^[[:space:]]*$/d' "$tmp_del")
    rm -f -- "$tmp_del"

    for f in "${ACTUAL_FILES[@]}"; do
      base="${f##*/}"
      if [[ $base =~ $re ]]; then
        nm="${BASH_REMATCH[1]}"
        if [[ -z ${ALLOWED[$nm]:-} ]]; then
          TO_DELETE["$base"]=1
        fi
      fi
    done

    # 5) Delete files from BACKUP_DIR
    local deleted=0 failed=0 path
    for fn in "${!TO_DELETE[@]}"; do
      path="$BACKUP_DIR/$fn"
      if [[ -f $path ]]; then
        if rm -f -- "$path"; then
          ((deleted++)) || true
          [[ "$VERBOSE" == true ]] && printf 'deleted: %s\n' "$path"
        else
          ((failed++)) || true
          printf 'WARN: failed to delete: %s\n' "$path" >&2
        fi
      else
        [[ "$VERBOSE" == true ]] && printf 'WARN: missing or not a regular file: %s\n' "$path"
      fi
    done

    # 6) Rebuild ages for remaining entries
    make_age || printf 'WARN: make_age failed; ages may be stale.\n' >&2

    [[ "$VERBOSE" == true ]] && {
      printf 'remove_unwanted_backups: removed_on_disk=%d, missing_or_failed=%d\n' "$deleted" "$failed"
    }
    return 0
  }
  remove_unwanted_backups

  delete_old() {
    # Verification part
    [[ -z ${AGE_CONF:-} ]] && {
      printf 'ERROR: AGE_CONF is not set.\n' >&2
      return 1
    }
    [[ ! -f $AGE_CONF ]] && {
      printf 'ERROR: AGE_CONF does not exist: %s\n' "$AGE_CONF" >&2
      return 1
    }
    [[ -z ${BACKUP_DIR:-} ]] && {
      printf 'ERROR: BACKUP_DIR is not set.\n' >&2
      return 1
    }
    [[ ! -d $BACKUP_DIR ]] && {
      printf 'ERROR: BACKUP_DIR is not a directory: %s\n' "$BACKUP_DIR" >&2
      return 1
    }

    # BACKUP_NUMBER: how many to keep per section
    local keep="${BACKUP_NUMBER:-3}"
    case "$keep" in '' | *[!0-9]*)
      printf 'ERROR: BACKUP_NUMBER must be integer\n' >&2
      return 1
      ;;
    esac
    [[ "$VERBOSE" == true ]] && printf 'delete_old: keeping %d newest per section\n' "$keep"

    local tmp_conf tmp_list
    tmp_conf="$(mktemp "${TMPDIR:-/tmp}/ageconf.new.XXXXXXXX")" || {
      printf 'ERROR: mktemp failed\n' >&2
      return 1
    }
    tmp_list="$(mktemp "${TMPDIR:-/tmp}/ageconf.todel.XXXXXXXX")" || { # todel = to delete
      rm -f -- "$tmp_conf"
      printf 'ERROR: mktemp failed\n' >&2
      return 1
    }

    # One pass:
    # - Copy headers and keep the first <keep> filenames per section into tmp_conf (without AGE fields)
    # - Collect every filename with index >= keep into tmp_list
    gawk -v keep="$keep" -v out_keep="$tmp_conf" -v out_del="$tmp_list" '
    BEGIN {
      refile = /^backup-(.+)-[0-9]{4}(-[0-9]{2}){5}\.tar\.gz$/
      in_section = 0
      idx = -1
    }
    function start_section() { in_section=1; idx=-1 }
    function end_section()   { in_section=0; idx=-1 }

    {
      line = $0
      # Section header
      if (line ~ /^-.*:$/) {
        print line >> out_keep
        start_section()
        next
      }
      if (in_section) {
        # Normalize line to pure filename
        fn = line
        sub(/ -> AGE=.*/, "", fn)
        if (fn ~ refile) {
          idx++
          if (idx < keep) {
            print fn >> out_keep
          } else {
            print fn >> out_del
          }
          next
        }
      }
      # Outside section or non-matching lines: preserve as-is
      print line >> out_keep
    }
  ' "$AGE_CONF" || {
      rm -f -- "$tmp_conf" "$tmp_list"
      printf 'ERROR: parse/prune failed\n' >&2
      return 1
    }

    # Atomically replace the config with the pruned version first
    mv -- "$tmp_conf" "$AGE_CONF" || {
      rm -f -- "$tmp_list"
      printf 'ERROR: could not replace %s\n' "$AGE_CONF" >&2
      return 1
    }

    # Delete the pruned files on disk (best effort)
    local deleted=0 failed=0 fname path
    while IFS= read -r fname; do
      # skip empties
      [[ -z "${fname//[[:space:]]/}" ]] && continue
      path="$BACKUP_DIR/$fname"
      if [[ -f $path ]]; then
        if rm -f -- "$path"; then
          ((deleted++)) || true
          [[ "$VERBOSE" == true ]] && printf 'deleted: %s\n' "$path"
        else
          ((failed++)) || true
          printf 'WARN: failed to delete: %s\n' "$path" >&2
        fi
      else
        ((failed++)) || true # last added !
        [[ "$VERBOSE" == true ]] && printf 'WARN: not a regular file, skipping: %s\n' "$path"
      fi
    done <"$tmp_list"
    rm -f -- "$tmp_list"

    # Recompute contiguous AGE indices
    make_age || printf 'WARN: make_age failed; ages may be stale.\n' >&2
    [[ "$VERBOSE" == true ]] && printf 'delete_old: pruned lines now; removed_on_disk=%d, missing_or_failed=%d\n' "$deleted" "$failed"
    return 0
  }
  delete_old

done
# Finish the log
echo "=== END Delete Run ==="

exec sudo bash "$NEXT_SCRIPT"
