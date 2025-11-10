#!/usr/bin/env bash
# Author: Decarnelle Samuel
#
# Auto-install packages based on detected distro/PMs.
# This version always runs a detector script located at DETECT_PATH.
# - Reads key=value lines from the detector output
# - Chooses a primary package manager
# - Installs packages from a list with optional per-manager overrides
# - Supports --dry-run and --assume-yes for non-interactive usage
#
# Use inside isolated lab VMs/hosts only.

set -euo pipefail

have() { command -v -- "$1" >/dev/null 2>&1; }

# ---------- configuration ----------
# Path to your first script (distro_and_pkgman_detect.sh). Can be overridden via env.
DETECT_PATH="${DETECT_PATH:-./../distro-and-pkgman-detect/distro-and-pkgman-detect.sh}"

# Default package list file
PKG_FILE="packages.list"

# Flags
DRY_RUN="false"
ASSUME_YES="false"
VERBOSE="true"

usage() {
  cat <<'EOF'
Usage: pkg_auto_install.sh [options]
  --pkg-file FILE   Package list file (default: packages.list)
  --dry-run         Show commands only (do not execute)
  --assume-yes      Non-interactive mode (-y/--noconfirm, etc.)
  --quiet           Less output
  -h|--help         This help

Environment:
  DETECT_PATH=/path/to/distro_and_pkgman_detect.sh
Examples:
  DETECT_PATH=./distro_and_pkgman_detect.sh ./pkg_auto_install.sh --assume-yes
  ./pkg_auto_install.sh --dry-run
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
  --pkg-file)
    PKG_FILE="$2"
    shift 2
    ;;
  --dry-run)
    DRY_RUN="true"
    shift
    ;;
  --assume-yes)
    ASSUME_YES="true"
    shift
    ;;
  --quiet)
    VERBOSE="false"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown option: $1" >&2
    usage
    exit 1
    ;;
  esac
done

# ---------- run detector ----------
[ -x "$DETECT_PATH" ] || {
  echo "[!] Detector not found or not executable: $DETECT_PATH" >&2
  exit 1
}
[ "$VERBOSE" = "true" ] && echo "[*] Running detector at: $DETECT_PATH" >&2

declare -A KV
read_kv() {
  local line k v
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^\# ]] && continue
    if [[ "$line" =~ ^([A-Za-z0-9_]+)=(.*)$ ]]; then
      k="${BASH_REMATCH[1]}"
      v="${BASH_REMATCH[2]}"
      KV["$k"]="$v"
    fi
  done
}

# Capture and parse detector output
mapfile -t DET_OUT < <("$DETECT_PATH")
printf '%s\n' "${DET_OUT[@]}" | read_kv

DistroID="${KV[DistroID]:-${KV[ID]:-unknown}}"
PM_CSV="${KV[Package - Managers]:-}"
OSTREE="${KV[OSTree]:-${KV[OSTREE]:-false}}"

if [ "$DistroID" = "unknown" ] || [ -z "$PM_CSV" ]; then
  echo "[!] Could not determine DistroID or Package-Managers from detector output." >&2
  echo "[i] Detector output preview:" >&2
  printf '    %s\n' "${DET_OUT[@]:0:10}" >&2
  exit 1
fi

IFS=',' read -r -a PM_LIST <<<"$PM_CSV"

# ---------- choose primary package manager ----------
choose_primary_pm() {
  local id="$1"
  shift
  local -a pms=("$@")
  local prefer=()

  case "$id" in
  debian | ubuntu | linuxmint | elementary | pop | kali | parrot | raspbian) prefer=(apt apt-get aptitude) ;;
  fedora | rhel | centos | rocky | almalinux | oracle | ol)
    if [ "${OSTREE,,}" = "true" ]; then prefer=(rpm-ostree); else prefer=(dnf microdnf yum); fi
    ;;
  opensuse* | sles | sle) prefer=(zypper) ;;
  arch | manjaro | endeavouros | arco | garuda | artix) prefer=(pacman yay paru trizen pikaur) ;;
  alpine) prefer=(apk) ;;
  gentoo) prefer=(emerge) ;;
  void) prefer=(xbps-install) ;;
  slackware) prefer=(slackpkg installpkg) ;;
  solus) prefer=(eopkg) ;;
  clear-linux | clearlinux) prefer=(swupd) ;;
  photon) prefer=(tdnf) ;;
  nixos | nix | nixos-small) prefer=(nix-env nix) ;;
  *) prefer=("${pms[@]}" apt dnf zypper pacman apk xbps-install emerge eopkg swupd tdnf nix-env rpm-ostree) ;;
  esac

  for want in "${prefer[@]}"; do
    for have_pm in "${pms[@]}"; do
      if [ "$want" = "$have_pm" ]; then
        echo "$want"
        return 0
      fi
    done
  done
  echo "${pms[0]}"
}

PRIMARY_PM="$(choose_primary_pm "$DistroID" "${PM_LIST[@]}")"
[ "$VERBOSE" = "true" ] && echo "[*] DistroID=$DistroID | Primary manager=$PRIMARY_PM" >&2

# ---------- read package file ----------
[ -r "$PKG_FILE" ] || {
  echo "[!] Package file not found: $PKG_FILE" >&2
  exit 1
}

declare -A OVERRIDES # key: "generic|manager" -> real name
declare -a GENERIC_PKGS=()

while IFS= read -r line; do
  line="${line%%#*}"
  line="$(echo "$line" | xargs || true)"
  [ -z "$line" ] && continue
  read -r generic rest <<<"$line"
  [ -z "$generic" ] && continue
  GENERIC_PKGS+=("$generic")
  for tok in $rest; do
    if [[ "$tok" =~ ^([A-Za-z0-9._+-]+)=(.+)$ ]]; then
      mgr="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"
      OVERRIDES["$generic|$mgr"]="$val"
    fi
  done
done <"$PKG_FILE"

resolve_pkg_name() {
  local generic="$1" mgr="$2"
  local key="$generic|$mgr"
  if [[ -n "${OVERRIDES[$key]:-}" ]]; then printf '%s' "${OVERRIDES[$key]}"; else printf '%s' "$generic"; fi
}

# ---------- non-interactive flags per manager ----------
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
    echo "nix-env -iA nixpkgs.{${pkgs[*]// /,}}"
    ;;
  *)
    echo "echo 'Unsupported package manager: $mgr' >&2; exit 2"
    ;;
  esac
}

# Resolve package names for chosen manager
declare -a RESOLVED=()
for g in "${GENERIC_PKGS[@]}"; do
  RESOLVED+=("$(resolve_pkg_name "$g" "$PRIMARY_PM")")
done

if [ "$VERBOSE" = "true" ]; then
  echo "[*] Generic packages: ${GENERIC_PKGS[*]}" >&2
  echo "[*] Resolved for $PRIMARY_PM: ${RESOLVED[*]}" >&2
fi

mapfile -t CMDS < <(build_cmds "$PRIMARY_PM" "${RESOLVED[@]}")

if [ "$DRY_RUN" = "true" ]; then
  echo "[DRY-RUN] Commands to run:"
  printf '  %s\n' "${CMDS[@]}"
  if [ "${OSTREE,,}" = "true" ] && [ "$PRIMARY_PM" = "rpm-ostree" ]; then
    echo "[DRY-RUN] rpm-ostree: changes typically apply after a reboot."
  fi
  exit 0
fi

# Execute commands
for cmd in "${CMDS[@]}"; do
  [ "$VERBOSE" = "true" ] && echo "[+] $cmd"
  eval "$cmd"
done

if [ "${OSTREE,,}" = "true" ] && [ "$PRIMARY_PM" = "rpm-ostree" ]; then
  echo "[i] rpm-ostree: changes will apply after the next reboot."
fi

echo "[✓] Installation finished with $PRIMARY_PM"
