#!/bin/sh
set -euo pipefail
IFS=$'\n\t'

### Constants
SCRIPT_NAME="boot.sh"
LOG_FILE="/root/os_bootstrap.log"
SETTINGS_FILE="/root/settings_validation.JSON"
BOOTSTRAP_SCRIPT="/root/bootstrap.sh"
DRY_RUN=false
BOOTSTRAP_STARTED=false

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

get_current_value() {
  local command="$1"
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

    if ! $BOOTSTRAP_STARTED; then
      log "🚀 Launching bootstrap.sh in background..."
      $DRY_RUN || "$BOOTSTRAP_SCRIPT" &
      BOOTSTRAP_STARTED=true
    fi

    return 1
  fi
}

main() {
  log "🔍 Starting settings validation..."

  while IFS= read -r entry; do
    name=$(echo "$entry" | jq -r '.name')
    expected=$(echo "$entry" | jq -r '.expected')
    check_cmd=$(echo "$entry" | jq -r '.check')

    validate_setting "$name" "$expected" "$check_cmd" || true
  done < <(jq -c '.[]' "$SETTINGS_FILE")

  log "✅ Validation complete."
}

main "$@"
