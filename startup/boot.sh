#!/bin/sh
set -eu

# === CONFIG ===
SCRIPT_NAME="validate_hardening.sh"
SCRIPT_URL="https://raw.githubusercontent.com/devops-savua-org/AlpineMX/<PERMALINK-COMMIT>/startup/$SCRIPT_NAME"
LOCAL_CACHE="/etc/hardening/cache/$SCRIPT_NAME"
LOCAL_PATH="/tmp/$SCRIPT_NAME"
LOG="/var/log/hardening_boot.log"

# Create cache dir if missing
mkdir -p "$(dirname "$LOCAL_CACHE")"

# Lock to avoid concurrent runs
exec 200>/var/lock/boot.lock
flock -n 200 || exit 1

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"
}

log "🔐 Boot sequence started"

# === Download and cache ===
if curl -fsSL "$SCRIPT_URL" -o "$LOCAL_PATH"; then
  log "✅ Downloaded $SCRIPT_NAME from GitHub"

  # Optional: SHA256 check
  # EXPECTED_HASH="..."
  # ACTUAL_HASH=$(sha256sum "$LOCAL_PATH" | awk '{print $1}')
  # if [ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]; then
  #   log "❌ SHA256 mismatch. Falling back to cached version."
  #   cp "$LOCAL_CACHE" "$LOCAL_PATH"
  # fi

  cp "$LOCAL_PATH" "$LOCAL_CACHE"
  chmod 700 "$LOCAL_PATH"
else
  log "⚠️  Failed to download. Using cached version"
  cp "$LOCAL_CACHE" "$LOCAL_PATH"
fi

# === Execute ===
if [ -f "$LOCAL_PATH" ]; then
  log "🚀 Running $SCRIPT_NAME"
  sh "$LOCAL_PATH" || log "❌ $SCRIPT_NAME exited with error"
else
  log "❌ No valid copy of $SCRIPT_NAME found"
  exit 1
fi

log "✅ Boot sequence completed"
