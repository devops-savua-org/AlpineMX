
# Alpine Manual App Base — Secure Bootstrap

This Alpine base is used to deploy manual (non-Docker/non-LXC) applications onto hardened, minimal systems.
It supports both pure Alpine VMs and LXC containers and is designed as a reusable Helper Script LXC template.

---

## 📦 Script Source URL

All scripts are hosted at:

https://gist.githubusercontent.com/devops-savua-org/aa5a147371d59c7bef9383d713ff1954/raw/fc5efa494fd7adce4657d2f712172e99a82a7687/{filename}

Replace `{filename}` with one of the following:
- alpine_baseline.sh
- alpine_hardening.sh
- alpine_monitoring.sh
- alpine_deploy.sh
- alpine_cronjobs.sh
- bootstrap.sh

---

## 📁 Module Overview

| Step | Script               | Description                                                                 |
|------|----------------------|-----------------------------------------------------------------------------|
| 1️⃣   | alpine_baseline.sh   | Install baseline tools (bash, cryptsetup, systemd or fallback cron, network + CLI utils) |
| 2️⃣   | alpine_hardening.sh | OS security hardening (SSH, firewall, disable IPv6, lock root, ufw or iptables) |
| 3️⃣   | alpine_monitoring.sh| Tailscale, Netdata, Wazuh Agent, CrowdSec (optional)                          |
| 4️⃣   | alpine_deploy.sh    | Mount encrypted vault, load DEVICE_CONTEXT from Gist, store metadata          |
| 5️⃣   | alpine_cronjobs.sh  | IP reporting, health checks, Netdata push (via systemd or fallback to cron)  |
| 🔁   | bootstrap.sh         | Entry point script to run all the above in correct order                     |

---

## 🔐 Encrypted Vault

Vault is always mounted using cryptsetup at:

`/mnt/secure_vault`

This must be present before executing deployment, metadata sync, or telemetry logging.

---

## 📋 Metadata & Context

- `DEVICE_CONTEXT.env` is fetched during bootstrap and saved to:  
  `/root/Home/metadata/DEVICE_CONTEXT.env`

- Trust logs and encrypted telemetry (if mounted) are stored at:  
  `/root/Home/metadata_encrypted/`

---

## 🧠 LXC Compatibility Notes

- Some kernel-level tools like `auditd` or `osquery` may not function in unprivileged LXCs.
- To maximize compatibility, containers should enable:  
  `features: nesting=1,keyctl=1`
- Fallback to `cron` if `systemd` is unavailable.

---

## 🛠 Baseline Packages

The following tools are installed by `alpine_baseline.sh`:

**Essentials**
- bash, curl, wget, sudo, nano, openssh, apk-tools

**Security**
- iptables, ufw, audit, netdata, tailscale, cryptsetup

**Monitoring**
- htop, tmux, ncdu, logrotate

**Optional**
- gnupg, osquery, rsync, bash-completion

---

## 🔁 Bootstrap Workflow

1. Run `bootstrap.sh`
2. Each module installs in order
3. Vault is mounted
4. Metadata and device context is recorded
5. Monitoring + cron/timer jobs configured
6. Ready for manual app deployment

---

## 📌 Example Usage

```sh
wget https://gist.githubusercontent.com/devops-savua-org/aa5a147371d59c7bef9383d713ff1954/raw/fc5efa494fd7adce4657d2f712172e99a82a7687/bootstrap.sh -O /root/bootstrap.sh
chmod +x /root/bootstrap.sh
/root/bootstrap.sh
```

---

## ✅ Ready For Manual App Deployment

Once bootstrapped, this base is ideal for:
- Ollama
- PiSignage
- FileFlows
- Magic Mirror
- Any other app requiring a secure, minimal Alpine host

---

# 🕒 Scheduling & Frequency Configuration

The `alpine_cronjobs.sh` script supports automated scheduling through either:

- **systemd timers** (preferred if available)
- **cron fallback** (for minimal Alpine setups)

---

## ✅ Default Schedule

- **Daily at boot**:
  - Starts 10 minutes after boot
  - Repeats every 24 hours

---

## 🔁 Modify Cron/systemd Frequency

You can change the job's frequency by passing a flag during the first run:

| Frequency     | Flag       | systemd Schedule           | cron Schedule         |
|---------------|------------|----------------------------|------------------------|
| Hourly        | `--hourly` | Every 1h after boot        | `0 * * * *`            |
| Every 6 hours | `--6h`     | Every 6h after boot        | `0 */6 * * *`          |
| Daily         | `--daily`  | Every 24h after boot       | `0 4 * * *` (default)  |
| Weekly        | `--weekly` | Every Sunday via calendar  | `0 4 * * 0`            |

Run the script once with the desired frequency:

```sh
/root/alpine_cronjobs.sh --daily
```

---

## 🧪 Manual Execution

To run the script immediately (without modifying schedule):

```sh
/root/alpine_cronjobs.sh --now
```

To test without making changes:

```sh
/root/alpine_cronjobs.sh --now --dry-run
```

---

## 🔄 Updating or Resetting the Schedule

If you already installed the script and want to change the frequency later:

### For systemd (VMs, LXC with systemd)
```sh
rm -f /etc/systemd/system/alpine_cronjobs.*
systemctl daemon-reload
/root/alpine_cronjobs.sh --6h
```

### For cron fallback (minimal Alpine)
```sh
crontab -r
/root/alpine_cronjobs.sh --weekly
```

This will regenerate the proper timer or crontab entry based on your new schedule.

