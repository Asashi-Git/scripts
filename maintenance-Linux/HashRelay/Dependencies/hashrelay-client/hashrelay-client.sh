#!/bin/bash
# The purpose of this script is to make the initial configuration of the client agent
# and the user can lunch it to change the configuration after the installation
# or to get information about the actual configuration and the state of the server-agent.
#
# Author: Decarnelle Samuel
#
# This script need gum for the graphical interface to work "sudo pacman -S gum"

# Ensure the script is luched as sudo
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "this script must be run as root (use sudo)." >&2
  exit 1
fi

VERBOSE=false # If true, print extra diagnostic logs
DRY_RUN=false # If true, only print commands; do not execute
CLI=false     # If true, no graphical interface will be displayed

# usage(): print help text:
usage() {
  cat <<'USAGE'
  hashrelay-client.sh
  Options:
    --verbose           Extra logging
    --dry-run           Show commands without executing
    --cli               Run the script without graphical interface
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
    VERBOSE=true # Extra logging
    shift
    ;;
  --dry-run)
    DRY_RUN=true # Extra show commands without executing
    shift
    ;;
  --cli)
    CLI=true # Run the script without graphical interface
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

# This function read the configuration file to ensure that the client agent
# is the agent that the user want to install.
loading_agent_config() {
  local path="${CONFIG_FILE:-}"

  # 1) Require CONFIG_PATH and the file
  if [[ -z "$path" ]]; then
    echo "CONFIG_PATH is not set"
    return 1
  fi
  if [[ ! -f "$path" ]]; then
    echo "Configuration file do not exist, contact your administrator"
    return 1
  fi

  # 2) Parse safely (no sourcing)
  local line key val v
  local client=""
  local server=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    # strip comments and whitespace
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}" # ltrim
    line="${line%"${line##*[![:space:]]}"}" # rtrim
    [[ -z "$line" ]] && continue

    # match KEY = VALUE
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"

      # remove surrounding quotes if present
      if [[ "$val" =~ ^\'(.*)\'$ ]]; then
        val="${BASH_REMATCH[1]}"
      elif [[ "$val" =~ ^\"(.*)\"$ ]]; then
        val="${BASH_REMATCH[1]}"
      fi

      v="${val,,}" # to lowercase
      case "$key" in
      CLIENT_AGENT)
        if [[ "$v" =~ ^(true|yes|on|1)$ ]]; then client=true; else client=false; fi
        ;;
      SERVER_AGENT)
        if [[ "$v" =~ ^(true|yes|on|1)$ ]]; then server=true; else server=false; fi
        ;;
      esac
    fi
  done <"$path"

  # defaults if keys absent
  [[ -z "$client" ]] && client=false
  [[ -z "$server" ]] && server=false

  # 3) Output exactly as requested
  if [[ "$client" == true ]]; then
    if [[ "$CLI" == false ]]; then
      echo "You Have choosen to install the client agent with the graphical configurator"
      echo "We will now configure it."
      gum spin --title "Configuring the Client graphical interface" -- sleep 5
    fi
    if [[ "$CLI" == true ]]; then
      echo "You have choosen to install the client agent with CLI, we will now configure it."
      sleep 5
      echo "Strating the client configuration:"
    fi
  fi

  if [[ "$server" == true ]]; then
    if [[ "$CLI" == false ]]; then
      echo "You have choosen to install the server agent with the graphical configurator"
      echo "We will now configure it:"
      gum spin --title "Configuring the Server graphical interface" -- sleep 5
    fi
    if [[ "$CLI" == true ]]; then
      echo "You have choosen to install the server agent with CLI, we will now configure it."
      sleep 5
      echo "Strating the server configuration:"
    fi
  fi

  # 4) Sanity check (optional but useful)
  if [[ "$client" == "$server" ]]; then
    echo "Warning: invalid configuration in $path (exactly one should be true)."
    return 2
  fi

  return 0
}

loading_agent_config
