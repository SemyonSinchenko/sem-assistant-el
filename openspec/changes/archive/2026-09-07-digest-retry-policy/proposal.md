## Why

Every morning both digests (general RSS and arXiv) dispatch their LLM requests
about one second apart. With upstream rate limits shared across the OpenRouter
pool (observed with `qwen/qwen3.8-flash`, HTTP 429), the two near-simultaneous
requests collide. The current digest backoff (20 s base, doubling, 3 attempts
total) is shorter than the upstream rate-limit window, so one digest exhausted
its attempts and failed into `errors.org` on 2026-09-07 while the other only
succeeded minutes later.

## What Changes

- Stagger the arXiv digest 5 seconds after the general digest, so the two LLM
  requests are no longer dispatched back-to-back. The offset is hardcoded.
- On HTTP 429 (rate limit), retry up to 3 times (initial request plus 3
  retries, 4 attempts total) with a fixed 5-minute delay between attempts,
  scoped to digest generation.
- This replaces the digest's current rate-limit backoff (20 s base doubling
  per attempt, capped at 300 s, 3 attempts total, shared
  `SEM_TASK_RATE_LIMIT_RETRY_DELAY` env var).
- Non-429 API errors keep the existing behavior: no retry, error logged to
  `errors.org`, no output file written.
- The shared `sem-llm-rate-limit-retry-delay` helper and its env var stay
  unchanged for the task pipeline (`sem-router.el`) and url-capture.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `rss-digest`: add a requirement that arXiv digest generation starts 5
  seconds after general digest generation, and a requirement that 429
  rate-limit responses are retried up to 3 times with a fixed 5-minute delay
  before the failure is logged to `errors.org`; the existing "API error logged
  with RETRY status" wording changes to apply only after retries are exhausted.

## Impact

- **Code:** `app/elisp/sem-rss.el` — `sem-rss-generate-morning-digest`
  (stagger) and `sem-rss--generate-file` (retry loop, new digest-scoped
  constants for attempt count and delay).
- **Unchanged:** `sem-llm.el` rate-limit helpers, task pipeline retry
  behavior, url-capture retry behavior.
- **Tests:** `app/elisp/tests/sem-rss-test.el` — new cases for retry count,
  fixed 5-minute delay, and stagger timing (mocked timers).
- **Ops:** worst-case digest completion time grows to roughly 15 minutes of
  retry delays plus LLM generation time; digest files may appear later than
  today when upstream rate limits persist.
