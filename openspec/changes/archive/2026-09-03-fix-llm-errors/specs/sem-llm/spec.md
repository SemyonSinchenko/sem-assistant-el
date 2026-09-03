## ADDED Requirements

### Requirement: sem-llm delivers one final response per request
The `sem-llm` module SHALL deliver the caller callback exactly one invocation per LLM
request, passing the complete response text (a string) or `nil` on failure, regardless of
whether the underlying gptel backend operates in streaming or non-streaming mode. The
`sem-llm` module SHALL NOT forward gptel-internal streaming values to callers, including
partial text chunks, `(reasoning . TEXT)` reasoning conses, and the `t` success sentinel.

#### Scenario: Streaming content chunks are accumulated
- **WHEN** gptel delivers the response as multiple partial string chunks
- **THEN** `sem-llm` invokes the caller callback exactly once with the concatenated full text

#### Scenario: Reasoning chunks are not delivered as response text
- **WHEN** the stream contains `(reasoning . TEXT)` conses or a `(reasoning . t)` marker
- **THEN** `sem-llm` does not pass them to the caller callback as response text
- **AND** the caller callback receives the concatenated non-reasoning text

#### Scenario: Success sentinel triggers final delivery
- **WHEN** gptel signals end of stream with the success sentinel `t`
- **THEN** `sem-llm` invokes the caller callback once with the accumulated response text

#### Scenario: Empty stream delivers nil once
- **WHEN** a request ends without any response text
- **THEN** `sem-llm` invokes the caller callback exactly once with `nil`

#### Scenario: Non-streaming backends keep single delivery
- **WHEN** the backend operates in non-streaming mode and gptel calls the callback once with the full text
- **THEN** `sem-llm` invokes the caller callback exactly once with that text

#### Scenario: Callback errors are caught without breaking delivery
- **WHEN** the caller callback raises an error
- **THEN** `sem-llm` catches the error and logs it
- **AND** the error is not propagated to the daemon


### Requirement: Per-request watchdog timeout
The `sem-llm` module SHALL arm a per-request watchdog timer (default 180 seconds,
configurable via `SEM_LLM_REQUEST_TIMEOUT_SECONDS`). If no callback event arrives
within the window, the wrapper SHALL deliver a timeout failure to the caller exactly
once. Any response arriving after the timeout SHALL be discarded, and successful
requests SHALL cancel the watchdog.

#### Scenario: Hung request times out
- **WHEN** a request produces no callback event within the configured timeout
- **THEN** the caller callback receives `nil` with a timeout error cause exactly once

#### Scenario: Late response after timeout is discarded
- **WHEN** the underlying request completes after the watchdog already fired
- **THEN** the late response is not delivered to the caller

#### Scenario: Successful request cancels the watchdog
- **WHEN** the response completes before the timeout
- **THEN** the watchdog timer is canceled and the response is delivered normally

## MODIFIED Requirements

### Requirement: sem-llm calls sem-core-log on success/failure
The `sem-llm` module SHALL call `sem-core-log` on both success and failure of LLM requests,
using the documented status values (`OK`, `RETRY`, `DLQ`, `FAIL`). On failure, `sem-llm`
SHALL pass the underlying failure cause reported by the transport layer to the caller
(when available) instead of a generic literal, so that failure records in `errors.org`
identify the real cause (HTTP error, transport failure, or empty stream).

#### Scenario: Success logged
- **WHEN** an LLM request completes successfully
- **THEN** `sem-core-log` is called with `STATUS=OK` once per request, after the final
  response is known

#### Scenario: Failure preserves the underlying cause
- **WHEN** an LLM request fails with a transport or HTTP error reported by gptel
- **THEN** the callback receives an error context containing that failure detail
- **AND** `errors.org` records the same failure detail rather than a generic literal

#### Scenario: Failure logged
- **WHEN** an LLM request fails
- **THEN** `sem-core-log` is called with a documented status value (`FAIL` or `RETRY`)
