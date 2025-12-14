# LLHRM – Linux Lightweight Host Resource Monitor

**LLHRM** is a lightweight, containerized monitoring solution for Linux hosts, built on **Alpine Linux**.

It monitors CPU, RAM, and disk usage, triggers alerts when thresholds are exceeded, and sends email notifications using **msmtp**.

---
## ⚡ Scope

- Monitor host resources (CPU, RAM, Disk) from within a container.
- Generate alerts and recovery notifications via email.
- Supports customizable thresholds, intervals, and re-notifications.
- Lightweight Alpine-based Docker image.
- Minimal privilege usage and easy deployment.

---
## 🖥️ Tested Environment

- Host OS: **CentOS 9** (kernel 5.14.0-639.el9.x86_64)  
- Works on any Linux system exposing `/proc/stat` and `/proc/meminfo`.  
- Disk usage monitored via `df -P /`.  

> Bind mounts provide the container read-only access to host `/proc` and persistent storage.
> 
---
## 🛠️ Prerequisites

- Docker >= 20.10
- Linux host exposing `/proc/stat` and `/proc/meminfo`
- SMTP account for email notifications (Gmail, Office365, etc.)

---
## 📂 Project Structure
```
.
├── dockerfile
├── entrypoint.sh
├── scripts/
│   ├── monitor.sh
│   └── mailer.sh
├── templates/
│   └── en/
│       ├── alert.txt
│       ├── re_alert.txt
│       ├── recovery.txt
│       ├── suppressed.txt
│       ├── monitor_degraded.txt
│       └── monitor_recovered.txt
├── config/
│   └── msmtprc        # Example msmtp configuration
├── examples/
│   └── msmtprc.*      # Gmail, Office365, SES, Mailgun, SendGrid examples
```

---
## ⚙️ Configuration

### Environment Variables

Defaults are defined in the Dockerfile and can be overridden with `docker run -e` flags:

| Variable               | Description |
|------------------------|-------------|
| `ALERT_TO`             | Comma-separated email addresses for alerts |
| `ALERT_CC`             | Optional CC recipients |
| `ALERT_BCC`            | Optional BCC recipients |
| `ALERT_LANG`           | Template language (`en` default) |
| `CPU_THRESHOLD`        | CPU usage % to trigger alert |
| `RAM_THRESHOLD`        | RAM usage % to trigger alert |
| `DISK_THRESHOLD`       | Disk usage % to trigger alert |
| `CHECK_INTERVAL`       | Time in seconds between resource checks |
| `ALERT_AFTER`          | Seconds above threshold to trigger alert |
| `RECOVERY_AFTER`       | Seconds below threshold to recover |
| `RENOTIFY_INTERVAL`    | Interval in seconds for re-alerts |
| `MAX_RENOTIFICATIONS`  | Maximum re-alert attempts |
| `CONTAINER_NAME`       | Optional override for container name in notifications |

### Email service (msmtp)

- **Before** running the container, you must configure msmtp to enable email notifications.
- Use the examples provided in the examples/ folder as templates for Gmail, Office365, SES, Mailgun, or SendGrid.
- Ensure the /etc/msmtprc file is correctly mounted or included in the image, and that credentials are valid.
- Basic knowledge of SMTP configuration is required to set this up safely.

---

## 🔒 Security & Permissions

LLHRM is designed to run with minimal privileges for safety:

- The container runs as a non-root user monitor by default.

File system access is restricted:

- /app/state is the only persistent writable directory.
- Host /proc is mounted read-only to collect system metrics.


Ensure that volumes and bind mounts have appropriate ownership and permissions to prevent unauthorized access.

Best practices:

- Never mount sensitive host directories other than /proc.
- Keep /app/state volume private if multiple users share the Docker host.
- Use strong SMTP credentials stored securely (do not commit to repository).


---
## 🚀 Usage

### Build the Docker Image
```
docker build -t llhrm .
```
### Run the Container

- You can override any default environment variable without rebuilding the image:

```
docker run -d \
  --name llhrm \
  --mount type=bind,src=/proc,dst=/host/proc,ro \
  --mount type=volume,src=llhrm_state,dst=/app/state \
  -e ALERT_TO="admin@example.com" \
  diegoespinozapacheco/llhrm
```

- `--mount type=bind,src=/proc,dst=/host/proc,ro` gives read-only access to host stats.
- `--mount type=volume,src=llhrm_state,dst=/app/state` persists monitor state and logs.
> Environment variables override Dockerfile defaults.

### Verify Environment Variables

After starting the container, you can check which environment variables are active:
```
docker exec -it llhrm env | grep -E 'ALERT|CPU|RAM|DISK|CONTAINER_NAME'
```
This allows you to confirm that the container is using the intended thresholds, recipients, and custom settings.

### Dry-Run Mode

Test the mailer without running the monitor:
```
docker run --rm -e DRY_RUN=1 -e ALERT_TO="admin@example.com" llhrm
```
- Sends a test alert email.
- Useful to validate email configuration before production use.

### Logs & Debugging
```
docker logs -f llhrm
```
Common warnings:

- `Host /proc not readable` → missing or incorrect bind mount.
- `msmtprc not found` → ensure `/etc/msmtprc` exists and is readable.
- `ALERT_TO is empty` → define recipient(s) in environment variables or Dockerfile.



### Persistent State

- State files are stored under `/app/state` (bind to Docker volume).  
- Includes resource state, alerts, re-notifications, and monitor status.  
- Threshold values are read from environment variables, not persisted state.

## ✉️ Email Notifications

- Uses **msmtp** to send emails.
- Templates in `/app/templates/en/` support placeholders:

```
{{RESOURCE}}, {{VALUE}}, {{THRESHOLD}}, {{DURATION}}, {{RECOVERY_DURATION}},
{{RENOTIFY_COUNT}}, {{MAX_RENOTIFICATIONS}}, {{FAILED_METRICS}},
{{RECOVERED_METRICS}}, {{HOSTNAME}}, {{CONTAINER_NAME}}, {{TIMESTAMP}}
```
- Example Gmail configuration:
```
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /tmp/msmtp.log

account gmail
host smtp.gmail.com
port 587
from "you@example.com"
user "you@example.com"
password "APP_PASSWORD_HERE"

account default : gmail
```
> Never commit real credentials in a public repository.

## 💡 Notes

- Container hostname is used in notifications; can override with `CONTAINER_NAME`.
- Can run multiple containers with different thresholds by overriding environment variables.
- Runs under non-root user `monitor` for security.
- Logs and state persist in Docker volume, allowing safe restarts.

## 🔧 Tested Scenarios

- Alerts triggered when CPU, RAM, or disk exceed thresholds.
- Recovery emails when resources fall below thresholds.
- Re-alert notifications on sustained threshold violations.
- Dry-run mode confirms mailer functionality.
- Alpine 3.20 Docker image on CentOS 9 host.

## 📝 Contribution & License

- Contributions are welcome via GitHub pull requests.
- Licensed for free use and modification; no warranties provided.


![GitHub release downloads](https://img.shields.io/github/downloads/DiegoEspinozaPacheco/LLHRM/total?color=blue&style=flat-square)

![Docker Pulls](https://img.shields.io/docker/pulls/diegoespinozapacheco/llhrm)

![License](https://img.shields.io/badge/license-MIT-green)
