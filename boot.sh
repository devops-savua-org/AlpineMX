#!/bin/sh
set -euo pipefail
IFS=$'\n\t'

### Constants
STATUS_FILE="/root/bootstrap_status.json"
LOG_FILE="/var/log/boot.log"
STAGE_FLAGS=".baseline_done .hardening_done .monitoring_done .deploy_done"
REBOOT_FLAG="/root/.needs_reboot"
BOOTSTRAP="/root/bootstrap.sh"

log() {
  echo "[$(date -Iseconds)] [BOOT] $*" | tee -a "$LOG_FILE"
}

check_flag() {
  [ -f "/root/$1" ] && echo true || echo false
}

check_network() {
  ping -q -c1 1.1.1.1 >/dev/null 2>&1 && echo true || echo false
}

generate_json_status() {
  log "📄 Generating JSON status at $STATUS_FILE..."

  {
    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"baseline\": $(check_flag .baseline_done),"
    echo "  \"hardening\": $(check_flag .hardening_done),"
    echo "  \"monitoring\": $(check_flag .monitoring_done),"
    echo "  \"deploy\": $(check_flag .deploy_done),"
    echo "  \"reboot_required\": $(check_flag .needs_reboot),"
    echo "  \"network\": $(check_network)"
    echo "}"
  } > "$STATUS_FILE"
}

main() {
  log "🔁 Boot script started."

  generate_json_status

  if [ -f "$REBOOT_FLAG" ]; then
    log "⚠️  Reboot was pending — clearing flag and exiting for reboot."
    rm -f "$REBOOT_FLAG"
    exit 0
  fi

  log "📦 Handing control to bootstrap.sh..."
  "$BOOTSTRAP" --status-json "$STATUS_FILE"
}

main
