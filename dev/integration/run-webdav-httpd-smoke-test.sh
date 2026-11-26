#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker-compose.yml"
COMPOSE_OVERRIDE="$SCRIPT_DIR/docker-compose.webdav-httpd.test.yml"
TEST_DATA_DIR="$REPO_ROOT/test-data-httpd"
# Apache serves only the /data/tasks subtree of the mounted volume.
TEST_SERVED_DIR="$TEST_DATA_DIR/tasks"
TEST_CERTS_DIR="$REPO_ROOT/test-data-httpd-certs"

WEBDAV_PORT="${WEBDAV_PORT:-16066}"
WEBDAV_DOMAIN="${WEBDAV_DOMAIN:-webdav-test.local}"
ORGANICE_DOMAIN="${ORGANICE_DOMAIN:-organice-test.local}"
ORGANICE_ORIGIN="${ORGANICE_ORIGIN:-https://organice-test.local}"
WEBDAV_USERNAME="${WEBDAV_USERNAME:-orgzly}"
WEBDAV_PASSWORD="${WEBDAV_PASSWORD:-SmokeTestPassword2026Strong}"
WEBDAV_UID="${WEBDAV_UID:-$(id -u)}"
WEBDAV_GID="${WEBDAV_GID:-$(id -g)}"
WEBDAV_BASE_URL="https://localhost:${WEBDAV_PORT}"

export WEBDAV_PORT
export WEBDAV_DOMAIN
export ORGANICE_DOMAIN
export ORGANICE_ORIGIN
export WEBDAV_USERNAME
export WEBDAV_PASSWORD
export WEBDAV_UID
export WEBDAV_GID

COMPOSE_CMD=""
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v podman-compose >/dev/null 2>&1; then
  COMPOSE_CMD="podman-compose"
else
  echo "ERROR: neither 'docker compose' nor 'podman-compose' is available." >&2
  exit 1
fi

cleanup() {
  echo ""
  echo "== Cleanup =="
  $COMPOSE_CMD -f "$COMPOSE_FILE" -f "$COMPOSE_OVERRIDE" down -v >/dev/null 2>&1 || true
}
trap cleanup EXIT

assert_status() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $label (expected HTTP $expected, got $actual)"
    exit 1
  fi
  echo "PASS: $label (HTTP $actual)"
}

extract_etag() {
  local path="$1"
  local etag
  etag=$(curl -k -sS -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" -I "${WEBDAV_BASE_URL}/${path}" | awk -F': ' 'tolower($1)=="etag"{gsub("\r", "", $2); print $2; exit}')
  if [[ -z "$etag" ]]; then
    echo "FAIL: missing ETag for ${path}" >&2
    exit 1
  fi
  printf '%s' "$etag"
}

extract_last_modified() {
  local path="$1"
  local last_modified
  last_modified=$(curl -k -sS -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" -I "${WEBDAV_BASE_URL}/${path}" | awk -F': ' 'tolower($1)=="last-modified"{gsub("\r", "", $2); print $2; exit}')
  if [[ -z "$last_modified" ]]; then
    echo "FAIL: missing Last-Modified for ${path}" >&2
    exit 1
  fi
  printf '%s' "$last_modified"
}

echo "== Preparing fixture data =="
rm -rf "$TEST_DATA_DIR" "$TEST_CERTS_DIR" 2>/dev/null || true
if [[ -d "$TEST_DATA_DIR" || -d "$TEST_CERTS_DIR" ]]; then
  if command -v podman >/dev/null 2>&1; then
    podman unshare rm -rf "$TEST_DATA_DIR" "$TEST_CERTS_DIR" >/dev/null 2>&1 || true
  fi
fi
mkdir -p "$TEST_SERVED_DIR" "$TEST_CERTS_DIR/live/$WEBDAV_DOMAIN" "$TEST_CERTS_DIR/live/$ORGANICE_DOMAIN"
printf 'v1\n' > "$TEST_SERVED_DIR/simple.txt"
# The compose file mounts ./org-ui/dist at /ui; make sure something is there.
if [[ ! -f "$REPO_ROOT/org-ui/dist/index.html" ]]; then
  mkdir -p "$REPO_ROOT/org-ui/dist"
  printf '<!doctype html><title>org-ui smoke</title>\n' > "$REPO_ROOT/org-ui/dist/index.html"
fi

openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout "$TEST_CERTS_DIR/live/$WEBDAV_DOMAIN/privkey.pem" \
  -out "$TEST_CERTS_DIR/live/$WEBDAV_DOMAIN/fullchain.pem" \
  -days 1 \
  -subj "/CN=$WEBDAV_DOMAIN" >/dev/null 2>&1

openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout "$TEST_CERTS_DIR/live/$ORGANICE_DOMAIN/privkey.pem" \
  -out "$TEST_CERTS_DIR/live/$ORGANICE_DOMAIN/fullchain.pem" \
  -days 1 \
  -subj "/CN=$ORGANICE_DOMAIN" >/dev/null 2>&1

echo "== Starting isolated WebDAV (Apache/mod_dav) =="
$COMPOSE_CMD -f "$COMPOSE_FILE" -f "$COMPOSE_OVERRIDE" up -d webdav >/dev/null

echo "== Waiting for WebDAV readiness =="
ready="false"
for attempt in $(seq 1 20); do
  status=$(curl -k -sS -o /dev/null -w '%{http_code}' -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" "${WEBDAV_BASE_URL}/simple.txt" || true)
  if [[ "$status" == "200" ]]; then
    ready="true"
    break
  fi
  sleep 1
done
if [[ "$ready" != "true" ]]; then
  echo "FAIL: WebDAV did not become ready"
  exit 1
fi

echo "== Check 1: data mount semantics (host -> WebDAV) =="
downloaded=$(curl -k -sS -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" "${WEBDAV_BASE_URL}/simple.txt")
if [[ "$downloaded" != $'v1' ]]; then
  echo "FAIL: WebDAV did not expose host-mounted /data content"
  exit 1
fi
echo "PASS: WebDAV reads host-mounted data"

echo "== Check 2: conditional PUT behavior =="
# organice writes without preconditions; such PUTs must keep working.
status_no_header=$(curl -k -sS -o /dev/null -w '%{http_code}' \
  -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
  -X PUT --data-binary $'v2-no-header\n' \
  "${WEBDAV_BASE_URL}/simple.txt" || true)
if [[ ! "$status_no_header" =~ ^20[0-9]$ ]]; then
  echo "FAIL: unconditional PUT should succeed, got HTTP $status_no_header"
  exit 1
fi
echo "PASS: unconditional PUT accepted (HTTP $status_no_header)"
sleep 1
etag_v1=$(extract_etag "simple.txt")
echo "INFO: detected ETag: ${etag_v1}"

if [[ "$etag_v1" =~ ^W/ ]]; then
  echo "INFO: weak ETag detected; using If-Unmodified-Since for positive conditional checks"

  lm_v1=$(extract_last_modified "simple.txt")
  lm_future_valid=$(date -u -d '+120 seconds' '+%a, %d %b %Y %H:%M:%S GMT' 2>/dev/null || true)
  if [[ -z "$lm_future_valid" ]]; then
    lm_future_valid="$lm_v1"
  fi
  status_valid=$(curl -k -sS -o /dev/null -w '%{http_code}' \
    -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
    -H "If-Unmodified-Since: ${lm_future_valid}" \
    -X PUT --data-binary $'v2\n' \
    "${WEBDAV_BASE_URL}/simple.txt" || true)
  if [[ ! "$status_valid" =~ ^20[0-9]$ ]]; then
    echo "FAIL: valid conditional PUT should succeed, got HTTP $status_valid"
    exit 1
  fi
  echo "PASS: valid conditional PUT accepted (HTTP $status_valid)"

  echo "== Check 3: stale conditional PUT rejection =="
  printf 'v3-host-side-change\n' > "$TEST_SERVED_DIR/simple.txt"

  status_stale=$(curl -k -sS -o /dev/null -w '%{http_code}' \
    -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
    -H "If-Unmodified-Since: ${lm_v1}" \
    -X PUT --data-binary $'v4-stale-should-fail\n' \
    "${WEBDAV_BASE_URL}/simple.txt" || true)
  assert_status "412" "$status_stale" "stale conditional PUT rejected"

  sleep 1
  lm_v3=$(extract_last_modified "simple.txt")
  lm_future=$(date -u -d '+120 seconds' '+%a, %d %b %Y %H:%M:%S GMT' 2>/dev/null || true)
  if [[ -z "$lm_future" ]]; then
    lm_future="$lm_v3"
  fi
  status_fresh=$(curl -k -sS -o /dev/null -w '%{http_code}' \
    -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
    -H "If-Unmodified-Since: ${lm_future}" \
    -X PUT --data-binary $'v4-fresh\n' \
    "${WEBDAV_BASE_URL}/simple.txt" || true)
  if [[ ! "$status_fresh" =~ ^20[0-9]$ ]]; then
    echo "FAIL: fresh conditional PUT should succeed, got HTTP $status_fresh"
    exit 1
  fi
  echo "PASS: fresh conditional PUT accepted (HTTP $status_fresh)"
else
  status_valid=$(curl -k -sS -o /dev/null -w '%{http_code}' \
    -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
    -H "If-Match: ${etag_v1}" \
    -X PUT --data-binary $'v2\n' \
    "${WEBDAV_BASE_URL}/simple.txt" || true)
  if [[ ! "$status_valid" =~ ^20[0-9]$ ]]; then
    echo "FAIL: valid conditional PUT should succeed, got HTTP $status_valid"
    exit 1
  fi
  echo "PASS: valid conditional PUT accepted (HTTP $status_valid)"

  etag_v2=$(extract_etag "simple.txt")

  echo "== Check 3: stale conditional PUT rejection =="
  printf 'v3-host-side-change\n' > "$TEST_SERVED_DIR/simple.txt"

  status_stale=$(curl -k -sS -o /dev/null -w '%{http_code}' \
    -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
    -H "If-Match: ${etag_v2}" \
    -X PUT --data-binary $'v4-stale-should-fail\n' \
    "${WEBDAV_BASE_URL}/simple.txt" || true)
  assert_status "412" "$status_stale" "stale conditional PUT rejected"

  sleep 1
  etag_v3=$(extract_etag "simple.txt")
  status_fresh=$(curl -k -sS -o /dev/null -w '%{http_code}' \
    -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
    -H "If-Match: ${etag_v3}" \
    -X PUT --data-binary $'v4-fresh\n' \
    "${WEBDAV_BASE_URL}/simple.txt" || true)
  if [[ ! "$status_fresh" =~ ^20[0-9]$ ]]; then
    echo "FAIL: fresh conditional PUT should succeed, got HTTP $status_fresh"
    exit 1
  fi
  echo "PASS: fresh conditional PUT accepted (HTTP $status_fresh)"
fi

echo "== Check 4: data mount semantics (WebDAV -> host) =="
host_content=$(cat "$TEST_SERVED_DIR/simple.txt")
if [[ "$host_content" != $'v4-fresh' ]]; then
  echo "FAIL: WebDAV write did not persist to host-mounted /data"
  exit 1
fi
echo "PASS: WebDAV writes persist to host-mounted data"

echo "== Check 5: allowed origin returns deterministic CORS headers =="
allowed_headers=$(curl -k -sS -o /dev/null -D - \
  -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
  -H "Origin: ${ORGANICE_ORIGIN}" \
  "${WEBDAV_BASE_URL}/simple.txt")
if [[ "$allowed_headers" != *"Access-Control-Allow-Origin: ${ORGANICE_ORIGIN}"* ]]; then
  echo "FAIL: allowed origin did not receive Access-Control-Allow-Origin"
  exit 1
fi
if [[ "$allowed_headers" != *"Access-Control-Allow-Credentials: true"* ]]; then
  echo "FAIL: allowed origin did not receive Access-Control-Allow-Credentials"
  exit 1
fi
if [[ "$allowed_headers" != *"Vary: Origin"* ]]; then
  echo "FAIL: allowed origin response missing Vary: Origin"
  exit 1
fi
echo "PASS: allowed origin CORS response headers are correct"

echo "== Check 6: disallowed origin is not granted CORS access =="
blocked_headers=$(curl -k -sS -o /dev/null -D - \
  -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
  -H "Origin: https://blocked-origin.invalid" \
  "${WEBDAV_BASE_URL}/simple.txt")
if [[ "$blocked_headers" == *"Access-Control-Allow-Origin:"* ]]; then
  echo "FAIL: disallowed origin unexpectedly received Access-Control-Allow-Origin"
  exit 1
fi
echo "PASS: disallowed origin receives no granted CORS origin"

echo "== Check 7: OPTIONS preflight is unauthenticated for allowed origin =="
preflight_headers=$(curl -k -sS -o /dev/null -D - -w 'HTTP_STATUS:%{http_code}' \
  -X OPTIONS \
  -H "Origin: ${ORGANICE_ORIGIN}" \
  -H "Access-Control-Request-Method: PROPFIND" \
  -H "Access-Control-Request-Headers: authorization,depth" \
  "${WEBDAV_BASE_URL}/")
preflight_status="${preflight_headers##*HTTP_STATUS:}"
assert_status "204" "$preflight_status" "unauthenticated OPTIONS preflight"
if [[ "$preflight_headers" != *"Access-Control-Allow-Methods:"* ]]; then
  echo "FAIL: allowed preflight missing Access-Control-Allow-Methods"
  exit 1
fi
if [[ "$preflight_headers" != *"Access-Control-Allow-Headers:"* ]]; then
  echo "FAIL: allowed preflight missing Access-Control-Allow-Headers"
  exit 1
fi
echo "PASS: OPTIONS preflight returns expected CORS metadata"

echo "== Check 8: non-OPTIONS request without auth remains unauthorized =="
unauth_get_status=$(curl -k -sS -o /dev/null -w '%{http_code}' "${WEBDAV_BASE_URL}/simple.txt" || true)
assert_status "401" "$unauth_get_status" "unauthenticated GET remains unauthorized"

echo "== Check 8b: org-ui static is served without auth and is not writable =="
ui_status=$(curl -k -sS -o /dev/null -w '%{http_code}' "${WEBDAV_BASE_URL}/ui/" || true)
assert_status "200" "$ui_status" "org-ui index served without auth"
ui_put_status=$(curl -k -sS -o /dev/null -w '%{http_code}' \
  -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
  -X PUT --data-binary 'x' "${WEBDAV_BASE_URL}/ui/probe.txt" || true)
if [[ "$ui_put_status" =~ ^20[0-9]$ ]]; then
  echo "FAIL: PUT under /ui must not be accepted (got HTTP $ui_put_status)"
  exit 1
fi
echo "PASS: PUT under /ui rejected (HTTP $ui_put_status)"

echo "== Check 9: live certificate rotation after on-disk renewal =="

# Capture the currently served WEBDAV_DOMAIN cert fingerprint via openssl s_client.
served_fp_before=$(echo | openssl s_client -connect "localhost:${WEBDAV_PORT}" -servername "$WEBDAV_DOMAIN" 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null || true)
if [[ -z "$served_fp_before" ]]; then
  echo "FAIL: could not capture initial served certificate fingerprint"
  exit 1
fi
echo "INFO: initial served cert fingerprint: ${served_fp_before}"

# Overwrite the on-disk WEBDAV_DOMAIN certificate with a freshly generated
# self-signed cert of distinct serial (matching key pair).
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout "$TEST_CERTS_DIR/live/$WEBDAV_DOMAIN/privkey.pem" \
  -out "$TEST_CERTS_DIR/live/$WEBDAV_DOMAIN/fullchain.pem" \
  -days 1 \
  -set_serial 2 \
  -subj "/CN=$WEBDAV_DOMAIN" >/dev/null 2>&1

new_disk_fp=$(openssl x509 -in "$TEST_CERTS_DIR/live/$WEBDAV_DOMAIN/fullchain.pem" -noout -fingerprint -sha256 2>/dev/null || true)
if [[ -z "$new_disk_fp" ]]; then
  echo "FAIL: could not compute replacement on-disk certificate fingerprint"
  exit 1
fi
echo "INFO: replacement on-disk cert fingerprint: ${new_disk_fp}"

if [[ "$served_fp_before" == "$new_disk_fp" ]]; then
  echo "FAIL: replacement cert has the same fingerprint as the original"
  exit 1
fi

# Wait beyond the configured reload interval (2s in test) for the watcher to
# detect the on-disk change and gracefully reload httpd.
sleep 6

served_fp_after=$(echo | openssl s_client -connect "localhost:${WEBDAV_PORT}" -servername "$WEBDAV_DOMAIN" 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null || true)
echo "INFO: post-rotation served cert fingerprint: ${served_fp_after}"

if [[ "$served_fp_after" != "$new_disk_fp" ]]; then
  echo "FAIL: served certificate was not rotated to match the renewed on-disk certificate"
  exit 1
fi
if [[ "$served_fp_after" == "$served_fp_before" ]]; then
  echo "FAIL: served certificate fingerprint is unchanged after on-disk renewal"
  exit 1
fi
echo "PASS: served certificate rotated to match renewed on-disk certificate"

echo "== Check 10: startup fails with missing organice certificate lineage =="
$COMPOSE_CMD -f "$COMPOSE_FILE" -f "$COMPOSE_OVERRIDE" down -v >/dev/null 2>&1 || true
rm -f "$TEST_CERTS_DIR/live/$ORGANICE_DOMAIN/fullchain.pem" "$TEST_CERTS_DIR/live/$ORGANICE_DOMAIN/privkey.pem"

set +e
$COMPOSE_CMD -f "$COMPOSE_FILE" -f "$COMPOSE_OVERRIDE" up -d webdav >/dev/null
start_rc=$?
set -e
if [[ "$start_rc" -ne 0 ]]; then
  echo "PASS: container startup command failed when organice certificates were missing"
else
  sleep 2
  startup_probe=$(curl -k -sS -o /dev/null -w '%{http_code}' -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" "${WEBDAV_BASE_URL}/simple.txt" || true)
  if [[ "$startup_probe" == "200" ]]; then
    echo "FAIL: service became healthy despite missing organice certificate files"
    exit 1
  fi

  webdav_logs=$($COMPOSE_CMD -f "$COMPOSE_FILE" -f "$COMPOSE_OVERRIDE" logs webdav 2>/dev/null || true)
  if [[ "$webdav_logs" != *"Missing TLS certificate files for ORGANICE_DOMAIN"* ]]; then
    echo "FAIL: startup logs did not include ORGANICE_DOMAIN certificate prerequisite failure"
    exit 1
  fi
  echo "PASS: startup fails closed and logs ORGANICE_DOMAIN certificate prerequisite failure"
fi

echo ""
echo "All Apache WebDAV smoke checks passed."
