#!/usr/bin/env bash
# This is a simple helper that we can call inside multiples script, for the
# script to see if he is wuning onto a client or a server via the config file
#
# Author: Decarnelle Samuel

CONFIG_FILE="/usr/local/bin/HashRelay/agent.conf"

get_client() {
  [[ -f "$CONFIG_FILE" ]] || {
    echo ""
    return
  }

  local line
  line="$(grep -E '^[[:space:]]*CLIENT_AGENT[[:space:]]*=' "$CONFIG_FILE" | tail -n1 || true)"
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

RESULT=$(get_client)

if [[ "$RESULT" == "true" ]]; then
  echo 'You are onto a client machine'
else
  echo 'You are onto a server machine'
fi
