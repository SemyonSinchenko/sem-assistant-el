## Purpose

This capability defines the system cron scheduling for all timed execution in the Emacs daemon environment.

## Requirements

### Requirement: System cron drives all timed execution
The system SHALL use the system cron daemon inside the Emacs container for all scheduled task execution. All cron jobs SHALL invoke Emacs functions via `emacsclient`.

#### Scenario: Cron triggers scheduled tasks
- **WHEN** a scheduled time arrives
- **THEN** cron executes `emacsclient -e "(function-name)"`

### Requirement: Crontab committed to repository
The system SHALL have a crontab file committed to the repository. The Dockerfile SHALL install this crontab via `COPY` + `crontab /etc/cron.d/sem-cron`.

#### Scenario: Crontab installed in container
- **WHEN** the Docker image is built
- **THEN** the crontab file is copied to `/etc/cron.d/sem-cron`

#### Scenario: Schedule change requires rebuild
- **WHEN** the cron schedule needs to be modified
- **THEN** a container rebuild is required

### Requirement: Complete schedule defined
The system SHALL implement the following complete schedule with no gaps or overlaps, and cron schedule interpretation SHALL use the configured client timezone from `CLIENT_TIMEZONE` rather than implicit VPS/container-local timezone.

```
*/30 * * * *  root  emacsclient -e "(sem-core-process-inbox)"
0    4 * * *  root  emacsclient -e "(sem-core-purge-inbox)"
0    5 * * *  root  emacsclient -e "(elfeed-update)"
0    6 * * *  root  emacsclient -e "(elfeed-update)"
0    7 * * *  root  emacsclient -e "(elfeed-update)"
0    8 * * *  root  emacsclient -e "(elfeed-update)"
30   9 * * *  root  emacsclient -e "(sem-rss-generate-morning-digest)"
*/15 * * * *  root  /usr/local/bin/sem-daemon-watchdog
0 */3 * * *  root  emacsclient -e "(sem-git-sync-org-roam)"
0    3 * * *  root  emacsclient -e "(sem-rss-archive-old-digests)"
```

#### Scenario: Inbox processing every 30 minutes in client timezone
- **WHEN** every 30th minute of every hour arrives in `CLIENT_TIMEZONE`
- **THEN** `sem-core-process-inbox` is called

#### Scenario: Purge at 4AM in client timezone
- **WHEN** 4:00 AM arrives in `CLIENT_TIMEZONE`
- **THEN** `sem-core-purge-inbox` is called

#### Scenario: Elfeed update 5-8AM in client timezone
- **WHEN** 5:00, 6:00, 7:00, 8:00 AM arrive in `CLIENT_TIMEZONE`
- **THEN** `elfeed-update` is called each hour

#### Scenario: RSS digest at 9:30AM in client timezone
- **WHEN** 9:30 AM arrives in `CLIENT_TIMEZONE`
- **THEN** `sem-rss-generate-morning-digest` is called

#### Scenario: Watchdog executes every 15 minutes in client timezone
- **WHEN** every 15th minute of every hour arrives in `CLIENT_TIMEZONE`
- **THEN** `sem-daemon-watchdog` is called

#### Scenario: Git sync executes every 3 hours in client timezone
- **WHEN** every 3rd hour arrives at minute 0 in `CLIENT_TIMEZONE`
- **THEN** `sem-git-sync-org-roam` is called

#### Scenario: Morning-read archival daily at 3AM in client timezone
- **WHEN** 3:00 AM arrives in `CLIENT_TIMEZONE`
- **THEN** `sem-rss-archive-old-digests` is called
- **AND** digest files from previous months are moved to `/data/archive/`

#### Scenario: Cron timezone comes from CLIENT_TIMEZONE
- **WHEN** the container loads cron configuration for daemon schedules
- **THEN** cron evaluates schedule expressions in `CLIENT_TIMEZONE`
- **AND** schedule timing does not depend on implicit host/container default timezone
### Requirement: Timezone bootstrap precedes cron daemon startup
The system SHALL bootstrap runtime timezone files and environment from `CLIENT_TIMEZONE` before launching the cron daemon. Startup MUST fail fast when timezone bootstrap cannot be completed.

#### Scenario: Runtime timezone files align with CLIENT_TIMEZONE
- **WHEN** container startup applies timezone bootstrap
- **THEN** `/etc/localtime` references `/usr/share/zoneinfo/CLIENT_TIMEZONE`
- **AND** `/etc/timezone` contains `CLIENT_TIMEZONE`
- **AND** `TZ` environment equals `CLIENT_TIMEZONE`

#### Scenario: Startup fails when timezone bootstrap cannot resolve zoneinfo
- **WHEN** `CLIENT_TIMEZONE` does not map to an existing file under `/usr/share/zoneinfo`
- **THEN** startup exits with an explicit configuration error before cron starts

#### Scenario: Runtime offset matches configured timezone semantics
- **WHEN** runtime time is evaluated in the container after startup
- **THEN** observed UTC offset matches the expected offset for `CLIENT_TIMEZONE` at that instant (including DST transitions)

### Requirement: Watchdog cron job is operational-only
The cron schedule SHALL treat the daemon liveness watchdog as an operational supervision job. The watchdog cron entry MUST NOT invoke inbox processing, purge, RSS generation, or git synchronization workflows.

#### Scenario: Watchdog command scope
- **WHEN** the watchdog cron entry executes
- **THEN** it performs only liveness probe and restart supervision behavior

#### Scenario: Business workflows remain separate
- **WHEN** business workflows are scheduled by cron
- **THEN** they are executed only by their dedicated cron entries and not by the watchdog job

### Requirement: Emacs internal timers not used
The system SHALL NOT use Emacs internal timers (`run-at-time`, `idle-timer`) for scheduled tasks. All scheduling SHALL be done via system cron.

#### Scenario: No run-at-time timers
- **WHEN** the daemon is running
- **THEN** no `run-at-time` timers are set for scheduled tasks

#### Scenario: No idle-timer timers
- **WHEN** the daemon is running
- **THEN** no `idle-timer` timers are set for scheduled tasks

### Requirement: Each cron invocation is independent
The system SHALL ensure each cron invocation is independent. A crash in one execution SHALL NOT affect the next scheduled run.

#### Scenario: Crash does not affect next run
- **WHEN** a cron job crashes during execution
- **THEN** the next scheduled run executes normally

### Requirement: No locking required between jobs
The system SHALL serialize cron invocations via the cron daemon. The 4AM purge and `*/30` inbox-processing SHALL share the same time domain without requiring explicit locking.

#### Scenario: Cron serializes execution
- **WHEN** inbox-processing is running and purge time arrives
- **THEN** cron waits for the current job to complete before starting purge
