#!/bin/sh
set -euo pipefail
IFS=$'\n\t'

### Constants
SCRIPT_NAME="alpine_baseline.sh"
LOG_FILE="/root/os_bootstrap.log"
NEXT_SCRIPT="/root/bootstrap.sh"
APK_CONF="/etc/apk/repositories"

log() {
  echo "[$(date -Iseconds)] [$SCRIPT_NAME] $*" | tee -a "$LOG_FILE"
}

log "Starting baseline installation..."

### Enable community repo if needed
if ! grep -q "community" "$APK_CONF"; then
  log "Enabling community repository..."
  echo "https://dl-cdn.alpinelinux.org/alpine/$(cut -d. -f1,2 /etc/alpine-release)/community" >> "$APK_CONF"
fi

log "Updating APK index..."
apk update

### Essentials
log "Installing essential packages..."
apk add --no-cache \
  bash curl wget sudo nano openssh \
  apk-tools gnupg unzip zip tar \
  bash-completion rsync

### Security & Networking
log "Installing security and networking tools..."
apk add --no-cache \
  iptables ufw audit cryptsetup \
  tailscale

### Monitoring & CLI Tools
log "Installing monitoring and CLI tools..."
apk add --no-cache \
  htop tmux ncdu logrotate

### Optional: osquery (skip in container)
if grep -qa 'container=' /proc/1/environ; then
  log "Skipping osquery: running inside container"
else
  log "Installing osquery..."
  apk add --no-cache osquery || log "Failed to install osquery"
fi

### Metadata folders (required by deploy/monitoring)
log "Preparing metadata folders..."
mkdir -p /root/Home/metadata
mkdir -p /root/Home/metadata_encrypted

### Ask for reboot and resume bootstrap if confirmed
read -r -p "Do you want to reboot now and resume bootstrap on startup? [y/N] " confirm
if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
  log "Enabling resume after reboot..."
  echo "$NEXT_SCRIPT" > /etc/local.d/resume_bootstrap.start
  chmod +x /etc/local.d/resume_bootstrap.start
  rc-update add local default
  log "Rebooting now..."
  reboot
else
  log "Skipping reboot. Resuming bootstrap..."
  exec "$NEXT_SCRIPT"
fi
