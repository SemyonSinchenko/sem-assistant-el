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

### Requirement: No file written if no entries found
The system SHALL NOT write a digest file if no entries are found for a filter. No LLM call SHALL be made in this case. On malformed LLM output, the error SHALL be logged to `errors.org` and the output file SHALL NOT be written. On API error, the error SHALL be logged to `errors.org` with RETRY status and the output file SHALL NOT be written.

#### Scenario: No entries, no file
- **WHEN** no entries match the general filter in the last 24 hours
- **THEN** no general digest file is written

#### Scenario: Malformed output logged to errors.org
- **WHEN** the LLM returns malformed output for rss-digest
- **THEN** the error is logged to `/data/errors.org` and no output file is written

#### Scenario: API error logged with RETRY status
- **WHEN** the LLM API returns an error during rss-digest generation
- **THEN** the error is logged to `/data/errors.org` with RETRY status and no output file is written

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
The `sem-rss--generate-file` callback SHALL process LLM responses containing backslash characters (e.g., LaTeX markup from arXiv paper titles) without signaling an error. The callback SHALL call `sem-security-sanitize-urls` on the raw LLM response, and the sanitization SHALL complete without raising "Invalid use of '\\' in replacement text". The digest file SHALL be written successfully when the LLM response is non-empty, regardless of whether the response contains backslashes.

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
- **AND** the digest file is written with sanitized URLs
