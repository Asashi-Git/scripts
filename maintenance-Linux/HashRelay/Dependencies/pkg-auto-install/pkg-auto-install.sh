#!/usr/bin/env bash
# Purpose: Auto-install a package set across Linux distros using your detector.
# Author: Decarnelle Samuel
# Safety: Only use in your isolated lab; review commands before running.
# Usage:
#   sudo bash ./pkg-auto-install.sh --dry-run --verbose --assume-yes --packages ./packages.list
# Env:
#   DETECT_PATH=/opt/sec/distro-and-pkgman-detect.sh (default below)

set -euo pipefail

# -------------- Defaults and CLI -----------------
DETECT_PATH="${DETECT_PATH:-/opt/sec/distro-and-pkgman-detect.sh}"
PKG_LIST="./packages.list"
DRY_RUN=false
VERBOSE=false
ASSUME_YES=false

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
  DETECT_PATH=/opt/sec/distro-and-pkgman-detect.sh (path to detector)
Behavior:
  Invokes: sudo bash "$DETECT_PATH" kv
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --packages)
    PKG_LIST="$2"
    shift 2
    ;;
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  --verbose)
    VERBOSE=true
    shift
    ;;
  --assume-yes)
    ASSUME_YES=true
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "[!] Unknown arg: $1"
    usage
    exit 1
    ;;
  esac
done

# -------------- Helpers -----------------
log() { printf '%s\n' "$*" >&2; }
vlog() { [[ "$VERBOSE" == "true" ]] && log "$*"; }
run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '[DRY-RUN] %s\n' "$*"
  else
    printf '[RUN] %s\n' "$*"
    eval "$@"
  fi
}
require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "[!] Required command not found: $1"
    exit 1
  fi
}

# -------------- Detector invocation -----------------
run_detector() {
  # Intentionally via sudo bash as requested
  if [[ ! -x "$DETECT_PATH" && ! -f "$DETECT_PATH" ]]; then
    log "[!] Detector not found at $DETECT_PATH"
    exit 1
  fi
  vlog "[*] Running detector (sudo bash): $DETECT_PATH kv"
  # Use a subshell execution but capture output into an array cleanly
  sudo bash "$DETECT_PATH" kv
}

# Capture detector output (array-safe)
mapfile -t DET_OUT < <(run_detector)

# Parse in current shell (fixes prior subshell bug)
declare -Ag KV=()
for line in "${DET_OUT[@]}"; do
  [[ -z "$line" || "$line" =~ ^\# ]] && continue
  if [[ "$line" =~ ^([A-Za-z0-9._-]+)=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"
    KV["$key"]="$val"
  fi
done

# Preview for troubleshooting
if [[ "$VERBOSE" == "true" ]]; then
  for k in DistroPretty DistroID DistroLike DistroVersion "Package-Managers" OSTree WSL Container; do
    printf '[*] %s=%s\n' "$k" "${KV[$k]:-}" >&2
  done
fi

# Validate detector essentials
DISTRO_ID="${KV[DistroID]:-unknown}"
[[ "$DISTRO_ID" == "unknown" || -z "$DISTRO_ID" ]] && {
  log "[!] Could not determine DistroID."
  for k in DistroPretty DistroID DistroLike DistroVersion WSL Container; do
    log "    detector preview: $k=${KV[$k]:-}"
  done
  exit 1
}

PM_CSV="${KV[Package - Managers]:-}"
if [[ -z "$PM_CSV" ]]; then
  log "[!] Detector returned no Package-Managers."
  exit 1
fi

# -------------- Package manager selection -----------------
# Convert CSV to array
IFS=',' read -r -a PMS <<<"$PM_CSV"

# Rank PMs (first viable wins). Tune order if you like.
PM_PREF=(pacman apt-get apt dnf zypper xbps-install emerge apk nix-env brew rpm-ostree)
PRIMARY_PM=""

# Normalize names provided by detector just in case
norm_pm() {
  case "$1" in
  apt-get | apt) echo "apt-get" ;;
  dnf5) echo "dnf" ;; # future-proof
  rpm-ostree | rpm_ostree) echo "rpm-ostree" ;;
  pacman | zypper | xbps-install | emerge | apk | nix-env | brew | dnf) echo "$1" ;;
  *) echo "$1" ;;
  esac
}

declare -A HAVE_PM=()
for pm in "${PMS[@]}"; do
  n="$(norm_pm "$pm")"
  if command -v "$n" >/dev/null 2>&1; then
    HAVE_PM["$n"]=1
  fi
done

for pref in "${PM_PREF[@]}"; do
  if [[ -n "${HAVE_PM[$pref]:-}" ]]; then
    PRIMARY_PM="$pref"
    break
  fi
done

if [[ -z "$PRIMARY_PM" ]]; then
  log "[!] No supported package manager found among: ${PMS[*]}"
  exit 1
fi
vlog "[*] DistroID=$DISTRO_ID; Primary PM=$PRIMARY_PM; All PMs=(${PMS[*]})"

# -------------- Package list parsing -----------------
if [[ ! -r "$PKG_LIST" ]]; then
  log "[!] Package list not readable: $PKG_LIST"
  exit 1
fi

# Each line supports:
#   pkgname
#   pkgname pmA=override1 pmB="override with spaces"
#   # comments allowed
declare -a WANT_PKGS=()

# Read respecting quotes
while IFS= read -r raw || [[ -n "$raw" ]]; do
  # Trim
  line="${raw#"${raw%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" || "$line" =~ ^# ]] && continue

  # Split tokens while respecting quotes
  # shellcheck disable=SC2206
  tokens=($line)
  base="${tokens[0]}"
  override=""

  # Collect per-PM overrides
  for ((i = 1; i < ${#tokens[@]}; i++)); do
    tok="${tokens[$i]}"
    if [[ "$tok" =~ ^([A-Za-z0-9._-]+)=(.*)$ ]]; then
      k="${BASH_REMATCH[1]}"
      v="${BASH_REMATCH[2]}"
      k="$(norm_pm "$k")"
      # Strip optional quotes around value
      v="${v%\"}"
      v="${v#\"}"
      v="${v%\'}"
      v="${v#\'}"
      if [[ "$k" == "$PRIMARY_PM" ]]; then
        override="$v"
      fi
    fi
  done

  if [[ -n "$override" ]]; then
    # Allow multiple space-separated names in override
    # shellcheck disable=SC2206
    arr=($override)
    WANT_PKGS+=("${arr[@]}")
  else
    WANT_PKGS+=("$base")
  fi
done <"$PKG_LIST"

# Deduplicate packages (simple)
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
yes_flag() {
  case "$PRIMARY_PM" in
  pacman) $ASSUME_YES && printf -- "--noconfirm" ;;
  apt-get) $ASSUME_YES && printf -- "-y" ;;
  dnf) $ASSUME_YES && printf -- "-y" ;;
  zypper) $ASSUME_YES && printf -- "-y" ;;
  xbps-install) $ASSUME_YES && printf -- "-y" ;;
  emerge) $ASSUME_YES && printf -- "--ask=n" ;;
  apk) $ASSUME_YES && printf -- "-y" ;;
  nix-env) ;; # nix often doesn't need a -y
  brew) $ASSUME_YES && printf -- "-y" || true ;;
  rpm-ostree) ;; # layered commits are transactional, no -y
  esac
}

do_update() {
  case "$PRIMARY_PM" in
  pacman) run "sudo pacman -Sy" ;;
  apt-get) run "sudo apt-get update" ;;
  dnf) run "sudo dnf makecache" ;;
  zypper) run "sudo zypper refresh" ;;
  xbps-install) run "sudo xbps-install -S" ;;
  emerge) run "sudo emaint sync -a || sudo emerge --sync" ;;
  apk) run "sudo apk update" ;;
  nix-env) : ;; # not needed
  brew) run "brew update" ;;
  rpm-ostree) : ;; # catalog managed separately
  esac
}

do_install() {
  local yflag
  yflag="$(yes_flag || true)"
  case "$PRIMARY_PM" in
  pacman)
    run "sudo pacman -S ${yflag:-} ${FINAL_PKGS[*]}"
    ;;
  apt-get)
    run "sudo apt-get install ${yflag:-} ${FINAL_PKGS[*]}"
    ;;
  dnf)
    run "sudo dnf install ${yflag:-} ${FINAL_PKGS[*]}"
    ;;
  zypper)
    run "sudo zypper install ${yflag:-} ${FINAL_PKGS[*]}"
    ;;
  xbps-install)
    run "sudo xbps-install ${yflag:-} ${FINAL_PKGS[*]}"
    ;;
  emerge)
    run "sudo emerge ${FINAL_PKGS[*]}"
    ;;
  apk)
    run "sudo apk add ${FINAL_PKGS[*]}"
    ;;
  nix-env)
    # Nix installs are per-user by default; consider flakes for reproducibility
    for pkg in "${FINAL_PKGS[@]}"; do
      run "nix-env -iA nixpkgs.${pkg}"
    done
    ;;
  brew)
    run "brew install ${FINAL_PKGS[*]}"
    ;;
  rpm-ostree)
    # Layer and reboot is typically required to apply
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
if [[ "${#FINAL_PKGS[@]}" -eq 0 ]]; then
  log "[!] No packages to install after parsing."
  exit 1
fi

do_update
do_install

log "[✓] Installation finished with $PRIMARY_PM"
