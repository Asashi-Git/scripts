#!/usr/bin/env bash
#
# configure-ip — a friendly IPv4 configurator on top of NetworkManager (nmcli)
#
# Usage: configure-nmcli.sh [command] [args]
#
#   (no command)      interactive menu
#   list              list connections and their IPv4 setup
#   show [NAME]       show the IPv4 details of a connection
#   dhcp [NAME]       switch a connection to DHCP (automatic IP)
#   static [NAME]     give a connection a static IP
#   dns [NAME]        set custom DNS servers (or go back to automatic DNS)
#   apply [NAME]      re-activate a connection (reconnect / renew DHCP lease)
#   test              check gateway, Internet and DNS
#   help              show this help
#
# NAME is a connection name or UUID; a picker is shown when it is omitted.
# Environment: NO_COLOR=1 disables colours.
#
# Each change is saved in one step and rolled back automatically if the
# connection fails to come back up. If fzf is installed it is used for pickers.

set -uo pipefail

SPIN_TMP=''
SPIN_OUT=''
SEL=-1
PICK=-1

# ───────────────────────────── presentation ─────────────────────────────

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  B=$'\e[1m' DIM=$'\e[2m' R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' C=$'\e[36m' N=$'\e[0m'
else
  B='' DIM='' R='' G='' Y='' C='' N=''
fi

ok()   { printf '%s✓%s %s\n' "$G" "$N" "$*"; }
info() { printf '%s›%s %s\n' "$C" "$N" "$*"; }
warn() { printf '%s!%s %s\n' "$Y" "$N" "$*" >&2; }
err()  { printf '%s✗%s %s\n' "$R" "$N" "$*" >&2; }
die()  { err "$*"; exit 1; }

cleanup() {
  [[ -t 1 ]] && tput cnorm 2>/dev/null
  [[ -n $SPIN_TMP ]] && rm -f "$SPIN_TMP"
}
trap cleanup EXIT
trap 'printf "\n"; exit 130' INT TERM

usage() { sed -n '3,21s/^# \{0,1\}//p' "$0"; }

# Truncate a string to N characters, adding an ellipsis.
trunc() { local s=$1 n=$2; (( ${#s} > n )) && s="${s:0:n-1}…"; printf '%s' "$s"; }

# Last line of a command's output (nmcli puts its "Error: …" there).
last_line() { local s=${1%$'\n'}; printf '%s' "${s##*$'\n'}"; }

kv() { printf '  %-12s %s\n' "$1" "$2"; }

# confirm "question" [default y|n]
confirm() {
  local q=$1 def=${2:-n} hint ans
  [[ $def == y ]] && hint='[Y/n]' || hint='[y/N]'
  read -rp "$q $hint " ans || { echo; return 1; }
  ans=${ans:-$def}
  [[ ${ans,,} == y* ]]
}

# ask VAR "prompt" [default] — read one trimmed line into VAR; fails on EOF.
ask() {
  local __var=$1 __prompt=$2 __def=${3:-} __ans
  [[ -n $__def ]] && __prompt+=" ${DIM}[$__def]${N}"
  read -rp "$__prompt: " __ans || { echo; return 1; }
  __ans=${__ans:-$__def}
  __ans=${__ans#"${__ans%%[![:space:]]*}"}
  __ans=${__ans%"${__ans##*[![:space:]]}"}
  printf -v "$__var" '%s' "$__ans"
}

# spin "message" cmd [args...] — run cmd with a spinner; its output ends up in $SPIN_OUT.
spin() {
  local msg=$1 rc pid i=0
  shift
  SPIN_TMP=$(mktemp) || return 1
  if [[ -t 1 ]]; then
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    "$@" >"$SPIN_TMP" 2>&1 &
    pid=$!
    tput civis 2>/dev/null
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r%s%s%s %s' "$C" "${frames[i++ % ${#frames[@]}]}" "$N" "$msg"
      sleep 0.1
    done
    wait "$pid"; rc=$?
    printf '\r\e[K'
    tput cnorm 2>/dev/null
  else
    "$@" >"$SPIN_TMP" 2>&1; rc=$?
  fi
  SPIN_OUT=$(<"$SPIN_TMP")
  rm -f "$SPIN_TMP"; SPIN_TMP=''
  return "$rc"
}

# pick "prompt" item... — let the user choose an item; sets PICK to its index.
pick() {
  local prompt=$1 choice i
  shift
  local n=$#
  (( n > 0 )) || return 1

  if command -v fzf >/dev/null && [[ -t 0 && -t 1 ]]; then
    choice=$(for (( i = 1; i <= n; i++ )); do printf '%3d  %s\n' "$i" "${!i}"; done |
      fzf --ansi --reverse --height='~60%' --prompt="$prompt › ") || return 1
    choice=${choice#"${choice%%[! ]*}"}
    PICK=$(( ${choice%% *} - 1 ))
    return 0
  fi

  for (( i = 1; i <= n; i++ )); do printf '  %s%2d%s  %s\n' "$B" "$i" "$N" "${!i}"; done
  echo
  while :; do
    read -rp "$prompt [1-$n, q to cancel]: " choice || { echo; return 1; }
    [[ $choice == [qQ] || -z $choice ]] && return 1
    if [[ $choice =~ ^[0-9]+$ ]] && (( 10#$choice >= 1 && 10#$choice <= n )); then
      PICK=$(( 10#$choice - 1 ))
      return 0
    fi
    warn "Please enter a number between 1 and $n."
  done
}

# ───────────────────────────── IPv4 helpers ─────────────────────────────

valid_ip() {
  local o
  [[ $1 =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  for o in "${BASH_REMATCH[@]:1}"; do (( 10#$o <= 255 )) || return 1; done
}

ip2int() {
  local a b c d
  IFS=. read -r a b c d <<<"$1"
  echo $(( (10#$a << 24) | (10#$b << 16) | (10#$c << 8) | 10#$d ))
}

int2ip() {
  local n=$1
  printf '%d.%d.%d.%d' $(( n >> 24 & 255 )) $(( n >> 16 & 255 )) $(( n >> 8 & 255 )) $(( n & 255 ))
}

# Normalise an address: "192.168.001.010" → "192.168.1.10".
norm_ip() { int2ip "$(ip2int "$1")"; }

mask_int() { local p=$1; echo $(( p == 0 ? 0 : (0xFFFFFFFF << (32 - p)) & 0xFFFFFFFF )); }

prefix_to_mask() { int2ip "$(mask_int "$1")"; }

# "24", "/24" or "255.255.255.0" → prefix length; fails on anything else.
to_prefix() {
  local m=${1#/} n p=0
  if [[ $m =~ ^[0-9]{1,2}$ ]]; then
    (( 10#$m >= 1 && 10#$m <= 32 )) || return 1
    echo $(( 10#$m ))
    return 0
  fi
  valid_ip "$m" || return 1
  n=$(ip2int "$m")
  while (( n & 0x80000000 )); do p=$(( p + 1 )); n=$(( (n << 1) & 0xFFFFFFFF )); done
  (( n == 0 && p >= 1 )) || return 1   # bits must be contiguous
  echo "$p"
}

# same_subnet IP1 IP2 PREFIX
same_subnet() {
  local m
  m=$(mask_int "$3")
  (( ($(ip2int "$1") & m) == ($(ip2int "$2") & m) ))
}

# ask_ip VAR "prompt" [default] [optional yes|no] — "-" clears an optional field, q cancels.
ask_ip() {
  local __v=$1 __p=$2 __def=${3:-} __opt=${4:-no} __a
  [[ $__opt == yes ]] && __p+=" ${DIM}(- for none)${N}"
  while :; do
    ask __a "$__p" "$__def" || return 1
    [[ $__a == [qQ] ]] && return 1
    if [[ -z $__a || $__a == - ]]; then
      if [[ $__opt == yes ]]; then printf -v "$__v" '%s' ''; return 0; fi
      warn "This field is required (q to cancel)."
      continue
    fi
    if valid_ip "$__a"; then
      printf -v "$__v" '%s' "$(norm_ip "$__a")"
      return 0
    fi
    warn "'$__a' is not a valid IPv4 address (example: 192.168.1.10)."
  done
}

# ask_dns VAR [default] — up to 3 servers, space or comma separated; "-" means none.
# VAR receives a comma-separated list (what nmcli expects).
ask_dns() {
  local __v=$1 __def=${2:-} __a __s __bad __list __words
  while :; do
    ask __a "DNS servers ${DIM}(space separated, - for none)${N}" "$__def" || return 1
    [[ $__a == [qQ] ]] && return 1
    if [[ -z $__a || $__a == - ]]; then printf -v "$__v" '%s' ''; return 0; fi
    __list=() __bad=''
    read -ra __words <<<"${__a//,/ }"
    for __s in "${__words[@]}"; do
      if valid_ip "$__s"; then __list+=("$(norm_ip "$__s")"); else __bad=$__s; break; fi
    done
    if [[ -n $__bad ]]; then
      warn "'$__bad' is not a valid IPv4 address."
    elif (( ${#__list[@]} > 3 )); then
      warn "Please give at most 3 DNS servers."
    else
      local IFS=,
      printf -v "$__v" '%s' "${__list[*]}"
      return 0
    fi
  done
}

# ───────────────────────────── nmcli helpers ────────────────────────────

preflight() {
  command -v nmcli >/dev/null || die "nmcli not found — install networkmanager."
  [[ $(nmcli -t -f RUNNING general 2>/dev/null) == running ]] ||
    die "NetworkManager is not running (try: sudo systemctl start NetworkManager)."
}

type_label() {
  case $1 in
    802-3-ethernet)  echo Ethernet ;;
    802-11-wireless) echo Wi-Fi ;;
    wireguard)       echo WireGuard ;;
    vpn)             echo VPN ;;
    bridge)          echo Bridge ;;
    bond)            echo Bond ;;
    vlan)            echo VLAN ;;
    gsm|cdma)        echo Mobile ;;
    *)               echo "$1" ;;
  esac
}

method_label() {
  case $1 in
    auto)       echo DHCP ;;
    manual)     echo Static ;;
    disabled)   echo Off ;;
    link-local) echo Link-local ;;
    shared)     echo Shared ;;
    '')         echo - ;;
    *)          echo "$1" ;;
  esac
}

# Fill CONN_* arrays from NetworkManager's profiles (active ones come first).
# Everything is keyed by UUID, so names with spaces, colons or duplicates are safe.
load_conns() {
  CONN_UUID=() CONN_TYPE=() CONN_DEV=() CONN_NAME=() CONN_METHOD=()
  local out line uuid type dev name
  out=$(nmcli -t -e no -f UUID,TYPE,DEVICE,NAME connection show 2>&1) ||
    { err "Could not list connections: $(last_line "$out")"; return 1; }
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    # NAME is the last field, so everything after the 3rd colon belongs to it.
    uuid=${line%%:*}; line=${line#*:}
    type=${line%%:*}; line=${line#*:}
    dev=${line%%:*};  name=${line#*:}
    [[ $type == loopback ]] && continue
    CONN_UUID+=("$uuid") CONN_TYPE+=("$type") CONN_DEV+=("$dev") CONN_NAME+=("$name")
    CONN_METHOD+=("$(nmcli -e no -g ipv4.method connection show uuid "$uuid" 2>/dev/null)")
  done <<<"$out"
}

# Read the saved IPv4 settings of a profile into CFG_*.
read_cfg() {
  local out
  out=$(nmcli -e no -g ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv4.ignore-auto-dns \
    connection show uuid "$1" 2>&1) || { err "Could not read the connection: $(last_line "$out")"; return 1; }
  { IFS= read -r CFG_METHOD; IFS= read -r CFG_ADDR; IFS= read -r CFG_GW
    IFS= read -r CFG_DNS;    IFS= read -r CFG_IGNORE; } <<<"$out"
}

# Read what is really live on a device into LIVE_* (addresses / DNS are comma-joined).
read_live() {
  LIVE_ADDR='' LIVE_GW='' LIVE_DNS=''
  [[ -n ${1:-} ]] || return 0
  local out
  out=$(nmcli -e no -g IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show "$1" 2>/dev/null) || return 0
  { IFS= read -r LIVE_ADDR; IFS= read -r LIVE_GW; IFS= read -r LIVE_DNS; } <<<"$out"
  LIVE_ADDR=${LIVE_ADDR// | /,} LIVE_DNS=${LIVE_DNS// | /,}
}

# Current device of a profile (empty when inactive) — re-read, never cached.
conn_device() { nmcli -e no -g GENERAL.DEVICES connection show uuid "$1" 2>/dev/null; }

# One formatted line for connection #i.
conn_row() {
  local i=$1 mark=' ' name dev m mc ip
  [[ -n ${CONN_DEV[i]} ]] && mark="${G}●${N}"
  printf -v name '%-26s' "$(trunc "${CONN_NAME[i]}" 26)"
  printf -v dev '%-10s' "$(trunc "${CONN_DEV[i]:--}" 10)"
  m=$(method_label "${CONN_METHOD[i]}")
  case $m in DHCP) mc=$C ;; Static) mc=$Y ;; *) mc=$DIM ;; esac
  if [[ -n ${CONN_DEV[i]} ]]; then
    ip=$(nmcli -e no -g IP4.ADDRESS device show "${CONN_DEV[i]}" 2>/dev/null); ip=${ip%% |*}
  else
    ip=$(nmcli -e no -g ipv4.addresses connection show uuid "${CONN_UUID[i]}" 2>/dev/null); ip=${ip%%,*}
    [[ -n $ip ]] && ip="$ip ${DIM}(saved)${N}"
  fi
  printf '%s %s %-9s %s %s%-7s%s %s' "$mark" "$name" "$(type_label "${CONN_TYPE[i]}")" "$dev" \
    "$mc" "$m" "$N" "${ip:-${DIM}-${N}}"
}

list_header() {
  printf '%s  %-26s %-9s %-10s %-7s %s%s\n' "$DIM" "NAME" "TYPE" "DEVICE" "IPV4" "ADDRESS" "$N"
}

# select_conn [NAME|UUID] [prompt] — sets SEL. Returns 2 when the user cancels.
select_conn() {
  local want=${1:-} prompt=${2:-Connection} i rows=() matches=()
  load_conns || return 1
  (( ${#CONN_UUID[@]} > 0 )) || { warn "No network connections found."; return 1; }

  if [[ -n $want ]]; then
    for i in "${!CONN_UUID[@]}"; do
      [[ ${CONN_UUID[i]} == "$want" || ${CONN_NAME[i]} == "$want" ]] && matches+=("$i")
    done
    case ${#matches[@]} in
      0) err "No connection named '$want' (see: $(basename "$0") list)."; return 1 ;;
      1) SEL=${matches[0]}; return 0 ;;
    esac
    warn "Several connections are named '$want' — pick one:"
  else
    matches=("${!CONN_UUID[@]}")
  fi

  for i in "${matches[@]}"; do rows+=("$(conn_row "$i")"); done
  list_header
  pick "$prompt" "${rows[@]}" || { info "Cancelled."; return 2; }
  SEL=${matches[PICK]}
}

# Interface + gateway carrying the default route right now.
default_route() {
  ROUTE_DEV='' ROUTE_GW=''
  local line
  line=$(ip -4 route show default 2>/dev/null | head -n1)
  [[ $line =~ via\ ([0-9.]+) ]] && ROUTE_GW=${BASH_REMATCH[1]}
  [[ $line =~ dev\ ([^ ]+) ]] && ROUTE_DEV=${BASH_REMATCH[1]}
}

# One-line summary of the current state, used as the menu header.
status_line() {
  default_route
  if [[ -z $ROUTE_DEV ]]; then
    printf '%snot connected%s' "$Y" "$N"
    return
  fi
  local conn ip method uuid
  conn=$(nmcli -e no -g GENERAL.CONNECTION device show "$ROUTE_DEV" 2>/dev/null)
  ip=$(nmcli -e no -g IP4.ADDRESS device show "$ROUTE_DEV" 2>/dev/null); ip=${ip%% |*}
  uuid=$(nmcli -e no -g GENERAL.CON-UUID device show "$ROUTE_DEV" 2>/dev/null)
  [[ -n $uuid ]] && method=$(method_label "$(nmcli -e no -g ipv4.method connection show uuid "$uuid" 2>/dev/null)")
  printf '%s · %s%s%s · %s%s' "$ROUTE_DEV" "$G$B" "${conn:-?}" "$N" "${ip:-no IP}" "${method:+ · $method}"
}

# ─────────────────────────── applying changes ───────────────────────────

# activate IDX — (re)activate a profile; nmcli waits until it has an IP or gives up.
activate() {
  local i=$1
  if spin "Activating ${CONN_NAME[i]}…" nmcli --wait 45 connection up uuid "${CONN_UUID[i]}"; then
    ok "${CONN_NAME[i]} is up."
    return 0
  fi
  err "Activation failed: $(last_line "$SPIN_OUT")"
  return 1
}

# apply_change IDX nmcli-settings... — save in one step, re-activate, roll back on failure.
apply_change() {
  local i=$1 rc=0
  shift
  local uuid=${CONN_UUID[i]} name=${CONN_NAME[i]} was_active=no
  [[ -n $(conn_device "$uuid") ]] && was_active=yes

  read_cfg "$uuid" || return 1
  OLD_SETTINGS=(ipv4.method "$CFG_METHOD" ipv4.addresses "$CFG_ADDR" ipv4.gateway "$CFG_GW"
                ipv4.dns "$CFG_DNS" ipv4.ignore-auto-dns "${CFG_IGNORE:-no}")

  # Don't let Ctrl-C leave the connection half-configured.
  trap '' INT

  if ! spin "Saving settings…" nmcli connection modify uuid "$uuid" "$@"; then
    err "NetworkManager rejected the settings: $(last_line "$SPIN_OUT")"
    [[ $SPIN_OUT == *[Nn]ot\ authorized* || $SPIN_OUT == *[Pp]ermission* ]] && info "Try again with sudo."
    trap 'printf "\n"; exit 130' INT
    return 1
  fi
  ok "Settings saved."

  if [[ $was_active == no ]] && ! confirm "'$name' is not active. Activate it now?" y; then
    info "The new settings will be used next time '$name' connects."
  elif ! activate "$i"; then
    rollback "$i" "$was_active"
    rc=1
  fi

  trap 'printf "\n"; exit 130' INT
  return "$rc"
}

# rollback IDX WAS_ACTIVE — restore OLD_SETTINGS and reconnect if it was up before.
rollback() {
  local i=$1 was_active=$2
  warn "Restoring the previous settings…"
  if ! nmcli connection modify uuid "${CONN_UUID[i]}" "${OLD_SETTINGS[@]}" >/dev/null 2>&1; then
    err "Could not restore the previous settings — fix them with: nmtui"
    return 1
  fi
  ok "Previous settings restored."
  if [[ $was_active == yes ]]; then
    if spin "Reconnecting…" nmcli --wait 45 connection up uuid "${CONN_UUID[i]}"; then
      ok "Reconnected with the previous settings."
    else
      err "Could not reconnect: $(last_line "$SPIN_OUT")"
    fi
  fi
}

# After a successful change: test, and offer to undo if the network is broken.
verify_change() {
  local i=$1
  [[ -n $(conn_device "${CONN_UUID[i]}") ]] || return 0
  echo
  if ! cmd_test "$(conn_device "${CONN_UUID[i]}")"; then
    echo
    if confirm "Connectivity looks broken. Undo the change?" n; then
      rollback "$i" yes
    fi
  fi
}

summary() {
  echo
  printf '%sAbout to apply:%s\n' "$B" "$N"
  while (( $# >= 2 )); do kv "$1" "$2"; shift 2; done
  echo
}

# ─────────────────────────────── commands ───────────────────────────────

cmd_list() {
  load_conns || return 1
  (( ${#CONN_UUID[@]} > 0 )) || { info "No network connections."; return 0; }
  local i
  list_header
  for i in "${!CONN_UUID[@]}"; do conn_row "$i"; echo; done
}

cmd_show() {
  select_conn "${1:-}" "Show which connection" || return $(( $? == 2 ? 0 : 1 ))
  local i=$SEL dev dns_cfg
  read_cfg "${CONN_UUID[i]}" || return 1
  dev=$(conn_device "${CONN_UUID[i]}")

  echo
  printf '%s%s%s  %s%s · %s%s\n\n' "$B" "${CONN_NAME[i]}" "$N" "$DIM" \
    "$(type_label "${CONN_TYPE[i]}")" "${CONN_UUID[i]}" "$N"

  if [[ -n $dev ]]; then kv "State" "${G}active${N} on $dev"; else kv "State" "${DIM}inactive${N}"; fi
  kv "Method" "$(method_label "$CFG_METHOD")"
  if [[ $CFG_METHOD == manual ]]; then
    kv "Address" "${CFG_ADDR//,/, }"
    kv "Gateway" "${CFG_GW:-${DIM}none${N}}"
  fi
  if [[ -n $CFG_DNS ]]; then
    dns_cfg=${CFG_DNS//,/, }
    [[ $CFG_METHOD == auto && $CFG_IGNORE == yes ]] && dns_cfg+=" ${DIM}(DHCP DNS ignored)${N}"
    [[ $CFG_METHOD == auto && $CFG_IGNORE != yes ]] && dns_cfg+=" ${DIM}(+ DHCP DNS)${N}"
  else
    [[ $CFG_METHOD == auto ]] && dns_cfg="${DIM}from DHCP${N}" || dns_cfg="${DIM}none${N}"
  fi
  kv "DNS" "$dns_cfg"

  if [[ -n $dev ]]; then
    read_live "$dev"
    echo
    printf '  %sLive on %s%s\n' "$DIM" "$dev" "$N"
    kv "Address" "${LIVE_ADDR:-${DIM}none${N}}"
    kv "Gateway" "${LIVE_GW:-${DIM}none${N}}"
    if [[ -n $LIVE_DNS ]]; then kv "DNS" "${LIVE_DNS//,/, }"; else kv "DNS" "${DIM}none${N}"; fi
    local mac
    mac=$(nmcli -e no -g GENERAL.HWADDR device show "$dev" 2>/dev/null)
    [[ -n $mac ]] && kv "MAC" "$mac"
  fi
}

cmd_dhcp() {
  select_conn "${1:-}" "Use DHCP on" || return $(( $? == 2 ? 0 : 1 ))
  local i=$SEL dns='' ignore=no
  read_cfg "${CONN_UUID[i]}" || return 1

  if [[ $CFG_METHOD == auto ]]; then
    info "'${CONN_NAME[i]}' already uses DHCP."
    if confirm "Just reconnect it to renew the lease?" y; then
      activate "$i"
      return
    fi
  fi

  if confirm "Use your own DNS servers instead of the DHCP ones?" n; then
    ask_dns dns "$CFG_DNS" || { info "Cancelled."; return 0; }
    [[ -n $dns ]] && ignore=yes
  fi

  summary "Connection" "${CONN_NAME[i]}" "Method" "DHCP (automatic)" \
          "DNS" "$( [[ -n $dns ]] && echo "${dns//,/, }" || echo "from DHCP" )"
  confirm "Apply these settings?" y || { info "Cancelled."; return 0; }

  apply_change "$i" ipv4.method auto ipv4.addresses '' ipv4.gateway '' \
    ipv4.dns "$dns" ipv4.ignore-auto-dns "$ignore" || return 1
  verify_change "$i"
}

cmd_static() {
  select_conn "${1:-}" "Static IP for" || return $(( $? == 2 ? 0 : 1 ))
  local i=$SEL dev cur_ip='' cur_pfx='' cur_gw='' cur_dns='' a ip pfx gw dns host net bcast mask

  read_cfg "${CONN_UUID[i]}" || return 1
  dev=$(conn_device "${CONN_UUID[i]}")
  read_live "$dev"

  # Suggest what the connection uses today (live values first, then saved ones).
  a=${LIVE_ADDR%%,*}; [[ -z $a ]] && a=${CFG_ADDR%%,*}
  [[ $a == */* ]] && cur_ip=${a%/*} cur_pfx=${a#*/}
  cur_gw=${LIVE_GW:-$CFG_GW}
  cur_dns=${CFG_DNS:-$LIVE_DNS}

  info "Enter keeps the value in [brackets], q cancels."
  echo

  # Address — "192.168.1.10/24" is accepted too.
  while :; do
    ask a "IP address" "$cur_ip" || { info "Cancelled."; return 0; }
    [[ $a == [qQ] || -z $a ]] && { info "Cancelled."; return 0; }
    pfx=''
    if [[ $a == */* ]]; then
      pfx=$(to_prefix "${a#*/}") || { warn "'${a#*/}' is not a valid mask."; continue; }
      a=${a%/*}
    fi
    valid_ip "$a" || { warn "'$a' is not a valid IPv4 address (example: 192.168.1.10)."; continue; }
    ip=$(norm_ip "$a")
    break
  done

  # Mask — CIDR (24) or dotted (255.255.255.0).
  while [[ -z $pfx ]]; do
    ask a "Subnet mask ${DIM}(24 or 255.255.255.0)${N}" "${cur_pfx:-24}" || { info "Cancelled."; return 0; }
    [[ $a == [qQ] ]] && { info "Cancelled."; return 0; }
    pfx=$(to_prefix "$a") || { warn "'$a' is not a valid mask — use 1-32 or a dotted mask."; pfx=''; }
  done

  mask=$(mask_int "$pfx")
  host=$(ip2int "$ip")
  net=$(( host & mask ))
  bcast=$(( net | (~mask & 0xFFFFFFFF) ))
  if (( pfx <= 30 )) && (( host == net || host == bcast )); then
    warn "$ip is the $( (( host == net )) && echo network || echo broadcast ) address of $(int2ip "$net")/$pfx."
    confirm "Use it anyway?" n || { info "Cancelled."; return 0; }
  fi

  # Gateway — default to the current one if it fits the subnet, else the first host.
  [[ -n $cur_gw ]] && valid_ip "$cur_gw" && same_subnet "$cur_gw" "$ip" "$pfx" || cur_gw=$(int2ip $(( net + 1 )))
  while :; do
    ask_ip gw "Gateway" "$cur_gw" yes || { info "Cancelled."; return 0; }
    [[ -z $gw ]] && { warn "No gateway: only the local network will be reachable."; break; }
    [[ $gw == "$ip" ]] && { warn "The gateway cannot be your own address."; continue; }
    same_subnet "$gw" "$ip" "$pfx" && break
    warn "$gw is outside $(int2ip "$net")/$pfx — it will not be reachable."
    confirm "Use it anyway?" n && break
  done

  [[ -z $cur_dns && -n $gw ]] && cur_dns=$gw
  ask_dns dns "$cur_dns" || { info "Cancelled."; return 0; }
  [[ -z $dns ]] && warn "No DNS servers: names (like archlinux.org) will not resolve."

  summary "Connection" "${CONN_NAME[i]}" "Method" "Static" \
          "Address" "$ip/$pfx ${DIM}($(prefix_to_mask "$pfx"))${N}" \
          "Gateway" "${gw:-none}" "DNS" "$( [[ -n $dns ]] && echo "${dns//,/, }" || echo none )"
  confirm "Apply these settings?" y || { info "Cancelled."; return 0; }

  # Everything in ONE modify call: setting method=manual alone (with no address) is rejected.
  apply_change "$i" ipv4.method manual ipv4.addresses "$ip/$pfx" ipv4.gateway "$gw" \
    ipv4.dns "$dns" ipv4.ignore-auto-dns no || return 1
  verify_change "$i"
}

cmd_dns() {
  select_conn "${1:-}" "Set DNS for" || return $(( $? == 2 ? 0 : 1 ))
  local i=$SEL dns ignore=no label
  read_cfg "${CONN_UUID[i]}" || return 1
  [[ $CFG_METHOD == auto ]] && info "Leave empty (-) to go back to the DNS servers from DHCP."
  ask_dns dns "$CFG_DNS" || { info "Cancelled."; return 0; }
  [[ -n $dns && $CFG_METHOD == auto ]] && ignore=yes

  if [[ -n $dns ]]; then label=${dns//,/, }
  elif [[ $CFG_METHOD == auto ]]; then label="from DHCP"
  else label=none; warn "No DNS servers: names will not resolve."
  fi
  summary "Connection" "${CONN_NAME[i]}" "DNS" "$label"
  confirm "Apply?" y || { info "Cancelled."; return 0; }

  apply_change "$i" ipv4.dns "$dns" ipv4.ignore-auto-dns "$ignore" || return 1
  verify_change "$i"
}

cmd_apply() {
  select_conn "${1:-}" "Re-activate which connection" || return $(( $? == 2 ? 0 : 1 ))
  activate "$SEL"
}

# cmd_test [DEV] — gateway, Internet and DNS checks. Fails if any check fails.
cmd_test() {
  local dev=${1:-} gw='' fails=0 state
  if [[ -n $dev ]]; then
    gw=$(ip -4 route show default dev "$dev" 2>/dev/null | awk '/via/ { print $3; exit }')
  else
    default_route
    dev=$ROUTE_DEV gw=$ROUTE_GW
  fi
  [[ -n $dev ]] || { err "No default route — this machine is not connected."; return 1; }
  printf '%sConnectivity via %s%s\n' "$B" "$dev" "$N"

  # Gateway: many routers ignore ping, so silence is only a warning.
  if [[ -z $gw ]]; then
    warn "No gateway on $dev."
  elif command -v ping >/dev/null; then
    if spin "Pinging gateway $gw…" ping -c 2 -W 2 -I "$dev" "$gw"; then ok "Gateway $gw answers."
    else warn "Gateway $gw does not answer ping (it may just ignore ping)."; fi
  fi

  # Internet: ICMP first, then a plain TCP connection for networks that block ping.
  if spin "Reaching the Internet…" bash -c '
      ping -c 1 -W 3 1.1.1.1 || ping -c 1 -W 3 8.8.8.8 ||
      timeout 4 bash -c "</dev/tcp/1.1.1.1/443" || timeout 4 bash -c "</dev/tcp/8.8.8.8/53"'; then
    ok "Internet reachable."
  else
    err "Internet not reachable."; fails=$(( fails + 1 ))
  fi

  if spin "Resolving archlinux.org…" timeout 8 getent ahostsv4 archlinux.org; then
    ok "DNS works."
  else
    err "DNS does not resolve names."; fails=$(( fails + 1 ))
  fi

  state=$(nmcli networking connectivity check 2>/dev/null)
  case $state in
    full)    ok "NetworkManager reports full connectivity." ;;
    portal)  warn "Captive portal detected — open a browser to log in." ;;
    limited) warn "NetworkManager reports limited connectivity." ;;
    none)    err "NetworkManager reports no connectivity." ;;
  esac

  (( fails == 0 ))
}

# ───────────────────────────── interactive menu ─────────────────────────

pause() { echo; read -rsp "${DIM}Press Enter to continue…${N}" _ || exit 0; echo; }

menu() {
  local choice
  while :; do
    [[ -t 1 ]] && clear
    printf '%s╭─ IP Configuration ──────────────────────────╮%s\n' "$C" "$N"
    printf '  %s\n' "$(status_line)"
    printf '%s╰─────────────────────────────────────────────╯%s\n' "$C" "$N"
    printf '\n'
    printf '  %s1%s  List connections\n'          "$B" "$N"
    printf '  %s2%s  Connection details\n'        "$B" "$N"
    printf '  %s3%s  Use DHCP (automatic IP)\n'   "$B" "$N"
    printf '  %s4%s  Set a static IP\n'           "$B" "$N"
    printf '  %s5%s  Set DNS servers\n'           "$B" "$N"
    printf '  %s6%s  Reconnect / renew lease\n'   "$B" "$N"
    printf '  %s7%s  Test connectivity\n'         "$B" "$N"
    printf '  %sq%s  Quit\n\n'                    "$B" "$N"

    read -rp "Choose: " choice || { echo; exit 0; }
    echo
    case $choice in
      1) cmd_list ;;
      2) cmd_show ;;
      3) cmd_dhcp ;;
      4) cmd_static ;;
      5) cmd_dns ;;
      6) cmd_apply ;;
      7) cmd_test ;;
      q|Q) exit 0 ;;
      '') continue ;;
      *) warn "Unknown option: $choice" ;;
    esac
    pause
  done
}

# ─────────────────────────────────── main ───────────────────────────────

main() {
  case ${1:-} in
    -h|--help|help) usage; return 0 ;;
  esac
  preflight
  case ${1:-} in
    '')      menu ;;
    list)    cmd_list ;;
    show)    cmd_show "${2:-}" ;;
    dhcp)    cmd_dhcp "${2:-}" ;;
    static)  cmd_static "${2:-}" ;;
    dns)     cmd_dns "${2:-}" ;;
    apply)   cmd_apply "${2:-}" ;;
    test)    cmd_test ;;
    *)       err "Unknown command: $1"; usage >&2; return 1 ;;
  esac
}

main "$@"
