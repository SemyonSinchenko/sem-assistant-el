#!/bin/bash
# Run a local Apache with the production vhost template (webdav/apache/
# httpd-webdav.conf.template) for org-ui end-to-end tests. Paths are
# rewritten to a temp directory; nothing touches real data.
#
# Usage: org-ui/e2e/local-apache.sh start|stop  (needs apache2 + openssl)
# Env:   PORT (16065), ROOT (/tmp/org-ui-e2e), DAV_USER, DAV_PASS

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
PORT="${PORT:-16065}"
ROOT="${ROOT:-/tmp/org-ui-e2e}"
DAV_USER="${DAV_USER:-orgzly}"
DAV_PASS="${DAV_PASS:-E2eTestPassword2026Strong}"
MODS="${APACHE_MODULES:-/usr/lib/apache2/modules}"
HTTPD="${HTTPD:-apache2}"

stop() {
  if [[ -f "$ROOT/httpd.pid" ]]; then
    local pid
    pid="$(cat "$ROOT/httpd.pid")"
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
    rm -f "$ROOT/httpd.pid"
  fi
}

start() {
  stop
  mkdir -p "$ROOT/tasks" "$ROOT/certs" "$ROOT/logs"
  [[ -f "$ROOT/certs/cert.pem" ]] || openssl req -x509 -nodes -newkey rsa:2048 -days 2 \
    -keyout "$ROOT/certs/key.pem" -out "$ROOT/certs/cert.pem" -subj "/CN=localhost" >/dev/null 2>&1
  htpasswd -bc "$ROOT/htpasswd" "$DAV_USER" "$DAV_PASS" >/dev/null 2>&1

  # first vhost only (WebDAV + /ui); the organice proxy vhost is not needed here
  awk '/^<VirtualHost/{n++} n<=1' "$REPO/webdav/apache/httpd-webdav.conf.template" |
    sed -e "s|@@WEBDAV_DOMAIN@@|localhost|g" \
        -e "s|@@ORGANICE_ORIGIN@@|https://organice.invalid|g" \
        -e "s|@@WEBDAV_CERT_FILE@@|$ROOT/certs/cert.pem|g" \
        -e "s|@@WEBDAV_KEY_FILE@@|$ROOT/certs/key.pem|g" \
        -e "s|Listen 6065|Listen $PORT|" \
        -e "s|<VirtualHost \*:6065>|<VirtualHost *:$PORT>|" \
        -e "s|/data/tasks|$ROOT/tasks|g" \
        -e "s|/usr/local/apache2/ui|$REPO/org-ui/dist|g" \
        -e "s|/usr/local/apache2/conf/webdav.htpasswd|$ROOT/htpasswd|g" \
        -e "s|DavLockDB /tmp/DavLock|DavLockDB $ROOT/DavLock|" \
        -e "s|/proc/self/fd/2|$ROOT/logs/error.log|; s|/proc/self/fd/1 combined|$ROOT/logs/access.log combined|" \
        >"$ROOT/vhost.conf"

  cat >"$ROOT/httpd.conf" <<EOF
ServerRoot "$ROOT"
PidFile "$ROOT/httpd.pid"
ServerName localhost
LoadModule mpm_event_module $MODS/mod_mpm_event.so
LoadModule authz_core_module $MODS/mod_authz_core.so
LoadModule authz_user_module $MODS/mod_authz_user.so
LoadModule authn_core_module $MODS/mod_authn_core.so
LoadModule authn_file_module $MODS/mod_authn_file.so
LoadModule auth_basic_module $MODS/mod_auth_basic.so
LoadModule alias_module $MODS/mod_alias.so
LoadModule dir_module $MODS/mod_dir.so
LoadModule mime_module $MODS/mod_mime.so
LoadModule headers_module $MODS/mod_headers.so
LoadModule ssl_module $MODS/mod_ssl.so
LoadModule socache_shmcb_module $MODS/mod_socache_shmcb.so
LoadModule dav_module $MODS/mod_dav.so
LoadModule dav_fs_module $MODS/mod_dav_fs.so
TypesConfig /etc/mime.types
DirectoryIndex index.html
ErrorLog "$ROOT/logs/error.log"
Include "$ROOT/vhost.conf"
EOF
  "$HTTPD" -f "$ROOT/httpd.conf" -k start
  for _ in $(seq 1 20); do
    curl -ks -o /dev/null "https://localhost:$PORT/ui/" && { echo "Apache up: https://localhost:$PORT/ (user $DAV_USER)"; return 0; }
    sleep 0.3
  done
  echo "Apache did not start; see $ROOT/logs/error.log" >&2
  exit 1
}

case "${1:-start}" in
  start) start ;;
  stop) stop ;;
  *) echo "usage: $0 start|stop" >&2; exit 2 ;;
esac
