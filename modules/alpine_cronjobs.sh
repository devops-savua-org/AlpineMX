#!/bin/sh
set -euo pipefail
IFS=$'\n\t'

### Constants
SCRIPT_NAME="alpine_cronjobs.sh"
LOG_FILE="/root/os_bootstrap.log"
METADATA_ENCRYPTED_DIR="/root/Home/metadata_encrypted"
METADATA_FILE="/root/Home/metadata/telemetry.json"
ENCRYPTED_FILE="${METADATA_FILE}.gpg"
NETDATA_SYNC_SCRIPT="/usr/local/bin/sync_monitoring_config.sh"
DRY_RUN=false

# Parse --dry-run
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      echo "[DRY RUN] No changes will be made."
      ;;
  esac
done

log() {
  echo "[$(date -Iseconds)] [$SCRIPT_NAME] $*" | tee -a "$LOG_FILE"
}

run() {
  if $DRY_RUN; then
    echo "[DRY RUN] $*"
  else
    eval "$@" | tee -a "$LOG_FILE"
  fi
}

### 1. Check if public key exists
if [ ! -f "$METADATA_ENCRYPTED_DIR/public.gpg" ]; then
  log "❌ Public GPG key not found at $METADATA_ENCRYPTED_DIR/public.gpg"
  log "Please run generate_gpg_keypair.sh first."
  exit 1
fi

### 2. Netdata sync
if [ -x "$NETDATA_SYNC_SCRIPT" ]; then
  log "🔁 Running Netdata sync script..."
  run "$NETDATA_SYNC_SCRIPT"
else
  log "⚠️ Netdata sync script not found or not executable"
fi

### 3. Collect telemetry data
log "🧠 Collecting telemetry..."
HOSTNAME=$(hostname)
UPTIME=$(cut -d. -f1 /proc/uptime)
TIMESTAMP=$(date -Iseconds)

cat <<EOF > "$METADATA_FILE"
{
  "hostname": "$HOSTNAME",
  "uptime_seconds": "$UPTIME",
  "timestamp": "$TIMESTAMP"
}
EOF

### 4. Encrypt telemetry
log "🔐 Encrypting telemetry..."
run "gpg --yes --batch --output \"$ENCRYPTED_FILE\" --encrypt --recipient-file \"$METADATA_ENCRYPTED_DIR/public.gpg\" \"$METADATA_FILE\""

### 5. Health checks
log "💡 Checking services..."
for svc in osqueryd netdata wazuh-agent; do
  if pidof "$svc" >/dev/null 2>&1; then
    log "✅ $svc is running"
  else
    log "❌ $svc is not running — attempting restart"
    run "rc-service $svc restart || true"
  fi
done

### 6. Schedule task
log "🕒 Scheduling telemetry via systemd or cron..."
if command -v systemctl >/dev/null && [ -d /etc/systemd/system ]; then
  cat <<EOF > /etc/systemd/system/alpine_cronjobs.service
[Unit]
Description=Alpine Cronjobs (Telemetry + Health)

[Service]
Type=oneshot
ExecStart=/root/alpine_cronjobs.sh
EOF

  cat <<EOF > /etc/systemd/system/alpine_cronjobs.timer
[Unit]
Description=Run alpine_cronjobs.sh daily

[Timer]
OnBootSec=10min
OnUnitActiveSec=1d
Persistent=true

[Install]
WantedBy=timers.target
EOF

  run "systemctl daemon-reload"
  run "systemctl enable --now alpine_cronjobs.timer"
else
  log "🌀 Using cron fallback"
  (crontab -l 2>/dev/null; echo "0 4 * * * /root/alpine_cronjobs.sh") | crontab -
fi

log "✅ alpine_cronjobs.sh completed."
