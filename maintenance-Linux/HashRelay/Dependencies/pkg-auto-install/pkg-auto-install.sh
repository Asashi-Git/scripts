#!/usr/bin/env bash
# Purpose: Auto-install a package set across Linux distros using your detector.
#
# Author: Decarnelle Samuel
#
# Usage example:
#   sudo bash ./pkg-auto-install.sh --dry-run --verbose --assume-yes --packages ./packages.list
# Environment variables:
#   DETECT_PATH=/usr/local/bin/HashRelay/distro-and-pkgman-detect.sh  # path to the detector script
#
# Security note:
# - This script is intended for controlled lab environments. Always review package sources
#   and commands (use --dry-run first). Logging goes to stderr to ease auditing.
#
# Mini glossary of abbreviations used:
# - PM: Package Manager (e.g., pacman, apt-get, dnf).
# - KV: Key-Value associative array holding detector outputs (e.g., KV["DistroID"]="arch").
# - CSV: Comma-Separated Values string (here, the list of PMs from the detector).
# - CLI: Command-Line Interface (flags and arguments we pass to the script).
# - DRY-RUN: Mode that prints commands without executing them (safe preview).
# - VERBOSE: Mode that prints extra diagnostic lines.
# - ASSUME_YES: Mode that auto-confirms prompts (-y, --noconfirm, etc.).

set -euo pipefail
# -e : exit immediately on any command error
# -u : treat unset variables as errors
# -o pipefail : fail a pipeline if any command fails (not just the last one)

# -------------- Defaults and CLI -----------------
DETECT_PATH="${DETECT_PATH:-/usr/local/bin/HashRelay/distro-and-pkgman-detect/distro-and-pkgman-detect.sh}"
# Default path to our detector; can be overridden by env var DETECT_PATH
CONFIG_PATH="/usr/local/bin/HashRelay/agent.conf"

PKG_LIST="/usr/local/bin/HashRelay/pkg-auto-install/packages.list" # Default file containing package specifications
DRY_RUN=false                                                      # If true, only print commands; do not execute
VERBOSE=true                                                       # If true, print extra diagnostic logs
ASSUME_YES=false                                                   # If true, auto-confirm installs (PM-specific flags)

# usage(): prints help text
usage() {
  cat <<'USAGE'
pkg-auto-install.sh
Options:
  --packages FILE     Path to packages list (default: ./packages.list)
  --dry-run           Show commands without executing
  --verbose           Extra logging
  --assume-yes        Auto-confirm installs (e.g., -y / --noconfirm)
  -h|--help           This help
Environment:
  DETECT_PATH=/usr/local/bin/HashRelay/distro-and-pkgman-detect.sh (path to detector)
Behavior:
  Invokes: sudo bash "$DETECT_PATH" kv
USAGE
}

# Parse CLI arguments in a loop until all are consumed
while [[ $# -gt 0 ]]; do
  case "$1" in
  --packages)
    PKG_LIST="$2" # take the next token as the path
    shift 2
    ;;
  --dry-run)
    DRY_RUN=true # enable dry-run mode
    shift
    ;;
  --verbose)
    VERBOSE=true # enable verbose logs
    shift
    ;;
  --assume-yes)
    ASSUME_YES=true # enable non-interactive install flags
    shift
    ;;
  -h | --help)
    usage # print help and exit success
    exit 0
    ;;
  *)
    echo "[!] Unknown arg: $1"
    usage
    exit 1 # unknown option -> exit with error
    ;;
  esac
done

# -------------- Helpers -----------------
log() { printf '%s\n' "$*" >&2; }
# log(): prints to stderr (>&2) so stdout can be piped elsewhere cleanly

vlog() { [[ "$VERBOSE" == "true" ]] && log "$*"; }
# vlog(): conditional logger; only prints when VERBOSE=true

run() {
  # run(): uniform runner that honors DRY_RUN
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '[DRY-RUN] %s\n' "$*"
  else
    printf '[RUN] %s\n' "$*"
    eval "$@" # eval to keep quoting consistent with composed command strings
  fi
}

# -------------- Detector invocation -----------------
run_detector() {
  # Validate detector path exists (file) and/or is executable
  if [[ ! -x "$DETECT_PATH" && ! -f "$DETECT_PATH" ]]; then
    log "[!] Detector not found at $DETECT_PATH"
    exit 1
  fi
  vlog "[*] Running detector (sudo bash): $DETECT_PATH kv"
  sudo bash "$DETECT_PATH" kv
  # The detector prints key=value lines (e.g., DistroID=arch, Package-Managers=pacman)
  # The trailing "kv" tells our detector to output key-value format.
}

# Capture detector output into an array, one element per line.
mapfile -t DET_OUT < <(run_detector)

# Parse detector output lines into an associative array KV
declare -Ag KV=() # -A: associative array, -g: global (in case inside a function)
for line in "${DET_OUT[@]}"; do
  [[ -z "$line" || "$line" =~ ^\# ]] && continue     # skip empty or commented lines
  if [[ "$line" =~ ^([A-Za-z0-9._-]+)=(.*)$ ]]; then # key=value pattern
    key="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"
    KV["$key"]="$val"
  fi
done

# Preview a few useful keys when verbose
if [[ "$VERBOSE" == "true" ]]; then
  # Note: keys with hyphens must be quoted when indexing: KV["Package-Managers"]
  for k in DistroPretty DistroID DistroLike DistroVersion "Package-Managers" OSTree WSL Container; do
    printf '[*] %s=%s\n' "$k" "${KV["$k"]:-}" >&2
  done
fi

# Validate detector essentials
DISTRO_ID="${KV[DistroID]:-unknown}"
if [[ -z "$DISTRO_ID" || "$DISTRO_ID" == "unknown" ]]; then
  log "[!] Could not determine DistroID."
  for k in DistroPretty DistroID DistroLike DistroVersion WSL Container; do
    log "    detector preview: $k=${KV["$k"]:-}"
  done
  exit 1
fi

# IMPORTANT: quote hyphenated key; otherwise Bash treats it as subtraction.
PM_CSV="${KV["Package-Managers"]:-}"
if [[ -z "$PM_CSV" ]]; then
  log "[!] Detector returned no Package-Managers."
  exit 1
fi

# -------------- Package manager selection -----------------
# Split the comma-separated PM list (e.g., "pacman,brew") into array PMS
IFS=',' read -r -a PMS <<<"$PM_CSV"

# Preference order (first match wins). Tailor for your estate.
PM_PREF=(pacman apt-get apt dnf zypper xbps-install emerge apk nix-env brew rpm-ostree)

PRIMARY_PM="" # the package manager we will actually use

# norm_pm(): normalize aliases to canonical names
norm_pm() {
  case "$1" in
  apt-get | apt) echo "apt-get" ;; # treat apt as apt-get
  dnf5) echo "dnf" ;;              # unify dnf versions
  rpm-ostree | rpm_ostree) echo "rpm-ostree" ;;
  pacman | zypper | xbps-install | emerge | apk | nix-env | brew | dnf) echo "$1" ;;
  *) echo "$1" ;; # unknown stays as-is
  esac
}

# Build a set of PMs that are both reported by detector and present in PATH
declare -A HAVE_PM=()
for pm in "${PMS[@]}"; do
  n="$(norm_pm "$pm")"
  if command -v "$n" >/dev/null 2>&1; then
    HAVE_PM["$n"]=1
  fi
done

# Choose the first preferred PM that is available
for pref in "${PM_PREF[@]}"; do
  if [[ -n "${HAVE_PM[$pref]:-}" ]]; then
    PRIMARY_PM="$pref"
    break
  fi
done

# If we still don’t have a PM, bail out with context
if [[ -z "$PRIMARY_PM" ]]; then
  log "[!] No supported package manager found among: ${PMS[*]}"
  exit 1
fi
vlog "[*] DistroID=$DISTRO_ID; Primary PM=$PRIMARY_PM; All PMs=(${PMS[*]})"

# -------------- Package list parsing -----------------
# Ensure the packages file is readable
if [[ ! -r "$PKG_LIST" ]]; then
  log "[!] Package list not readable: $PKG_LIST"
  exit 1
fi

declare -a WANT_PKGS=() # intermediate list after applying per-line overrides

# Read the packages.list file line by line
while IFS= read -r raw || [[ -n "$raw" ]]; do
  # Trim leading/trailing whitespace
  line="${raw#"${raw%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" || "$line" =~ ^# ]] && continue # skip blanks/comments

  # Tokenize the line on whitespace (quotes in overrides handled by stripping later)
  tokens=($line)
  base="${tokens[0]}" # the generic package name (first bare token)
  override=""         # will hold PM-specific override(s) if present

  # Scan remaining tokens for key=value overrides (e.g., pacman="base-devel")
  for ((i = 1; i < ${#tokens[@]}; i++)); do
    tok="${tokens[$i]}"
    if [[ "$tok" =~ ^([A-Za-z0-9._-]+)=(.*)$ ]]; then
      k="${BASH_REMATCH[1]}"
      v="${BASH_REMATCH[2]}"
      k="$(norm_pm "$k")" # normalize override key to canonical PM
      # Strip surrounding single/double quotes if present
      v="${v%\"}"
      v="${v#\"}"
      v="${v%\'}"
      v="${v#\'}"
      if [[ "$k" == "$PRIMARY_PM" ]]; then
        override="$v" # capture the override that matches our PRIMARY_PM
      fi
    fi
  done

  # If we found an override for our PM, expand it (may be multiple packages)
  if [[ -n "$override" ]]; then
    arr=($override) # split override into array by spaces
    WANT_PKGS+=("${arr[@]}")
  else
    # Otherwise fall back to the generic package name
    WANT_PKGS+=("$base")
  fi
done <"$PKG_LIST"

# Deduplicate while preserving order -> FINAL_PKGS
declare -A SEEN=()
declare -a FINAL_PKGS=()
for p in "${WANT_PKGS[@]}"; do
  [[ -z "$p" ]] && continue
  if [[ -z "${SEEN[$p]:-}" ]]; then
    SEEN["$p"]=1
    FINAL_PKGS+=("$p")
  fi
done

# -------------- Command builder per PM -----------------
# yes_flag(): return the correct non-interactive flag for the active PM (if ASSUME_YES=true)
yes_flag() {
  case "$PRIMARY_PM" in
  pacman) $ASSUME_YES && printf -- "--noconfirm" ;;
  apt-get) $ASSUME_YES && printf -- "-y" ;;
  dnf) $ASSUME_YES && printf -- "-y" ;;
  zypper) $ASSUME_YES && printf -- "-y" ;;
  xbps-install) $ASSUME_YES && printf -- "-y" ;;
  emerge) $ASSUME_YES && printf -- "--ask=n" ;; # Gentoo-specific
  apk) $ASSUME_YES && printf -- "-y" ;;
  nix-env) ;;                                    # nix-env doesn’t use a generic -y
  brew) $ASSUME_YES && printf -- "-y" || true ;; # Homebrew supports -y for some taps
  rpm-ostree) ;;                                 # transactional; no -y here
  esac
}

# do_update(): perform metadata refresh appropriate to each PM
do_update() {
  case "$PRIMARY_PM" in
  pacman) run "sudo pacman -Sy" ;;
  apt-get) run "sudo apt-get update" ;;
  dnf) run "sudo dnf makecache" ;;
  zypper) run "sudo zypper refresh" ;;
  xbps-install) run "sudo xbps-install -S" ;;
  emerge) run "sudo emaint sync -a || sudo emerge --sync" ;;
  apk) run "sudo apk update" ;;
  nix-env) : ;; # nixpkgs channel mgmt is user-specific
  brew) run "brew update" ;;
  rpm-ostree) : ;; # updates handled differently (deploys)
  esac
}

# do_install(): build and execute the installation command(s)
do_install() {
  local yflag
  yflag="$(yes_flag || true)" # capture optional -y/--noconfirm etc.

  case "$PRIMARY_PM" in
  pacman) run "sudo pacman -S ${yflag:-} ${FINAL_PKGS[*]}" ;;
  apt-get) run "sudo apt-get install ${yflag:-} ${FINAL_PKGS[*]}" ;;
  dnf) run "sudo dnf install ${yflag:-} ${FINAL_PKGS[*]}" ;;
  zypper) run "sudo zypper install ${yflag:-} ${FINAL_PKGS[*]}" ;;
  xbps-install) run "sudo xbps-install ${yflag:-} ${FINAL_PKGS[*]}" ;;
  emerge) run "sudo emerge ${FINAL_PKGS[*]}" ;;
  apk) run "sudo apk add ${FINAL_PKGS[*]}" ;;
  nix-env)
    # Nix installs are per-package; loop to keep logs explicit
    for pkg in "${FINAL_PKGS[@]}"; do
      run "nix-env -iA nixpkgs.${pkg}"
    done
    ;;
  brew) run "brew install ${FINAL_PKGS[*]}" ;;
  rpm-ostree)
    run "sudo rpm-ostree install ${FINAL_PKGS[*]}"
    log "[i] rpm-ostree changes may require a reboot."
    ;;
  *)
    log "[!] Unsupported PM: $PRIMARY_PM"
    exit 1
    ;;
  esac
}

# -------------- Execute -----------------
vlog "[*] Packages after overrides/dedup: ${FINAL_PKGS[*]:-<none>}"
# Helpful trace showing the final package set we’re about to install

if [[ "${#FINAL_PKGS[@]}" -eq 0 ]]; then
  log "[!] No packages to install after parsing."
  exit 1
fi

do_update  # refresh package metadata/index
do_install # install the final deduplicated list

log "[✓] Installation finished with $PRIMARY_PM"

# Lunch the main configuration script
# by looking at the configuration file
# if CLIENT_AGENT=true lunch the hashrelay-client.sh script
# of SERVER_AGENT=true lunch the hashrelay-server.sh script
lunch_agent_config() {
  local path="${CONFIG_PATH:-}"

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
    echo "client agent true"
  else
    echo "client agent false"
  fi

  if [[ "$server" == true ]]; then
    echo "server agent true"
  else
    echo "server agent false"
  fi

  # 4) Sanity check (optional but useful)
  if [[ "$client" == "$server" ]]; then
    echo "Warning: invalid configuration in $path (exactly one should be true)."
    return 2
  fi

  return 0
}
