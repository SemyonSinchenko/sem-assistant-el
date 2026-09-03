## ADDED Requirements

### Requirement: Rate-limited task LLM requests retry in-process with backoff
When the LLM layer reports a transient rate limit (HTTP 429) for a task request and
retry budget remains, the task pipeline SHALL reschedule the request in-process after
a backoff delay instead of deferring the retry to the next inbox processing cycle.
The backoff delay SHALL start from a configurable base (default 20 seconds, env
`SEM_TASK_RATE_LIMIT_RETRY_DELAY`), double with each attempt, and be capped at 300
seconds. The task completion callback SHALL fire only on the terminal outcome
(success, non-rate-limit failure, or retry budget exhausted), so batch accounting
is unchanged.

#### Scenario: 429 with retry budget remaining
- **WHEN** a task LLM request fails with a 429 rate-limit error and fewer than the
  maximum retries have been used
- **THEN** the request is rescheduled in-process after the computed backoff delay
- **AND** the task completion callback has not fired yet

#### Scenario: Backoff delay grows per attempt
- **WHEN** successive attempts keep failing with 429
- **THEN** each scheduled delay doubles relative to the previous attempt, capped at
  300 seconds

#### Scenario: 429 with retry budget exhausted
- **WHEN** a task LLM request fails with 429 and the maximum retries are exhausted
- **THEN** the task is routed to DLQ like any other terminal API failure
- **AND** the task completion callback fires

#### Scenario: Non-rate-limit failures keep existing behavior
- **WHEN** a task LLM request fails with a non-rate-limit error
- **THEN** the existing retry accounting applies without any in-process delay

### Requirement: Task dispatches are staggered across a batch
When a batch dispatches multiple task LLM requests, the pipeline SHALL stagger the
dispatches to avoid simultaneous upstream rate-limit bursts. The first task SHALL
dispatch immediately and each subsequent task SHALL be delayed by a configurable
step (default 2 seconds, env `SEM_TASK_DISPATCH_STAGGER_SECONDS`), capped at 30
seconds. A non-positive step SHALL disable staggering.

#### Scenario: Multiple tasks dispatch spread over time
- **WHEN** a batch contains several task headlines
- **THEN** each task request starts at increasing intervals instead of
  simultaneously

#### Scenario: Staggering disabled
- **WHEN** `SEM_TASK_DISPATCH_STAGGER_SECONDS` is set to a non-positive value
- **THEN** all tasks dispatch immediately as before
