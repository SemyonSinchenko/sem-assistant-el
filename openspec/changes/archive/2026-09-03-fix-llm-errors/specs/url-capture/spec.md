## ADDED Requirements

### Requirement: Rate-limited URL captures retry in-process with backoff
When the LLM layer reports a transient rate limit (HTTP 429) for a URL-capture
request and retry budget remains, the pipeline SHALL reschedule the capture
in-process after a backoff delay (same schedule as task retries: base
`SEM_TASK_RATE_LIMIT_RETRY_DELAY`, default 20 seconds, doubling per attempt,
capped at 300 seconds) instead of failing immediately. The completion callback
SHALL fire only on the terminal outcome, so batch accounting is unchanged.
Captures whose retry budget is exhausted SHALL route to DLQ as before.

#### Scenario: 429 with retry budget remaining
- **WHEN** a URL-capture LLM request fails with a 429 rate-limit error and
  fewer than the maximum retries have been used
- **THEN** the capture is rescheduled in-process after the computed backoff delay
- **AND** the completion callback has not fired yet

#### Scenario: 429 with retry budget exhausted
- **WHEN** a URL-capture LLM request fails with 429 and the maximum retries are
  exhausted
- **THEN** the capture is routed to DLQ as before
