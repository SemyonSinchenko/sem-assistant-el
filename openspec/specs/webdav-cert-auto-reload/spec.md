# webdav-cert-auto-reload Specification

## Purpose
TBD - Update Purpose after archive

## Requirements

### Requirement: Automatic certificate reload after renewal
The webdav container SHALL automatically detect on-disk certificate renewal and reload httpd so the renewed certificate is served without manual operator intervention. Detection SHALL cover both the `WEBDAV_DOMAIN` and `ORGANICE_DOMAIN` certificate paths; a change in either SHALL trigger a single reload.

#### Scenario: Renewed certificate is detected and served
- **WHEN** Certbot renews the `WEBDAV_DOMAIN` certificate, repointing `live/<domain>/fullchain.pem` to new archive material on the read-only `/certs` mount
- **THEN** the webdav watcher detects the change within one poll interval
- **AND** httpd is reloaded
- **AND** the certificate served over TLS (`openssl s_client`) matches the renewed on-disk certificate rather than the previously loaded one

#### Scenario: Either domain triggers a reload
- **WHEN** the `ORGANICE_DOMAIN` certificate is renewed while the `WEBDAV_DOMAIN` certificate is unchanged
- **THEN** the watcher detects the organice certificate change
- **AND** httpd is reloaded once to pick up both current certificates

#### Scenario: Unchanged certificates do not trigger a reload
- **WHEN** a poll runs and neither monitored certificate fingerprint has changed since the last poll
- **THEN** httpd is not reloaded

### Requirement: Graceful reload preserves WebDAV availability
Certificate reloads SHALL use `httpd -k graceful` (SIGUSR1 to the httpd master) so that in-flight WebDAV requests complete and the service remains available throughout the reload. The system SHALL NOT use a hard restart that drops active connections.

#### Scenario: Reload is graceful
- **WHEN** the watcher detects a certificate change and reloads httpd
- **THEN** the reload is performed via graceful reload
- **AND** active WebDAV sync connections are not dropped during the reload

### Requirement: Fingerprint-based change detection
Change detection SHALL be based on the SHA-256 fingerprint of the leaf certificate (`openssl x509 -in fullchain.pem -noout -fingerprint -sha256`), not on file mtime or stat metadata. The watcher SHALL compare the current fingerprint against the previously observed fingerprint and reload only when they differ.

#### Scenario: Fingerprint change triggers reload
- **WHEN** the leaf certificate fingerprint computed from `live/<domain>/fullchain.pem` differs from the previously stored fingerprint
- **THEN** the watcher records the new fingerprint and reloads httpd

#### Scenario: Symlink and mtime quirks do not cause false reloads
- **WHEN** the certbot `live/` symlink or file mtime changes across the read-only bind mount without a change to the leaf certificate content
- **THEN** the fingerprint remains identical
- **AND** no reload is triggered

### Requirement: Watcher does not reload on bootstrap
On the first poll after container startup, the watcher SHALL record the current certificate fingerprints WITHOUT reloading httpd, because httpd already loaded the current on-disk certificate at startup.

#### Scenario: First poll records fingerprint without reload
- **WHEN** the webdav container starts and the watcher performs its first poll
- **THEN** the current fingerprints for both domains are recorded as the baseline
- **AND** httpd is not reloaded as a result of this first poll

### Requirement: Configurable reload interval with safe default and minimum
The watcher poll interval SHALL be configurable via the `WEBDAV_CERT_RELOAD_INTERVAL` environment variable in seconds, with a default of 300. The effective interval SHALL be clamped to a minimum of 60 seconds to prevent accidental tight polling loops. The variable SHALL be documented in `.env.example` and exposed in the `webdav` service environment of `docker-compose.yml`.

#### Scenario: Default interval applies when unset
- **WHEN** `WEBDAV_CERT_RELOAD_INTERVAL` is not set in the environment
- **THEN** the watcher polls every 300 seconds

#### Scenario: Custom interval is honored
- **WHEN** an operator sets `WEBDAV_CERT_RELOAD_INTERVAL=120`
- **THEN** the watcher polls every 120 seconds

#### Scenario: Sub-minimum interval is clamped
- **WHEN** an operator sets `WEBDAV_CERT_RELOAD_INTERVAL` to a value below 60
- **THEN** the effective poll interval is clamped to 60 seconds
- **AND** the watcher does not poll more frequently than once per 60 seconds

### Requirement: Watcher process resilience
The watcher loop SHALL be defensive and MUST never exit as a result of transient errors. Transient `openssl` failures SHALL cause that single poll to be skipped without terminating the loop. A failed reload SHALL be logged as non-fatal and retried on the next poll. The watcher SHALL continue running for the lifetime of the container.

#### Scenario: Transient openssl error does not stop the watcher
- **WHEN** an `openssl` fingerprint computation fails for a certificate during a poll
- **THEN** that poll is skipped
- **AND** the watcher loop continues to run and polls again at the next interval

#### Scenario: Reload failure is non-fatal and retried
- **WHEN** an `httpd -k graceful` reload fails
- **THEN** the failure is logged
- **AND** the watcher does not exit
- **AND** the reload is retried on the next poll that still observes a fingerprint change

#### Scenario: httpd remains PID 1 with the watcher as a background process
- **WHEN** the webdav container starts
- **THEN** the watcher runs as a background process
- **AND** httpd remains the foreground process (PID 1) so that `docker stop` signal handling is preserved

### Requirement: End-to-end live certificate rotation verification
The integration smoke test SHALL verify that a certificate rotation is reflected in the served TLS certificate. After overwriting the on-disk certificate with a distinctly identifiable new certificate and waiting beyond the configured reload interval, the test SHALL assert that the served certificate fingerprint (obtained via `openssl s_client`) matches the new certificate and not the original.

#### Scenario: Smoke test proves served cert rotates after on-disk change
- **WHEN** the webdav smoke test replaces the on-disk certificate with a new self-signed certificate of a distinct serial
- **AND** the test waits longer than the configured reload interval
- **THEN** the certificate fingerprint served by the webdav TLS endpoint matches the new on-disk certificate
- **AND** it does not match the original certificate that was loaded at startup
