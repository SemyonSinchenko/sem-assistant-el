## Purpose

This capability defines the RSS digest generation system that creates morning digests from Elfeed entries.

## Requirements

### Requirement: rss-digest runs daily at 9:30 AM
The system SHALL generate RSS digests daily at 9:30 AM via cron schedule `30 9 * * *` interpreted in `CLIENT_TIMEZONE`. The digest SHALL fetch and process entries from the Elfeed database from the last 24 hours via LLM and write output to `/data/morning-read/YYYY-MM-DD.org` (general) and `/data/morning-read/YYYY-MM-DD-arxiv.org` (arXiv), where `YYYY-MM-DD` is derived from the client-timezone calendar day at generation time. The function `sem-rss--generate-file` SHALL use `sem-llm-request` instead of direct `gptel-request` calls.

#### Scenario: Scheduled digest generation in client timezone
- **WHEN** cron triggers at 9:30 AM in `CLIENT_TIMEZONE`
- **THEN** `emacsclient -e "(sem-rss-generate-morning-digest)"` is executed

#### Scenario: Digest file date uses client calendar day
- **WHEN** digest output path is generated
- **THEN** the `YYYY-MM-DD` filename date is computed from current day in `CLIENT_TIMEZONE`
- **AND** day rollover follows `CLIENT_TIMEZONE`, not UTC-forced semantics

#### Scenario: sem-llm-request used for LLM call
- **WHEN** `sem-rss--generate-file` generates the digest
- **THEN** it calls `sem-llm-request` (not `gptel-request`)

### Requirement: arXiv digest is staggered behind the general digest
The morning digest flow SHALL start arXiv digest generation 5 seconds after
the general digest generation step begins. The offset SHALL be hardcoded
(no configuration variable, no environment variable). The stagger SHALL
apply regardless of whether the general digest is generated, skipped
(already exists or no entries), or fails.

#### Scenario: Stagger between the two digest LLM requests
- **WHEN** the morning digest flow runs and both digests are generated
- **THEN** arXiv digest generation starts 5 seconds after the general digest generation step begins
- **AND** the two LLM requests are not dispatched back-to-back

#### Scenario: Stagger applies when the general digest is skipped
- **WHEN** the general digest file already exists or no general entries are found
- **THEN** arXiv digest generation still starts 5 seconds after the general digest step begins

#### Scenario: Stagger is hardcoded
- **WHEN** the daemon starts with no configuration changes
- **THEN** the stagger offset is 5 seconds without any operator setup
### Requirement: No file written if no entries found
The system SHALL NOT write a digest file if no entries are found for a
filter. No LLM call SHALL be made in this case. On malformed LLM output,
the error SHALL be logged to `errors.org` and the output file SHALL NOT be
written. On API error other than rate limit (HTTP 429), the error SHALL be
logged to `errors.org` and the output file SHALL NOT be written, with no
retry. Rate-limit (429) errors SHALL be retried according to the digest
rate-limit retry policy; once retries are exhausted, the failure SHALL be
logged to `errors.org` and the output file SHALL NOT be written.

#### Scenario: No entries, no file
- **WHEN** no entries match the general filter in the last 24 hours
- **THEN** no general digest file is written

#### Scenario: Malformed output logged to errors.org
- **WHEN** the LLM returns malformed output for rss-digest
- **THEN** the error is logged to `/data/errors.org` and no output file is written

#### Scenario: API error logged with RETRY status
- **WHEN** the LLM API returns an error during rss-digest generation
- **THEN** a rate-limit (HTTP 429) error is first retried per the digest rate-limit retry policy and is logged to `/data/errors.org` only once retries are exhausted
- **AND** any other API error is logged to `/data/errors.org` immediately with no retry
- **AND** in both cases no output file is written

#### Scenario: Non-rate-limit API error logged without retry
- **WHEN** the LLM API returns an error other than HTTP 429 during rss-digest generation
- **THEN** the error is logged to `/data/errors.org` and no output file is written
- **AND** no retry is scheduled

#### Scenario: Rate-limit failure logged after retries are exhausted
- **WHEN** all digest rate-limit retries are exhausted with HTTP 429 responses
- **THEN** the failure is logged to `/data/errors.org` and no output file is written
### Requirement: Digest rate-limit retry policy
When a digest LLM request fails with an HTTP 429 rate-limit response, the
system SHALL retry the identical request up to 3 times (the initial attempt
plus 3 retries, 4 attempts in total) with a fixed 300-second delay between
attempts. The delay SHALL be hardcoded. Each scheduled retry SHALL be
logged. No digest file SHALL be written until an attempt succeeds. If a
retried attempt succeeds, the digest SHALL be written and no further
retries SHALL be scheduled. Rate-limit detection SHALL reuse the shared
LLM rate-limit detection. This retry policy SHALL apply only to digest
generation; the retry behavior of the task pipeline and url-capture SHALL
NOT change.

#### Scenario: First 429 schedules a retry after 5 minutes
- **WHEN** the initial digest LLM attempt fails with HTTP 429
- **THEN** exactly one retry is scheduled 300 seconds later
- **AND** no digest file is written at that point

#### Scenario: Persistent 429 retries up to three times
- **WHEN** every attempt up to and including the third retry fails with HTTP 429
- **THEN** exactly 4 attempts are made in total and 3 retries are scheduled
- **AND** each retry uses the same prompt as the initial attempt

#### Scenario: Retried attempt succeeds
- **WHEN** a retry attempt returns a non-empty LLM response
- **THEN** the digest file is written from that response
- **AND** no further retries are scheduled

#### Scenario: Retry delay is fixed
- **WHEN** consecutive 429 failures schedule the first, second, and third retries
- **THEN** each retry is scheduled with the same 300-second delay
- **AND** the delay does not double between attempts

#### Scenario: Task pipeline and url-capture retries unchanged
- **WHEN** a task-pipeline or url-capture LLM request fails with HTTP 429
- **THEN** its retry behavior still follows the shared exponential backoff and is not affected by the digest retry policy
### Requirement: sem-llm-request handles nil hash for rss-digest
The function `sem-rss--generate-file` SHALL pass `nil` as the `hash` argument to `sem-llm-request` because RSS digest has no per-entry cursor deduplication. The functions `sem-llm-request` and its helpers (e.g., `sem-core--mark-processed`) SHALL handle `nil` hash without crashing.

#### Scenario: nil hash passed to sem-llm-request
- **WHEN** `sem-rss--generate-file` calls `sem-llm-request`
- **THEN** it passes `nil` as the `hash` argument

#### Scenario: nil hash handled gracefully
- **WHEN** `sem-llm-request` receives `nil` hash
- **THEN** it completes without crashing

#### Scenario: sem-core--mark-processed no-op on nil
- **WHEN** `sem-core--mark-processed` is called with `nil`
- **THEN** it is a no-op (does not crash, does not modify cursor)

### Requirement: RSS prompt builders use template variables
The functions `sem-rss--build-general-prompt` and `sem-rss--build-arxiv-prompt` SHALL replace inline `format` string literals with `format` using the loaded template variables `sem-rss-general-prompt-template` and `sem-rss-arxiv-prompt-template`. The argument order and types SHALL remain unchanged: general prompt uses (days, category-list, days, entries-text); arXiv prompt uses (category-list, days, entries-text).

#### Scenario: General prompt uses template variable
- **WHEN** `sem-rss--build-general-prompt` is called
- **THEN** it calls `(format sem-rss-general-prompt-template days category-list days entries-text)`
- **AND** it does not use a hardcoded string literal

#### Scenario: arXiv prompt uses template variable
- **WHEN** `sem-rss--build-arxiv-prompt` is called
- **THEN** it calls `(format sem-rss-arxiv-prompt-template category-list days entries-text)`
- **AND** it does not use a hardcoded string literal

#### Scenario: Template variables loaded at startup
- **WHEN** the `sem-rss` module finishes loading
- **THEN** `sem-rss-general-prompt-template` is a non-nil, non-empty string
- **AND** `sem-rss-arxiv-prompt-template` is a non-nil, non-empty string

#### Scenario: Missing template file aborts daemon
- **WHEN** the `sem-rss` module loads and a prompt file is missing or empty
- **THEN** an error is signaled and the daemon aborts startup

### Requirement: RSS digest callback processes backslash-containing LLM output without crashing
The `sem-rss--generate-file` callback SHALL process LLM responses containing backslash characters (e.g., LaTeX markup from arXiv paper titles) without signaling an error. The callback SHALL apply whitelist-aware URL sanitization to the raw LLM response: URLs whose host matches a trusted source domain are preserved verbatim, all other URLs are defanged (`http://` becomes `hxxp://`, `https://` becomes `hxxps://`). The sanitization SHALL complete without raising "Invalid use of '\\' in replacement text". The digest file SHALL be written successfully when the LLM response is non-empty, regardless of whether the response contains backslashes.

#### Scenario: LaTeX in org-link description does not crash digest
- **WHEN** the LLM returns a response containing an org-link with LaTeX in the description (e.g., `[[https://arxiv.org/abs/2406.15797][$\texttt{SynC}$: Synergistic Boosting]]`)
- **THEN** `sem-rss--generate-file` callback processes the response without signaling an error
- **AND** the digest file is written to the target path
- **AND** the file contains the sanitized content

#### Scenario: Backslash escape in replacement text does not crash
- **WHEN** the LLM returns a response containing a URL immediately followed by backslash sequences (e.g., `https://example.com\texttt{word}`)
- **THEN** the callback completes without raising "Invalid use of '\\' in replacement text"
- **AND** the digest file is written successfully

#### Scenario: Normal response still processed correctly
- **WHEN** the LLM returns a normal Org-mode response without backslashes
- **THEN** the callback processes the response as before
- **AND** the digest file is written with URLs sanitized according to the trusted source whitelist

### Requirement: Digest preserves trusted source URLs
The system SHALL derive trusted source hosts from the configured elfeed feed sources (the feed URLs loaded from the feeds Org file); no second hand-maintained list of trusted hosts SHALL be required. When writing a digest file, the system SHALL preserve URLs whose host matches a trusted source host in their plain `http://`/`https://` form, and SHALL defang all other URLs (`http://` becomes `hxxp://`, `https://` becomes `hxxps://`). A URL SHALL be treated as trusted when its host equals a trusted source host, or when the base domain of its host (the last two labels of the host) equals the base domain of a trusted source host. Host comparison SHALL be case-insensitive and SHALL consider only the host component of the URL, ignoring scheme, port, path, and query. If no trusted source hosts are available, the system SHALL defang all URLs.

#### Scenario: Trusted source URL is preserved
- **WHEN** the configured feeds include a feed at `https://arxiv.org/rss/cs.LG`
- **AND** the LLM response contains a link to `https://arxiv.org/abs/2406.15797`
- **THEN** the digest file contains `https://arxiv.org/abs/2406.15797` unchanged

#### Scenario: Link host shares base domain with feed host
- **WHEN** the configured feeds include a feed at `https://rss.arxiv.org/rss/cs.DB`
- **AND** the LLM response contains a link to `https://arxiv.org/abs/2406.15797`
- **THEN** the digest file contains `https://arxiv.org/abs/2406.15797` unchanged

#### Scenario: Untrusted URL is still defanged
- **WHEN** the LLM response contains a URL whose host does not match any trusted source host or trusted base domain
- **THEN** the digest file contains the URL in defanged form (`hxxp://` or `hxxps://`)

#### Scenario: Trusted hosts derived from elfeed feed sources
- **WHEN** the feeds Org file defines feed URLs for multiple hosts
- **THEN** each distinct feed URL host, and the base domain of each feed URL host, is treated as trusted
- **AND** no hand-maintained second list of trusted hosts is required

#### Scenario: Host match ignores scheme and path
- **WHEN** a feed is configured at `http://example.org/feed.xml`
- **AND** the LLM response contains `https://example.org/post/1`
- **THEN** the digest file contains `https://example.org/post/1` unchanged

#### Scenario: No trusted hosts available
- **WHEN** no feed sources are configured or loaded
- **AND** the LLM response contains URLs
- **THEN** all URLs in the digest file are defanged
