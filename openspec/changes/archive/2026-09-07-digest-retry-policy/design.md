## Context

`sem-rss-generate-morning-digest` (cron entry point, guarded by
`sem-core-run-cron-guarded`) generates the general digest and then the arXiv
digest back-to-back in one synchronous body. Both go through
`sem-rss--generate-file`, which calls `sem-llm-request` asynchronously and
retries HTTP 429 in-process via `run-at-time`, using the shared
`sem-llm-rate-limit-retry-delay` helper (20 s base from
`SEM_TASK_RATE_LIMIT_RETRY_DELAY`, doubling per attempt, capped at 300 s,
3 attempts total). That helper is also consumed by `sem-router.el` (task
pipeline) and `sem-url-capture.el`, whose retry behavior is spec'd in
`task-llm-pipeline` and `url-capture` and must not change. The cron guard
already releases when the synchronous body returns; async LLM work outlives
it today. The existing test `sem-rss-test-generate-file-429-retries-in-process`
mocks `run-at-time` and `sem-llm-request` and asserts the scheduled delay
(currently 20) - the same pattern covers the new behavior.

## Goals / Non-Goals

**Goals:**
- Digest-only stagger and rate-limit retry policy, implemented in `sem-rss.el`.
- Fixed, hardcoded values (5 s stagger, 300 s retry delay, 3 retries) per the
  specs - no new configuration knobs.
- Keep the existing in-process `run-at-time` retry structure and mocked-timer
  test pattern so the change stays small and testable.

**Non-Goals:**
- No changes to `sem-llm.el` (`sem-llm-rate-limit-p` is reused for detection;
  `sem-llm-rate-limit-retry-delay` and its env var stay for router/url-capture).
- No request serialization or locking between the two digests beyond the
  fixed offset.
- No jitter, exponential backoff, or provider-routing changes for digests.
- No DB or on-disk format changes.

## Decisions

1. **Stagger via `run-at-time` in the cron entry point.** The arXiv half of
   `sem-rss-generate-morning-digest` moves into a lambda scheduled
   `sem-rss-arxiv-stagger-seconds` (5) after the general step begins.
   - Alternative considered: chain arXiv off the general digest completion
     callback - rejected; it couples the digests, delays arXiv by the general
     request duration, and blocks arXiv entirely when the general digest fails.
   - The deferred lambda gets its own `condition-case` that logs via
     `sem-core-log-error`, because the outer guard's handler has already
     returned by the time the timer fires.
   - The "Morning digest generation completed" log fires after scheduling,
     before the arXiv timer - consistent with today, where it also fires
     before async LLM completion.

2. **Digest-scoped constants in `sem-rss.el`.** `sem-rss-arxiv-stagger-seconds`
   (5), `sem-rss-rate-limit-retry-delay-seconds` (300),
   `sem-rss-rate-limit-max-retries` (3) as `defconst`s. Hardcoded per the
   specs; no env read at call time.

3. **Retry loop keeps its shape, values change.** In `run-attempt`, the
   rate-limit branch keeps `sem-llm-rate-limit-p` detection and in-process
   `run-at-time` rescheduling, but the guard becomes
   `(< attempt-number (1+ sem-rss-rate-limit-max-retries))` (attempts 1-3
   schedule retries 2-4; attempt 4 is terminal) and the delay becomes the
   fixed constant instead of `sem-llm-rate-limit-retry-delay`. Each scheduled
   retry keeps a RETRY log line with the attempt counter and delay. The
   retry reuses the captured prompt and context unchanged (already true).

4. **Terminal behavior unchanged in shape.** A non-429 API error and a
   rate-limit failure after the final attempt both go through
   `sem-core-log-error` (one errors.org entry per terminal failure, not per
   retry) and write no file - matching the delta spec's modified requirement.

5. **Tests follow the existing mocked-timer pattern.** Update
   `sem-rss-test-generate-file-429-retries-in-process` (delay 20 -> 300,
   chain scheduled timers to walk attempts), plus new tests for: exhaustion
   after 4 attempts, fixed (non-doubling) delay, non-429 error schedules no
   retry, and the morning-digest stagger (mocked `run-at-time` captures the
   deferred arXiv lambda at delay 5).

## Risks / Trade-offs

- [Later digests on persistent rate limits] Worst case adds ~15 min of retry
  delays before terminal failure. → Accepted: a morning digest minutes late
  beats a failed digest; the stagger plus fixed delay cleared the observed 429.
- [5 s stagger does not prevent in-flight overlap] LLM generation takes
  minutes, so requests can still overlap; the stagger only avoids
  back-to-back dispatch. → The retry policy is the real mitigation; both are
  cheap.
- [Daemon restart during a retry window loses the pending retry] `run-at-time`
  timers are in-process. → Same exposure as today's 20 s retries; digest can
  be regenerated manually or next day.
- [Shared-pool contention at exact 5-minute marks] No jitter. → Scale is two
  digest requests per day; not worth the complexity.

## Migration Plan

Deploy with the normal daemon restart (docker-compose). No data or config
migration. Rollback is reverting the commit; both behaviors degrade to the
current 20 s/40 s backoff and simultaneous dispatch.

## Open Questions

None.
