#!/bin/sh
set -eu

if [ -z "${WEBDAV_DOMAIN:-}" ]; then
  echo "[webdav] ERROR: WEBDAV_DOMAIN is required."
  exit 1
fi

if [ -z "${ORGANICE_DOMAIN:-}" ]; then
  echo "[webdav] ERROR: ORGANICE_DOMAIN is required."
  exit 1
fi

if [ -z "${ORGANICE_ORIGIN:-}" ]; then
  echo "[webdav] ERROR: ORGANICE_ORIGIN is required."
  exit 1
fi

if [ "$ORGANICE_ORIGIN" != "https://${ORGANICE_DOMAIN}" ]; then
  echo "[webdav] ERROR: ORGANICE_ORIGIN must be exactly https://${ORGANICE_DOMAIN}."
  echo "[webdav] Received ORGANICE_ORIGIN=${ORGANICE_ORIGIN}"
  exit 1
fi

if [ -z "${WEBDAV_USERNAME:-}" ] || [ -z "${WEBDAV_PASSWORD:-}" ]; then
  echo "[webdav] ERROR: WEBDAV_USERNAME and WEBDAV_PASSWORD are required."
  exit 1
fi

WEBDAV_RUNTIME_MODE="${WEBDAV_RUNTIME_MODE:-production}"

if [ "$WEBDAV_RUNTIME_MODE" = "production" ]; then
  password_len="${#WEBDAV_PASSWORD}"
  has_lower=0
  has_upper=0
  has_digit=0

  if printf '%s' "$WEBDAV_PASSWORD" | grep -Eq '[a-z]'; then
    has_lower=1
  fi
  if printf '%s' "$WEBDAV_PASSWORD" | grep -Eq '[A-Z]'; then
    has_upper=1
  fi
  if printf '%s' "$WEBDAV_PASSWORD" | grep -Eq '[0-9]'; then
    has_digit=1
  fi

  if [ "$password_len" -lt 20 ] || [ "$has_lower" -ne 1 ] || [ "$has_upper" -ne 1 ] || [ "$has_digit" -ne 1 ]; then
    echo "[webdav] ERROR: Production password policy validation failed."
    echo "[webdav] Remediation: set WEBDAV_PASSWORD to >=20 chars with lowercase, uppercase, and digit."
    exit 1
  fi
fi

WEBDAV_UID="${WEBDAV_UID:-1000}"
WEBDAV_GID="${WEBDAV_GID:-1000}"

CERT_FILE="/certs/live/${WEBDAV_DOMAIN}/fullchain.pem"
KEY_FILE="/certs/live/${WEBDAV_DOMAIN}/privkey.pem"
ORGANICE_CERT_FILE="/certs/live/${ORGANICE_DOMAIN}/fullchain.pem"
ORGANICE_KEY_FILE="/certs/live/${ORGANICE_DOMAIN}/privkey.pem"

if [ ! -r "$CERT_FILE" ] || [ ! -r "$KEY_FILE" ]; then
  echo "[webdav] ERROR: Missing TLS certificate files for WEBDAV_DOMAIN=${WEBDAV_DOMAIN}."
  echo "[webdav] Expected: $CERT_FILE and $KEY_FILE"
  exit 1
fi

if [ ! -r "$ORGANICE_CERT_FILE" ] || [ ! -r "$ORGANICE_KEY_FILE" ]; then
  echo "[webdav] ERROR: Missing TLS certificate files for ORGANICE_DOMAIN=${ORGANICE_DOMAIN}."
  echo "[webdav] Expected: $ORGANICE_CERT_FILE and $ORGANICE_KEY_FILE"
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "[webdav] ERROR: openssl binary not found in container image."
  exit 1
fi

if ! openssl x509 -in "$CERT_FILE" -noout >/dev/null 2>&1; then
  echo "[webdav] ERROR: Invalid certificate file for WEBDAV_DOMAIN=${WEBDAV_DOMAIN}: $CERT_FILE"
  exit 1
fi

if ! openssl pkey -in "$KEY_FILE" -noout >/dev/null 2>&1; then
  echo "[webdav] ERROR: Invalid private key file for WEBDAV_DOMAIN=${WEBDAV_DOMAIN}: $KEY_FILE"
  exit 1
fi

if ! openssl x509 -in "$ORGANICE_CERT_FILE" -noout >/dev/null 2>&1; then
  echo "[webdav] ERROR: Invalid certificate file for ORGANICE_DOMAIN=${ORGANICE_DOMAIN}: $ORGANICE_CERT_FILE"
  exit 1
fi

if ! openssl pkey -in "$ORGANICE_KEY_FILE" -noout >/dev/null 2>&1; then
  echo "[webdav] ERROR: Invalid private key file for ORGANICE_DOMAIN=${ORGANICE_DOMAIN}: $ORGANICE_KEY_FILE"
  exit 1
fi

ORGNOTE_DOMAIN="${ORGNOTE_DOMAIN:-}"
ORGNOTE_CERT_FILE=""
if [ -n "$ORGNOTE_DOMAIN" ]; then
  ORGNOTE_CERT_FILE="/certs/live/${ORGNOTE_DOMAIN}/fullchain.pem"
  ORGNOTE_KEY_FILE="/certs/live/${ORGNOTE_DOMAIN}/privkey.pem"
  if [ ! -r "$ORGNOTE_CERT_FILE" ] || [ ! -r "$ORGNOTE_KEY_FILE" ]; then
    echo "[webdav] ERROR: Missing TLS certificate files for ORGNOTE_DOMAIN=${ORGNOTE_DOMAIN}."
    echo "[webdav] Expected: $ORGNOTE_CERT_FILE and $ORGNOTE_KEY_FILE"
    echo "[webdav] Issue it first (certbot profile) or unset ORGNOTE_DOMAIN."
    exit 1
  fi
  if ! openssl x509 -in "$ORGNOTE_CERT_FILE" -noout >/dev/null 2>&1; then
    echo "[webdav] ERROR: Invalid certificate file for ORGNOTE_DOMAIN=${ORGNOTE_DOMAIN}: $ORGNOTE_CERT_FILE"
    exit 1
  fi
fi

if ! command -v htpasswd >/dev/null 2>&1; then
  echo "[webdav] ERROR: htpasswd binary not found in container image."
  exit 1
fi

# The served subtree must be writable by the unprivileged httpd user: Apache
# DAV writes to a temp file and renames it, which needs directory permissions.
mkdir -p /data/tasks
chown -R "${WEBDAV_UID}:${WEBDAV_GID}" /data/tasks

HTPASSWD_FILE="/usr/local/apache2/conf/webdav.htpasswd"
htpasswd -bc "$HTPASSWD_FILE" "$WEBDAV_USERNAME" "$WEBDAV_PASSWORD"

CONF_TEMPLATE="/usr/local/apache2/conf/extra/httpd-webdav.conf.template"
CONF_OUTPUT="/usr/local/apache2/conf/extra/httpd-webdav.conf"

if [ ! -r "$CONF_TEMPLATE" ]; then
  echo "[webdav] ERROR: Missing Apache template: $CONF_TEMPLATE"
  exit 1
fi

sed "s|@@WEBDAV_DOMAIN@@|$WEBDAV_DOMAIN|g; s|@@ORGANICE_DOMAIN@@|$ORGANICE_DOMAIN|g; s|@@ORGANICE_ORIGIN@@|$ORGANICE_ORIGIN|g; s|@@WEBDAV_CERT_FILE@@|$CERT_FILE|g; s|@@WEBDAV_KEY_FILE@@|$KEY_FILE|g; s|@@ORGANICE_CERT_FILE@@|$ORGANICE_CERT_FILE|g; s|@@ORGANICE_KEY_FILE@@|$ORGANICE_KEY_FILE|g" "$CONF_TEMPLATE" > "$CONF_OUTPUT"

ORGNOTE_TEMPLATE="/usr/local/apache2/conf/extra/httpd-orgnote.conf.template"
ORGNOTE_OUTPUT="/usr/local/apache2/conf/extra/httpd-orgnote.conf"
if [ -n "$ORGNOTE_DOMAIN" ]; then
  sed "s|@@ORGNOTE_DOMAIN@@|$ORGNOTE_DOMAIN|g; s|@@ORGNOTE_CERT_FILE@@|$ORGNOTE_CERT_FILE|g; s|@@ORGNOTE_KEY_FILE@@|$ORGNOTE_KEY_FILE|g" "$ORGNOTE_TEMPLATE" > "$ORGNOTE_OUTPUT"
  echo "[webdav] INFO: orgnote API proxy enabled for ${ORGNOTE_DOMAIN}."
else
  # Keep the Include valid while orgnote is disabled.
  : > "$ORGNOTE_OUTPUT"
fi

httpd_conf="/usr/local/apache2/conf/httpd.conf"
sed -i 's/^#\(LoadModule ssl_module modules\/mod_ssl.so\)$/\1/' "$httpd_conf"
sed -i 's/^#\(LoadModule socache_shmcb_module modules\/mod_socache_shmcb.so\)$/\1/' "$httpd_conf"
sed -i 's/^#\(LoadModule dav_module modules\/mod_dav.so\)$/\1/' "$httpd_conf"
sed -i 's/^#\(LoadModule dav_fs_module modules\/mod_dav_fs.so\)$/\1/' "$httpd_conf"
sed -i 's/^#\(LoadModule rewrite_module modules\/mod_rewrite.so\)$/\1/' "$httpd_conf"
sed -i 's/^#\(LoadModule headers_module modules\/mod_headers.so\)$/\1/' "$httpd_conf"
sed -i 's/^#\(LoadModule proxy_module modules\/mod_proxy.so\)$/\1/' "$httpd_conf"
sed -i 's/^#\(LoadModule proxy_http_module modules\/mod_proxy_http.so\)$/\1/' "$httpd_conf"
sed -i 's/^#\(LoadModule authn_file_module modules\/mod_authn_file.so\)$/\1/' "$httpd_conf"
sed -i 's/^#\(LoadModule auth_basic_module modules\/mod_auth_basic.so\)$/\1/' "$httpd_conf"
sed -i "s/^User .*/User #${WEBDAV_UID}/" "$httpd_conf"
sed -i "s/^Group .*/Group #${WEBDAV_GID}/" "$httpd_conf"

if ! grep -q '^Include conf/extra/httpd-webdav.conf$' "$httpd_conf"; then
  printf '\nInclude conf/extra/httpd-webdav.conf\n' >> "$httpd_conf"
fi
if ! grep -q '^Include conf/extra/httpd-orgnote.conf$' "$httpd_conf"; then
  printf 'Include conf/extra/httpd-orgnote.conf\n' >> "$httpd_conf"
fi

# --- Certificate auto-reload watcher -----------------------------------------
# Polling interval (seconds) for detecting on-disk certificate renewals.
# Default 300s; clamped to a minimum of 60s to prevent tight polling loops.
WEBDAV_CERT_RELOAD_INTERVAL="${WEBDAV_CERT_RELOAD_INTERVAL:-300}"
case "$WEBDAV_CERT_RELOAD_INTERVAL" in
  ''|*[!0-9]*)
    echo "[webdav] WARN: WEBDAV_CERT_RELOAD_INTERVAL='${WEBDAV_CERT_RELOAD_INTERVAL}' is not a valid integer; using default 300."
    WEBDAV_CERT_RELOAD_INTERVAL=300
    ;;
esac
if [ "$WEBDAV_RUNTIME_MODE" = "production" ] && [ "$WEBDAV_CERT_RELOAD_INTERVAL" -lt 60 ]; then
  echo "[webdav] INFO: WEBDAV_CERT_RELOAD_INTERVAL=${WEBDAV_CERT_RELOAD_INTERVAL} is below the 60s minimum; clamping to 60."
  WEBDAV_CERT_RELOAD_INTERVAL=60
fi

# Background watcher: detects cert fingerprint changes and gracefully reloads
# httpd. Runs as a background subshell so httpd stays PID 1 (correct signal
# handling on docker stop). The loop is defensive and never exits.
(
  set +e
  first_poll="true"
  prev_cert_fp=""
  prev_organice_fp=""
  prev_orgnote_fp=""

  while true; do
    sleep "$WEBDAV_CERT_RELOAD_INTERVAL"

    cert_fp="$(openssl x509 -in "$CERT_FILE" -noout -fingerprint -sha256 2>/dev/null)"
    organice_fp="$(openssl x509 -in "$ORGANICE_CERT_FILE" -noout -fingerprint -sha256 2>/dev/null)"
    orgnote_fp=""
    if [ -n "$ORGNOTE_CERT_FILE" ]; then
      orgnote_fp="$(openssl x509 -in "$ORGNOTE_CERT_FILE" -noout -fingerprint -sha256 2>/dev/null)"
    fi

    # Transient openssl failure: skip this poll, retry next interval.
    if [ -z "$cert_fp" ] || [ -z "$organice_fp" ]; then
      echo "[webdav] WARN: certificate fingerprint computation failed; skipping this poll."
      continue
    fi

    # Bootstrap: record baseline fingerprints without reloading (httpd loaded
    # the current on-disk certs at startup).
    if [ "$first_poll" = "true" ]; then
      prev_cert_fp="$cert_fp"
      prev_organice_fp="$organice_fp"
      prev_orgnote_fp="$orgnote_fp"
      first_poll="false"
      echo "[webdav] INFO: certificate watcher armed (interval=${WEBDAV_CERT_RELOAD_INTERVAL}s)."
      continue
    fi

    # Reload only when a monitored fingerprint changed.
    if [ "$cert_fp" != "$prev_cert_fp" ] || [ "$organice_fp" != "$prev_organice_fp" ] || [ "$orgnote_fp" != "$prev_orgnote_fp" ]; then
      echo "[webdav] INFO: certificate change detected; reloading httpd."
      if httpd -k graceful; then
        prev_cert_fp="$cert_fp"
        prev_organice_fp="$organice_fp"
        prev_orgnote_fp="$orgnote_fp"
        echo "[webdav] INFO: httpd graceful reload complete."
      else
        # Non-fatal: logged and retried on the next poll.
        echo "[webdav] ERROR: httpd graceful reload failed; will retry on the next poll."
      fi
    fi
  done
) &

exec httpd -DFOREGROUND
