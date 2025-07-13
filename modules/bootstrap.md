#!/bin/sh
set -euo pipefail
IFS=$'\n\t'

### Constants
SCRIPT_DIR="/root"
STATUS_FILE="/root/.bootstrap_status"
LOG_FILE="/root/os_bootstrap.log"
REBOOT_FLAG="/root/.needs_reboot"
METADATA_OUTPUT="/root/Home/metadata/bootstrap_status.json"
SCRIPT_BASE_URL="https://gist.githubusercontent.com/devops-savua-org/aa5a147371d59c7bef9383d713ff1954/raw/fc5efa494fd7adce4657d2f712172e99a82a7687"
GPG_KEY_ID="0482D84022F52DF1C4E7CD43293ACD0907D9495A"

### Variables
STATUS_JSON=""
DRY_RUN=false

### Stage Map
STAGES="\
baseline:.baseline_done:alpine_baseline.sh
hardening:.hardening_done:alpine_hardening.sh
monitoring:.monitoring_done:alpine_monitoring.sh
deploy:.deploy_done:alpine_deploy.sh"

log() {
  echo "[$(date -Iseconds)] [BOOTSTRAP] $*" | tee -a "$LOG_FILE"
}

run() {
  if $DRY_RUN; then
    echo "[DRY RUN] $*" | tee -a "$LOG_FILE"
  else
    eval "$@" | tee -a "$LOG_FILE"
  fi
}

mark_done() {
  local flag="$1"
  touch "/root/$flag"
}

verify_script() {
  local file="$1"
  log "Verifying GPG + SHA256 for $file..."

  run "wget -q ${SCRIPT_BASE_URL}/${file}.sha256 -O ${SCRIPT_DIR}/${file}.sha256"
  run "wget -q ${SCRIPT_BASE_URL}/${file}.asc -O ${SCRIPT_DIR}/${file}.asc"
  gpg --keyserver keyserver.ubuntu.com --recv-keys "$GPG_KEY_ID" 2>/dev/null || true
  gpg --verify "${SCRIPT_DIR}/${file}.asc" "${SCRIPT_DIR}/${file}" || {
    log "❌ GPG verification failed"; exit 1;
  }

  sha256sum -c "${SCRIPT_DIR}/${file}.sha256" || {
    log "❌ SHA256 mismatch"; exit 1;
  }
}

### Parse Args
for arg in "$@"; do
  case "$arg" in
    --status-json)
      shift
      STATUS_JSON="$1"
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
  esac
done

[ -z "$STATUS_JSON" ] && { log "❌ --status-json missing"; exit 1; }

### Main Logic
main() {
  log "🚀 Bootstrap launched with JSON: $STATUS_JSON"

  cp "$STATUS_JSON" "$METADATA_OUTPUT"

  for entry in $STAGES; do
    stage="${entry%%:*}"
    flag="${entry#*:}"
    flag="${flag%%:*}"
    script="${entry##*:}"

    done=$(jq -r ".${stage}" "$STATUS_JSON")
    [ "$done" = "true" ] && continue

    log "➡️  Executing stage: $stage ($script)"

    run "wget -q ${SCRIPT_BASE_URL}/${script} -O ${SCRIPT_DIR}/${script}"
    run "chmod +x ${SCRIPT_DIR}/${script}"
    verify_script "$script"

    if run "${SCRIPT_DIR}/${script}"; then
      mark_done "$flag"
      log "✅ Stage $stage complete."
    else
      log "❌ Failed: $stage — exiting."
      exit 1
    fi

    if [ -f "$REBOOT_FLAG" ]; then
      log "⚠️  $script requested reboot."
      sync
      reboot
      exit 0
    fi

    break  # Only one stage per boot
  done

  log "🎉 All required stages completed or waiting on next boot."
}

main
