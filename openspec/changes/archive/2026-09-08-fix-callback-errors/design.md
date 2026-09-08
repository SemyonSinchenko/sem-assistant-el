## Context

`sem-router-process-inbox` dispatches URL captures asynchronously. It binds an
anonymous completion lambda and passes it to `sem-url-capture-process`. On a
rate-limited failure, that lambda calls
`sem-router--schedule-url-capture-retry` passing the variable `callback`, which
is not bound anywhere in its lexical scope. Evaluating that argument raises
`void-variable`, the retry is never scheduled, and the error resurfaces in the
LLM response handler's log as `Callback error: Symbol's value as variable is
void: callback`. The byte compiler confirms the defect at HEAD:
`sem-router.el:1220:47: Warning: reference to free variable ‘callback’`.

The task branch of the same function already demonstrates the intended pattern:
a `let`-bound `completion-callback` used both for the initial dispatch and for
retry scheduling. All retry machinery the URL path needs already exists:
`sem-router--schedule-url-capture-retry` (in-process `run-at-time`
rescheduling of `sem-url-capture-process`), the shared backoff helper
`sem-router--rate-limit-retry-delay`, the `sem-core` retry counter, and the
`deferred` flag that skips the batch-barrier check until a terminal outcome.

## Goals / Non-Goals

**Goals:**
- Make 429 on URL capture retry in-process without signalling, with the same
  callback identity flowing through the original dispatch and the retry.
- Keep batch-barrier accounting exactly-once: deferred retries do not resolve
  the barrier; the retried terminal outcome does.
- Regression tests that fail if the free-variable reference returns.

**Non-Goals:**
- No changes to the `sem-llm` callback contract or its error logging.
- No changes to RSS or planner rate-limit policies (they already retry).
- No new retry counters or DLQ semantics; the existing URL-capture retry
  counter (3 cumulative failures) applies.

## Decisions

1. **`let`-bind the completion callback in the URL branch** and pass that one
   binding to both `sem-url-capture-process` and
   `sem-router--schedule-url-capture-retry`, mirroring the task branch's
   `completion-callback`. Alternative considered: extracting a named defun —
   rejected because it would require partially applying per-headline state
   (hash, batch id, title) that the closure already captures, and the in-file
   `let` pattern is the established convention here.
2. **No signature changes.** `sem-router--schedule-url-capture-retry` keeps its
   `(url callback batch-id hash retry-count)` contract.
3. **Test strategy:** `cl-letf`-stub `sem-router--schedule-url-capture-retry`
   to capture arguments, then drive the completion lambda with a
   `(:failure-kind 'rate-limited)` context. Assert (a) no error is signalled,
   (b) the captured callback is `eq` to the one registered with
   `sem-url-capture-process`, (c) the barrier check is not resolved on the
   deferred path. Companion tests cover the DLQ-exhausted and stale-batch
   paths. Tests stub scheduling and never wait on real timers, following
   `sem-router-test.el` conventions (`sem-mock.el` loaded first).
4. **Compile-time gate:** run `batch-byte-compile` over `app/elisp/*.el` during
   verification and require zero `reference to free variable` warnings.

## Risks / Trade-offs

- [Persistent 429 retries a URL capture repeatedly] → the cumulative retry
  counter caps attempts at 3, then DLQ; backoff is capped at 300 seconds.
- [Barrier resolved twice (deferred + terminal paths)] → the existing
  `deferred` flag already suppresses the barrier check on the deferred branch;
  a regression test asserts exactly-once resolution.
- [Fix covers only the URL path; a similar free variable could appear later] →
  the byte-compile gate in verification catches free-variable references at
  compile time; tasks include running it over all modules.

## Migration Plan

- Deploy by rebuilding/restarting the daemon as usual; modules load at startup.
- Rollback is a plain `git revert`; no data, config, or file-format changes.

## Open Questions

None.
