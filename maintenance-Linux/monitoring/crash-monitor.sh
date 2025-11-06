#!/usr/bin/env bash
# /usr/local/bin/crash-monitor.sh
# crash-monitor.sh - Flexible, hardware-agnostic monitor for Arch Linux
# Auteur: Samuel Decarnelle
# Dépendances optionnelles auto-détectées: lm_sensors, jq, sysstat (iostat), smartmontools, ethtool, upower, nvidia-smi
# sudo pacman -S --needed lm_sensors jq sysstat smartmontools ethtool upower
set -Eeuo pipefail

CONFIG_FILE="/etc/crash-monitor.conf"

# Valeurs par défaut
INTERVAL=60
JOURNAL_WINDOW="1 min"
TEMP_WARN=85
TEMP_CRIT=95
TOP_N=8
MODULES="thermal,cpu,mem,io,fs,luks,net,battery,gpu,top,dmesg,journal"
LOG_DIR="/var/log/crash-debug"
LOG_FILE="$LOG_DIR/system-monitor.log"
MAX_LOG_SIZE_MIB=50
ROTATIONS=3

# Charger config si présente
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
chmod 640 "$LOG_FILE"

LOCK_FILE="/run/crash-monitor.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "$(date '+%F %T%z') [WARN] Instance déjà en cours, abandon." >>"$LOG_FILE"
  exit 0
fi

timestamp() { date '+%F %T%z'; }

log_section() {
  printf "\n=========================================\n=== %s - %s ===\n=========================================\n" "$1" "$(timestamp)"
}

rotate_if_needed() {
  [[ "$MAX_LOG_SIZE_MIB" -gt 0 ]] || return 0
  local size_mib
  size_mib=$(du -m "$LOG_FILE" | awk '{print $1}')
  if [[ "$size_mib" -ge "$MAX_LOG_SIZE_MIB" ]]; then
    for ((i = ROTATIONS - 1; i >= 1; i--)); do
      [[ -f "${LOG_FILE}.${i}" ]] && mv -f "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))" || true
    done
    cp -f "$LOG_FILE" "${LOG_FILE}.1" || true
    : >"$LOG_FILE"
    echo "$(timestamp) [INFO] Rotation simple du journal (taille ${size_mib}MiB)." >>"$LOG_FILE"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }
module_enabled() { [[ ",$MODULES," == *",$1,"* ]]; }

# -------- Thermal (CPU && autres capteurs) --------
section_thermal() {
  echo "=== Thermal Information ==="
  if have sensors; then
    if have jq && sensors -j >/dev/null 2>&1; then
      # Format JSON pour parsing fiable
      sensors -j | jq -r '
        to_entries[] as $chip |
        ($chip.key) as $name |
        $chip.value | to_entries[] |
        select(.key|test("temp[0-9]+_input")) |
        "\($name) \(.key): \(.value)°C"
      ' 2>/dev/null || sensors
      # Seuils: on recalcule depuis sensors texte si pas jq
    else
      sensors
    fi
    # Extraction robuste des températures numériques
    temps=$(sensors | awk '
      match($0, /([0-9]+(\.[0-9])?)°C/, a) { print a[1] }' | tr -d '+' || true)
  else
    # Fallback sysfs thermal zones
    while IFS= read -r tfile; do
      [[ -r "$tfile" ]] || continue
      local temp_c zone type
      temp_c=$(($(cat "$tfile") / 1000))
      zone=$(basename "$(dirname "$tfile")")
      type=$(cat "$(dirname "$tfile")/type" 2>/dev/null || echo "unknown")
      echo "$zone ($type): ${temp_c}°C"
      temps+=$'\n'"$temp_c"
    done < <(find /sys/class/thermal -maxdepth 2 -type f -name temp 2>/dev/null)
  fi

  if [[ -n "${temps:-}" ]]; then
    while IFS= read -r t; do
      [[ -z "$t" ]] && continue
      awk -v v="$t" -v w="$TEMP_WARN" -v c="$TEMP_CRIT" '
        BEGIN{
          if (v>c) printf("CRITICAL: Very high temperature: %.1f°C (>%d)\n", v, c);
          else if (v>w) printf("WARNING: High temperature: %.1f°C (>%d)\n", v, w);
        }'
    done <<<"$temps"
  fi
  echo ""
}

# -------- CPU (fréquence, gouverneur, charge) --------
section_cpu() {
  echo "=== CPU Information ==="
  # Fréquences par policy (plus portable que /proc/cpuinfo)
  if ls /sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq >/dev/null 2>&1; then
    for pol in /sys/devices/system/cpu/cpufreq/policy*; do
      [[ -r "$pol/scaling_cur_freq" ]] || continue
      cur=$(awk '{printf "%.2f", $1/1000/1000}' "$pol/scaling_cur_freq" 2>/dev/null)
      gov=$(cat "$pol/scaling_governor" 2>/dev/null || echo "n/a")
      min=$(awk '{printf "%.2f", $1/1000/1000}' "$pol/scaling_min_freq" 2>/dev/null)
      max=$(awk '{printf "%.2f", $1/1000/1000}' "$pol/scaling_max_freq" 2>/dev/null)
      echo "$(basename "$pol"): ${cur}GHz (min ${min}GHz / max ${max}GHz) governor=${gov}"
    done
  else
    # Fallback
    grep -m1 -E 'model name|Hardware' /proc/cpuinfo || true
    grep -E 'cpu MHz' /proc/cpuinfo | head -4 || true
  fi
  echo ""
  echo "Load Average:"
  uptime
  echo ""
  # Throttling intel/amd (si dispo)
  for f in /sys/devices/system/cpu/intel_pstate/status /sys/devices/system/cpu/cpufreq/boost; do
    [[ -r "$f" ]] && echo "$f: $(cat "$f")"
  done
  echo ""
}

# -------- Mémoire --------
section_mem() {
  echo "=== Detailed Memory Information ==="
  free -h
  echo ""
  echo "Memory pressure (PSI):"
  cat /proc/pressure/memory 2>/dev/null || echo "No PSI available"
  echo ""
  echo "Recent OOM events:"
  dmesg --ctime | grep -i "killed process" | tail -5 || echo "No recent OOM events"
  echo ""
}

# -------- I/O & Filesystems --------
section_io() {
  echo "=== I/O Information ==="
  if have iostat; then
    iostat -x 1 1 | awk 'NR>3' | sed -n '1,12p'
  else
    echo "Block device stats (top 10):"
    head -10 /proc/diskstats
  fi
  echo ""
}

section_fs() {
  echo "=== Mount points and usage ==="
  df -hT | awk 'NR==1 || /\/dev\/|tmpfs|zfs|btrfs/'
  echo ""
  # Btrfs/ZFS état rapide si présents
  if have btrfs; then
    btrfs filesystem usage -h / 2>/dev/null | sed -n '1,20p'
    echo ""
  fi
  if have zpool; then
    zpool status -x 2>/dev/null || true
    echo ""
  fi
  # SMART résumé (rapide) pour NVMe/SATA si smartctl
  if have smartctl; then
    echo "=== SMART quick health (NVMe/SATA) ==="
    for dev in /dev/nvme*n1 /dev/sd?; do
      [[ -b "$dev" ]] || continue
      smartctl -H "$dev" 2>/dev/null | awk -v d="$dev" 'BEGIN{ok=0}
        /SMART overall-health/ {print d": "$0; ok=1}
        /SMART Health Status/ {print d": "$0; ok=1}
        END{ if (ok==0) {} }'
    done
    echo ""
  fi
}

# -------- LUKS --------
section_luks() {
  echo "=== LUKS/Encryption Status ==="
  for dev in /dev/mapper/*; do
    [[ -e "$dev" ]] || continue
    [[ "$(basename "$dev")" == "control" ]] && continue
    echo "Device: $(basename "$dev")"
    cryptsetup status "$dev" 2>/dev/null || echo "  Status: Not accessible or not LUKS"
  done
  echo ""
}

# -------- Réseau --------
section_net() {
  echo "=== Network Information ==="
  ip -brief link | awk '{print $1, $2, $3}'
  echo ""
  ip -brief addr | awk '{print $0}'
  echo ""
  echo "Active sockets (summary):"
  ss -s || true
  echo ""
  echo "Listening ports (top 10):"
  ss -tuln | head -10 || true
  echo ""
  if have ethtool; then
    # Stats rapides sur interfaces up
    for ifc in $(ip -o link show up | awk -F': ' '{print $2}'); do
      echo "--- ethtool stats: $ifc ---"
      ethtool -S "$ifc" 2>/dev/null | sed -n '1,20p' || true
    done
    echo ""
  fi
}

# -------- Batterie (laptop) --------
section_battery() {
  shopt -s nullglob
  local bats=(/sys/class/power_supply/BAT*)
  [[ ${#bats[@]} -eq 0 ]] && return 0
  echo "=== Battery ==="
  for b in "${bats[@]}"; do
    echo "$(basename "$b"): status=$(cat "$b/status" 2>/dev/null || echo n/a) capacity=$(cat "$b/capacity" 2>/dev/null || echo n/a)%"
    [[ -f "$b/temp" ]] && echo "temp=$(awk '{printf "%.1f", $1/10}' "$b/temp")°C"
  done
  echo ""
}

# -------- GPU (NVIDIA/AMD/Intel) --------
section_gpu() {
  echo "=== GPU ==="
  if have nvidia-smi; then
    nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null || true
  fi
  # AMD/Intel via sensors (amdgpu/i915), fallback via sysfs
  if have sensors; then
    sensors | awk '/amdgpu|edge:|junction:|i915/ {print}'
  fi
  for t in /sys/class/drm/card*/device/hwmon/hwmon*/temp*_input; do
    [[ -r "$t" ]] || continue
    printf "%s: %.1f°C\n" "$(echo "$t" | sed 's|.*/card[0-9]/|card|;s|/.*||')" "$(awk '{print $1/1000}' "$t")"
  done
  echo ""
}

# -------- TOP processus --------
section_top() {
  echo "=== Top Processes (CPU) ==="
  ps axo pid,ppid,cmd,%cpu,%mem --sort=-%cpu | head -"$((TOP_N + 1))"
  echo ""
  echo "=== Top Processes (Memory) ==="
  ps axo pid,ppid,cmd,%cpu,%mem --sort=-%mem | head -"$((TOP_N + 1))"
  echo ""
}

# -------- dmesg et journal --------
section_dmesg() {
  echo "=== Recent Kernel Messages ==="
  dmesg --ctime | tail -10
  echo ""
}
section_journal() {
  echo "=== System Journal (errors since ${JOURNAL_WINDOW}) ==="
  journalctl -p err --since "${JOURNAL_WINDOW} ago" --no-pager -q || echo "No recent errors"
  echo ""
}

run_once() {
  log_section "System Monitor"
  module_enabled thermal && section_thermal
  module_enabled cpu && section_cpu
  module_enabled mem && section_mem
  module_enabled io && section_io
  module_enabled fs && section_fs
  module_enabled luks && section_luks
  module_enabled net && section_net
  module_enabled battery && section_battery
  module_enabled gpu && section_gpu
  module_enabled top && section_top
  module_enabled dmesg && section_dmesg
  module_enabled journal && section_journal
}

# --- CLI options: --once / --interval N ---
INTERVAL_FLAG="$INTERVAL"
if [[ "${1:-}" == "--once" ]]; then
  run_once >>"$LOG_FILE"
  exit 0
fi
if [[ "${1:-}" == "--interval" && -n "${2:-}" ]]; then
  INTERVAL_FLAG="$2"
fi

# Boucle principale
while true; do
  rotate_if_needed
  run_once >>"$LOG_FILE"
  sleep "$INTERVAL_FLAG"
done
