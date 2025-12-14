# syntax=docker/dockerfile:1
FROM alpine:3.20

LABEL org.opencontainers.image.title="Linux Lightweight Host Resource Monitor" \
      org.opencontainers.image.description="Linux Lightweight host resource monitor with email alerts. Community project, AI-assisted." \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.authors="Diego Espinoza Pacheco" \
      org.opencontainers.image.licenses="Unlicense" \
      org.opencontainers.image.documentation="https://github.com/DiegoEspinozaPacheco/LLHRM/blob/main/README.md" \
      org.opencontainers.image.source="https://github.com/DiegoEspinozaPacheco/LLHRM.git"

# ---- Dependencies ----
RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    msmtp \
    busybox-extras

# ---- Non-root user ----
RUN addgroup -S monitor && adduser -S monitor -G monitor

WORKDIR /app

# ---- Configuration variables ----
# Default values for the container. You can either:
# 1) Rebuild the image with updated defaults in this Dockerfile, or
# 2) Override these defaults at runtime using `-e VARIABLE=value` with `docker run`
# Thresholds are in percentages (%) and times in seconds.
ENV ALERT_TO="" \
    ALERT_CC="" \
    ALERT_BCC="" \
    ALERT_LANG="en" \
    CPU_THRESHOLD=80 \
    RAM_THRESHOLD=85 \
    DISK_THRESHOLD=85 \
    CHECK_INTERVAL=60 \
    ALERT_AFTER=300 \
    RECOVERY_AFTER=300 \
    RENOTIFY_INTERVAL=300 \
    MAX_RENOTIFICATIONS=3 \
    CONTAINER_NAME="LLHRM"

# ---- Copy scripts and templates ----
COPY scripts/ /app/scripts/
COPY entrypoint.sh /app/
COPY templates/ /app/templates/
COPY config/msmtprc /etc/msmtprc

# ---- Permissions ----
RUN chmod +x /app/*.sh /app/scripts/*.sh \
 && mkdir -p /app/state \
 && chown -R monitor:monitor /app \
 && chown monitor:monitor /etc/msmtprc \
 && chmod 600 /etc/msmtprc

USER monitor

ENTRYPOINT ["/app/entrypoint.sh"]