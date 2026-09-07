## ADDED Requirements

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

## MODIFIED Requirements

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
