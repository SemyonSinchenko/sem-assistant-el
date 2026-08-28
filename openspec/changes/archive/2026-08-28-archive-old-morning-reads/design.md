## Context

Digest generation writes two files per day (`YYYY-MM-DD.org`, `YYYY-MM-DD-arxiv.org`)
flat into `/data/morning-read/` (`sem-rss-dir` in `sem-rss.el`); nothing ever removes
them. `/data` is a host bind mount exposed over WebDAV to organice/Orgzly. All timed
work runs via the committed `crontab` invoking `emacsclient`. See proposal.md for
motivation and specs/ for the behavior contract.

## Goals / Non-Goals

**Goals:**
- Keep `/data/morning-read/` limited to the current month's files, so the organice
  daily view stays short.
- Keep archived digests browsable through the same WebDAV tree under `/data/archive/`.
- Tolerate daemon/container downtime at the month boundary (catch-up on next run).
- Reuse existing conventions: structured logging, never-crash entry points, ERT tests
  without real `/data` or network access.

**Non-Goals:**
- No compression, encryption, or content rewriting of archived files.
- No changes to digest generation, WebDAV auth, or any client configuration.
- No retention limit (no auto-deletion of old archives) — history is kept forever.
- No general-purpose archive framework for other `/data` content.

## Decisions

### D1: Extend `sem-rss.el` rather than a new module
Archival is digest-specific (knows about `sem-rss-dir` and the `YYYY-MM-DD*.org`
naming) and is ~2 public/private functions. Adding `sem-rss-archive-old-digests` to
`sem-rss.el` avoids new load-order plumbing. *Alternative considered*: a new
`sem-archive.el` module — rejected until a second archival use case appears;
extraction is mechanical later.

### D2: Daily idempotent check instead of a month-end-only trigger
Cron entry `30 2 * * *` calls `sem-rss-archive-old-digests` every day; the function
moves only files older than the current month. *Why*: Debian cron cannot express
"last day of month" (`L` is unsupported), `28-31 * *` still requires the same date
check, and a daily pass self-heals missed boundaries (downtime, rebuild windows).
Time 2:30 AM sits in the quiet window between git-sync (0:00/3:00) and the 4:00 AM
purge. *Alternative considered*: piggybacking on an existing daily job — rejected:
mixes concerns and couples this behavior to the purge spec.

### D3: Month attribution from the filename, not file mtime
The leading `YYYY-MM-DD` of the filename is the digest date contract
(`sem-rss--generate-file` writes it). Parsing `^\([0-9]\{4\}\)-\([0-9]\{2\}\)`
from `file-name-nondirectory` is stable across WebDAV uploads that may alter mtime.
Files not matching the pattern are left in place and logged as `SKIP` (protects any
future non-digest files placed in the folder). Destination is
`/data/archive/YYYY-MM/` using the file's own year-month.

### D4: `rename-file` for the move; house cron guard wrapper
Source and destination are under the same `/data` bind mount, so `rename-file` is
atomic and cheap. The routine stays idempotent — a duplicate concurrent run no-ops
on already-moved files — but the cron-overlap-guard-policy spec requires a guard on
cron-triggered jobs, so the entry point runs under `sem-core-run-cron-guarded` with
guard key `rss-morning-archive`, policy `skip`, and a short stale TTL (job is fast),
registered in `sem-core-cron-guard-job-config` like every other cron job.
Directory creation uses `make-directory ... t` on demand.

### D5: Entry point wraps `condition-case`; per-file failures do not stop the batch
`sem-rss-archive-old-digests` catches errors at the top level (never crash the
daemon), logs each successful move via `sem-core-log` (module `rss`, status `OK`),
and logs failures with `sem-core-log-error` to `errors.org`, continuing with
remaining files. Date "now" is injectable via an optional argument (default
`current-time`) so tests do not mock clocks.

### D6: Testing with real temp directories
Tests bind `sem-rss-dir` and the archive root to `make-temp-file` directories,
create fixture files for several months, run the routine, and assert placement,
idempotency (second run moves nothing), pattern-mismatch `SKIP`, and error logging
via the `sem-mock.el` helpers. No real `/data` access.

## Risks / Trade-offs

- [organice shows a stale folder listing after a move] → Clients refresh on folder
  re-entry; archival runs at 2:30 AM, long before daily use; files are moved, not
  deleted, so a refresh finds them under `archive/`.
- [A WebDAV client holding an open file during its move] → Only previous-month
  files move; active editing targets current-month files. A single failed read
  self-corrects on retry; conditional-write rules already guard divergent edits.
- [`rename-file` across filesystems fails] → Source and destination share the
  `/data` mount; if deployment ever splits them, the error path logs to
  `errors.org` and leaves the file in place (visible, not lost).
- [Archive grows unbounded] → Accepted by non-goal; text digests are small
  (~60 files/month, few hundred KB).

## Migration Plan

1. Rebuild the container (crontab is installed at image build; existing rule).
2. First 2:30 AM run creates `/data/archive/` and moves the ~4-month backlog into
   month subdirectories; no manual data migration needed.
3. Rollback: remove the cron line and rebuild; the `archive/` folder is inert.
   Moving files back (`mv /data/archive/YYYY-MM/* /data/morning-read/`) restores
   the old layout if ever desired.

## Open Questions

None — layout (`/data/archive/YYYY-MM/`), trigger (`30 2 * * *` daily check), and
module placement (`sem-rss.el`) are decided here; remaining choices are
implementation-level and covered by tasks.
