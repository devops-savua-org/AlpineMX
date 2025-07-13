#!/bin/sh
set -euo pipefail
IFS=$'\n\t'

### Constants
SCRIPT_NAME="alpine_deploy.sh"
LOG_FILE="/root/os_bootstrap.log"
ENCRYPTED_DEV="/dev/sda1"  # CHANGE THIS if needed
MAPPER_NAME="secure_vault"
MOUNTPOINT="/mnt/secure_vault"
METADATA_DIR="/root/Home/metadata"
ENCRYPTED_DIR="/root/Home/metadata_encrypted"
DEVICE_CONTEXT_URL="https://gist.githubusercontent.com/devops-savua-org/fffcdfb96cac6f6f37921530d410f2ec/raw"
DEVICE_CONTEXT_ENV="$METADATA_DIR/DEVICE_CONTEXT.env"
METADATA_JSON="$METADATA_DIR/deployment.json"

log() {
  echo "[$(date -Iseconds)] [$SCRIPT_NAME] $*" | tee -a "$LOG_FILE"
}

run() {
  eval "$@" | tee -a "$LOG_FILE"
}

### 1. Mount Encrypted Vault
log "🔐 Mounting encrypted vault..."

if [ ! -e "$ENCRYPTED_DEV" ]; then
  log "❌ Encrypted device not found at $ENCRYPTED_DEV"
  exit 1
fi

mkdir -p "$MOUNTPOINT"

if ! grep -q "$MOUNTPOINT" /proc/mounts; then
  cryptsetup open "$ENCRYPTED_DEV" "$MAPPER_NAME"
  mount "/dev/mapper/$MAPPER_NAME" "$MOUNTPOINT"
  log "✅ Vault mounted at $MOUNTPOINT"
else
  log "⚠️ Vault already mounted."
fi

### 2. Load DEVICE_CONTEXT.env from Gist
log "📥 Downloading DEVICE_CONTEXT.env..."
mkdir -p "$METADATA_DIR"
wget -q "$DEVICE_CONTEXT_URL" -O "$DEVICE_CONTEXT_ENV"

if [ -f "$DEVICE_CONTEXT_ENV" ]; then
  log "✅ DEVICE_CONTEXT.env loaded:"
  cat "$DEVICE_CONTEXT_ENV" | tee -a "$LOG_FILE"
else
  log "❌ Failed to fetch DEVICE_CONTEXT.env"
  exit 1
fi

### 3. Export DEVICE_CONTEXT
log "🔧 Exporting device context..."
set -o allexport
. "$DEVICE_CONTEXT_ENV"
set +o allexport

### 4. Write structured metadata
log "🧠 Writing deployment metadata..."
HOSTNAME=$(hostname)
TS_IP=$(tailscale ip -4 2>/dev/null | head -n1)
TIMESTAMP=$(date -Iseconds)

cat <<EOF > "$METADATA_JSON"
{
  "device_tag": "${DEVICE_TAG:-undefined}",
  "device_role": "${DEVICE_ROLE:-undefined}",
  "device_env": "${DEVICE_ENV:-undefined}",
  "hostname": "$HOSTNAME",
  "tailscale_ip": "$TS_IP",
  "timestamp": "$TIMESTAMP",
  "vault_mounted": "$MOUNTPOINT"
}
EOF

### 5. Interactive Tailscale provisioning
log "🔗 Tailscale provisioning..."

echo "You are about to bring up Tailscale temporarily to authorize this device."
echo "This will allow it to be provisioned and tagged in the admin panel before ACLs are applied."
echo

read -r -p "Do you want to run 'tailscale up' now? [y/N] " confirm
if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
  log "Running 'tailscale up'..."
  tailscale up

  log "📎 Please visit the URL shown above to authorize this device."
  read -r -p "Press Enter once device is authorized and appears in the admin panel..."

  log "🚫 Shutting down Tailscale until ACLs are enforced..."
  tailscale down
else
  log "Skipped Tailscale provisioning."
fi

log "✅ alpine_deploy.sh completed."
