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
      break
      ;;
    2)
      echo "You choose to install the hashrelay-server agent."
      echo "Starting the installation/configuration !"
      CLIENT_AGENT=false
      SERVER_AGENT=true
      break
      ;;
    *)
      echo "Invalid selection: '$mode'. Please enter 1 or 2." >&2
      ;;
    esac
  done
}

agent_selector

# Moving the specifics scripts to the created directory /usr/local/bin/HashRelay
if [[ "$CLIENT_AGENT" == true ]]; then
  if [[ "$VERBOSE" == true ]]; then
    echo "CLIENT_AGENT=true"
    echo "Starting to move the client necessary scripts to the HashRelay directory"
  fi
  # Moving the client necessary scripts to the HashRelay directory
elif [[ "$SERVER_AGENT" == true ]]; then
  if [[ "$VERBOSE" == true ]]; then
    echo "SERVER_AGENT=true"
    echo "Starting to move the server necessary scripts to the HashRelay directory"
    # Moving the server necessary scripts to the HashRelay directory
  fi
else
  echo "Cannot find the agent configuration (This should not happen)."
  exit 1
fi

# This fonction make the scripts inside the /usr/local/bin/HashRelay executables
chmod_scripts() {
  # Make the scripts inside the directory executables
  while true; do
    echo "Making the necessary scripts executables"
  done
}
