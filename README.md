# Alpine Bootstrap Workflow

This document describes the bootstrapping and hardening workflow for Alpine-based systems using a modular, reboot-aware script chain.

---

## ✅ Workflow Overview

### 1. `boot.sh` — Runs at Every Boot

**Responsibilities:**
- Validates current system settings via `settings_validation.json`
- Logs all checks to `/root/os_bootstrap.log`
- Detects current progress using `.???_completed.sh` markers
- Generates `/root/bootstrap_status.json`
- Launches `bootstrap.sh` **only if validation fails**

---

### 2. `bootstrap.sh` — Orchestration Engine

**Responsibilities:**
- Reads JSON input from `boot.sh`
- Executes the next incomplete stage only
- Verifies scripts via GPG and SHA256
- Marks completion with `.baseline_completed.sh`, `.hardening_completed.sh`, etc.
- Requests reboot if `/root/.needs_reboot` is created

---

## 🔁 One Stage Per Boot (Staged Execution)

| Stage      | Script                  | Marker File                | Description                                                         |
|------------|-------------------------|-----------------------------|---------------------------------------------------------------------|
| BASELINE   | `alpine_baseline.sh`    | `.baseline_completed.sh`    | Installs essential packages, bash, system tools, cryptsetup        |
| HARDENING  | `alpine_hardening.sh`   | `.hardening_completed.sh`   | SSH config, IPv6 disable, firewall, fail2ban, auditd               |
| MONITORING | `alpine_monitoring.sh`  | `.monitoring_completed.sh`  | Netdata, Wazuh, osquery, logrotate                                 |
| DEPLOY     | `alpine_deploy.sh`      | `.deploy_completed.sh`      | Mounts encrypted vault, loads device context, captures metadata    |
| CRONJOBS   | `alpine_cronjobs.sh`    | `.cronjobs_completed.sh`    | Sets systemd timers and sync tasks                                 |

---

### 🔄 Reboot Flow

- If a script sets `/root/.needs_reboot`, execution halts
- System reboots
- `boot.sh` runs again and continues from next incomplete stage

---

## 📂 Key Files

| Path                              | Purpose                                         |
|-----------------------------------|-------------------------------------------------|
| `/root/.needs_reboot`             | Reboot signal                                   |
| `/root/.<stage>_completed.sh`     | Stage checkpoint marker                         |
| `/root/bootstrap_status.json`     | Latest system config snapshot                   |
| `/root/os_bootstrap.log`          | Logs from all scripts                           |
| `/root/Home/metadata/*.json`      | Stage-specific metadata (monitoring, deploy)    |
| `/root/settings_validation.json`  | Definition of expected system configuration     |

---

## 🔒 Safe, Resilient, and Auditable

- Fully idempotent: every script can be rerun safely
- Logged and staged for maximum traceability
- Supports dry-run mode (`--dry-run`) for testing
