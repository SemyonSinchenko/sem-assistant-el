## ADDED Requirements

### Requirement: Rate-limited URL-capture LLM requests retry in-process with backoff
When the LLM layer reports a transient rate limit (HTTP 429) for a URL-capture
request and the headline's retry budget remains (fewer than 3 cumulative
retryable failures), the router SHALL reschedule the URL capture in-process
after a backoff delay instead of deferring the retry to the next inbox
processing cycle. The backoff delay SHALL follow the shared rate-limit policy:
it starts from a configurable base, doubles with each attempt, and is capped at
300 seconds. The completion callback registered for the original dispatch SHALL
be reused for the retried attempt, so stale-batch guarding, retry counting, and
batch-barrier accounting continue to apply to the retried outcome.

#### Scenario: 429 with retry budget remaining
- **WHEN** a URL-capture LLM request fails with a 429 rate-limit error and fewer
  than 3 cumulative retryable failures are recorded for the headline
- **THEN** the URL capture is rescheduled in-process after the computed backoff
  delay without signalling an error
- **AND** the completion callback has not fired yet, so the batch barrier for the
  dispatch is not resolved

#### Scenario: Retried outcome reuses the original completion path
- **WHEN** a rate-limited URL capture is rescheduled in-process
- **THEN** the retried attempt reports its outcome through the original
  dispatch's completion path
- **AND** stale-batch guarding, retry counting, and batch-barrier accounting
  apply to that outcome exactly as they would for the initial attempt

#### Scenario: Backoff delay grows per attempt and is capped
- **WHEN** successive attempts keep failing with 429
- **THEN** each scheduled delay doubles relative to the previous attempt, capped
  at 300 seconds

#### Scenario: Retry budget exhausted
- **WHEN** a URL-capture request fails with a retryable failure and the 3rd
  cumulative retryable failure is recorded
- **THEN** the headline is routed to DLQ like any other terminal failure
- **AND** the completion callback fires and resolves the batch barrier

#### Scenario: Non-rate-limit failures keep existing behavior
- **WHEN** a URL-capture request fails with a non-rate-limit error
- **THEN** the existing behavior applies: timeouts log a FAIL and defer to the
  next inbox processing cycle, and security-malformed failures route directly to
  DLQ without consuming retry budget
