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

CONFIG_FILE="/usr/local/bin/HashRelay/agent.conf"

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

# Make sure the configuration file have the client-conf flag in it
if [[ "$CONFIG_FILE" ]]; then
  echo "The configuration file exist !"
else
  echo "Configuration file not found, you must lunch the installer-script first !"
fi

# This function read the configuration file to ensure that the client agent
# is the agent that the user want to install.
client_configurator() {
  if [[ "$CLI" == false ]]; then
    echo "You Have choosen to install the client agent with the graphical configurator"
    echo "We will now configure it."
    gum spin --title "Configuring the Client graphical interface" -- sleep 1

    title="HASHRELAY CLIENT CONFIGURATOR"
    gum style --border double --margin "1 2" --padding "1 2" --border-foreground 212 \
      "Welcome to $title"

    # Menu
    choice=$(printf "Configure the server IP\nConfigure the server Port\nSee the config file\nQuit" |
      gum choose --cursor.foreground="#ff5fd2" --header "Choose an action")
    [ -z "${choice:-}" ] && exit 0

    case "$choice" in
    "Configure the server IP")
      if [[ "$DRY_RUN" == false ]]; then
        sudo bash /usr/local/bin/HashRelay/contact-ip/contact-ip.sh
      fi
      if [[ "$VERBOSE" == true ]]; then
        echo "lunching the contact-ip script"
      fi
      ;;
    "Configure the server Port")
      if [[ "$DRY_RUN" == false ]]; then
        sudo bash /usr/local/bin/HashRelay/contact-port/contact-port.sh
      fi
      if [[ "$VERBOSE" == true ]]; then
        echo "lunching the contact-port script"
      fi
      ;;
    "See the config file")
      if [[ "$DRY_RUN" == false ]]; then
        gum pager </usr/local/bin/HashRelay/agent.conf
      fi
      if [[ "$VERBOSE" == true ]]; then
        echo "Show the configuration file"
      fi
      ;;
    "Quit")
      echo "See you later !"
      exit 0
      ;;
    esac

  fi
  if [[ "$CLI" == true ]]; then
    echo "You have choosen to install the client agent with CLI, we will now configure it."
    sleep 5
    echo "Strating the client configuration:"
  fi

}
client_configurator
