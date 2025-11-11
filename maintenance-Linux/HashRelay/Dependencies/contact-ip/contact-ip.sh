#!/usr/bin/env bash
# The goal of this script is to ask for the port of
# the server and to store the input of the user into the config file
# that is stored in /usr/local/bin/HashRelay/agent.conf
#
# Author: Decaarnelle Samuel
#

set -euo pipefail

title="Server IP Configurator"

gum style --border double --margin "1 2" --padding "1 2" --border-foreground 212 \
  "Welcome to $title"

# Asking of the user input
host=$(gum input --placeholder "e.g. 192.168.10.100 or 1.1.1.1")
[[ -z "${host:-}" ]] && exit 0
if [[ ! "$host" =~ ^[0-9\.\-:]+$ ]]; then
  gum confirm "Host looks suspicious. Continue?" || sudo bash /usr/local/bin/HashRelay/hashrelay-client/hashrelay-client.sh
fi

gum spin --title "Pinging $host" -- ping -c 4 -- "$host"

SERVER_IP="$host"
printf "SERVER_IP=%s$SERVER_IP\n" | sudo tee -a "/usr/local/HashRelay/agent.conf"
echo "Your server IP is $SERVER_IP"

sudo bash /usr/local/bin/HashRelay/hashrelay-client/hashrelay-client.sh
