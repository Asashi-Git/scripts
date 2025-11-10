#!/usr/bin/env bash
# Author: Decarnelle Samuel
# Detect Linux distribution and enumerate installed package managers.
# Works on most Linux distros and containers. No root required.
# This script neet to be moved to /opt/sec/distro-and-pkgman-detect.sh

set -euo pipefail

have() { command -v -- "$1" >/dev/null 2>&1; }

# ---------- Read os-release with fallbacks ----------
OS_RELEASE_FILE=""
for f in /etc/os-release /usr/lib/os-release; do
  if [ -r "$f" ]; then
    OS_RELEASE_FILE="$f"
    break
  fi
done

DIST_PRETTY="Unknown Linux"
DIST_ID="unknown"
DIST_ID_LIKE=""
DIST_VERSION=""
if [ -n "$OS_RELEASE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$OS_RELEASE_FILE"
  DIST_PRETTY="${PRETTY_NAME:-${NAME:-Unknown Linux}}"
  DIST_ID="$(echo "${ID:-unknown}" | tr '[:upper:]' '[:lower:]')"
  DIST_ID_LIKE="$(echo "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')"
  DIST_VERSION="${VERSION_ID:-}"
else
  if [ -f /etc/alpine-release ]; then
    DIST_PRETTY="Alpine Linux"
    DIST_ID="alpine"
  elif [ -f /etc/arch-release ]; then
    DIST_PRETTY="Arch Linux"
    DIST_ID="arch"
  elif [ -f /etc/gentoo-release ]; then
    DIST_PRETTY="Gentoo"
    DIST_ID="gentoo"
  elif [ -f /etc/slackware-version ]; then
    DIST_PRETTY="Slackware"
    DIST_ID="slackware"
  elif [ -f /etc/void-release ]; then
    DIST_PRETTY="Void Linux"
    DIST_ID="void"
  fi
fi

# ---------- Environment hints ----------
IS_OSTREE="false"
[ -f /run/ostree-booted ] && IS_OSTREE="true"
IS_WSL="false"
grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null && IS_WSL="true"

IS_CONTAINER="false"
if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
  IS_CONTAINER="true"
elif have systemd-detect-virt && systemd-detect-virt --container >/dev/null 2>&1; then
  IS_CONTAINER="true"
fi

# ---------- Package manager catalog ----------
# Keys must match real binary names in PATH (no spaces)
PM_CANDIDATES=(
  # Debian/Ubuntu
  "apt" "apt-get" "aptitude"
  # Fedora/RHEL
  "dnf" "microdnf" "yum"
  # openSUSE
  "zypper"
  # Arch
  "pacman"
  # Alpine
  "apk"
  # Void
  "xbps-install" "xbps-query"
  # Gentoo
  "emerge" "eix"
  # Solus
  "eopkg"
  # Clear Linux
  "swupd"
  # Photon/Tanzu
  "tdnf"
  # OSTree
  "rpm-ostree"
  # Nix
  "nix-env" "nix"
)

detect_pms() {
  local found=()
  for pm in "${PM_CANDIDATES[@]}"; do
    if have "$pm"; then found+=("$pm"); fi
  done
  # CSV output with no spaces
  local IFS=","
  printf "%s" "${found[*]}"
}

# ---------- Output mode ----------
# default: human. if "kv" passed: key=value pairs only (for machine parsing)
MODE="${1:-human}"

PACKAGE_MANAGERS="$(detect_pms)"

if [ "$MODE" = "kv" ]; then
  echo "DistroPretty=${DIST_PRETTY}"
  echo "DistroID=${DIST_ID}"
  echo "DistroLike=${DIST_ID_LIKE}"
  echo "DistroVersion=${DIST_VERSION}"
  echo "WSL=${IS_WSL}"
  echo "Container=${IS_CONTAINER}"
  echo "OSTree=${IS_OSTREE}"
  echo "Package-Managers=${PACKAGE_MANAGERS}"
  exit 0
fi

# Human-readable (not used by the installer)
cat <<EOF
Distribution   : ${DIST_PRETTY} (id=${DIST_ID}, version=${DIST_VERSION}, like=${DIST_ID_LIKE})
Environment    : WSL=${IS_WSL} Container=${IS_CONTAINER} OSTree=${IS_OSTREE}
Package managers in PATH:
  ${PACKAGE_MANAGERS//,/ }
EOF
