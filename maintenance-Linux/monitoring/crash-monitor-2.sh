#!/usr/bin/env bash
# crash-monitor.sh - Flexible, hardware-agnostic system monitor for Arch Linux
# Author: Decarnelle Samuel
#
# Key features:
# - Auto-detect VM and adapt modules
# - Modular sections: thermal,cpu,mem,io,fs,luks,net,battery,gpu,top,dmesg,journal,vm
# - Graceful fallbacks when tools are missing
# - Thresholds for temperature warnings
# - Simple log rotation
# - Single-instance lock
#
# Optional config: /etc/crash-monitor.conf
# Example keys:
#   INTERVAL=60
#   JOURNAL_WINDOW="1 min"
#   TEMP_WARN=85
#   TEMP_CRIT=95
#   TOP_N=8
#   MODULES="thermal,cpu,mem,io,fs,luks,net,battery,gpu,top,dmesg,journal,vm"
#   LOG_DIR="/var/log/crash-debug"
#   LOG_FILE="/var/log/crash-debug/system-monitor.log"
#   MAX_LOG_SIZE_MIB=50
#   ROTATIONS=3

set -Eeuo pipefail

CONFIG_FILE="/etc/crash-monitor.conf"

# -------- Defaults --------
INTERVAL=60
RUN_ONCE=0
JOURNAL_WINDOW="1 min"
TEMP_WARN=85
TEMP_CRIT=95
TOP_N=8
MODULES="thermal,cpu,mem,io,fs,luks,net,battery,gpu,top,dmesg,journal,vm"
LOG_DIR="/var/log/crash-debug"
LOG_FILE="$LOG_DIR/system-monitor.log"
MAX_LOG_SIZE_MIB=50
ROTATIONS=3

# -------- Helpers --------
usage() {
  cat <<'USAGE'
crash-monitor.sh - flexible system monitor

Usage:
  crash-monitor.sh [--once] [--interval SECONDS] [--modules list] [--log FILE]
                   [--warn TEMP] [--crit TEMP]

Options:
  --once                  Run a single collection and exit
  --interval N           Interval in seconds between collections (default 60)
  --modules LIST         Comma-separated modules to enable
  --log FILE             Log file path (default /var/log/crash-debug/system-monitor.log)
  --warn TEMP            Temperature warn threshold in °C (default 85)
  --crit TEMP            Temperature critical threshold in °C (default 95)
  -h, --help            Show this help

Modules:
  thermal,cpu,mem,io,fs,luks,net,battery,gpu,top,dmesg,journal,vm
USAGE
}

have() { command -v "$1" >/dev/null 2>&1; }

timestamp() { date '+%F %T%z'; }

# -------- Parse CLI --------
while [[ $# -gt 0 ]]; do
  case "$1" in
  --once)
    RUN_ONCE=1
    shift
    ;;
  --interval)
    INTERVAL="${2:-60}"
    shift 2
    ;;
  --modules)
    MODULES="$2"
    shift 2
    ;;
  --log)
    LOG_FILE="$2"
    LOG_DIR="$(dirname "$LOG_FILE")"
    shift 2
    ;;
  --warn)
    TEMP_WARN="$2"
    shift 2
    ;;
  --crit)
    TEMP_CRIT="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    usage
    exit 1
    ;;
  esac
done

# -------- Load config (after CLI defaults; config can override) --------
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

# CLI should override config: reapply if flags were given (we can detect by env if needed).
# Keep it simple: precedence has already happened because we sourced after parsing CLI;
# if you prefer CLI > config, move 'source' above arg parsing.

# -------- Prepare logging & lock --------
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
chmod 640 "$LOG_FILE"

LOCK_FILE="/run/crash-monitor.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "$(timestamp) [WARN] Another instance is running. Exiting." >>"$LOG_FILE"
  exit 0
fi

log_section() {
  printf "\n=========================================\n=== %s - %s ===\n=========================================\n" "$1" "$(timestamp)" >>"$LOG_FILE"
}

rotate_if_needed() {
  [[ "${MAX_LOG_SIZE_MIB:-0}" -gt 0 ]] || return 0
  # du -m is not always portable; use bytes and convert
  local size_bytes
  size_bytes=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
  local max_bytes=$((MAX_LOG_SIZE_MIB * 1024 * 1024))
  if ((size_bytes > max_bytes)); then
    # simple rotate: .1..N
    for ((i = ROTATIONS - 1; i >= 1; i--)); do
      [[ -f "${LOG_FILE}.${i}" ]] && mv -f "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
    done
    [[ -f "${LOG_FILE}.1" ]] && mv -f "${LOG_FILE}.1" "${LOG_FILE}.2" 2>/dev/null || true
    cp -f "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || true
    : >"$LOG_FILE"
    echo "$(timestamp) [INFO] Log rotated (>${MAX_LOG_SIZE_MIB} MiB)" >>"$LOG_FILE"
  fi
}

module_enabled() {
  local m="$1"
  [[ ",${MODULES}," == *",${m},"* ]]
}

# -------- VM detection & module adjustments --------
is_vm() {
  if have systemd-detect-virt; then
    systemd-detect-virt --quiet && return 0 || return 1
  fi
  grep -qiE 'qemu|kvm|vmware|virtualbox|hyper-v' /sys/devices/virtual/dmi/id/* 2>/dev/null && return 0
  return 1
}

adjust_modules_for_vm() {
  is_vm || return 0
  local remove="thermal,battery,gpu"
  IFS=, read -r -a arr <<<"$MODULES"
  local out=()
  for m in "${arr[@]}"; do
    case ",$remove," in
    *,"$m",*) continue ;;
    *) out+=("$m") ;;
    esac
  done
  MODULES="$(
    IFS=,
    echo "${out[*]}"
  )"
  # ensure vm module
  [[ ",$MODULES," == *",vm,"* ]] || MODULES="$MODULES,vm"
}

adjust_modules_for_vm

# -------- Sections (modules) --------

section_thermal() {
  echo "=== Thermal Information ==="
  local printed=0

  # Try lm_sensors
  if have sensors; then
    # sensors returns 0 even if no chips; filter noisy "No sensors found!" to /dev/null
    local out
    if out=$(sensors 2>/dev/null) && [[ -n "$out" ]]; then
      echo "$out"
      printed=1
      # Threshold checks: parse all °C values
      # Accept forms like +45.0°C, 45.0°C
      local temps
      temps=$(printf "%s\n" "$out" | grep -Eo '(\+)?[0-9]+(\.[0-9]+)?°C' | tr -d '+°C')
      for t in $temps; do
        awk -v t="$t" -v w="$TEMP_WARN" -v c="$TEMP_CRIT" '
          BEGIN{
            if (t>c) printf "CRITICAL: High temperature: %.1f°C (>%d)\n", t, c;
            else if (t>w) printf "WARNING: High temperature: %.1f°C (>%d)\n", t, w;
          }'
      done
    fi
  fi

  # Fallback: sysfs thermal zones
  local found_sysfs=0
  while IFS= read -r tfile; do
    [[ -r "$tfile" ]] || continue
    local raw
    raw=$(cat "$tfile" 2>/dev/null || echo 0)
    # Some platforms expose milli-Celsius, others 0-255; assume mC and clamp sane
    local temp_c=$((raw / 1000))
    local zone dir type
    dir="$(dirname "$tfile")"
    zone=$(basename "$dir")
    type=$(cat "$dir/type" 2>/dev/null || echo "unknown")
    echo "$zone ($type): ${temp_c}°C"
    found_sysfs=1
    printed=1
    if ((temp_c > TEMP_CRIT)); then
      echo "CRITICAL: $zone very high temperature: ${temp_c}°C (>${TEMP_CRIT})"
    elif ((temp_c > TEMP_WARN)); then
      echo "WARNING: $zone high temperature: ${temp_c}°C (>${TEMP_WARN})"
    fi
  done < <(find /sys/class/thermal -maxdepth 2 -type f -name temp 2>/dev/null)

  if [[ $printed -eq 0 ]]; then
    echo "Thermal sensors: N/A on this system (likely a VM)."
  fi
  echo ""
}

section_cpu() {
  echo "=== CPU Information ==="
  # Frequencies (if exposed)
  if compgen -G "/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor" >/dev/null; then
    echo "CPU Governor(s):"
    paste -d' ' <(ls -1 /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | xargs -I{} basename "$(dirname "{}")") \
      <(for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do cat "$g"; done 2>/dev/null) | sed 's/^/  /'
  else
    echo "CPU Governor: N/A"
  fi

  echo ""
  echo "Load Average and Uptime:"
  uptime || true

  # Instant usage sample: user/sys/iowait/steal via mpstat or /proc/stat
  echo ""
  echo "CPU sample (1s):"
  if have mpstat; then
    mpstat 1 1 | awk 'NR==4 {printf "usr=%.1f%% sys=%.1f%% iowait=%.1f%% steal=%.1f%% idle=%.1f%%\n",$3,$5,$6,$8,$12}'
  else
    # crude /proc/stat delta
    read -r _ u n s iow w st gi _ </proc/stat
    t1=$((u + n + s + iow + w + st + gi))
    sleep 1
    read -r _ U N S IOW W ST GI _ </proc/stat
    t2=$((U + N + S + IOW + W + ST + GI))
    dt=$((t2 - t1))
    du=$((U - u))
    dn=$((N - n))
    ds=$((S - s))
    diow=$((IOW - iow))
    dst=$((ST - st))
    awk -v dt="$dt" -v du="$du" -v ds="$ds" -v diow="$diow" -v dst="$dst" '
      BEGIN{
        if (dt<=0){print "N/A"; exit}
        printf "usr=%.1f%% sys=%.1f%% iowait=%.1f%% steal=%.1f%%\n", 100*du/dt, 100*ds/dt, 100*diow/dt, 100*dst/dt
      }'
  fi
  echo ""
}

section_mem() {
  echo "=== Memory Information ==="
  free -h || true
  echo ""
  echo "Memory pressure (PSI):"
  if [[ -r /proc/pressure/memory ]]; then
    cat /proc/pressure/memory
  else
    echo "No PSI available"
  fi
  echo ""
  echo "Recent OOM kills:"
  dmesg --since "$(date -d '2 hours ago' '+%Y-%m-%d %H:%M:%S')" 2>/dev/null | grep -i "killed process" | tail -5 || echo "No recent OOM events"
  echo ""
}

section_io() {
  echo "=== I/O Information ==="
  if have iostat; then
    # Extended stats, 1s sample
    iostat -x 1 1 | sed -n '1,3p;/^Device/{:a;n;/^\s*$/q;p;ba}' || true
  else
    echo "Block device stats (top 10):"
    head -10 /proc/diskstats || true
  fi
  echo ""
}

section_fs() {
  echo "=== Filesystems and Usage ==="
  df -hT | awk 'NR==1 || /^\/dev\// || $2=="tmpfs" || $2=="zfs"' || true
  echo ""
  echo "Mount options:"
  mount | awk '{print $1,$3,$5,$6}' | sed 's/^/  /'
  echo ""
}

section_luks() {
  echo "=== LUKS/Encryption Status ==="
  if have cryptsetup; then
    ls /dev/mapper/ 2>/dev/null | grep -v '^control$' | while read -r dev; do
      [[ -n "$dev" ]] || continue
      echo "Device: $dev"
      cryptsetup status "/dev/mapper/$dev" 2>/dev/null || echo "  Status: Not LUKS or not accessible"
    done
  else
    echo "cryptsetup not installed."
  fi
  echo ""
}

section_net() {
  echo "=== Network Information ==="
  if have ip; then
    ip -br link | sed 's/^/  /'
    echo ""
    ip -br addr | sed 's/^/  /'
  else
    echo "ip(8) not available."
  fi
  echo ""
  echo "Active sockets (top 10):"
  if have ss; then
    ss -tuln | head -10
  else
    netstat -tuln 2>/dev/null | head -10 || echo "ss/netstat not available"
  fi
  echo ""
}

section_battery() {
  echo "=== Power/Battery ==="
  # Prefer upower if available; fallback to sysfs
  if have upower; then
    local bat
    bat=$(upower -e | grep -E 'battery|DisplayDevice' | head -1 || true)
    if [[ -n "$bat" ]]; then
      upower -i "$bat" | grep -E 'state|to full|to empty|percentage|time to' | sed 's/^/  /'
    else
      echo "No battery devices via upower."
    fi
  else
    # sysfs check
    if compgen -G "/sys/class/power_supply/BAT*/uevent" >/dev/null; then
      for f in /sys/class/power_supply/BAT*/uevent; do
        echo "Device: $(basename "$(dirname "$f")")"
        grep -E 'STATUS=|CAPACITY=|VOLTAGE_NOW=|CURRENT_NOW=' "$f" | sed 's/^/  /'
      done
    else
      echo "No battery found."
    fi
  fi
  echo ""
}

section_gpu() {
  echo "=== GPU ==="
  # NVIDIA
  if have nvidia-smi; then
    nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null |
      awk -F', ' '{printf "GPU: %s | Temp=%s°C | Util=%s | Mem=%s/%s\n",$1,$2,$3,$4,$5}'
  else
    # amdgpu temp via hwmon if available
    if ls /sys/class/drm/*/device/hwmon/*/temp1_input >/dev/null 2>&1; then
      for t in /sys/class/drm/*/device/hwmon/*/temp1_input; do
        local name
        name=$(basename "$(dirname "$t")")
        local c=$(($(cat "$t") / 1000))
        echo "GPU (hwmon:$name) Temp: ${c}°C"
      done
    else
      echo "No dedicated GPU telemetry available."
    fi
  fi
  echo ""
}

section_top() {
  echo "=== Top Processes (CPU) ==="
  ps aux --sort=-%cpu | head -"$((TOP_N + 1))" || true
  echo ""
  echo "=== Top Processes (Memory) ==="
  ps aux --sort=-%mem | head -"$((TOP_N + 1))" || true
  echo ""
}

section_dmesg() {
  echo "=== Recent Kernel Messages ==="
  dmesg | tail -50 || echo "No dmesg available"
  echo ""
}

section_journal() {
  echo "=== System Journal (errors, ${JOURNAL_WINDOW}) ==="
  if have journalctl; then
    journalctl -p err --since "$JOURNAL_WINDOW" --no-pager -q || echo "No recent errors"
  else
    echo "journalctl not available."
  fi
  echo ""
}

section_vm() {
  echo "=== Virtualization Metrics ==="
  if have systemd-detect-virt; then
    echo "Hypervisor: $(systemd-detect-virt 2>/dev/null || echo unknown)"
  fi

  # CPU iowait & steal (1s)
  if have mpstat; then
    mpstat 1 1 | awk 'NR==4 {printf "CPU: usr=%.1f%% sys=%.1f%% iowait=%.1f%% steal=%.1f%% idle=%.1f%%\n",$3,$5,$6,$8,$12}'
  else
    read -r _ u n s iow w st gi _ </proc/stat
    t1=$((u + n + s + iow + w + st + gi))
    sleep 1
    read -r _ U N S IOW W ST GI _ </proc/stat
    t2=$((U + N + S + IOW + W + ST + GI))
    dt=$((t2 - t1))
    diow=$((IOW - iow))
    dst=$((ST - st))
    awk -v dt="$dt" -v diow="$diow" -v dst="$dst" \
      'BEGIN{if (dt<=0){print "CPU approx: iowait=N/A steal=N/A"; exit}
             printf "CPU approx: iowait=%.1f%% steal=%.1f%%\n", 100*diow/dt, 100*dst/dt}'
  fi

  # Guest agent status
  if systemctl list-unit-files | grep -q '^qemu-guest-agent.service'; then
    echo "qemu-guest-agent: $(systemctl is-active qemu-guest-agent.service 2>/dev/null || echo unknown)"
  elif systemctl list-unit-files | grep -q '^vmtoolsd.service'; then
    echo "open-vm-tools: $(systemctl is-active vmtoolsd.service 2>/dev/null || echo unknown)"
  elif systemctl list-unit-files | grep -qi hyperv; then
    echo "hyperv-daemons: $(systemctl is-active hv_kvp_daemon.service 2>/dev/null || echo unknown)"
  fi

  # KSM stats if enabled
  for f in /sys/kernel/mm/ksm/run /sys/kernel/mm/ksm/pages_sharing; do
    [[ -r "$f" ]] && echo "KSM $(basename "$f"): $(cat "$f")"
  done
  echo ""
}

# -------- One collection --------
collect_once() {
  rotate_if_needed
  log_section "System Monitor"

  module_enabled thermal && section_thermal >>"$LOG_FILE" 2>&1
  module_enabled cpu && section_cpu >>"$LOG_FILE" 2>&1
  module_enabled mem && section_mem >>"$LOG_FILE" 2>&1
  module_enabled io && section_io >>"$LOG_FILE" 2>&1
  module_enabled fs && section_fs >>"$LOG_FILE" 2>&1
  module_enabled luks && section_luks >>"$LOG_FILE" 2>&1
  module_enabled net && section_net >>"$LOG_FILE" 2>&1
  module_enabled battery && section_battery >>"$LOG_FILE" 2>&1
  module_enabled gpu && section_gpu >>"$LOG_FILE" 2>&1
  module_enabled top && section_top >>"$LOG_FILE" 2>&1
  module_enabled dmesg && section_dmesg >>"$LOG_FILE" 2>&1
  module_enabled journal && section_journal >>"$LOG_FILE" 2>&1
  module_enabled vm && section_vm >>"$LOG_FILE" 2>&1

  echo "" >>"$LOG_FILE"
}

# -------- Main loop --------
if ((RUN_ONCE == 1)); then
  collect_once
else
  while :; do
    collect_once
    sleep "$INTERVAL"
  done
fi
