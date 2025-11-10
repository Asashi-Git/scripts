#!/usr/bin/env bash
# Author: Decarnelle Samuel
# Install generic packages using the native package manager detected on the host.
# This script calls the detector as: sudo bash /path/to/distro-and-pkgman-detect.sh kv

set -euo pipefail

# ---------- Defaults and args ----------
DETECT_PATH="${DETECT_PATH:-/opt/sec/distro-and-pkgman-detect.sh}"
PKG_FILE="${PKG_FILE:-./packages.list}"
ASSUME_YES="false"
DRY_RUN="false"
VERBOSE="false"

usage() {
  cat <<'EOF'
Usage: pkg-auto-install.sh [--packages FILE] [--detector PATH] [--assume-yes] [--dry-run] [--verbose]
Env overrides:
  DETECT_PATH=/abs/path/to/distro-and-pkgman-detect.sh
  PKG_FILE=./packages.list

packages.list format (generic name + optional per-manager overrides):
  curl
  python3 apt=python3 python3-pip=python3-pip dnf=python3 pip=pip
  build-essential dnf="gcc gcc-c++ make" zypper="gcc gcc-c++ make"
  git
Lines support comments (#) and trimming.

Examples:
  DETECT_PATH=/opt/sec/distro-and-pkgman-detect.sh ./pkg-auto-install.sh --dry-run --verbose
  ./pkg-auto-install.sh --packages ./packages.list --assume-yes
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
  --packages | -p)
    PKG_FILE="$2"
    shift 2
    ;;
  --detector | -d)
    DETECT_PATH="$2"
    shift 2
    ;;
  --assume-yes | -y)
    ASSUME_YES="true"
    shift
    ;;
  --dry-run)
    DRY_RUN="true"
    shift
    ;;
  --verbose | -v)
    VERBOSE="true"
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

have() { command -v -- "$1" >/dev/null 2>&1; }

# ---------- Run detector via sudo bash ----------
[ -f "$DETECT_PATH" ] || {
  echo "[!] Detector not found: $DETECT_PATH" >&2
  exit 1
}
DETECT_ABS="$(readlink -f "$DETECT_PATH" 2>/dev/null || realpath "$DETECT_PATH" 2>/dev/null || echo "$DETECT_PATH")"

[ "$VERBOSE" = "true" ] && echo "[*] Running detector (sudo bash): $DETECT_ABS kv" >&2

declare -A KV
read_kv() {
  local line k v
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^\# ]] && continue
    if [[ "$line" =~ ^([A-Za-z0-9_-]+)=(.*)$ ]]; then
      k="${BASH_REMATCH[1]}"
      v="${BASH_REMATCH[2]}"
      KV["$k"]="$v"
    fi
  done
}

run_detector() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    bash "$DETECT_ABS" kv
  else
    if ! have sudo; then
      echo "[!] sudo not found; required for detector invocation." >&2
      exit 1
    fi
    sudo bash "$DETECT_ABS" kv
  fi
}

mapfile -t DET_OUT < <(run_detector)
printf '%s\n' "${DET_OUT[@]}" | read_kv

DistroID="${KV[DistroID]:-${KV[ID]:-unknown}}"
PM_CSV="$(printf '%s' "${KV[Package - Managers]:-}" | sed 's/, \+/,/g')"
OSTREE="${KV[OSTree]:-${KV[OSTREE]:-false}}"

if [ "$DistroID" = "unknown" ]; then
  echo "[!] Could not determine DistroID." >&2
  printf '    detector preview: %s\n' "${DET_OUT[@]:0:6}" >&2
  exit 1
fi
if [ -z "$PM_CSV" ]; then
  echo "[!] Detector did not report any package managers in PATH." >&2
  exit 1
fi

IFS=',' read -r -a PM_LIST <<<"$PM_CSV"
[ "$VERBOSE" = "true" ] && echo "[*] DistroID=$DistroID; PMs=(${PM_LIST[*]}) OSTree=$OSTREE" >&2

# ---------- Choose primary PM ----------
choose_primary_pm() {
  local -a pref=(
    # Nix (opt-in if present; put later if you prefer native PMs)
    nix-env nix
    # Debian/Ubuntu
    apt apt-get aptitude
    # Fedora/RHEL
    dnf microdnf yum
    # openSUSE
    zypper
    # Arch
    pacman
    # Alpine
    apk
    # Void
    xbps-install
    # Gentoo
    emerge
    # Solus
    eopkg
    # Clear
    swupd
    # Photon
    tdnf
    # OSTree (only if OSTree=true)
    rpm-ostree
  )
  local seen
  for p in "${pref[@]}"; do
    for seen in "${PM_LIST[@]}"; do
      if [ "$p" = "$seen" ]; then
        # If rpm-ostree but env not OSTree, skip
        if [ "$p" = "rpm-ostree" ] && [ "${OSTREE,,}" != "true" ]; then
          continue
        fi
        echo "$p"
        return 0
      fi
    done
  done
  return 1
}

PRIMARY_PM="$(choose_primary_pm || true)"
if [ -z "$PRIMARY_PM" ]; then
  echo "[!] No supported package manager found among: ${PM_LIST[*]}" >&2
  exit 2
fi
[ "$VERBOSE" = "true" ] && echo "[*] Selected package manager: $PRIMARY_PM" >&2

# ---------- Read package mapping file ----------
[ -r "$PKG_FILE" ] || {
  echo "[!] Package file not readable: $PKG_FILE" >&2
  exit 1
}

declare -A OVERRIDES # key: "generic|manager" -> realname(s)
declare -a GENERIC_PKGS=()

while IFS= read -r line; do
  # Strip comments and trim
  line="${line%%#*}"
  line="$(echo "$line" | xargs || true)"
  [ -z "$line" ] && continue
  read -r generic rest <<<"$line"
  [ -z "$generic" ] && continue
  GENERIC_PKGS+=("$generic")
  # parse tokens: mgr=val (quoted value allowed)
  while [ -n "${rest:-}" ]; do
    # shellcheck disable=SC2086
    case "$rest" in
    *=*)
      # Extract first key=value (respect optional quotes)
      if [[ "$rest" =~ ^([A-Za-z0-9._+-]+)=(\"[^\"]+\"|\'[^\']+\'|[^[:space:]]+)([[:space:]].*|$) ]]; then
        mgr="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        rest="${BASH_REMATCH[3]:-}"
        val="${val%\"}"
        val="${val#\"}"
        val="${val%\'}"
        val="${val#\'}"
        OVERRIDES["$generic|$mgr"]="$val"
        rest="$(echo "$rest" | xargs || true)"
        continue
      fi
      ;;
    esac
    # No more key=value tokens
    break
  done
done <"$PKG_FILE"

resolve_pkg_name() {
  local generic="$1" mgr="$2"
  local key="$generic|$mgr"
  if [[ -n "${OVERRIDES[$key]:-}" ]]; then
    printf '%s' "${OVERRIDES[$key]}"
  else
    printf '%s' "$generic"
  fi
}

# ---------- Non-interactive flags ----------
YESFLAG=""
case "$PRIMARY_PM" in
apt | apt-get | aptitude) YESFLAG=$([ "$ASSUME_YES" = "true" ] && echo "-y" || echo "") ;;
dnf | microdnf | yum) YESFLAG=$([ "$ASSUME_YES" = "true" ] && echo "-y" || echo "") ;;
zypper) YESFLAG=$([ "$ASSUME_YES" = "true" ] && echo "--non-interactive" || echo "") ;;
pacman) YESFLAG=$([ "$ASSUME_YES" = "true" ] && echo "--noconfirm" || echo "") ;;
apk) YESFLAG=$([ "$ASSUME_YES" = "true" ] && echo "--no-interactive" || echo "") ;;
xbps-install) YESFLAG=$([ "$ASSUME_YES" = "true" ] && echo "-y" || echo "") ;;
emerge) YESFLAG=$([ "$ASSUME_YES" = "true" ] && echo "--ask=n" || echo "") ;;
eopkg) YESFLAG=$([ "$ASSUME_YES" = "true" ] && echo "-y" || echo "") ;;
swupd) YESFLAG=$([ "$ASSUME_YES" = "true" ] && echo "--assume=yes" || echo "") ;;
tdnf) YESFLAG=$([ "$ASSUME_YES" = "true" ] && echo "-y" || echo "") ;;
rpm-ostree) YESFLAG=$([ "$ASSUME_YES" = "true" ] && echo "-y" || echo "") ;;
nix-env | nix) YESFLAG="" ;;
*) YESFLAG="" ;;
esac

# ---------- Build commands for the chosen manager ----------
build_cmds() {
  local mgr="$1"
  shift
  local -a pkgs=("$@")
  case "$mgr" in
  apt | apt-get | aptitude)
    echo "sudo $mgr update"
    echo "sudo $mgr install $YESFLAG ${pkgs[*]}"
    ;;
  dnf | microdnf | yum)
    echo "sudo $mgr makecache"
    echo "sudo $mgr install $YESFLAG ${pkgs[*]}"
    ;;
  zypper)
    echo "sudo zypper refresh"
    echo "sudo zypper install $YESFLAG ${pkgs[*]}"
    ;;
  pacman)
    echo "sudo pacman -Sy"
    echo "sudo pacman -S $YESFLAG ${pkgs[*]}"
    ;;
  apk)
    echo "sudo apk update"
    echo "sudo apk add ${pkgs[*]}"
    ;;
  xbps-install)
    echo "sudo xbps-install -S"
    echo "sudo xbps-install $YESFLAG ${pkgs[*]}"
    ;;
  emerge)
    echo "sudo emerge --sync"
    echo "sudo emerge ${pkgs[*]}"
    ;;
  eopkg)
    echo "sudo eopkg update-repo"
    echo "sudo eopkg install $YESFLAG ${pkgs[*]}"
    ;;
  swupd)
    echo "sudo swupd update"
    echo "sudo swupd bundle-add ${pkgs[*]}"
    ;;
  tdnf)
    echo "sudo tdnf makecache"
    echo "sudo tdnf install $YESFLAG ${pkgs[*]}"
    ;;
  rpm-ostree)
    echo "sudo rpm-ostree install ${pkgs[*]}"
    ;;
  nix-env | nix)
    # Install attributes from nixpkgs; expects generic names to be nix attrs via overrides
    echo "nix-env -iA nixpkgs.{${pkgs[*]// /,}}"
    ;;
  *)
    echo "echo 'Unsupported package manager: $mgr' >&2; exit 2"
    ;;
  esac
}

# ---------- Resolve package names ----------
declare -a RESOLVED=()
for g in "${GENERIC_PKGS[@]}"; do
  RESOLVED+=("$(resolve_pkg_name "$g" "$PRIMARY_PM")")
done

if [ "$VERBOSE" = "true" ]; then
  echo "[*] Generic packages: ${GENERIC_PKGS[*]}" >&2
  echo "[*] Resolved for $PRIMARY_PM: ${RESOLVED[*]}" >&2
fi

mapfile -t CMDS < <(build_cmds "$PRIMARY_PM" "${RESOLVED[@]}")

# ---------- Dry-run or execute ----------
if [ "$DRY_RUN" = "true" ]; then
  echo "[DRY-RUN] Commands to run:"
  printf '  %s\n' "${CMDS[@]}"
  if [ "${OSTREE,,}" = "true" ] && [ "$PRIMARY_PM" = "rpm-ostree" ]; then
    echo "[DRY-RUN] rpm-ostree: changes typically apply after a reboot."
  fi
  exit 0
fi

for cmd in "${CMDS[@]}"; do
  [ "$VERBOSE" = "true" ] && echo "[+] $cmd"
  eval "$cmd"
done

if [ "${OSTREE,,}" = "true" ] && [ "$PRIMARY_PM" = "rpm-ostree" ]; then
  echo "[i] rpm-ostree: changes will apply after the next reboot."
fi

echo "[✓] Installation finished with $PRIMARY_PM"
