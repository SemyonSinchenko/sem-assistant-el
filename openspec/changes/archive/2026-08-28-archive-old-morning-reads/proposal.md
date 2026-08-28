## Why

Morning digest files accumulate flat in `/data/morning-read/` (two files per day:
`YYYY-MM-DD.org` and `YYYY-MM-DD-arxiv.org`). After four months of use the folder
holds hundreds of files, and the Organice UI lists them as one long flat list, so
finding today's digest means scrolling past every older file. Moving past months
out of the folder keeps the daily view short without losing history.

## What Changes

- Add a monthly archival routine that moves digest files belonging to previous
  months from `/data/morning-read/` into `/data/archive/`.
- The routine is idempotent and self-healing: it moves anything older than the
  current month, so it converges even if the daemon was down at the month boundary
  or the archive folder does not exist yet.
- Add a cron entry to the committed `crontab` that triggers the archival at the
  month boundary (exact schedule decided in `design.md`; a schedule change requires
  a container rebuild per the cron-scheduling spec).
- Log every move through structured logging (module `rss`, statuses `OK`/`FAIL`);
  failures are logged to `errors.org` and never crash the daemon.
- Archived files remain reachable through the existing WebDAV/Organice tree under
  the `archive/` folder — no new services, auth, or LLM calls.
- ERT tests with mocked filesystem; no real network calls or real `/data` paths.

## Capabilities

### New Capabilities

- `morning-read-archive`: Monthly retention of morning digest files. Covers moving
  previous-month digest files from `/data/morning-read/` to `/data/archive/`,
  idempotent re-runs, structured logging of moves, and the guarantee that after a
  run `/data/morning-read/` only contains the current month's files.

### Modified Capabilities

- `cron-scheduling`: The "Complete schedule defined" requirement gains the new
  archival cron entry in the committed crontab.

## Impact

- **Code**: New archival functions (in `sem-rss.el` or a small dedicated module);
  one new cron line in `crontab`.
- **Specs**: New `specs/morning-read-archive/spec.md`; delta to the existing
  `cron-scheduling` spec.
- **Data layout**: New `data/archive/` directory on the existing host bind mount;
  on first run, all current files from previous months move there.
- **Clients**: Organice/WebDAV listings show `archive/` as a regular folder and the
  `morning-read/` folder shrinks to the current month. No auth, API, or LLM changes.
- **Ops**: Crontab change requires a container rebuild (existing rule).
