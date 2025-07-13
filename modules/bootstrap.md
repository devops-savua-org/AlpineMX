#!/bin/sh
set -euo pipefail
IFS=$'\n\t'

### 0. Constants
SCRIPT_DIR="/root"
SCRIPT_BASE_URL="https://gist.githubusercontent.com/devops-savua-org/aa5a147371d59c7bef9383d713ff1954/raw/fc5efa494fd7adce4657d2f712172e99a82a7687"
LOG_FILE="/root/os_bootstrap.log"
STATUS_FILE="/root/.bootstrap_status"
RESUME_LOG="/var/log/bootstrap_resume.log"
REBOOT_FLAG="/root/.reboot_required"
SCRIPT_LIST="alpine_baseline.sh alpine_hardening.sh alpine_monitoring.sh alpine_deploy.sh alpine_cronjobs.sh"
GPG_KEY_ID="0482D84022F52DF1C4E7CD43293ACD0907D9495A"
DRY_RUN=false

### 1. Parse Args
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      echo "[DRY RUN] No changes will be made."
      ;;
  esac
done

### 2. Logging Setup
log() {
  echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"
}

run() {
  if $DRY_RUN; then
    echo "[DRY RUN] $*" | tee -a "$LOG_FILE"
  else
    eval "$@" | tee -a "$LOG_FILE"
  fi
}

### 3. Enable persistent journald logging early
log "Ensuring /var/log/journal exists..."
mkdir -p /var/log/journal

log "Setting journald to use persistent storage..."
sed -i 's|^#*Storage=.*|Storage=persistent|' /etc/systemd/journald.conf

log "Restarting journald to apply changes..."
systemctl restart systemd-journald 2>/dev/null || rc-service systemd-journald restart 2>/dev/null || true

### 4. Redirect shell output to persistent log
exec > >(tee -a /var/log/bootstrap.log) 2>&1

### 5. Network Check
check_network() {
  log "Checking network connectivity..."
  ping -q -c 1 1.1.1.1 || { log "❌ Network unreachable."; exit 1; }
  log "✅ Network reachable."
}

### 6. GPG Key Import
setup_gpg() {
  if ! gpg --list-keys "$GPG_KEY_ID" > /dev/null 2>&1; then
    log "Importing GPG key..."
    run "gpg --keyserver keyserver.ubuntu.com --recv-keys $GPG_KEY_ID"
  fi
}

### 7. Verify Script
verify_script() {
  local file="$1"

  log "Verifying $file..."

  run "wget -q ${SCRIPT_BASE_URL}/${file}.sha256 -O ${SCRIPT_DIR}/${file}.sha256"
  run "wget -q ${SCRIPT_BASE_URL}/${file}.asc -O ${SCRIPT_DIR}/${file}.asc"

  gpg --verify "${SCRIPT_DIR}/${file}.asc" "${SCRIPT_DIR}/${file}" || {
    log "❌ GPG verification failed for $file"; exit 1;
  }

  cd "$SCRIPT_DIR"
  sha256sum -c "${file}.sha256" || {
    log "❌ SHA256 checksum failed for $file"; exit 1;
  }

  log "✅ $file verified successfully."
}

### 8. Status Tracking
has_run() {
  grep -q "$1" "$STATUS_FILE" 2>/dev/null
}

mark_done() {
  echo "$1" >> "$STATUS_FILE"
}

### 9. Bootstrap Execution
main() {
  # Handle resume after reboot
  if [ -f "$REBOOT_FLAG" ]; then
    log "🔁 Detected resume after reboot. Continuing bootstrap..."
    echo "[$(date -Iseconds)] Resumed after reboot" >> "$RESUME_LOG"
    rm -f "$REBOOT_FLAG"
  fi

  check_network
  setup_gpg

  for script in $SCRIPT_LIST; do
    if has_run "$script"; then
      log "Skipping $script — already completed."
      continue
    fi

    log "Fetching $script..."
    run "wget -q ${SCRIPT_BASE_URL}/${script} -O ${SCRIPT_DIR}/${script}"
    run "chmod +x ${SCRIPT_DIR}/${script}"

    verify_script "$script"

    log "Running $script..."
    if ! run "${SCRIPT_DIR}/${script}"; then
      log "❌ Failed executing $script — exiting bootstrap."
      exit 1
    fi

    mark_done "$script"
    echo "[$(date -Iseconds)] Finished $script" >> "$RESUME_LOG"
    log "✅ Completed $script."

    # Trigger reboot if the script requests it
    if [ -f "$REBOOT_FLAG" ]; then
      log "⚠️  Script requested a reboot. Rebooting now..."
      sync
      reboot
      exit 0
    fi
  done

  log "🎉 All scripts completed successfully."
}

main "$@"
