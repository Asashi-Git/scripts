#!/bin/bash
# crash-monitor-n150.sh - Optimized for Intel N150 systems
LOG_FILE="/var/log/crash-debug/system-monitor.log"
mkdir -p /var/log/crash-debug

# Thermal monitoring function
get_thermal_info() {
  echo "=== Thermal Information ==="
  if command -v sensors >/dev/null 2>&1; then
    sensors
    # Extract temperature values for threshold checking
    temp_values=$(sensors | grep -E "Core|Package" | awk '{print $3}' | tr -d '+°C')
    for temp in $temp_values; do
      if (($(echo "$temp > 85" | bc -l))); then
        echo "WARNING: High temperature detected: ${temp}°C"
      fi
      if (($(echo "$temp > 95" | bc -l))); then
        echo "CRITICAL: Very high temperature: ${temp}°C - System may throttle"
      fi
    done
  else
    # Fallback for raw thermal zone reading
    find /sys/class/thermal/thermal_zone*/temp -type f 2>/dev/null | while read -r temp_file; do
      if [ -r "$temp_file" ]; then
        temp_raw=$(cat "$temp_file")
        temp_c=$((temp_raw / 1000))
        zone=$(basename "$(dirname "$temp_file")")
        echo "$zone: ${temp_c}°C"
        if [ "$temp_c" -gt 85 ]; then
          echo "WARNING: $zone high temperature: ${temp_c}°C"
        fi
      fi
    done
  fi
  echo ""
}

# CPU frequency and throttling
get_cpu_info() {
  echo "=== CPU Information ==="
  echo "CPU Frequency:"
  cat /proc/cpuinfo | grep "cpu MHz" | head -4
  echo ""
  echo "CPU Governor:"
  cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null || echo "No cpufreq info available"
  echo ""
  echo "Load Average:"
  uptime
  echo ""
}

# Memory analysis for low-memory systems
get_memory_detailed() {
  echo "=== Detailed Memory Information ==="
  free -h
  echo ""
  echo "Memory pressure:"
  cat /proc/pressure/memory 2>/dev/null || echo "No PSI available"
  echo ""
  echo "OOM events:"
  dmesg | grep -i "killed process" | tail -5 || echo "No recent OOM events"
  echo ""
}

# I/O monitoring for encrypted drives
get_io_detailed() {
  echo "=== I/O Information ==="
  if command -v iostat >/dev/null 2>&1; then
    iostat -x 1 1 | tail -n +4
  else
    echo "Block device stats:"
    cat /proc/diskstats | head -10
  fi
  echo ""
  echo "Mount points and usage:"
  df -h | grep -E "(Filesystem|/dev|tmpfs)"
  echo ""
}

# LUKS specific monitoring
get_luks_info() {
  echo "=== LUKS/Encryption Status ==="
  ls /dev/mapper/ | grep -v control | while read -r device; do
    if [ -n "$device" ]; then
      echo "Device: $device"
      cryptsetup status "$device" 2>/dev/null || echo "  Status: Not accessible or not LUKS"
    fi
  done
  echo ""
}

# Network monitoring for your VLAN setup
get_network_info() {
  echo "=== Network Information ==="
  ip addr show | grep -E "(inet|state UP|state DOWN)" | head -10
  echo ""
  echo "Active connections:"
  ss -tuln | head -10
  echo ""
}

# Main monitoring loop
while true; do
  {
    echo "========================================="
    echo "=== System Monitor - $(date) ==="
    echo "========================================="

    get_thermal_info
    get_cpu_info
    get_memory_detailed
    get_io_detailed
    get_luks_info
    get_network_info

    echo "=== Top Processes (CPU) ==="
    ps aux --sort=-%cpu | head -8
    echo ""

    echo "=== Top Processes (Memory) ==="
    ps aux --sort=-%mem | head -8
    echo ""

    echo "=== Recent Kernel Messages ==="
    dmesg | tail -10
    echo ""

    echo "=== System Journal Errors ==="
    journalctl -p err --since "1 minute ago" --no-pager -q || echo "No recent errors"
    echo ""

    echo "========================================="
    echo ""
  } >>"$LOG_FILE"

  sleep 60 # Reduced to 60 seconds for better crash detection
done
