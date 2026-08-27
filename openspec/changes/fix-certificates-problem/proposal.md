# Proposal: Fix certificates problem

## Intent
Root cause found:
The on-disk cert is fine: org.semsinchenko.com expires 2026-09-11:
--- issuer Let's Encrypt YE1, staging off, DNS correct, port 80 owned by the certbot container, renewals working;

But rclone reported the served cert expiring 2026-07-13. That mismatch is the smoking gun:
Apache (sem-webdav) is serving a stale cert from memory. It's been up 2 months, loaded the then-current cert (issued ~Apr 14, expiring Jul 13) at startup.
Certbot renewed on Jun 13 → on-disk fullchain.pem now points at the new cert (exp Sep 11), but httpd never reloaded. Yesterday the in-memory cert hit its Jul 13 expiry, so Orgzly/rclone started failing while organice (separate cert/domain) kept working.

## Scope
- Fix apache

## What Changes: Feature Name
Fix certificates expiration.

## Approach
The certbot loop has no way to tell httpd to reload.
