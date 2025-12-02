#!/bin/bash
# The purpose of this script is to make the initial configuration of the server agent
# and the user can lunch it to change the configuration after the installation
# or to get information about the actual configuration.
#
# Author: Decarnelle Samuel
#
# This script need gum for the graphical interface to work "sudo pacman -S gum"

# Ensure the script is lunched as root
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

CONFIG_FILE="/usr/local/bin/HashRelay/agent.conf"

VERBOSE=false # If true, print extra diagnostic logs
DRY_RUN=false # If true, only print commands; do not execute
CLI=false     # If true, no graphical interface will be displayed
NEXT="/usr/local/bin//HashRelay/ssh-configuration-manager/ssh-configuration-manager.sh"

# usage(): print help text:
usage() {
  cat <<'USAGE'
  hashrelay-server.sh 
  Options:
    --verbose           Extra logging
    --dry-run           Show commands without executing
    --cli               Run the script without graphical interface
    -h|--help           This help
  Environement:
    This script is your main script to interact with the configuration of you installed agent
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
  --cli)
    CLI=true
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

# Make sure the configuration file have the server-conf flag in it
if [[ "$CONFIG_FILE" ]]; then
  echo "The configuration file exist !"
else
  echo "Configuration file not found, you must lunch the installer-script first !"
fi

# This function read the configuration file to ensure that the server agent
# is the agent that the user have installed
server_configurator() {
  if [[ "$CLI" == false ]]; then
    if [[ "$VERBOSE" == true ]]; then
      echo "You have choosen to instal the server agent with the graphical configurator"
      echo "We will now configure it."
    fi
    clear
    gum spin --title "Configuring the Server graphical interface" -- sleep 1

    title="HASHRELAY SERVER CONFIGURATOR"
    gum style --border double --margin "1 2" --padding "1 2" --border-foreground 212 \
      "Welcome to $title"

    # Menu
    choice=$(printf "Configure how many backups of the same file do you want to keep on your machine\nSet your timer between each backups\nSee the config file\nQuit & Reload the configuration" |
      gum choose --cursor.foreground="#ff5fd2" --header "Choose an action")
    [ -z "${choice:-}" ] && exit 0

    case "$choice" in
    "Configure how many backups of the same file do you want to keep on your machine")
      if [[ "$DRY_RUN" == false ]]; then
        sudo bash /usr/local/bin/HashRelay/delete-manager/delete-manager.sh --number
      fi
      if [[ "$VERBOSE" == true ]]; then
        echo "lunching the delete-manager script with --number flag"
      fi
      ;;
    "Set your timer between each backups")
      if [[ "$DRY_RUN" == false ]]; then
        sudo bash /usr/local/bin/HashRelay/timer-manager/timer-manager.sh --timer
      fi
      if [[ "$VERBOSE" == true ]]; then
        echo "lunching the timer-manager script with --timer flag"
      fi
      ;;
    "See the config file")
      if [[ "$VERBOSE" == true ]]; then
        echo "Show the configuration file"
      fi
      if [[ "$DRY_RUN" == false ]]; then
        gum pager </usr/local/bin/HashRelay/agent.conf
        sudo bash /usr/local/bin/HashRelay/hashrelay-server/hashrelay-server.sh
      fi
      ;;
    "Quit & Reload the configuration")
      echo "See you later !"
      exec sudo bash "$NEXT"
      ;;
    esac
  fi

  # For the CLI
  if [[ "$CLI" == true ]]; then
    echo "You have choosen to install the server agent with CLI, we will now configure it."
    sleep 1
    echo "Starting the client configuration:"
  fi
}
