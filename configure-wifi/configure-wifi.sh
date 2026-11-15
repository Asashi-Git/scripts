#!/usr/bin/env bash
#
# configure-wifi — a friendly Wi-Fi manager on top of NetworkManager (nmcli)
#
# Usage: configure-wifi.sh [command] [args]
#
#   (no command)      interactive menu
#   scan              list nearby networks
#   connect [SSID]    connect to a network (picker if SSID is omitted)
#   saved             list saved networks
#   forget [NAME]     delete a saved network (picker if NAME is omitted)
#   status            show details of the current connection
#   on | off | toggle control the Wi-Fi radio
#   help              show this help
#
# Environment: WIFI_DEV=<iface> forces the Wi-Fi interface, NO_COLOR=1 disables colours.
#
# Passwords are never stored by this script: NetworkManager keeps saved
# networks and their secrets itself. If fzf is installed it is used for pickers.

set -uo pipefail

readonly LEGACY_FILE="$HOME/.wifi_connections"
SPIN_TMP=''
SPIN_OUT=''

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

usage() { sed -n '3,19s/^# \{0,1\}//p' "$0"; }

# Truncate a string to N characters, adding an ellipsis.
trunc() { local s=$1 n=$2; (( ${#s} > n )) && s="${s:0:n-1}…"; printf '%s' "$s"; }

# confirm "question" [default y|n]
confirm() {
  local q=$1 def=${2:-n} hint ans
  [[ $def == y ]] && hint='[Y/n]' || hint='[y/N]'
  read -rp "$q $hint " ans || return 1
  ans=${ans:-$def}
  [[ ${ans,,} == y* ]]
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
    read -rp "$prompt [1-$n, q to cancel]: " choice || return 1
    [[ $choice == [qQ] || -z $choice ]] && return 1
    if [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= n )); then
      PICK=$(( choice - 1 ))
      return 0
    fi
    warn "Please enter a number between 1 and $n."
  done
}

# ───────────────────────────── nmcli helpers ────────────────────────────

preflight() {
  command -v nmcli >/dev/null || die "nmcli not found — install networkmanager."
  [[ $(nmcli -t -f RUNNING general 2>/dev/null) == running ]] ||
    die "NetworkManager is not running (try: sudo systemctl start NetworkManager)."
  DEV=${WIFI_DEV:-$(nmcli -t -e no -f DEVICE,TYPE device | awk -F: '$2 == "wifi" { print $1; exit }')}
  [[ -n $DEV ]] || die "No Wi-Fi device found."
}

radio_on() { [[ $(nmcli radio wifi) == enabled ]]; }

dev_state() { nmcli -e no -g GENERAL.STATE device show "$DEV" 2>/dev/null; }

set_radio() {
  local want=$1 i
  nmcli radio wifi "$want" || { err "Could not turn Wi-Fi $want."; return 1; }
  if [[ $want == on ]]; then
    # Wait for the device to leave the "unavailable" state so scans work right away.
    for (( i = 0; i < 20; i++ )); do
      [[ $(dev_state) != 20* ]] && break
      sleep 0.5
    done
  fi
  if { [[ $want == on ]] && radio_on; } || { [[ $want == off ]] && ! radio_on; }; then
    ok "Wi-Fi is now $want."
  else
    err "Wi-Fi did not switch $want (rfkill? check: rfkill list)."
    return 1
  fi
}

ensure_radio() {
  radio_on && return 0
  warn "Wi-Fi is turned off."
  confirm "Turn it on?" y && set_radio on
}

# Raw scan output, with a fallback when NetworkManager refuses an immediate rescan.
wifi_list_raw() {
  nmcli -t -e no -f IN-USE,SIGNAL,BARS,SECURITY,SSID device wifi list ifname "$DEV" --rescan yes 2>/dev/null ||
    nmcli -t -e no -f IN-USE,SIGNAL,BARS,SECURITY,SSID device wifi list ifname "$DEV" --rescan auto
}

# Fill NET_* arrays: one entry per SSID (strongest access point), sorted by signal.
load_networks() {
  NET_SSID=() NET_SIGNAL=() NET_BARS=() NET_SEC=() NET_INUSE=()
  local -A idx=()
  local line inuse signal bars sec ssid i

  spin "Scanning for networks…" wifi_list_raw || { err "Scan failed: ${SPIN_OUT:-unknown error}"; return 1; }

  while IFS= read -r line; do
    # SSID is the last field, so everything after the 4th colon belongs to it.
    inuse=${line%%:*};  line=${line#*:}
    signal=${line%%:*}; line=${line#*:}
    bars=${line%%:*};   line=${line#*:}
    sec=${line%%:*};    ssid=${line#*:}
    [[ -z $ssid ]] && continue            # hidden networks
    if [[ -n ${idx[$ssid]+x} ]]; then
      [[ $inuse == '*' ]] && NET_INUSE[idx[$ssid]]='*'
      continue
    fi
    i=${#NET_SSID[@]}
    idx[$ssid]=$i
    NET_SSID[i]=$ssid NET_SIGNAL[i]=$signal NET_BARS[i]=$bars NET_SEC[i]=$sec NET_INUSE[i]=$inuse
  done < <(sort -t: -k2,2nr <<<"$SPIN_OUT")

  (( ${#NET_SSID[@]} > 0 )) || { warn "No networks found."; return 1; }
}

# Fill SAVED_* arrays and the SAVED_BY_SSID map from NetworkManager's profiles.
declare -A SAVED_BY_SSID=()
load_saved() {
  SAVED_UUID=() SAVED_NAME=() SAVED_SSID=() SAVED_BY_SSID=()
  local line uuid type name ssid
  while IFS= read -r line; do
    uuid=${line%%:*}; line=${line#*:}
    type=${line%%:*}; name=${line#*:}
    [[ $type == 802-11-wireless ]] || continue
    ssid=$(nmcli -e no -g 802-11-wireless.ssid connection show uuid "$uuid" 2>/dev/null)
    SAVED_UUID+=("$uuid") SAVED_NAME+=("$name") SAVED_SSID+=("$ssid")
    [[ -n $ssid ]] && SAVED_BY_SSID[$ssid]=$uuid
  done < <(nmcli -t -e no -f UUID,TYPE,NAME connection show)
}

active_uuids() { nmcli -t -f UUID connection show --active; }

signal_color() {
  local s=$1
  if   (( s >= 67 )); then printf '%s' "$G"
  elif (( s >= 34 )); then printf '%s' "$Y"
  else printf '%s' "$R"
  fi
}

# One formatted line for network #i.
net_row() {
  local i=$1 mark=' ' sec tag='' name
  [[ ${NET_INUSE[i]} == '*' ]] && mark="${G}●${N}"
  [[ -n ${SAVED_BY_SSID[${NET_SSID[i]}]:-} ]] && tag="${DIM}saved${N}"
  printf -v name '%-28s' "$(trunc "${NET_SSID[i]}" 28)"
  sec=${NET_SEC[i]}
  if [[ -z $sec || $sec == -- ]]; then
    printf -v sec '%s%-16s%s' "$Y" "open" "$N"
  else
    printf -v sec '%-16s' "$(trunc "$sec" 16)"
  fi
  printf '%s %s %s%s %3s%%%s  %s %s' "$mark" "$name" "$(signal_color "${NET_SIGNAL[i]}")" \
    "${NET_BARS[i]}" "${NET_SIGNAL[i]}" "$N" "$sec" "$tag"
}

# One-line summary of the current state, used as the menu header.
status_line() {
  if ! radio_on; then
    printf '%s · %sWi-Fi off%s' "$DEV" "$R" "$N"
    return
  fi
  local conn ip line sig=''
  conn=$(nmcli -e no -g GENERAL.CONNECTION device show "$DEV" 2>/dev/null)
  if [[ -z $conn ]]; then
    printf '%s · %snot connected%s' "$DEV" "$Y" "$N"
    return
  fi
  ip=$(nmcli -g IP4.ADDRESS device show "$DEV" 2>/dev/null); ip=${ip%% |*}
  line=$(nmcli -t -e no -f IN-USE,SIGNAL,BARS device wifi list ifname "$DEV" --rescan no 2>/dev/null | grep -m1 '^\*')
  if [[ -n $line ]]; then
    IFS=: read -r _ s b <<<"$line"
    sig=" $(signal_color "$s")$b $s%$N"
  fi
  printf '%s · %s%s%s%s · %s' "$DEV" "$G$B" "$conn" "$N" "$sig" "${ip:-no IP yet}"
}

# ─────────────────────────────── commands ───────────────────────────────

cmd_scan() {
  ensure_radio || return 1
  load_saved
  load_networks || return 1
  local i
  printf '%s  %-28s %-9s  %-16s%s\n' "$DIM" "SSID" "SIGNAL" "SECURITY" "$N"
  for i in "${!NET_SSID[@]}"; do net_row "$i"; echo; done
}

# Connect to an SSID: reuse a saved profile when there is one, otherwise create one.
connect_ssid() {
  local ssid=$1 hidden=${2:-no} sec=${3:-} uuid
  load_saved
  uuid=${SAVED_BY_SSID[$ssid]:-}

  if [[ -n $uuid ]]; then
    if spin "Connecting to $ssid (saved)…" nmcli connection up uuid "$uuid" ifname "$DEV"; then
      ok "Connected to $ssid."
      return 0
    fi
    err "Could not connect with the saved settings: ${SPIN_OUT##*$'\n'}"
    confirm "Forget the saved settings and try again (new password)?" || return 1
    nmcli connection delete uuid "$uuid" >/dev/null || return 1
  fi

  if [[ $sec == *802.1X* ]]; then
    err "$ssid uses WPA-Enterprise (802.1X), which needs extra settings."
    info "Use 'nmtui' or 'nm-connection-editor' to set it up."
    return 1
  fi

  local before after u
  before=$(nmcli -t -f UUID connection show)
  info "Connecting to $ssid… ${DIM}(nmcli will ask for the password if one is needed)${N}"
  local args=(--ask device wifi connect "$ssid" ifname "$DEV")
  [[ $hidden == yes ]] && args+=(hidden yes)
  if nmcli "${args[@]}"; then
    ok "Connected to $ssid. NetworkManager saved it for next time."
    return 0
  fi

  # Remove any half-created profile so a wrong password doesn't stick around.
  after=$(nmcli -t -f UUID connection show)
  while IFS= read -r u; do
    [[ -n $u ]] && ! grep -qxF "$u" <<<"$before" && nmcli connection delete uuid "$u" >/dev/null 2>&1
  done <<<"$after"
  err "Failed to connect to $ssid."
  return 1
}

cmd_connect() {
  ensure_radio || return 1
  if [[ -n ${1:-} ]]; then
    connect_ssid "$1"
    return
  fi
  load_saved
  load_networks || return 1
  local rows=() i
  for i in "${!NET_SSID[@]}"; do rows+=("$(net_row "$i")"); done
  rows+=("${DIM}  Hidden network (enter SSID manually)…${N}")
  pick "Network" "${rows[@]}" || { info "Cancelled."; return 0; }

  if (( PICK == ${#NET_SSID[@]} )); then
    local ssid
    read -rp "SSID of the hidden network: " ssid || return 1
    [[ -n $ssid ]] || { warn "No SSID given."; return 1; }
    connect_ssid "$ssid" yes
  else
    connect_ssid "${NET_SSID[PICK]}" no "${NET_SEC[PICK]}"
  fi
}

cmd_saved() {
  load_saved
  if (( ${#SAVED_UUID[@]} == 0 )); then
    info "No saved Wi-Fi networks."
    return 0
  fi
  local active i mark extra
  active=$(active_uuids)
  printf '%sSaved Wi-Fi networks:%s\n' "$B" "$N"
  for i in "${!SAVED_UUID[@]}"; do
    mark=' ' extra=''
    grep -qxF "${SAVED_UUID[i]}" <<<"$active" && mark="${G}●${N}"
    [[ -n ${SAVED_SSID[i]} && ${SAVED_SSID[i]} != "${SAVED_NAME[i]}" ]] && extra=" ${DIM}(SSID: ${SAVED_SSID[i]})${N}"
    printf '  %s %s%s\n' "$mark" "${SAVED_NAME[i]}" "$extra"
  done
}

cmd_forget() {
  load_saved
  (( ${#SAVED_UUID[@]} > 0 )) || { info "No saved Wi-Fi networks."; return 0; }
  local i=-1 j
  if [[ -n ${1:-} ]]; then
    for j in "${!SAVED_NAME[@]}"; do
      [[ ${SAVED_NAME[j]} == "$1" || ${SAVED_SSID[j]} == "$1" ]] && { i=$j; break; }
    done
    (( i >= 0 )) || { err "No saved network named '$1'."; return 1; }
  else
    pick "Forget which network" "${SAVED_NAME[@]}" || { info "Cancelled."; return 0; }
    i=$PICK
  fi
  confirm "Forget '${SAVED_NAME[i]}'? Its password will be deleted too." || { info "Cancelled."; return 0; }
  if nmcli connection delete uuid "${SAVED_UUID[i]}" >/dev/null; then
    ok "Forgot '${SAVED_NAME[i]}'."
  else
    err "Could not delete '${SAVED_NAME[i]}'."
    return 1
  fi
}

cmd_status() {
  printf '%s%s%s\n\n' "$B" "$(status_line)" "$N"
  radio_on || return 0
  local line
  line=$(nmcli -t -e no -f IN-USE,CHAN,RATE,SECURITY,SSID device wifi list ifname "$DEV" --rescan no 2>/dev/null | grep -m1 '^\*')
  if [[ -n $line ]]; then
    local chan rate sec ssid
    line=${line#*:}
    chan=${line%%:*}; line=${line#*:}
    rate=${line%%:*}; line=${line#*:}
    sec=${line%%:*};  ssid=${line#*:}
    [[ $sec == -- ]] && sec=''
    printf '  %-12s %s\n' "Network" "$ssid" "Channel" "$chan" "Rate" "$rate" "Security" "${sec:-open}"
    echo
  fi
  nmcli -f GENERAL.STATE,GENERAL.HWADDR,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS device show "$DEV" | sed 's/^/  /'
}

cmd_toggle() {
  if radio_on; then set_radio off; else set_radio on; fi
}

warn_legacy_file() {
  [[ -f $LEGACY_FILE ]] || return 0
  warn "$LEGACY_FILE (from the old version of this script) holds Wi-Fi passwords in plain text."
  warn "It is no longer used — NetworkManager already saves your networks. Remove it with: shred -u $LEGACY_FILE"
}

# ───────────────────────────── interactive menu ─────────────────────────

pause() { echo; read -rsp "${DIM}Press Enter to continue…${N}" _ || exit 0; echo; }

menu() {
  local choice radio_label
  while :; do
    [[ -t 1 ]] && clear
    radio_on && radio_label="Turn Wi-Fi off" || radio_label="Turn Wi-Fi on"
    printf '%s╭─ Wi-Fi Manager ─────────────────────────────╮%s\n' "$C" "$N"
    printf '  %s\n' "$(status_line)"
    printf '%s╰─────────────────────────────────────────────╯%s\n' "$C" "$N"
    printf '\n'
    printf '  %s1%s  Scan networks\n'      "$B" "$N"
    printf '  %s2%s  Connect\n'            "$B" "$N"
    printf '  %s3%s  Saved networks\n'     "$B" "$N"
    printf '  %s4%s  Forget a network\n'   "$B" "$N"
    printf '  %s5%s  Connection details\n' "$B" "$N"
    printf '  %s6%s  %s\n'                 "$B" "$N" "$radio_label"
    printf '  %sq%s  Quit\n\n'             "$B" "$N"

    read -rp "Choose: " choice || { echo; exit 0; }
    echo
    case $choice in
      1) cmd_scan ;;
      2) cmd_connect ;;
      3) cmd_saved ;;
      4) cmd_forget ;;
      5) cmd_status ;;
      6) cmd_toggle ;;
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
    '')       menu ;;
    scan)     cmd_scan ;;
    connect)  cmd_connect "${2:-}" ;;
    saved)    warn_legacy_file; cmd_saved ;;
    forget)   cmd_forget "${2:-}" ;;
    status)   cmd_status ;;
    on|off)   set_radio "$1" ;;
    toggle)   cmd_toggle ;;
    *)        err "Unknown command: $1"; usage >&2; return 1 ;;
  esac
}

main "$@"
