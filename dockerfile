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

# ---- Copy scripts and templates ----
COPY scripts/ /app/scripts/
COPY entrypoint.sh /app/
COPY templates/ /app/templates/

# ---- Permissions ----
RUN chmod +x /app/*.sh /app/scripts/*.sh \
 && mkdir -p /app/state \
 && touch /etc/msmtprc \
 && chown -R monitor:monitor /app /etc/msmtprc \
 && chmod 600 /etc/msmtprc

USER monitor

ENTRYPOINT ["/app/entrypoint.sh"]