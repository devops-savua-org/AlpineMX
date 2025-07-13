#!/bin/sh
set -euo pipefail
IFS=$'\n\t'

### Constants
SCRIPT_NAME="boot.sh"
LOG_FILE="/root/os_bootstrap.log"
SETTINGS_FILE="/root/settings_validation.yaml"
TEMP_FILE="/tmp/settings_validation.download"
BOOTSTRAP_SCRIPT="/root/bootstrap.sh"
BOOTSTRAP_MARKER="/root/.bootstrap_launched"
LOCK_FILE="/var/lock/boot.sh.lock"
SETTINGS_URL="https://raw.githubusercontent.com/devops-savua-org/AlpineMX/51ac7741dcd26f954382d0d7d57c8c58982a1d10/system_settings.yaml"

DRY_RUN=false
BOOTSTRAP_STARTED=false

### Parse --dry-run
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

### Lock execution
exec 200>"$LOCK_FILE"
flock -n 200 || {
  log "⛔ Another instance is already running. Exiting."
  exit 1
}

### Secure fetch and validate GitHub permalink file
fetch_and_verify_settings_file() {
  log "📥 Downloading settings file from GitHub permalink..."

  curl -fsSL "$SETTINGS_URL" -o "$TEMP_FILE"

  log "🔒 Verifying SHA256 against commit SHA..."

  file_hash=$(sha256sum "$TEMP_FILE" | awk '{print $1}')
  commit_sha=$(echo "$SETTINGS_URL" | awk -F '/' '{print $(NF-1)}')

  if echo "$file_hash" | grep -qi "$commit_sha"; then
    log "✅ SHA256 Pairing Passed (includes commit SHA)"
    mv "$TEMP_FILE" "$SETTINGS_FILE"
  else
    log "❌ SHA256 Pair returned FALSE"
    rm -f "$TEMP_FILE"
    exit 1
  fi
}

### File permission checks
check_permissions() {
  log "🔐 Checking file permissions..."
  [ "$(stat -c "%a" $SETTINGS_FILE)" = "600" ] || log "⚠️ WARNING: Incorrect permissions on $SETTINGS_FILE"
  [ "$(stat -c "%a" /root/boot.sh)" = "700" ] || log "⚠️ WARNING: Incorrect permissions on /root/boot.sh"
  [ "$(stat -c "%a" $BOOTSTRAP_SCRIPT)" = "700" ] || log "⚠️ WARNING: Incorrect permissions on $BOOTSTRAP_SCRIPT"
}

get_current_value() {
  local command="$1"
  if echo "$command" | grep -qE '[^a-zA-Z0-9 _|:&;<>/\.\-]' ; then
    log "🚫 Suspicious command detected: $command"
    echo ""
    return
  fi
  eval "$command" 2>/dev/null | tr -d '\n'
}

validate_setting() {
  local name="$1"
  local expected="$2"
  local check_cmd="$3"

  local current
  current=$(get_current_value "$check_cmd")

  if [ "$current" = "$expected" ]; then
    log "✅ [$name] OK = '$current'"
    return 0
  else
    log "❌ [$name] Expected '$expected' but found '$current'"

    if ! $BOOTSTRAP_STARTED && [ ! -f "$BOOTSTRAP_MARKER" ]; then
      log "🚀 Launching bootstrap.sh in background..."
      $DRY_RUN || "$BOOTSTRAP_SCRIPT" &
      echo "$!" > /var/run/bootstrap.pid
      touch "$BOOTSTRAP_MARKER"
      BOOTSTRAP_STARTED=true
    fi

    return 1
  fi
}

main() {
  log "🔍 Starting settings validation..."
  fetch_and_verify_settings_file
  check_permissions

  while IFS= read -r entry; do
    name=$(echo "$entry" | jq -r '.name')
    expected=$(echo "$entry" | jq -r '.expected')
    check_cmd=$(echo "$entry" | jq -r '.check')

    if [ -z "$name" ] || [ -z "$expected" ] || [ -z "$check_cmd" ]; then
      log "⚠️ Skipping invalid entry: $entry"
      continue
    fi

    validate_setting "$name" "$expected" "$check_cmd" || true
  done < <(jq -c '.[]' "$SETTINGS_FILE")

  log "✅ Validation complete."
}

main "$@"
