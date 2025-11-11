#!/bin/bash
# The purpose of this script is to make the initial configuration of the client agent
# and the user can lunch it to change the configuration after the installation
# or to get information about the actual configuration and the state of the server-agent.
#
# Author: Decarnelle Samuel
#
#

# Ensure the script is luched as sudo
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "this script must be run as root (use sudo)." >&2
  exit 1
fi

VERBOSE=false # If true, print extra diagnostic logs
DRY_RUN=false # If true, only print commands; do not execute

# usage(): print help text:
usage() {
  cat <<'USAGE'
  hashrelay-client.sh
  Options:
    --verbose           Extra logging
    --dry-run           Show commands without executing
    -h|--help           This help
  Environement:
    This scirpt is your main scritp to interact with the configuration of your installed agent
  Behavior:
    Put every configuration inside the already created configuration file so the agent can read
    it and configure itself via this configuration file.
USAGE
}

# Parse CLI arguments in a loop until all are consumed
while [[ $# -gt 0 ]]; do
  case "$1" in
  --verbose)
    VERBOSE=true
    shift
    ;;
  --dry-run)
    DRY_RUN=true
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

CONFIG_FILE="/usr/local/bin/HashRelay/agent.conf"

# Make sure the configuration file have the client-conf flag in it
if [[ "$CONFIG_FILE" ]]; then
  echo "The configuration file exist !"
else
  echo "Configuration file not found, you must lunch the installer-script first !"
fi
