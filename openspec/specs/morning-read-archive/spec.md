## Purpose

Monthly retention for morning digest files: keeps `/data/morning-read/` limited to
the current month's files by moving older digests into `/data/archive/`, so the
Organice/WebDAV daily view stays short while history remains browsable.

## Requirements

### Requirement: Previous-month digest files are archived
The system SHALL move digest files older than the current calendar month from
`/data/morning-read/` into `/data/archive/<YYYY-MM>/`, where `<YYYY-MM>` is the
year-month of the digest file being archived, derived from the client-timezone
calendar. Digest files belonging to the current month SHALL remain in
`/data/morning-read/`. The move SHALL preserve file content unchanged.

#### Scenario: March files move after month rollover
- **WHEN** the archival routine runs in April and `/data/morning-read/` contains
  `2026-03-15.org` and `2026-03-15-arxiv.org`
- **THEN** both files are moved to `/data/archive/2026-03/`
- **AND** they no longer appear in `/data/morning-read/`

#### Scenario: Current-month files stay in place
- **WHEN** the archival routine runs in April and `/data/morning-read/` contains
  `2026-04-02.org`
- **THEN** `2026-04-02.org` remains in `/data/morning-read/`

#### Scenario: Move preserves file content
- **WHEN** a digest file is archived
- **THEN** the file content at the destination is byte-identical to the source

### Requirement: Archival is idempotent and self-healing
The archival routine SHALL complete without error when there are no files to
archive, SHALL move nothing on a second immediate run, and SHALL create
`/data/archive/` (and the month subdirectory) on demand if it does not exist.
The routine SHALL catch up on backlog: any files older than the current month
are archived on the next run regardless of when they were generated.

#### Scenario: No-op run when nothing to archive
- **WHEN** the archival routine runs and all digest files belong to the current
  month
- **THEN** no files are moved and no error is signaled

#### Scenario: Idempotent second run
- **WHEN** the archival routine completes and runs again without new files
  appearing
- **THEN** no additional files are moved

#### Scenario: Archive directory created on demand
- **WHEN** the archival routine runs and `/data/archive/` does not exist
- **THEN** the directory and the target month subdirectory are created
- **AND** the files are archived successfully

#### Scenario: Backlog catch-up after downtime
- **WHEN** the archival routine has not run for several months and
  `/data/morning-read/` contains digest files from multiple previous months
- **THEN** a single run archives all previous-month files into their respective
  month subdirectories

### Requirement: Archived digests remain accessible via WebDAV
The system SHALL keep archived digest files under the `/data` volume so they
remain listed and downloadable through the existing WebDAV endpoint (organice
and Orgzly clients) under the `archive/` folder. Archival SHALL NOT delete any
digest file.

#### Scenario: Organice can browse the archive folder
- **WHEN** a WebDAV client lists the `archive/` folder after archival
- **THEN** the month subdirectories and their digest files are listed

#### Scenario: No digest file is deleted by archival
- **WHEN** the archival routine completes
- **THEN** every source file that existed before the run still exists under
  `/data/archive/`

### Requirement: Archival failures are logged and never crash the daemon
The archival entry point SHALL be wrapped so that errors never propagate to the
caller. Each successful move SHALL be logged via structured logging (module
`rss`, status `OK`), and failures SHALL be logged with `sem-core-log-error` to
`errors.org` and SHALL NOT abort processing of the remaining files beyond the
failing one where possible.

#### Scenario: Move failure logged to errors.org
- **WHEN** a digest file cannot be moved (e.g., destination unwritable)
- **THEN** the failure is logged to `/data/errors.org`
- **AND** the routine does not signal an error to the cron caller

#### Scenario: Successful move logged
- **WHEN** a digest file is archived successfully
- **THEN** a structured log entry with module `rss` and status `OK` records the
  move
