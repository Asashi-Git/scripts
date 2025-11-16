#!/usr/bin/env bash
# This script is the agent that listen for the input of a user to lunch the dependencies
# scripts that make the agent work.
#
# Author: Decarnelle Samuel

# === HASHRELAY AGENT ===
# A simple dispatcher CLI agent

# Ensure we are root
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

# usage(): print help text:
usage() {
  cat <<'USAGE'
  HASHRELAY
  Options:
    --config                  Change the configuration in your local machine
    -h|--help                 This help
  Environement:
    This agent work is used to make backups in your local machine and send them 
    automatically onto your configured server.
  Behavior:
    You must call the agent with flag to interact with him.
USAGE
}

# Parse CLI arguments in a loop until all are consumed
while [[ $# -gt 0 ]]; do
  case "$1" in
  --config)
    exec sudo bash /usr/local/bin/HashRelay/hashrelay-client/hashrelay-client.sh # Lunch the config script
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
