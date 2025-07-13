#!/bin/sh
set -euo pipefail
IFS=$'\n\t'

### Constants
SCRIPT_NAME="alpine_hardening.sh"
LOG_FILE="/root/os_bootstrap.log"
NEXT_SCRIPT="/root/bootstrap.sh"
SSH_CONFIG="/etc/ssh/sshd_config"
SYSCTL_FILE="/etc/sysctl.conf"
DRY_RUN=false

# Parse --dry-run if passed
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
    echo "[DRY RUN] $*" | tee -a "$LOG_FILE"
  else
    eval "$@" | tee -a "$LOG_FILE"
  fi
}

### Function: Configure restart-on-failure
configure_restart_on_failure() {
  local service="$1"

  if ! systemctl list-units --type=service --all | grep -q "^${service}.service"; then
    log "⚠️  Skipping restart policy — ${service}.service not found."
    return
  fi

  log "🛠️ Enabling restart-on-failure for $service..."

  run "mkdir -p /etc/systemd/system/${service}.service.d"

  run "cat <<EOF > /etc/systemd/system/${service}.service.d/override.conf
[Service]
Restart=on-failure
RestartSec=3
EOF"

  run "systemctl daemon-reexec"
  run "systemctl daemon-reload"
  run "systemctl restart $service"

  log "✅ $service will now restart on failure."
}

### Function: Set DNS to Quad9
set_dns_to_quad9() {
  log "🔧 Setting DNS to Quad9 (9.9.9.9)..."

  run "echo 'nameserver 9.9.9.9' > /etc/resolv.conf"
  run "mkdir -p /etc/udhcpc"
  run "echo -e '#!/bin/sh\nexit 0' > /etc/udhcpc/default.script"
  run "chmod +x /etc/udhcpc/default.script"
  run "chattr +i /etc/resolv.conf"

  grep "9.9.9.9" /etc/resolv.conf && log "✅ Quad9 DNS verified in /etc/resolv.conf"
}

### Function: Disable IPv6 at boot (extlinux only)
disable_ipv6_boot_param() {
  log "🔧 Checking for extlinux bootloader config..."
  if [ -f /etc/update-extlinux.conf ]; then
    log "Disabling IPv6 via boot parameters..."
    sed -i '/^default_kernel_opts=/s/"$/ ipv6.disable=1"/' /etc/update-extlinux.conf
    run "update-extlinux"
    log "✅ ipv6.disable=1 added to extlinux boot config"
  else
    log "⚠️  Bootloader not detected or unsupported — skipping ipv6.disable=1"
  fi
}

### MAIN
log "🚀 Starting OS hardening..."

### 1. Harden SSH
log "🔐 Configuring SSH..."
run "sed -i 's/#Port 22/Port 88/' $SSH_CONFIG"
run "sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' $SSH_CONFIG"
run "sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' $SSH_CONFIG"
run "echo 'LogLevel VERBOSE' >> $SSH_CONFIG"
run "echo 'AllowUsers alpine' >> $SSH_CONFIG"
run "echo 'MaxAuthTries 3' >> $SSH_CONFIG"
run "echo 'Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com' >> $SSH_CONFIG"
run "echo 'KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256' >> $SSH_CONFIG"
run "rc-update add sshd default"
run "rc-service sshd restart"

### 2. Lock Root Account
log "🔒 Locking root account..."
run "passwd -l root || true"
run "usermod -s /sbin/nologin root || true"

### 3. Set DNS to Quad9
set_dns_to_quad9

### 4. Configure UFW
log "🛡️ Configuring firewall rules..."
run "ufw default deny incoming"
run "ufw default allow outgoing"
run "ufw allow 88/tcp"
run "ufw allow out 53,443 proto tcp"
run "ufw allow out 53,443 proto udp"
run "ufw logging on"
run "ufw --force enable"

### 5. Disable IPv6 (sysctl + bootloader)
log "🔧 Disabling IPv6 via sysctl..."
run "echo 'net.ipv6.conf.all.disable_ipv6 = 1' >> $SYSCTL_FILE"
run "echo 'net.ipv6.conf.default.disable_ipv6 = 1' >> $SYSCTL_FILE"
run "echo 'net.ipv6.conf.lo.disable_ipv6 = 1' >> $SYSCTL_FILE"
run "sysctl -p || true"
disable_ipv6_boot_param

### 6. Enable Tailscale + Auditd
log "🔗 Enabling tailscaled and auditd..."
run "rc-update add tailscale default"
run "rc-service tailscale restart"

run "rc-update add auditd default"
run "rc-service auditd start"

run "mkdir -p /etc/audit/rules.d"
cat <<EOF | run "tee /etc/audit/rules.d/hardening.rules"
-w /etc/passwd -p wa -k passwd_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /var/log/auth.log -p r -k authlog
EOF

run "auditctl -R /etc/audit/rules.d/hardening.rules || true"

### 7. Configure fail2ban
log "🛡️ Installing and configuring fail2ban..."
run "apk add --no-cache fail2ban || true"
run "mkdir -p /etc/fail2ban/jail.d"
cat <<EOF | run "tee /etc/fail2ban/jail.d/sshd.conf"
[sshd]
enabled = true
port = 88
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF
run "rc-update add fail2ban default"
run "rc-service fail2ban restart"

### 8. Lock sudoers
log "🔒 Locking sudoers permissions..."
run "chmod 440 /etc/sudoers"
run "chmod 440 /etc/sudoers.d || true"
run "echo 'Defaults log_input,log_output' >> /etc/sudoers"

### 9. Configure restart-on-failure
configure_restart_on_failure "tailscaled"
configure_restart_on_failure "auditd"
configure_restart_on_failure "fail2ban"
configure_restart_on_failure "netdata"

### 10. Log and callback
log "✅ Hardening complete. Returning to bootstrap.sh..."
exec "$NEXT_SCRIPT"
