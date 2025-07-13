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
FORCE_RUN=false
FREQ="daily"  # default

# Parse args
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --now|--force) FORCE_RUN=true ;;
    --hourly) FREQ="hourly" ;;
    --6h)     FREQ="6h" ;;
    --daily)  FREQ="daily" ;;
    --weekly) FREQ="weekly" ;;
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

### 6. Skip scheduling if --now or --force passed
if $FORCE_RUN; then
  log "⚡ Manual run triggered: skipping schedule setup."
  exit 0
fi

### 7. Schedule task based on frequency
log "🕒 Scheduling telemetry ($FREQ)..."
if command -v systemctl >/dev/null && [ -d /etc/systemd/system ]; then
  cat <<EOF > /etc/systemd/system/alpine_cronjobs.service
[Unit]
Description=Alpine Cronjobs (Telemetry + Health)

[Service]
Type=oneshot
ExecStart=/root/alpine_cronjobs.sh
EOF

  TIMER_PATH="/etc/systemd/system/alpine_cronjobs.timer"

  case "$FREQ" in
    hourly)
      TIMER_CONTENT="[Timer]\nOnBootSec=5min\nOnUnitActiveSec=1h\nPersistent=true" ;;
    6h)
      TIMER_CONTENT="[Timer]\nOnBootSec=10min\nOnUnitActiveSec=6h\nPersistent=true" ;;
    daily)
      TIMER_CONTENT="[Timer]\nOnBootSec=10min\nOnUnitActiveSec=1d\nPersistent=true" ;;
    weekly)
      TIMER_CONTENT="[Timer]\nOnCalendar=weekly\nPersistent=true" ;;
  esac

  cat <<EOF > "$TIMER_PATH"
[Unit]
Description=Run alpine_cronjobs.sh ($FREQ)

$TIMER_CONTENT

[Install]
WantedBy=timers.target
EOF

  run "systemctl daemon-reexec"
  run "systemctl daemon-reload"
  run "systemctl enable --now alpine_cronjobs.timer"
else
  log "🌀 Using cron fallback"
  CRON_EXPR="0 4 * * *"  # default daily
  case "$FREQ" in
    hourly) CRON_EXPR="0 * * * *" ;;
    6h)     CRON_EXPR="0 */6 * * *" ;;
    weekly) CRON_EXPR="0 4 * * 0" ;;
  esac

  # Avoid duplicate entries
  (crontab -l 2>/dev/null | grep -v alpine_cronjobs.sh; echo "$CRON_EXPR /root/alpine_cronjobs.sh") | crontab -
fi

log "✅ alpine_cronjobs.sh completed."
