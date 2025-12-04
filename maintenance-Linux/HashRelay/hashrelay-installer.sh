#!/usr/bin/env bash
#
# Author: Decarnelle Samuel
#
# The purpose of this script is to move all the necessary scripts in there
# correct folders, and make the necessary scripts executables.
# So if the user choose the client agent, it will only make the necessary
# scripts executables and delete the unnecessary scripts and vice versa.
#

# Ensure we are root
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

CLIENT_AGENT=false # This variable will be changed when the user choose his version to insall.
SERVER_AGENT=false # This variable will be changed when the user choose his version to install.

VERBOSE=false # If true, print extra diagnostic logs
DRY_RUN=false # If true, only print commands; do not execute
LOCATION_PATH=""

# usage(): prints help text:
usage() {
  cat <<'USAGE'
hashrelay-installer.sh
Options:
  --verbose            Extra logging
  --dry-run            Show commands without executing
  -h|--help            This help
Environement:
  This script must be lunched before all of the others scripts direclty
  inside the git clone folder.
  It will then move all the necessary script himslef to the directory and then delete
  the old/unnecessary scripts to /usr/local/bin/HashRelay/ path.
Behavior:
  Make all the scripts executables and lunch the necessary downloads then finally
  lunch the main configuration script.
USAGE
}

# Parse CLI arguments in a loo until all are consumed
while [[ $# -gt 0 ]]; do
  case "$1" in
  --verbose)
    VERBOSE=true # enable verbose logs
    shift
    ;;
  --dry-run)
    DRY_RUN=true # enable dry-run move
    shift
    ;;
  -h | --help)
    usage # call the function usage to print the help and exit
    exit 0
    ;;
  *)
    echo "[!] Unknown arg: $1"
    usage
    exit 1 # unknown option -> exit with error
    ;;
  esac
done

# Creation of the necessary path to store the different scripts
if [[ "$VERBOSE" == true ]]; then
  echo "Creation of all the necessary directory"
fi
sudo mkdir -p /usr/local/bin/HashRelay
if [[ "$VERBOSE" == true ]]; then
  echo "directory /usr/local/bin/HashRelay correctly created"
fi

agent_selector() {
  while true; do
    echo "Choose the agent you want to install on this machine:"
    echo "  1) Client (Default)"
    echo "  2) Server"

    read -rp "Selection [1/2]: " mode || {
      echo "No input (EOF). Aborting." >&2
      exit 1
    }
    mode=${mode:-1} # Default 1 if empty

    case "$mode" in
    1)
      echo "You choose to install the hashrelay-client agent."
      echo "Starting the installation/configuration !"
      CLIENT_AGENT=true
      SERVER_AGENT=false
      sudo useradd -m -s /bin/bash HashRelay
      sudo passwd -l HashRelay
      break
      ;;
    2)
      echo "You choose to install the hashrelay-server agent."
      echo "Starting the installation/configuration !"
      CLIENT_AGENT=false
      SERVER_AGENT=true
      sudo useradd -m -s /bin/bash HashRelay
      sudo passwd -l HashRelay
      break
      ;;
    *)
      echo "Invalid selection: '$mode'. Please enter 1 or 2." >&2
      ;;
    esac
  done
}

agent_selector

# Echo the absolute, symlink-resolved path of this installer.
installer_path() {
  # ${BASH_SOURCE[0]} = path of this script file (reliable even if sourced)
  # readlink -f         = resolve symlinks and make absolute (GNU coreutils; present on Arch)
  local path
  path=$(readlink -f -- "${BASH_SOURCE[0]}") || {
    echo "ERROR: cannot resolve installer path." >&2
    return 1
  }
  printf '%s\n' "$path"
}

# Echo just the directory that contains the installer (what you need).
installer_dir() {
  local path
  path=$(installer_path) || return 1
  LOCATION_PATH="${path%/*}" # Remove the shortest match from the end
}

installer_dir
if [[ "$VERBOSE" == true ]]; then
  echo "All the scripts are actually located at $LOCATION_PATH and will be moved"
  echo "To /usr/local/bin/HashRelay/"
fi

# Moving the specifics scripts to the created directory /usr/local/bin/HashRelay
if [[ "$CLIENT_AGENT" == true ]]; then
  if [[ "$VERBOSE" == true ]]; then
    echo "CLIENT_AGENT=true"
    echo "Starting to move the client necessary scripts to the HashRelay directory"
  fi
  # Moving the client necessary scripts to the HashRelay directory
  if [[ "$DRY_RUN" == false ]]; then
    sudo mv "$LOCATION_PATH/Dependencies/backups-manager" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/contact-ip" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/contact-port" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/delete-manager" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/distro-and-pkgman-detect" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/hash-printer" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/hashrelay-client" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/pkg-auto-install" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/prob-viewer" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/sender" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/ssh-configuration-manager" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/scp" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/key-fetcher" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/ufw-configuration-manager" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/timer-manager" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/agent-detector" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/uninstaller" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/hashrelay/hashrelay" "/usr/local/bin"
    sudo chmod +x /usr/local/bin/hashrelay
    printf 'CLIENT_AGENT=true\n' | sudo tee -a "/usr/local/bin/HashRelay/agent.conf" >/dev/null
    printf 'SERVER_AGENT=false\n' | sudo tee -a "/usr/local/bin/HashRelay/agent.conf" >/dev/null
    printf '# Contain all the backup files paths\n' | sudo tee -a "/usr/local/bin/HashRelay/backups-manager/backups.conf" >/dev/null
    printf '# Contain all the hash for each backups file\n' | sudo tee -a "/usr/local/bin/HashRelay/hash-printer/hash.conf" >/dev/null
    sudo rm -rf "$LOCATION_PATH/Dependencies"
    sudo mkdir -p /home/HashRelay/backups
    sudo chown HashRelay:root /home/HashRelay/backups
  fi
elif [[ "$SERVER_AGENT" == true ]]; then
  if [[ "$VERBOSE" == true ]]; then
    echo "SERVER_AGENT=true"
    echo "Starting to move the server necessary scripts to the HashRelay directory"
  fi
  if [[ "$DRY_RUN" == false ]]; then
    sudo mv "$LOCATION_PATH/Dependencies/backups-manager" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/contact-ip" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/delete-manager" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/distro-and-pkgman-detect" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/hash-printer" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/hashrelay-server" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/pkg-auto-install" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/prob-viewer" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/receiver" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/ssh-configuration-manager" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/ufw-configuration-manager" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/timer-manager" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/agent-detector" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/key-sender" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/uninstaller" "/usr/local/bin/HashRelay"
    sudo mv "$LOCATION_PATH/Dependencies/hashrelay/hashrelay" "/usr/local/bin"
    sudo chmod +x /usr/local/bin/hashrelay
    printf 'CLIENT_AGENT=false\n' | sudo tee -a "/usr/local/bin/HashRelay/agent.conf" >/dev/null
    printf 'SERVER_AGENT=true\n' | sudo tee -a "/usr/local/bin/HashRelay/agent.conf" >/dev/null
    printf '# Contain all the backup files paths\n' | sudo tee -a "/usr/local/bin/HashRelay/backups-manager/backups.conf" >/dev/null
    printf '# Contain all the hash for each backups file\n' | sudo tee -a "/usr/local/bin/HashRelay/hash-printer/hash.conf" >/dev/null
    sudo rm -rf "$LOCATION_PATH/Dependencies"
    sudo mkdir -p /home/HashRelay/backups
    sudo chown HashRelay:root /home/HashRelay/backups
  fi
else
  echo "Cannot find the agent configuration (This should not happen)."
  exit 1
fi

# Recursively make every *.sh file under /usr/local/bin/HashRelay executable.
# - Works safely with spaces/newlines in filenames (NUL-delimited pipeline).
# - Honors global flags: VERBOSE (extra logs) and DRY_RUN (show, don’t do).
chmod_script_recursive() {
  # Directory containing your scripts
  local dir="/usr/local/bin/HashRelay"

  # Ensure target directory exists before proceeding
  if [[ ! -d "$dir" ]]; then
    echo "Directory not found: $dir" >&2
    return 1
  fi

  # When DRY_RUN is enabled, only print what would be executed.
  if [[ "$DRY_RUN" == true ]]; then
    # find:
    #   -P     : do not follow symlinks (safer in installers)
    #   -type f: only regular files
    #   -name '*.sh': files ending with .sh
    #   -print0: separate results with NUL (safe for any filename)
    # xargs:
    #   -0     : read NUL-separated input
    #   -r     : do nothing if no input (avoid running chmod with no args)
    #   -I{}   : replace token {} in the following printf command
    find -P "$dir" -type f -name '*.sh' -print0 |
      xargs -0 -r -I{} printf 'DRY-RUN: chmod +x -- %q\n' "{}"

    # Optional: also print a summary count in dry-run mode
    if [[ "$VERBOSE" == true ]]; then
      local count
      count=$(find -P "$dir" -type f -name '*.sh' -print0 | tr -cd '\0' | wc -c)
      echo "DRY-RUN summary: ${count} script(s) would be made executable under $dir"
    fi
    return 0
  fi

  # Real run: apply +x to all matching files, safely.
  # We use a two-step pipeline for both correctness and speed.
  # Note: chmod +x preserves existing r/w permissions and just adds execute bits.
  find -P "$dir" -type f -name '*.sh' -print0 |
    xargs -0 -r chmod +x

  # Optional verbose summary after changes
  if [[ "$VERBOSE" == true ]]; then
    local changed
    changed=$(find -P "$dir" -type f -name '*.sh' -perm -u=x -print0 | tr -cd '\0' | wc -c)
    echo "Made executable: ${changed} script(s) under $dir"
  fi
}

chmod_script_recursive

# Lunching the next step of the installation, the script to install all
# of the necessary program for our HashRelay service to work.
sudo bash /usr/local/bin/HashRelay/pkg-auto-install/pkg-auto-install.sh
