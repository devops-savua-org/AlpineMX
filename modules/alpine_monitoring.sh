#!/bin/sh
set -euo pipefail
IFS=$'\n\t'

### Constants
SCRIPT_NAME="alpine_monitoring.sh"
LOG_FILE="/root/os_bootstrap.log"
REBOOT_FLAG="/root/.needs_reboot"
METADATA_JSON="/root/Home/metadata/monitoring.json"
NETDATA_SYNC_GIST="https://gist.githubusercontent.com/devops-savua-org/9179fb1223d6e6f14e6d6dc4b8394dc3/raw/sync_monitoring_config.sh"
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

ask_install() {
  prompt="$1"
  default="$2"
  read -r -p "$prompt [y/N] " choice
  case "$choice" in
    y|Y ) echo "yes" ;;
    * ) echo "no" ;;
  esac
}

### 1. osquery setup
log "📦 Installing osquery..."
apk add --no-cache osquery

log "📁 Creating default osquery config..."
mkdir -p /etc/osquery
cat <<EOF > /etc/osquery/osquery.conf
{
  "options": {
    "disable_events": "false",
    "enable_monitor": "true",
    "audit_persist": "true",
    "logger_plugin": "filesystem",
    "logger_path": "/var/log/osquery",
    "config_plugin": "filesystem"
  },
  "schedule": {
    "processes": {
      "query": "SELECT pid, name, path FROM processes WHERE on_disk = 0;",
      "interval": 600
    },
    "users": {
      "query": "SELECT * FROM users WHERE shell NOT IN ('/sbin/nologin', '/usr/sbin/nologin');",
      "interval": 1800
    }
  }
}
EOF

chmod 640 /etc/osquery/osquery.conf
rc-update add osqueryd default
rc-service osqueryd restart

mkdir -p /etc/systemd/system/osqueryd.service.d
cat <<EOF > /etc/systemd/system/osqueryd.service.d/override.conf
[Service]
Restart=on-failure
RestartSec=5
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl restart osqueryd

### 2. logrotate
log "📁 Configuring logrotate for auth.log and audit.log..."
cat <<EOF > /etc/logrotate.d/security-logs
/var/log/auth.log /var/log/audit/audit.log {
  daily
  rotate 14
  compress
  delaycompress
  missingok
  notifempty
  create 0600 root root
  postrotate
    /etc/init.d/auditd restart >/dev/null 2>&1 || true
  endscript
}
EOF

logrotate --debug /etc/logrotate.d/security-logs

### 3. Monitoring optional components
if [ "$(ask_install 'Install Netdata Agent?' 'y')" = "yes" ]; then
  apk add --no-cache netdata
  rc-update add netdata default
  rc-service netdata start
fi

if [ "$(ask_install 'Install Wazuh Agent?' 'y')" = "yes" ]; then
  apk add --no-cache wazuh-agent || true
  rc-update add wazuh-agent default
  rc-service wazuh-agent start
fi

if [ "$(ask_install 'Install CrowdSec?' 'y')" = "yes" ]; then
  apk add --no-cache crowdsec || true
  rc-update add crowdsec default
  rc-service crowdsec start
fi

if [ "$(ask_install 'Enable syslog forwarding and webhook integration?' 'y')" = "yes" ]; then
  echo "*.* @logserver.example.com:514" >> /etc/rsyslog.conf
  rc-service rsyslog restart
fi

### 4. Netdata sync config
log "🌐 Injecting Netdata monitoring sync script..."
mkdir -p /usr/local/bin
wget -q $NETDATA_SYNC_GIST -O /usr/local/bin/sync_monitoring_config.sh
chmod +x /usr/local/bin/sync_monitoring_config.sh

cat <<EOF > /etc/systemd/system/sync_monitoring_config.service
[Unit]
Description=Sync Netdata config
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sync_monitoring_config.sh
EOF

cat <<EOF > /etc/systemd/system/sync_monitoring_config.timer
[Unit]
Description=Periodic Netdata config sync

[Timer]
OnBootSec=5min
OnUnitActiveSec=12h
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now sync_monitoring_config.timer

### 5. Metadata capture
log "🧠 Writing monitoring metadata..."
TS_IP=$(tailscale ip -4 2>/dev/null | head -n1)
HOSTNAME=$(hostname)
TAG=$(cat /etc/device_tag 2>/dev/null || echo "undefined")
TIMESTAMP=$(date -Iseconds)

mkdir -p "$(dirname "$METADATA_JSON")"
cat <<EOF > "$METADATA_JSON"
{
  "device_tag": "$TAG",
  "hostname": "$HOSTNAME",
  "tailscale_ip": "$TS_IP",
  "timestamp": "$TIMESTAMP"
}
EOF

### 6. Reboot trigger
log "⚠️ Monitoring setup complete — requesting reboot..."
touch "$REBOOT_FLAG"
