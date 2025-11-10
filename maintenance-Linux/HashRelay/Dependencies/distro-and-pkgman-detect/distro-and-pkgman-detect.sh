#!/usr/bin/env bash
# Purpose: Detect the Linux distribution and enumerate installed package managers.
#
# Author: Decarnelle Samuel
#
# Scope: Works on most Linux distros and containers. No root required.
# Install path: /usr/local/bin/HashRelay/distro-and-pkgman-detect.sh

set -euo pipefail
# -e : exit immediately on any error
# -u : treat unset variables as an error (fail fast on typos)
# -o pipefail : a pipeline fails if any command within it fails

# have(): tiny helper to check if a command exists in PATH
have() { command -v -- "$1" >/dev/null 2>&1; }

# ---------- Read os-release with fallbacks ----------
# Try to locate the canonical os-release file (present on systemd and most distros)
OS_RELEASE_FILE=""
for f in /etc/os-release /usr/lib/os-release; do
  if [ -r "$f" ]; then
    OS_RELEASE_FILE="$f" # remember the first readable file
    break
  fi
done

# Initialize distro identity variables with conservative defaults
DIST_PRETTY="Unknown Linux" # human-friendly name (e.g., "Ubuntu 24.04 LTS")
DIST_ID="unknown"           # normalized ID (e.g., "ubuntu", "arch", "fedora")
DIST_ID_LIKE=""             # related family IDs (e.g., "debian")
DIST_VERSION=""             # numeric version (e.g., "24.04")

if [ -n "$OS_RELEASE_FILE" ]; then
  # Source os-release to populate NAME, ID, VERSION_ID, ID_LIKE, PRETTY_NAME, ...
  # shellcheck disable=SC1090
  . "$OS_RELEASE_FILE"
  # Prefer PRETTY_NAME, fallback to NAME, finally "Unknown Linux"
  DIST_PRETTY="${PRETTY_NAME:-${NAME:-Unknown Linux}}"
  # Normalize IDs to lowercase (some distros ship uppercase)
  DIST_ID="$(echo "${ID:-unknown}" | tr '[:upper:]' '[:lower:]')"
  DIST_ID_LIKE="$(echo "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')"
  DIST_VERSION="${VERSION_ID:-}"
else
  # Fallback heuristics for minimal systems that lack os-release
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
# Detect OSTree systems (e.g., Fedora Silverblue, Kinoite); affects package strategy
IS_OSTREE="false"
[ -f /run/ostree-booted ] && IS_OSTREE="true"

# Detect Windows Subsystem for Linux (WSL) via kernel version string
IS_WSL="false"
grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null && IS_WSL="true"

# Detect containers (Docker/Podman/etc.) using common markers or systemd helper
IS_CONTAINER="false"
if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
  IS_CONTAINER="true"
elif have systemd-detect-virt && systemd-detect-virt --container >/dev/null 2>&1; then
  IS_CONTAINER="true"
fi

# ---------- Package manager catalog ----------
# PM_CANDIDATES: list of known package manager client binaries to probe in PATH.
# IMPORTANT: entries must match actual executable names (no spaces).
PM_CANDIDATES=(
  # Debian/Ubuntu family
  "apt" "apt-get" "aptitude"
  # Fedora/RHEL family
  "dnf" "microdnf" "yum"
  # openSUSE family
  "zypper"
  # Arch family
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
  # OSTree-based (transactional)
  "rpm-ostree"
  # Nix
  "nix-env" "nix"
)

# detect_pms(): iterate the catalog and return a CSV (no spaces) of PMs present in PATH
detect_pms() {
  local found=()
  for pm in "${PM_CANDIDATES[@]}"; do
    if have "$pm"; then found+=("$pm"); fi
  done
  # Emit comma-separated list (e.g., "pacman,brew")
  local IFS=","
  printf "%s" "${found[*]}"
}

# ---------- Output mode ----------
# MODE controls how we print results:
# - "human" (default): multi-line readable summary
# - "kv"            : key=value pairs for machine parsing (e.g., your installer)
MODE="${1:-human}"

# Compute once to keep behavior deterministic across both modes
PACKAGE_MANAGERS="$(detect_pms)"

if [ "$MODE" = "kv" ]; then
  # Strict key=value output (no extra whitespace or commentary)
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

# Human-readable (useful for manual checks; our installer does not use this)
cat <<EOF
Distribution   : ${DIST_PRETTY} (id=${DIST_ID}, version=${DIST_VERSION}, like=${DIST_ID_LIKE})
Environment    : WSL=${IS_WSL} Container=${IS_CONTAINER} OSTree=${IS_OSTREE}
Package managers in PATH:
  ${PACKAGE_MANAGERS//,/ }
EOF
