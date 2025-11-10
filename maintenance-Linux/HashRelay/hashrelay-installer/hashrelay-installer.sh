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
sudo mkdir -p /usr/local/bin/HashRelay
