# Design: Fix certificates problem

## Context

The SEM assistant runs as a Docker Compose stack. Two services are relevant:

- **`webdav`** (`httpd:2.4` + `mod_dav`) serves Orgzly/rclone WebDAV sync over HTTPS
  and reverse-proxies organice. It mounts the host's `/etc/letsencrypt` read-only at
  `/certs`. `start-webdav.sh` resolves the cert paths once, then
  `exec httpd -DFOREGROUND` loads those certs into memory at startup.
- **`certbot`** (separate container, `--profile certbot`) issues/renews Let's Encrypt
  certs via HTTP-01 and writes them to host `/etc/letsencrypt`, looping every
  `CERTBOT_RENEW_INTERVAL` (default 12h). Port 80 is owned by certbot.

The incident: `httpd` had been up ~2 months holding the Apr-14 → Jul-13 cert in
memory. Certbot renewed on Jun-13 (on-disk `fullchain.pem` now valid to Sep-11),
but `httpd` never reloaded, so it kept serving the now-expired Jul-13 cert →
Orgzly/rclone TLS failures. organice (separate cert/domain) was unaffected only
because its in-memory cert still had later expiry at that moment — it shares the
identical latent bug.

Root cause: **the certbot loop has no way to tell `httpd` to reload**, and
`start-webdav.sh` performs a one-shot cert load with no ongoing watch.

Constraints:
- `/certs` is mounted **read-only** in webdav (must stay that way).
- certbot and webdav are **separate containers** with no shared IPC.
- No Docker socket should be mounted into either container (security).
- WebDAV must stay available during rotation (Orgzly/rclone sync continuity).

## Goals / Non-Goals

**Goals:**
- After a certbot renewal, `httpd` serves the renewed cert with **no manual
  intervention** and **no downtime**.
- Keep certbot and webdav **decoupled** — certbot must not need to know about httpd.
- Make the reload cadence **configurable** with a safe default.
- Add an **automated smoke check** proving live cert rotation works end-to-end.

**Non-Goals:**
- Changing the certbot renewal loop or ACME provider.
- Replacing Apache with another web server.
- Fixing OCSP stapling or client-side trust.
- Multi-host / shared webdav clustering.

## Decisions

### Decision 1: httpd-side self-reload watcher (architecture)

Add a background watcher loop **inside the webdav container** (in
`start-webdav.sh`) that periodically detects an on-disk cert change and, when one
occurs, runs `httpd -k graceful`.

Rationale: decouples certbot from webdav; needs no Docker socket, no writable
shared volume, no cross-container signaling; works regardless of which entity
renews the cert; reads only the already-mounted read-only `/certs`.

Alternatives considered:
- **certbot `--deploy-hook` reaching httpd** — rejected: certbot and httpd run in
  separate containers; a deploy-hook cannot signal httpd's process. It would
  require the Docker socket or a shared control volume plus an httpd-side watcher,
  collapsing back to polling.
- **Docker-socket-driven `docker restart` from certbot** — rejected: mounting the
  Docker socket is a serious security exposure and a hard restart drops active
  WebDAV connections (downtime), unlike a graceful reload.
- **`inotifywait` on the cert file** — rejected: the httpd image lacks
  `inotifywait`, and inotify across bind-mounted/symlinked paths is unreliable.

### Decision 2: Graceful reload, not hard restart

Use `httpd -k graceful` (SIGUSR1 to the httpd master). Existing workers finish
in-flight requests; new children re-read config and cert files at the `live/`
paths, which certbot repoints via symlink on renewal. **Zero downtime.**

Alternative: `docker restart sem-webdav` — rejected (drops active connections).

### Decision 3: Fingerprint-based change detection

On each poll, compute the SHA-256 fingerprint of the leaf cert
(`openssl x509 -in fullchain.pem -noout -fingerprint -sha256`) and compare to the
previously seen fingerprint; reload only when it differs.

Rationale: certbot renewal repoints `live/<domain>/fullchain.pem` to a new archive
file and changes the leaf, so the fingerprint changes reliably. Fingerprinting is
immune to the symlink/mtime quirks that plague `stat`/mtime comparison across the
read-only bind mount.

Bootstrapping: the first poll records the fingerprint **without** reloading (httpd
already loaded the current cert at startup). Both the `WEBDAV_DOMAIN` and
`ORGANICE_DOMAIN` certs are watched; a change in either triggers one graceful
reload.

Alternative: mtime of the resolved file — rejected as fragile across bind
mounts/symlinks.

### Decision 4: Process model — background watcher + foreground httpd

In `start-webdav.sh`, start the watcher as a background subshell (`&`), then
`exec httpd -DFOREGROUND` so httpd stays **PID 1** (correct `docker stop` signal
handling). The watcher is defensive: any `openssl` error skips that poll (the loop
must never exit); a reload failure is logged but non-fatal and retried next poll.

On `docker stop`, httpd (PID 1) receives SIGTERM and exits; the runtime reaps the
orphaned watcher — no leak across the container lifetime.

### Decision 5: Configurability

- New env `WEBDAV_CERT_RELOAD_INTERVAL` (seconds), **default 300**, added to
  `.env.example`, `docker-compose.yml` (`webdav.environment`), and the test
  override. Clamped to a minimum of 60 to prevent accidental tight loops.
- The `[webdav]` log prefix is reused for consistency with existing startup logs.

## Risks / Trade-offs

- **[Watcher dies silently → certs go stale again]** → Mitigation: the loop is
  defensive and never exits on transient errors; reloads are logged. If PID 1
  (httpd) exits, `restart: unless-stopped` recreates the container, re-running
  `start-webdav.sh` and the watcher — automatic recovery.
- **[Graceful reload fails]** → Mitigation: logged non-fatally and retried on the
  next poll. Worst case equals today's behavior (stale cert until manual action) —
  no regression.
- **[Detection latency up to `WEBDAV_CERT_RELOAD_INTERVAL`]** → Mitigation: the
  300s default is far inside the 30-day renewal window; tunable down to 60s.
- **[Polling cost]** → Two `openssl` fingerprint computations every 5 min is
  negligible CPU.
- **[Symlink resolution across read-only bind mount]** → The whole
  `/etc/letsencrypt` is mounted, so `live/.../fullchain.pem` symlinks resolve to
  `archive/...` within `/certs`; verified by the existing mount.
- **Trade-off:** polling (vs event-driven deploy-hook) adds up to one interval of
  latency but removes all shared state / Docker-socket coupling between
  containers. Accepted.

## Migration Plan

1. Edit `webdav/apache/start-webdav.sh`: add the watcher subshell before
   `exec httpd -DFOREGROUND`; read `WEBDAV_CERT_RELOAD_INTERVAL` with default + clamp.
2. Add `WEBDAV_CERT_RELOAD_INTERVAL=300` to `.env.example` and the
   `webdav.environment` block in `docker-compose.yml`.
3. Set a short `WEBDAV_CERT_RELOAD_INTERVAL` (e.g., 2s) in
   `dev/integration/docker-compose.webdav-httpd.test.yml` so the smoke test can
   assert rotation quickly.
4. Add a smoke-test check in `run-webdav-httpd-smoke-test.sh`: after startup,
   overwrite the on-disk cert with a freshly generated self-signed cert (distinct
   serial), wait > interval, then assert the **served** cert fingerprint
   (`openssl s_client`) matches the new cert, not the old.
5. **Rollout (operator):** `docker compose restart webdav` (the script is
   volume-mounted — no rebuild). This immediately clears the stale in-memory cert
   (httpd re-reads the current on-disk cert at startup) and arms the watcher for
   future renewals.
6. **Rollback:** revert the script and `docker compose restart webdav`. Behavior
   returns to today's manual-reload model with no data impact (no persistent state
   is introduced — watcher state is in-memory only).

## Open Questions

- Should the watcher also reload on **near-expiry** as a safety net (in case a
  renewal silently fails for weeks)? Out of scope here — the 30-day renewal window
  plus the certbot loop already provide margin. Could be added later as a
  `--days` guard.
