# Tasks: Fix certificates problem

## 1. Certificate reload watcher

- [x] 1.1 Add a background watcher subshell in `webdav/apache/start-webdav.sh` started before `exec httpd -DFOREGROUND`, so httpd remains PID 1
- [x] 1.2 Implement SHA-256 fingerprint computation for `$CERT_FILE` and `$ORGANICE_CERT_FILE` via `openssl x509 -in <file> -noout -fingerprint -sha256`
- [x] 1.3 Implement the poll loop that sleeps `WEBDAV_CERT_RELOAD_INTERVAL`, recomputes both fingerprints, and reloads only when a fingerprint changed
- [x] 1.4 Implement bootstrap behavior: on the first poll, record both fingerprints WITHOUT reloading httpd
- [x] 1.5 Trigger a single `httpd -k graceful` when either domain fingerprint changes; update stored fingerprints after a successful reload
- [x] 1.6 Make the watcher defensive: transient `openssl` failures skip that poll; a failed reload is logged non-fatally and retried next poll; the loop never exits

## 2. Configurable interval

- [x] 2.1 Read `WEBDAV_CERT_RELOAD_INTERVAL` (seconds) in `start-webdav.sh` with a default of 300
- [x] 2.2 Clamp the effective interval to a minimum of 60 seconds and log when clamping occurs

## 3. Configuration wiring

- [x] 3.1 Add `WEBDAV_CERT_RELOAD_INTERVAL=300` to `.env.example` with a descriptive comment
- [x] 3.2 Add `WEBDAV_CERT_RELOAD_INTERVAL=${WEBDAV_CERT_RELOAD_INTERVAL:-300}` to the `webdav` service `environment` block in `docker-compose.yml`

## 4. Test infrastructure

- [x] 4.1 Add `WEBDAV_CERT_RELOAD_INTERVAL=2` to the webdav environment in `dev/integration/docker-compose.webdav-httpd.test.yml`
- [x] 4.2 Add a smoke-test check in `dev/integration/run-webdav-httpd-smoke-test.sh` that captures the initially served cert fingerprint via `openssl s_client`
- [x] 4.3 In the smoke test, overwrite the on-disk `WEBDAV_DOMAIN` fullchain.pem with a freshly generated self-signed cert of distinct serial
- [x] 4.4 In the smoke test, wait beyond the reload interval, then assert the served cert fingerprint matches the new on-disk cert and not the original
- [x] 4.5 Ensure the new rotation check runs before the destructive "missing certificate" check (Check 9) so it has valid certs available

## 5. Verification

- [x] 5.1 Run `sh dev/elisplint.sh` is N/A (shell change) — instead run `sh -n webdav/apache/start-webdav.sh` to syntax-check the modified script
- [x] 5.2 Run the webdav smoke test (`bash dev/integration/run-webdav-httpd-smoke-test.sh`) to confirm live cert rotation end-to-end
