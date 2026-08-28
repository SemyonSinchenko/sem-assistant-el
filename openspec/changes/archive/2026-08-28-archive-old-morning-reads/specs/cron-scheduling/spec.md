## MODIFIED Requirements

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
