## Why

When OpenRouter rate-limits a URL-capture LLM request (HTTP 429), the router's
async completion chain crashes with `Callback error: Symbol's value as variable
is void: callback`. The root cause is a free-variable reference in
`sem-router-process-inbox` (`sem-router.el:1220`): the URL-capture completion
lambda passes `callback` to `sem-router--schedule-url-capture-retry`, but no
such binding exists in its lexical scope. As a result the documented 429
backoff retry never runs, the batch barrier loses one pending callback, and a
transient rate limit surfaces as an opaque Elisp error instead of a retry.

## What Changes

- Bind the URL-capture completion callback to a lexical variable in
  `sem-router-process-inbox` (mirroring the task path's `completion-callback`)
  and pass that same value to both `sem-url-capture-process` and
  `sem-router--schedule-url-capture-retry`.
- Preserve once-only callback delivery and exactly-once batch-barrier
  accounting for deferred (rate-limited) retries.
- Add ERT regression coverage: a 429 URL-capture failure schedules the
  in-process retry instead of signalling a void-variable error; stale-batch
  and DLQ paths are unchanged.
- Document the rate-limited URL-capture in-process backoff retry as a spec
  requirement, mirroring the existing task-LLM pipeline requirement.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `url-capture`: add a requirement that rate-limited (429) URL-capture LLM
  requests retry in-process with backoff under the same policy as the
  task-LLM pipeline: bounded attempts, exponential delay, downstream callback
  fires on terminal outcome, batch-barrier accounting resolves exactly once.

## Impact

- `app/elisp/sem-router.el` — restructure the URL-capture branch of
  `sem-router-process-inbox` with a `let`-bound completion callback;
  `sem-router--schedule-url-capture-retry` signature unchanged.
- `app/elisp/tests/` — new regression tests (router + url-capture).
- `openspec/specs/url-capture/spec.md` — one new delta requirement.
- No changes to `sem-llm.el`: its `Callback error` log line is correct
  behavior; the bug is in the callback passed to it.
- Integration tests unaffected (429 cannot be forced in integration runs).
