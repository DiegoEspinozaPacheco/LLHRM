#!/bin/sh
set -eu

# ---- Helpers ----
ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log()  { echo "[ENTRYPOINT] [INFO]  $(ts) $*"; }
warn() { echo "[ENTRYPOINT] [WARN]  $(ts) $*" >&2; }
err()  { echo "[ENTRYPOINT] [ERROR] $(ts) $*" >&2; }

fail() {
  err "$*"
  exit 1
}

# ---- Configuration defaults ----
: "${CHECK_INTERVAL:=60}"
: "${ALERT_AFTER:=300}"
: "${RECOVERY_AFTER:=180}"
: "${RENOTIFY_INTERVAL:=900}"
: "${MAX_RENOTIFICATIONS:=3}"
: "${ALERT_LANG:=en}"
: "${ALERT_TO:?ALERT_TO must be set}"  # mandatory
: "${ALERT_CC:=}"
: "${ALERT_BCC:=}"

# ---- Validation ----
is_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

log "Validating configuration"

for v in CHECK_INTERVAL ALERT_AFTER RECOVERY_AFTER RENOTIFY_INTERVAL MAX_RENOTIFICATIONS; do
  eval val=\$$v
  is_int "$val" || fail "$v must be an integer (got '$val')"
done

[ "$CHECK_INTERVAL" -ge 5 ] || fail "CHECK_INTERVAL must be >= 5 seconds"

[ -n "${ALERT_TO:-}" ] || warn "ALERT_TO is empty – notifications will fail"

# ---- Dependency checks ----
log "Checking dependencies"

command -v msmtp >/dev/null 2>&1 || fail "msmtp not found"
[ -x /app/scripts/monitor.sh ] || fail "monitor.sh not executable in /app/scripts"
[ -x /app/scripts/mailer.sh ] || fail "mailer.sh not executable in /app/scripts"

# ---- Template checks ----
TEMPLATE_DIR="/app/templates/${ALERT_LANG}"
[ -d "$TEMPLATE_DIR" ] || {
  warn "Templates for language '$ALERT_LANG' not found, falling back to en"
  TEMPLATE_DIR="/app/templates/en"
}

for t in alert re_alert recovery suppressed monitor_degraded monitor_recovered; do
  [ -f "$TEMPLATE_DIR/$t.txt" ] || warn "Missing template: $TEMPLATE_DIR/$t.txt"
done

# ---- State directories ----
log "Initializing state directories"
mkdir -p /app/state

# ---- Host access sanity check ----
if [ ! -r /host/proc/stat ] || [ ! -r /host/proc/meminfo ]; then
  warn "Host /proc not readable"
  warn "Expected bind mount: --mount type=bind,src=/proc,dst=/host/proc,ro"
fi

# ---- Configuration file sanity check ----
if [ ! -r /etc/msmtprc ]; then
  warn "msmtprc not found or unreadable at /etc/msmtprc"
  warn "Mailer will not function until user provides a valid configuration"
fi

# ---- Debug / Dry-run mode ----
if [ "${DRY_RUN:-0}" = "1" ]; then
  log "DRY_RUN enabled – testing mailer only"
  EVENT=alert \
  RESOURCE=test \
  VALUE=99 \
  THRESHOLD=80 \
  DURATION=300 \
  HOSTNAME="$(hostname)" \
  CONTAINER_NAME="$(hostname)" \
  TIMESTAMP="$(ts)" \
  /app/scripts/mailer.sh || fail "Dry-run mail test failed"
  log "Dry-run completed successfully"
  exit 0
fi

# ---- Start monitor ----
log "Starting LLHRM monitor"
exec /app/scripts/monitor.sh
