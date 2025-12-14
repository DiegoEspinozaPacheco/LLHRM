#!/bin/sh
set -eu

TEMPLATE_BASE="/app/templates"
LANG="${ALERT_LANG:-en}"

log() {
  echo "[MAILER] $*" >&2
}

warn() {
  echo "[MAILER] WARNING: $*" >&2
}

fail() {
  log "ERROR: $*"
  exit 1
}

# ---- Validate required variables ----
EVENT="${EVENT:-}"
[ -n "$EVENT" ] || fail "EVENT not set"

[ -n "$ALERT_TO" ] || warn "ALERT_TO is empty – notifications will likely fail"

TEMPLATE="$TEMPLATE_BASE/$LANG/${EVENT}.txt"

# Fallback to English template
[ -f "$TEMPLATE" ] || TEMPLATE="$TEMPLATE_BASE/en/${EVENT}.txt"
[ -f "$TEMPLATE" ] || fail "Template not found for event: $EVENT"

TMP_MAIL="$(mktemp)"

# ---- Variable substitution ----
sed \
  -e "s/{{RESOURCE}}/${RESOURCE:-unknown}/g" \
  -e "s/{{VALUE}}/${VALUE:-unknown}/g" \
  -e "s/{{THRESHOLD}}/${THRESHOLD:-unknown}/g" \
  -e "s/{{DURATION}}/${DURATION:-0}/g" \
  -e "s/{{RECOVERY_DURATION}}/${RECOVERY_DURATION:-0}/g" \
  -e "s/{{RENOTIFY_COUNT}}/${RENOTIFY_COUNT:-0}/g" \
  -e "s/{{MAX_RENOTIFICATIONS}}/${MAX_RENOTIFICATIONS:-0}/g" \
  -e "s/{{FAILED_METRICS}}/${FAILED_METRICS:-none}/g" \
  -e "s/{{RECOVERED_METRICS}}/${RECOVERED_METRICS:-none}/g" \
  -e "s/{{HOSTNAME}}/${HOSTNAME:-unknown}/g" \
  -e "s/{{CONTAINER_NAME}}/${CONTAINER_NAME:-unknown}/g" \
  -e "s/{{TIMESTAMP}}/${TIMESTAMP:-unknown}/g" \
  "$TEMPLATE" > "$TMP_MAIL"

# ---- Extract subject and body ----
SUBJECT="$(sed -n 's/^Subject: //p' "$TMP_MAIL" | head -n1)"
BODY="$(sed '/^Subject: /d' "$TMP_MAIL")"

# ---- Build email ----
{
  echo "To: $ALERT_TO"
  [ -n "$ALERT_CC" ] && echo "Cc: $ALERT_CC"
  [ -n "$ALERT_BCC" ] && echo "Bcc: $ALERT_BCC"
  echo "Subject: $SUBJECT"
  echo
  echo "$BODY"
} > "$TMP_MAIL.email"

# ---- Send email ----
if ! command -v msmtp >/dev/null 2>&1; then
  warn "msmtp not found – cannot send email"
else
  if ! msmtp -t < "$TMP_MAIL.email"; then
    warn "msmtp failed – check /etc/msmtprc, credentials and connectivity"
  else
    log "Notification sent: EVENT=$EVENT RESOURCE=${RESOURCE:-n/a}"
  fi
fi

# ---- Cleanup ----
rm -f "$TMP_MAIL" "$TMP_MAIL.email"