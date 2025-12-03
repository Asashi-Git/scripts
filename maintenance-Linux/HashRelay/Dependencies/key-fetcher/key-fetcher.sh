#!/usr/bin/env bash
# SSH KEY FETCHER
#
# Author: VANCAPPEL Marc

# TODO: Change the chmod 600 to the key
# sudo chown -R HashRelay:HashRelay /home/HashRelay/.ssh
# sudo chmod 700 /home/HashRelay/.ssh
# sudo chmod 600 /home/HashRelay/.ssh/known_hosts
# sudo -u HashRelay ssh -i /home/HashRelay/.ssh/id_HashRelay HashRelay@192.168.150.22

set -euo pipefail

CONFIG="/usr/local/bin/HashRelay/agent.conf"
NEXT="/usr/local/bin/HashRelay/hashrelay-client/hashrelay-client.sh"
PORT="36150"
KEY_NAME="id_HashRelay"
IS_UP=false

get_existing() {
  [[ -f "$CONFIG" ]] || {
    echo ""
    return
  }

  ADDRESS=""
  local line
  # Find lines like: SERVER_IP = 1.2.3.4
  line="$(grep -E '^[[:space:]]*SERVER_IP[[:space:]]*=' "$CONFIG" | tail -n1 || true)"
  [[ -z "$line" ]] && {
    echo ""
    return
  }

  # Extract the right-hand side of '='
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
  ADDRESS=$line
}

confirm() {
  gum confirm "$1"
}

check_curl_connection() {
  local url=$1:$2
  local curl_cmd="curl -w httpcode=%{http_code}"
  # -m, --max-time <seconds> FOR curl operation
  local curl_max_connection_timeout="-m 100"

  # perform curl operation
  local curl_return_code=0
  CURL_OUTPUT=$(${curl_cmd} ${curl_max_connection_timeout} ${url} 2>/dev/null) || curl_return_code=$?
  if [ ${curl_return_code} -ne 0 ]; then
    echo "Curl connection failed with return code - ${curl_return_code}"
  else
    echo "Curl connection success"
    # Check http code for curl operation/response in CURL_OUTPUT
    HTTP_CODE=$(echo "${CURL_OUTPUT}" | grep -Eo '[0-9]{3}$')
    if [ ${HTTP_CODE} -ne 200 ]; then
      echo "Curl operation/command failed due to server return code - ${HTTP_CODE}"
    fi
  fi
}

check_connection() {
  STATE=false
  if [ ${IS_UP} = false ]; then
    echo "server is down"
  elif [ ! "${CURL_RESULT}" = "Curl connection success" ]; then
    echo "web server is down"
  else
    echo "both server and web server are up"
    STATE=true
  fi
}

key_verify() {
  if [ ! -f "/home/HashRelay/.ssh/id_HashRelay" ]; then
    key_get
  else
    if confirm "The key already exists. Do you want to replace it?"; then
      key_get
    fi
  fi
}

key_get() {
  if [ $STATE = true ]; then
    if [ ! -d /home/HashRelay/.ssh ]; then
      mkdir -p /home/HashRelay/.ssh
    fi
    wget -O /home/HashRelay/.ssh/id_HashRelay $ADDRESS:$PORT/$KEY_NAME
  fi
}

main() {
  get_existing >/dev/null 2>&1
  CURL_RESULT=$(check_curl_connection $ADDRESS $PORT)
  # Server Status
  bash /usr/local/bin/HashRelay/prob-viewer/prob-viewer.sh >/dev/null 2>&1

  if [[ $? -eq 0 ]]; then
    IS_UP=true
  else
    IS_UP=false
  fi
  check_connection
  key_verify
  exec sudo bash "$NEXT"
}

main "$@"
