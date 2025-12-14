#!/bin/sh
# Lightweight Linux Host Resource Monitor (LLHRM)
#
# Linux-only host resource monitoring loop.
# Reads CPU, RAM and disk usage from the host system via
# explicit read-only bind mounts to /proc.
#
# Implements a time-based state machine to:
# - detect sustained threshold violations
# - avoid alerting on short spikes
# - handle alert, re-alert, suppression and recovery events
#
# Stores minimal persistent state per resource (not raw metrics)
# to ensure deterministic behavior across restarts.
#
# This script never modifies the host system.
# It requires a Linux host and access to host /proc files.


set -eu

STATE_DIR="/app/state"
PROC_BASE="/host/proc"
MONITOR_STATE_FILE="$STATE_DIR/monitor.state"

MAILER="/app/scripts/mailer.sh"   # Actualización de ruta

# ---- Helpers ----
now() { date +%s; }
ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

log()  { echo "[INFO]  $(ts) $*"; }
warn() { echo "[WARN]  $(ts) $*" >&2; }
err()  { echo "[ERROR] $(ts) $*" >&2; }

clamp_min() { [ "$1" -lt "$2" ] && echo "$2" || echo "$1"; }

notify() {
  EVENT="$1"
  export EVENT
  export HOSTNAME="$(hostname)"
  export CONTAINER_NAME="$(hostname)"
  export TIMESTAMP="$(ts)"
  export ALERT_LANG="${ALERT_LANG:-en}"  # Actualización para idioma de templates

  if ! "$MAILER"; then
    err "Failed to send notification EVENT=$EVENT"
  fi
}

# ---- Monitor state ----
init_monitor_state() {
  [ -f "$MONITOR_STATE_FILE" ] || cat >"$MONITOR_STATE_FILE" <<EOF
MONITOR_STATE=OK
LAST_OK_TS=0
LAST_ERROR_TS=0
ERROR_REASON=""
EOF
}

write_monitor_state() {
  cat >"$MONITOR_STATE_FILE" <<EOF
STATE=$MONITOR_STATE
LAST_OK_TS=$LAST_OK_TS
LAST_ERROR_TS=$LAST_ERROR_TS
ERROR_REASON="$ERROR_REASON"
EOF
}

# ---- Resource state ----
init_resource_state() {
  file="$1"
  [ -f "$file" ] || cat >"$file" <<'EOF'
STATE=OK
TIME_ABOVE=0
TIME_BELOW=0
LAST_ALERT_TS=0
LAST_RENOTIFY_TS=0
RENOTIFY_COUNT=0
EOF
}

write_resource_state() {
  file="$1"
  cat >"$file" <<EOF
STATE=$STATE
TIME_ABOVE=$TIME_ABOVE
TIME_BELOW=$TIME_BELOW
LAST_ALERT_TS=$LAST_ALERT_TS
LAST_RENOTIFY_TS=$LAST_RENOTIFY_TS
RENOTIFY_COUNT=$RENOTIFY_COUNT
EOF
}

# ---- Metric readers ----
read_cpu() {
  [ -r "$PROC_BASE/stat" ] || return 1

  l1=$(grep '^cpu ' "$PROC_BASE/stat") || return 1
  sleep 1
  l2=$(grep '^cpu ' "$PROC_BASE/stat") || return 1

  set -- $l1; idle1=$5; total1=0; for v in $@; do total1=$((total1+v)); done
  set -- $l2; idle2=$5; total2=0; for v in $@; do total2=$((total2+v)); done

  dtotal=$((total2-total1))
  didle=$((idle2-idle1))

  [ "$dtotal" -gt 0 ] || return 1
  echo $((100*(dtotal-didle)/dtotal))
}

read_ram() {
  [ -r "$PROC_BASE/meminfo" ] || return 1

  awk '/MemTotal|MemAvailable/ {a[$1]=$2}
       END {if (a["MemTotal:"]>0) print int(100*(1-a["MemAvailable:"]/a["MemTotal:"])); else exit 1}' \
       "$PROC_BASE/meminfo"
}

read_disk() {
  df -P / | awk 'NR==2{gsub(/%/,"",$5);print $5}' || return 1
}

# ---- Evaluation ----
eval_resource() {
  name="$1"; value="$2"; threshold="$3"
  statefile="$STATE_DIR/$name.state"

  init_resource_state "$statefile"
  . "$statefile"

  export RESOURCE="$name"
  export VALUE="$value"
  export THRESHOLD="$threshold"

  if [ "$value" -ge "$threshold" ]; then
    TIME_ABOVE=$((TIME_ABOVE+CHECK_INTERVAL))
    TIME_BELOW=0
  else
    TIME_BELOW=$((TIME_BELOW+CHECK_INTERVAL))
    TIME_ABOVE=0
  fi

  NOW=$(now)

  case "$STATE" in
    OK)
      if [ "$TIME_ABOVE" -ge "$ALERT_AFTER" ]; then
        STATE=ALERT
        LAST_ALERT_TS=$NOW
        LAST_RENOTIFY_TS=$NOW
        RENOTIFY_COUNT=0
        export DURATION="$TIME_ABOVE"
        log "ALERT $name=${value}%"
        notify alert
      fi
      ;;
    ALERT)
      if [ "$TIME_BELOW" -ge "$RECOVERY_AFTER" ]; then
        STATE=OK
        export RECOVERY_DURATION="$TIME_BELOW"
        log "RECOVERY $name=${value}%"
        notify recovery
        TIME_ABOVE=0; TIME_BELOW=0
        LAST_ALERT_TS=0; LAST_RENOTIFY_TS=0; RENOTIFY_COUNT=0
      elif [ $((NOW-LAST_RENOTIFY_TS)) -ge "$RENOTIFY_INTERVAL" ] \
           && [ "$RENOTIFY_COUNT" -lt "$MAX_RENOTIFICATIONS" ]; then
        LAST_RENOTIFY_TS=$NOW
        RENOTIFY_COUNT=$((RENOTIFY_COUNT+1))
        export RENOTIFY_COUNT MAX_RENOTIFICATIONS
        warn "RE-ALERT $name=${value}%"
        notify re_alert
        [ "$RENOTIFY_COUNT" -eq "$MAX_RENOTIFICATIONS" ] && STATE=SUPPRESSED
      fi
      ;;
    SUPPRESSED)
      if [ "$TIME_BELOW" -ge "$RECOVERY_AFTER" ]; then
        STATE=OK
        export RECOVERY_DURATION="$TIME_BELOW"
        log "RECOVERY (after suppression) $name=${value}%"
        notify recovery
        TIME_ABOVE=0; TIME_BELOW=0
        LAST_ALERT_TS=0; LAST_RENOTIFY_TS=0; RENOTIFY_COUNT=0
      fi
      ;;
  esac

  write_resource_state "$statefile"
}

# ---- Main ----
mkdir -p "$STATE_DIR"
CHECK_INTERVAL=$(clamp_min "$CHECK_INTERVAL" 5)

init_monitor_state
. "$MONITOR_STATE_FILE"

PREV_FAILED=""

while :; do
  FAILED=""

  cpu=$(read_cpu) || FAILED="$FAILED cpu"
  ram=$(read_ram) || FAILED="$FAILED ram"
  disk=$(read_disk) || FAILED="$FAILED disk"

  NOW=$(now)

  if [ -n "$FAILED" ]; then
    if [ "$MONITOR_STATE" != "DEGRADED" ]; then
      MONITOR_STATE="DEGRADED"
      LAST_ERROR_TS=$NOW
      ERROR_REASON="Failed metrics:$FAILED"
      export FAILED_METRICS="$(echo "$FAILED" | sed 's/^ *//')"
      warn "MONITOR DEGRADED:$FAILED"
      notify monitor_degraded
      write_monitor_state
    fi
    PREV_FAILED="$FAILED"
    sleep "$CHECK_INTERVAL"
    continue
  fi

  if [ "$MONITOR_STATE" = "DEGRADED" ]; then
    MONITOR_STATE="OK"
    LAST_OK_TS=$NOW
    export RECOVERED_METRICS="$PREV_FAILED"
    log "MONITOR RECOVERED"
    notify monitor_recovered
    write_monitor_state
  fi

  eval_resource cpu "$cpu" "$CPU_THRESHOLD"
  eval_resource ram "$ram" "$RAM_THRESHOLD"
  eval_resource disk "$disk" "$DISK_THRESHOLD"

  PREV_FAILED=""
  sleep "$CHECK_INTERVAL"
done