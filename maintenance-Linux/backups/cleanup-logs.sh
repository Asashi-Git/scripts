#!/usr/bin/env bash
# cleanup_logs.sh — Maintain logs and caches on Arch Linux
# Version: 1.0
#
# Creator: Decarnelle Samuel
#
# Usage: sudo /usr/local/bin/cleanup_logs.sh [-n|--dry-run] [-v] [--full]
# Dry run (no deletions):
# sudo /usr/local/bin/cleanup_logs.sh --dry-run -v
# Real run:
# sudo /usr/local/bin/cleanup_logs.sh -v
# Aggressive cleanup (empties caches):
# sudo /usr/local/bin/cleanup_logs.sh --full
#
# - Deletes files older than 30 days in /var/log/backup
# - Cleans pacman/yay caches
# - Logs => /var/log/cleanup.log
#
# Suggested dependency:
#   pacman-contrib (for paccache)

set -euo pipefail

# --------- Config ----------
LOG_FILE="/var/log/cleanup.log"
BACKUP_DIR="/var/log/backup"
RETENTION_DAYS=30
LOCK_FILE="/run/cleanup_logs.lock"

# Behavior flags
DRYRUN=false
VERBOSE=false
FULL=false

# --------- Helpers ----------
ts() { date +"%Y-%m-%d %H:%M:%S%z"; }

log() {
  printf "[%s] %s\n" "$(ts)" "$*" | tee -a "$LOG_FILE" >/dev/null
}

run() {
  if $DRYRUN; then
    log "(dry-run) $*"
  else
    $VERBOSE && log "EXEC: $*"
    eval "$@"
  fi
}

usage() {
  cat <<EOF
Usage: $0 [-n|--dry-run] [-v|--verbose] [--full]
  -n, --dry-run   Show what would be done without deleting anything
  -v, --verbose   More details in the log
  --full          Aggressive cache cleanup (-Scc / keep 0 versions)
EOF
}

# --------- Parse args ----------
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

# --------- Environment prep ----------
umask 027

# Ensure log file exists (might fail if not root; that's fine until we check EUID)
touch "$LOG_FILE" 2>/dev/null || true

# Redirect stdout/stderr to console + log (timestamps are added by log())
exec > >(awk '{print}' | tee -a "$LOG_FILE") 2>&1

# Root check
if [[ $EUID -ne 0 ]]; then
  log "ERROR: run this script as root (sudo)."
  exit 1
fi

# Single-instance lock
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "Another cleanup is already running (lock: $LOCK_FILE)."
  exit 0
fi

log "=== Cleanup start — host=$(hostname) ==="
log "Options: DRYRUN=$DRYRUN VERBOSE=$VERBOSE FULL=$FULL"

# --------- Step 1: delete old backup logs ----------
if [[ -d "$BACKUP_DIR" ]]; then
  log "Deleting files > ${RETENTION_DAYS} days in $BACKUP_DIR"
  FIND_EXPR="-type f ( -name '*.log' -o -name '*.log.*' -o -name '*.gz' -o -name '*.xz' -o -name '*.bz2' ) -mtime +$RETENTION_DAYS -print"
  $VERBOSE && run "find '$BACKUP_DIR' $FIND_EXPR -exec ls -lh {} +"
  if $DRYRUN; then
    run "find '$BACKUP_DIR' $FIND_EXPR"
  else
    run "find '$BACKUP_DIR' -type f \\( -name '*.log' -o -name '*.log.*' -o -name '*.gz' -o -name '*.xz' -o -name '*.bz2' \\) -mtime +$RETENTION_DAYS -print -delete"
  fi
else
  log "Info: $BACKUP_DIR does not exist, skipping."
fi

# --------- Step 2: pacman cache cleanup ----------
log "Cleaning pacman cache"
if command -v paccache >/dev/null 2>&1; then
  if $FULL; then
    run "paccache -r -k0" # keep 0 package versions
  else
    run "paccache -r" # default: keep 3 versions
  fi
else
  log "Notice: paccache not found. Install 'pacman-contrib' for finer control."
  if $FULL; then
    run "pacman -Scc --noconfirm"
  else
    run "pacman -Sc --noconfirm"
  fi
fi

# --------- Step 3: yay cache cleanup ----------
if command -v yay >/dev/null 2>&1; then
  log "Cleaning yay cache"
  if $FULL; then
    run "yay -Scc --noconfirm"
  else
    run "yay -Sc --noconfirm"
  fi
else
  log "Info: yay not installed, skipping."
fi

log "=== Cleanup finished ==="
exit 0
