#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

### CONFIG
BOOT_URL="https://raw.githubusercontent.com/devops-savua-org/AlpineMX/3ea58f361c154dbd4e2952e364b248eedb81eeee/boot.sh"
YAML_URL="https://raw.githubusercontent.com/devops-savua-org/AlpineMX/3ea58f361c154dbd4e2952e364b248eedb81eeee/system_settings.yaml"
SELF_URL="https://raw.githubusercontent.com/devops-savua-org/AlpineMX/main/bootloader.sh"
CACHE_DIR="/root/.cache_boot"
LOG_FILE="/var/log/bootloader.log"
DRY_RUN=false
FORCE=false
GPG_KEY="4C0A87AE3EA4DE30E4BB3F27397F0F1D3C4FC6BB"

mkdir -p "$CACHE_DIR"
chmod 700 "$CACHE_DIR"
mkdir -p "$(dirname $LOG_FILE)"
chmod 600 "$LOG_FILE"

exec 200>/var/lock/bootloader.lock
flock -n 200 || exit 1

log() {
  echo "[$(date -Iseconds)] $1" | tee -a "$LOG_FILE"
}

run() {
  if $DRY_RUN; then
    log "[DRY RUN] $1"
  else
    eval "$1"
  fi
}

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --dry-run) DRY_RUN=true;;
      --force) FORCE=true;;
    esac
  done
}

verify_permissions() {
  [[ "$(stat -c "%U:%G %a" $1)" == "root:root 600" ]] || log "WARNING: Incorrect permissions on $1"
}

download_file() {
  local url="$1"
  local out="$2"
  curl -fsSL "$url" -o "$out"
}

sha256() {
  sha256sum "$1" | cut -d ' ' -f 1
}

encrypt_file() {
  local input="$1"
  local output="$2"
  gpg --yes --batch --output "$output" --encrypt --recipient "$GPG_KEY" "$input"
  chmod 600 "$output"
  chown root:root "$output"
}

decrypt_file() {
  local input="$1"
  gpg --quiet --decrypt "$input"
}

check_and_update_self() {
  TMP_SELF="${CACHE_DIR}/bootloader.sh.new"
  download_file "$SELF_URL" "$TMP_SELF"
  if ! cmp -s "$TMP_SELF" "$0"; then
    log "[+] Updating bootloader.sh with newer version."
    chmod +x "$TMP_SELF"
    mv "$TMP_SELF" "$0"
    exec "$0" "$@"
  else
    rm "$TMP_SELF"
  fi
}

import_gpg_key() {
  if ! gpg --list-keys "$GPG_KEY" &>/dev/null; then
    log "[+] Fetching GPG key from GitHub"
    curl -fsSL https://raw.githubusercontent.com/devops-savua-org/AlpineMX/refs/heads/main/startup/public.asc | gpg --import

    log "[+] Verifying GPG key fingerprint"
    EXPECTED_FPR="$GPG_KEY"
    ACTUAL_FPR=$(gpg --fingerprint --with-colons "$GPG_KEY" | awk -F: '/fpr:/ {print $10; exit}')
    if [ "$EXPECTED_FPR" != "$ACTUAL_FPR" ]; then
      log "[✗] GPG fingerprint mismatch. Exiting."
      exit 1
    fi
  else
    log "[✓] GPG key already imported"
  fi
}

main() {
  parse_args "$@"
  import_gpg_key

  log "[+] Checking for bootloader updates"
  check_and_update_self "$@"

  TMP_BOOT="${CACHE_DIR}/boot.sh"
  TMP_YAML="${CACHE_DIR}/system_settings.yaml"
  ENC_BOOT="${CACHE_DIR}/boot.sh.gpg"
  ENC_YAML="${CACHE_DIR}/system_settings.yaml.gpg"

  log "[+] Downloading boot.sh"
  download_file "$BOOT_URL" "$TMP_BOOT"

  log "[+] Encrypting boot.sh"
  encrypt_file "$TMP_BOOT" "$ENC_BOOT"
  rm "$TMP_BOOT"

  log "[+] Downloading system_settings.yaml"
  download_file "$YAML_URL" "$TMP_YAML"

  log "[+] Encrypting system_settings.yaml"
  encrypt_file "$TMP_YAML" "$ENC_YAML"
  rm "$TMP_YAML"

  verify_permissions "$ENC_BOOT"
  verify_permissions "$ENC_YAML"

  log "[+] Decrypting and executing boot.sh"
  decrypt_file "$ENC_BOOT" | bash -s -- "$@"
}

main "$@"
