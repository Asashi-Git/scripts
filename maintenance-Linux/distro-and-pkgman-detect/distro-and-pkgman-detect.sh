#!/usr/bin/env bash
# Author:Decarnelle Samuel

# Detect Linux distribution and enumerate installed package managers.
# Works on most Linux distros and containers. No root required.

set -euo pipefail

# ---------- helpers ----------
have() { command -v -- "$1" >/dev/null 2>&1; }

# Read os-release with fallbacks
OS_RELEASE_FILE=""
for f in /etc/os-release /usr/lib/os-release; do
  if [ -r "$f" ]; then
    OS_RELEASE_FILE="$f"
    break
  fi
done

# Defaults in case /etc/os-release is missing (very minimal containers)
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
  # Fallback heuristics
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

# Environment hints (informational)
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

# ---------- virtualization detection (VM vs bare metal) ----------
detect_virtualization() {
  local virt_bin="" virt_out="" hv="unknown" detail="" vm="false" bare="false"

  # 1) systemd-detect-virt (no root; most reliable)
  if have systemd-detect-virt; then
    # --quiet returns 0 if a virt environment is detected
    if systemd-detect-virt --quiet; then
      virt_out="$(systemd-detect-virt 2>/dev/null || true)"
      case "$virt_out" in
      kvm | qemu)
        hv="kvm"
        detail="KVM (QEMU)"
        vm="true"
        ;;
      vmware)
        hv="vmware"
        detail="VMware"
        vm="true"
        ;;
      oracle | virtualbox)
        hv="virtualbox"
        detail="VirtualBox"
        vm="true"
        ;;
      microsoft | hyperv)
        hv="hyperv"
        detail="Microsoft Hyper-V"
        vm="true"
        ;;
      xen)
        hv="xen"
        detail="Xen"
        vm="true"
        ;;
      parallels)
        hv="parallels"
        detail="Parallels"
        vm="true"
        ;;
      bhyve)
        hv="bhyve"
        detail="bhyve"
        vm="true"
        ;;
      zvm)
        hv="zvm"
        detail="IBM z/VM"
        vm="true"
        ;;
      apple)
        hv="apple"
        detail="Apple Virtualization"
        vm="true"
        ;;
      uml)
        hv="uml"
        detail="User-Mode Linux"
        vm="true"
        ;;
      # Containers/WSL are not considered "VM=true"
      docker | podman | lxc | lxd | openvz | systemd-nspawn) vm="false" ;;
      wsl) vm="false" ;;
      none | bare-metal) vm="false" ;;
      *)
        hv="unknown"
        detail="$virt_out"
        vm="true"
        ;;
      esac
    fi
  fi

  # 2) DMI sysfs heuristics (no root)
  if [ "$vm" = "false" ]; then
    for f in /sys/class/dmi/id/product_name /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/board_vendor /sys/class/dmi/id/bios_vendor; do
      [ -r "$f" ] || continue
      val="$(tr -d '\0' <"$f" | tr '[:upper:]' '[:lower:]')"
      case "$val" in
      *kvm* | *qemu*)
        hv="kvm"
        detail="KVM (QEMU)"
        vm="true"
        ;;
      *vmware*)
        hv="vmware"
        detail="VMware"
        vm="true"
        ;;
      *virtualbox* | *innotek* | *oracle*)
        hv="virtualbox"
        detail="VirtualBox"
        vm="true"
        ;;
      *microsoft* | *hyper-v*)
        hv="hyperv"
        detail="Microsoft Hyper-V"
        vm="true"
        ;;
      *xen*)
        hv="xen"
        detail="Xen"
        vm="true"
        ;;
      *parallels*)
        hv="parallels"
        detail="Parallels"
        vm="true"
        ;;
      *bhyve*)
        hv="bhyve"
        detail="bhyve"
        vm="true"
        ;;
      *google*compute*engine*)
        hv="kvm"
        detail="GCE (KVM)"
        vm="true"
        ;;
      *amazon*ec2* | *amazon* | *ec2*)
        hv="kvm"
        detail="Amazon EC2 (KVM)"
        vm="true"
        ;;
      *openstack*)
        hv="kvm"
        detail="OpenStack (KVM)"
        vm="true"
        ;;
      esac
      [ "$vm" = "true" ] && break
    done
  fi

  # 3) CPU hints (no root)
  if [ "$vm" = "false" ]; then
    if lscpu 2>/dev/null | grep -qi 'Hypervisor vendor'; then
      vm="true"
      hv_vendor="$(lscpu | awk -F: '/Hypervisor vendor/ {gsub(/^[ \t]+/,"",$2); print tolower($2)}')"
      case "$hv_vendor" in
      *kvm* | *qemu*)
        hv="kvm"
        detail="KVM (QEMU)"
        ;;
      *vmware*)
        hv="vmware"
        detail="VMware"
        ;;
      *microsoft* | *hyper-v*)
        hv="hyperv"
        detail="Microsoft Hyper-V"
        ;;
      *xen*)
        hv="xen"
        detail="Xen"
        ;;
      *virtualbox* | *oracle*)
        hv="virtualbox"
        detail="VirtualBox"
        ;;
      *parallels*)
        hv="parallels"
        detail="Parallels"
        ;;
      *)
        hv="unknown"
        detail="$hv_vendor"
        ;;
      esac
    elif grep -qE '^flags.*\bhypervisor\b' /proc/cpuinfo 2>/dev/null; then
      # Hypervisor flag set, but vendor unknown
      vm="true"
      hv="unknown"
      detail="CPU hypervisor flag present"
    fi
  fi

  # 4) dmidecode (needs root; optional fallback)
  if [ "$vm" = "false" ] && have dmidecode; then
    if sudo -n true 2>/dev/null; then
      dmi="$(sudo dmidecode -s system-manufacturer -s system-product-name 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
      case "$dmi" in
      *kvm* | *qemu*)
        hv="kvm"
        detail="KVM (QEMU)"
        vm="true"
        ;;
      *vmware*)
        hv="vmware"
        detail="VMware"
        vm="true"
        ;;
      *virtualbox* | *oracle*)
        hv="virtualbox"
        detail="VirtualBox"
        vm="true"
        ;;
      *microsoft* | *hyper-v*)
        hv="hyperv"
        detail="Microsoft Hyper-V"
        vm="true"
        ;;
      *xen*)
        hv="xen"
        detail="Xen"
        vm="true"
        ;;
      *parallels*)
        hv="parallels"
        detail="Parallels"
        vm="true"
        ;;
      esac
    fi
  fi

  # Finalize booleans
  # Treat containers and WSL as not-VM for this flag (you already have dedicated flags)
  if [ "$IS_CONTAINER" = "true" ] || [ "$IS_WSL" = "true" ]; then
    vm="false"
  fi

  if [ "$vm" = "true" ]; then
    BareMetal="false"
    VM="true"
    Hypervisor="$hv"
    VirtDetail="${detail:-$hv}"
  else
    BareMetal="true"
    VM="false"
    Hypervisor="none"
    VirtDetail="Bare metal"
  fi
}

# Invoke detection
detect_virtualization

# ---------- package manager catalog ----------
# We include native managers, helper/AUR tools, and universal managers.
# Order roughly by ecosystem.
declare -A PM_DESC=(
  # Debian/Ubuntu
  [apt]="Debian/Ubuntu package manager"
  [apt - get]="Low-level apt frontend"
  [aptitude]="NCurses apt frontend"
  [dpkg]="Debian package database tool"

  # Fedora/RHEL/CentOS/Mageia/OpenSUSE (RPM family)
  [dnf]="Fedora/RHEL modern RPM manager"
  [yum]="Legacy RPM manager"
  [microdnf]="Minimal DNF (containers)"
  [tdnf]="Tiny DNF (VMware Photon)"
  [zypper]="openSUSE package manager"
  [rpm]="RPM database tool"
  [rpm - ostree]="OSTree-managed RPMs"

  # Arch/Manjaro/EndeavourOS (Pacman family)
  [pacman]="Arch package manager"
  [yay]="AUR helper"
  [paru]="AUR helper"
  [trizen]="AUR helper"
  [pikaur]="AUR helper"

  # Alpine
  [apk]="Alpine package manager"

  # Gentoo
  [emerge]="Gentoo Portage manager"
  [equery]="Gentoo Portage query (gentoolkit)"

  # Void
  [xbps - install]="Void XBPS installer"
  [xbps - query]="Void XBPS query"

  # Slackware
  [slackpkg]="Slackware pkg tool"
  [installpkg]="Slackware install tool"
  [removepkg]="Slackware remove tool"
  [upgradepkg]="Slackware upgrade tool"

  # Solus
  [eopkg]="Solus package manager"

  # Mageia/ROSA (legacy)
  [urpmi]="Mandriva/Mageia legacy tool"

  # Clear Linux
  [swupd]="Clear Linux updater"

  # OpenWrt
  [opkg]="OpenWrt package manager"

  # Universal / extra ecosystems
  [nix]="Nix package manager"
  [nix - env]="Nix user env tool"
  [guix]="GNU Guix package manager"
  [snap]="Canonical Snap"
  [flatpak]="Flatpak apps"
)

# Build a list of managers present in PATH
present_managers=()
for pm in "${!PM_DESC[@]}"; do
  if have "$pm"; then
    present_managers+=("$pm")
  fi
done

# Sort managers for stable output
if have sort; then
  IFS=$'\n' read -r -d '' -a present_managers < <(printf '%s\n' "${present_managers[@]}" | sort && printf '\0')
fi

# ---------- pretty outputs ----------
OUTPUT_MODE="${1:-kv}" # kv or json

# Compose a useful "Distribution" label
DIST_LABEL="$DIST_PRETTY"
if [ -n "$DIST_VERSION" ] && [[ "$DIST_PRETTY" != *"$DIST_VERSION"* ]]; then
  DIST_LABEL="$DIST_PRETTY $DIST_VERSION"
fi

# Key=Value output (default)
if [ "$OUTPUT_MODE" = "kv" ]; then
  echo "Distribution=${DIST_LABEL}"
  echo "ID=${DIST_ID}"
  [ -n "$DIST_ID_LIKE" ] && echo "ID_LIKE=${DIST_ID_LIKE}"
  echo "Package-Managers=$(printf '%s' "${present_managers[*]:-none}" | sed 's/ /, /g')"
  echo "OSTree=${IS_OSTREE}"
  echo "WSL=${IS_WSL}"
  echo "Container=${IS_CONTAINER}"
  echo "VM=${VM}"
  echo "BareMetal=${BareMetal}"
  echo "Hypervisor=${Hypervisor}"
  echo "VirtDetail=${VirtDetail}"
  exit 0
fi

# JSON output (machine-readable)
if [ "$OUTPUT_MODE" = "json" ]; then
  # Minimal JSON without jq
  printf '{'
  printf '"Distribution":%q,' "$DIST_LABEL"
  printf '"ID":%q,' "$DIST_ID"
  printf '"ID_LIKE":%q,' "$DIST_ID_LIKE"
  printf '"OSTree":%q,' "$IS_OSTREE"
  printf '"WSL":%q,' "$IS_WSL"
  printf '"Container":%q,' "$IS_CONTAINER"
  printf '"BareMetal":%q,' "$BareMetal"
  printf '"Hypervisor":%q,' "$Hypervisor"
  printf '"VirtDetail":%q,' "$VirtDetail"
  printf '"Package-Managers":['
  if [ "${#present_managers[@]}" -gt 0 ]; then
    for i in "${!present_managers[@]}"; do
      printf '%q' "${present_managers[$i]}"
      [ "$i" -lt $((${#present_managers[@]} - 1)) ] && printf ','
    done
  fi
  printf ']}\n'
  exit 0
fi

echo "Unknown output mode: $OUTPUT_MODE" >&2
exit 2
