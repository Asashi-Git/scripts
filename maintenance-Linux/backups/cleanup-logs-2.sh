#!/usr/bin/env bash
# cleanup_logs.sh — filename-date based retention + pacman/yay cache (Arch)
# Requires: bash, GNU date, find, paccache (from pacman-contrib, optional)
# Preview (no deletion, verbose):
# sudo /usr/local/bin/cleanup_logs.sh --dry-run -v
# Real run:
# sudo /usr/local/bin/cleanup_logs.sh
# Aggressive caches:
# sudo /usr/local/bin/cleanup_logs.sh --full
# sudo pacman -S pacman-contrib
# sudo pacman -S inetutils
# To see the output :
# sudo tail -n 50 /var/log/cleanup_logs

set -euo pipefail

# ---------------- Config ----------------
LOG_FILE="/var/log/cleanup.log"
BACKUP_DIR="/var/log/backup"
RETENTION_DAYS=30
LOCK_FILE="/run/cleanup_logs.lock"

DRYRUN=false
VERBOSE=false
FULL=false

# ---------------- Helpers ----------------
ts() { date +"%Y-%m-%d %H:%M:%S%z"; }
log() { printf "[%s] %s\n" "$(ts)" "$*" | tee -a "$LOG_FILE" >/dev/null; }

usage() {
  cat <<EOF
Usage: sudo $0 [-n|--dry-run] [-v|--verbose] [--full]
  -n, --dry-run   Show what would be deleted (no changes)
  -v, --verbose   More log details
  --full          Aggressive cache cleanup (pacman -Scc; yay -Scc)
EOF
}

# ---------------- Args ----------------
while [[ $# -gt 0 ]]; do
  case "$1" in
  -n | --dry-run)
    DRYRUN=true
    shift
    ;;
  -v | --verbose)
    VERBOSE=true
    shift
    ;;
  --full)
    FULL=true
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown arg: $1"
    usage
    exit 2
    ;;
  esac
done

# ---------------- Prep ----------------
umask 027
touch "$LOG_FILE" 2>/dev/null || true
exec > >(tee -a "$LOG_FILE") 2>&1

if [[ $EUID -ne 0 ]]; then
  log "ERROR: Run as root (sudo)."
  exit 1
fi

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "Another cleanup is running (lock: $LOCK_FILE). Exiting."
  exit 0
fi

log "=== Cleanup start (host=$(hostname)) ==="
log "Options: DRYRUN=$DRYRUN VERBOSE=$VERBOSE FULL=$FULL"
log "Retention: ${RETENTION_DAYS} days; Source dir: $BACKUP_DIR"

# ---------------- Step 1: delete by filename date ----------------
delete_by_filename_date() {
  local dir="$1"
  local cutoff_days="$2"
  local today_epoch
  today_epoch=$(date +%s)

  if [[ ! -d "$dir" ]]; then
    log "Directory not found: $dir (skip)"
    return 0
  fi

  shopt -s nullglob
  local files=("$dir"/backup-*-????????.tar.gz)
  if ((${#files[@]} == 0)); then
    $VERBOSE && log "No matching backups in $dir"
    return 0
  fi

  for f in "${files[@]}"; do
    local base yyyymmdd y m d file_epoch age_days
    base=$(basename -- "$f")
    # Extract trailing YYYYMMDD before .tar.gz
    yyyymmdd="${base%.tar.gz}"
    yyyymmdd="${yyyymmdd##*-}"

    # Validate YYYYMMDD and compute epoch
    if [[ "$yyyymmdd" =~ ^[0-9]{8}$ ]] &&
      file_epoch=$(date -d "${yyyymmdd:0:4}-${yyyymmdd:4:2}-${yyyymmdd:6:2}" +%s 2>/dev/null); then
      age_days=$(((today_epoch - file_epoch) / 86400))
      if ((age_days > cutoff_days)); then
        if $DRYRUN; then
          log "(dry-run) delete $f (age ${age_days}d; date=$yyyymmdd)"
        else
          log "delete $f (age ${age_days}d; date=$yyyymmdd)"
          rm -f -- "$f"
        fi
      else
        $VERBOSE && log "keep $f (age ${age_days}d; date=$yyyymmdd)"
      fi
    else
      $VERBOSE && log "skip (unparsable date): $f"
    fi
  done
}

log "Deleting backups based on filename date pattern: backup-<name>-YYYYMMDD.tar.gz"
delete_by_filename_date "$BACKUP_DIR" "$RETENTION_DAYS"

# ---------------- Step 2: pacman/yay cache ----------------
clean_package_caches() {
  if command -v paccache >/dev/null 2>&1; then
    if $FULL; then
      # Keep 0 versions, remove uninstalled packages
      $DRYRUN && log "(dry-run) paccache --remove --uninstalled --keep 0" ||
        {
          log "Running: paccache --remove --uninstalled --keep 0"
          paccache --remove --uninstalled --keep 0
        }
      $DRYRUN && log "(dry-run) paccache --remove --keep 0" ||
        {
          log "Running: paccache --remove --keep 0"
          paccache --remove --keep 0
        }
    else
      # Sensible default: keep 3 versions, drop uninstalled
      $DRYRUN && log "(dry-run) paccache --remove --uninstalled --keep 3" ||
        {
          log "Running: paccache --remove --uninstalled --keep 3"
          paccache --remove --uninstalled --keep 3
        }
      $DRYRUN && log "(dry-run) paccache --remove --keep 3" ||
        {
          log "Running: paccache --remove --keep 3"
          paccache --remove --keep 3
        }
    fi
  else
    log "paccache not found (install pacman-contrib). Skipping pacman cache trim."
  fi

  if command -v yay >/dev/null 2>&1; then
    if $FULL; then
      $DRYRUN && log "(dry-run) yay -Scc --noconfirm" ||
        {
          log "Running: yay -Scc"
          yay -Scc --noconfirm
        }
    else
      # yay has no fine-grained keep count; -Sc clears old packages, -Scc clears all
      $DRYRUN && log "(dry-run) yay -Sc --noconfirm" ||
        {
          log "Running: yay -Sc"
          yay -Sc --noconfirm
        }
    fi
  else
    $VERBOSE && log "yay not found. Skipping AUR cache cleanup."
  fi
}

clean_package_caches

log "=== Cleanup end ==="
exit 0
