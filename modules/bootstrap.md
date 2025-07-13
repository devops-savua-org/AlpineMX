#!/bin/sh
set -euo pipefail
IFS=$'\n\t'

### Constants
SCRIPT_DIR="/root"
SCRIPT_BASE_URL="https://gist.githubusercontent.com/devops-savua-org/aa5a147371d59c7bef9383d713ff1954/raw/fc5efa494fd7adce4657d2f712172e99a82a7687"
LOG_FILE="/root/os_bootstrap.log"
STATUS_FILE="/root/.bootstrap_status"
SCRIPT_LIST="alpine_baseline.sh alpine_hardening.sh alpine_monitoring.sh alpine_deploy.sh alpine_cronjobs.sh"
GPG_KEY_ID="0482D84022F52DF1C4E7CD43293ACD0907D9495A"
DRY_RUN=false

### Parse Args
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true; echo "[DRY RUN] No changes will be made." ;;
  esac
done

run() {
  if $DRY_RUN; then
    echo "[DRY RUN] $*" | tee -a "$LOG_FILE"
  else
    eval "$@" | tee -a "$LOG_FILE"
  fi
}

log() {
  echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"
}

### Check Network
check_network() {
  log "Checking network connectivity..."
  ping -q -c 1 1.1.1.1 || { log "❌ Network unreachable."; exit 1; }
  log "✅ Network reachable."
}

### Fetch GPG Key
setup_gpg() {
  if ! gpg --list-keys "$GPG_KEY_ID" > /dev/null 2>&1; then
    log "Importing GPG key..."
    run "gpg --keyserver keyserver.ubuntu.com --recv-keys $GPG_KEY_ID"
  fi
}

### Validate Integrity
verify_script() {
  local file="$1"
  local url_base="$SCRIPT_BASE_URL"

  log "Verifying $file..."

  run "wget -q ${url_base}/${file}.sha256 -O ${SCRIPT_DIR}/${file}.sha256"
  run "wget -q ${url_base}/${file}.asc -O ${SCRIPT_DIR}/${file}.asc"

  # GPG verification
  gpg --verify "${SCRIPT_DIR}/${file}.asc" "${SCRIPT_DIR}/${file}" || {
    log "❌ GPG verification failed for $file"; exit 1;
  }

  # SHA256 verification
  cd "$SCRIPT_DIR"
  sha256sum -c "${file}.sha256" || {
    log "❌ SHA256 checksum failed for $file"; exit 1;
  }

  log "✅ $file verified successfully."
}

### Resume Support
has_run() {
  grep -q "$1" "$STATUS_FILE" 2>/dev/null
}

mark_done() {
  echo "$1" >> "$STATUS_FILE"
}

### Start Bootstrap
main() {
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
    log "✅ Completed $script."
  done

  log "🎉 All scripts completed successfully."
}

main "$@"
