## Context

See proposal.md - Why for motivation and reproduction evidence.

Current state:

- `init.el` registers the OpenRouter backend with `:stream t` and
  `:request-params '(:reasoning (:exclude t))`.
- gptel (installed at Docker image build time; locally pinned builds 20260322 and
  20260826 both exhibit the documented contract) invokes the request callback multiple
  times per request under streaming: `(reasoning . TEXT)` conses, `(reasoning . t)`,
  partial string chunks, then `t` (success) or `nil` (failure) at stream end. Under
  non-streaming it invokes the callback once with the full text or `nil`.
- `sem-llm-request` implements the non-streaming shape only: every non-nil invocation is
  treated as a complete response, and `nil` is replaced with the literal
  `"Empty response"` before the caller sees it.
- Callers (`sem-router.el`, `sem-rss.el`, `sem-url-capture.el`) expect the documented
  signature: one callback invocation with `(RESPONSE INFO CONTEXT)` where RESPONSE is the
  final text or nil. This contract must not change.
- `sem-mock.el` mocks gptel with a single complete-string invocation, so tests never
  exercised the streaming shapes.

## Goals / Non-Goals

**Goals:**

- Normalize the gptel callback contract inside `sem-llm-request`: exactly one caller
  invocation per request, with the final text or `nil`.
- Preserve the transport-reported failure cause and surface it in `errors.org`.
- Make the streaming behavior regression-testable with a realistic mock.
- Keep the caller-facing API and all retry/DLQ policy in callers unchanged.

**Non-Goals:**

- No changes to retry policy, backoff, or DLQ thresholds (caller-side concern).
- No change to the gptel backend configuration (streaming stays enabled; reasoning
  exclusion stays as-is).
- No prompt, model, or cost-optimization work (e.g., RSS digest prompt size).
- No changes to the integration test suite (agents do not run it).

## Decisions

### D1: Normalize inside the wrapper; keep streaming enabled

`sem-llm-request` becomes delivery-normalizing. Alternatives considered:

- *Disable streaming (`:stream nil`)*: one-line fix; gptel then calls the callback once.
  Rejected: long reasoning generations produce no bytes for many seconds to minutes; a
  fully idle connection is more exposed to intermediary/gateway resets (the RSS digest
  profile at 91-143s), and streaming progress data is useful for diagnostics. Also,
  transport failures occur in both modes, so this alone does not fix the
  error-cause-loss defect.
- *Fix in each caller*: duplicates contract knowledge in three modules. Rejected - the
  wrapper exists precisely to centralize gptel specifics.

### D2: Delivery strategy selected by streaming mode, with a once-only guard

The wrapper learns the streaming mode from the callback contract itself: gptel
attaches a `:stream` key to the info plist of every callback event when (and only
when) the request streams (verified in the pinned gptel sources), so the first
event selects the strategy:

- *Streaming mode*: accumulate string chunks in the request closure; ignore
  `(reasoning . ...)` conses (reasoning is already excluded via request params; arrivals
  are logged and skipped defensively); deliver the accumulated text when the `t`
  sentinel arrives; deliver `nil` when the failure sentinel arrives.
- *Non-streaming mode*: deliver on the first string (it is the complete response).

A per-request "delivered" flag guarantees the caller callback fires at most once, even if
gptel sends both chunk callbacks and a terminal sentinel, or retries internally. A
terminal event after delivery is logged as an anomaly, not acted on.

### D3: Failure cause passthrough

On failure the wrapper forwards `(list :error (or (plist-get info :error)
"Empty response") ...)` - gptel's cause first, generic literal only as last resort - and
logs the same cause via `sem-core-log-error`. Callers already read `(plist-get info
:error)`, so no caller changes are needed. The llm module's log entries keep documented
statuses (`FAIL`/`RETRY`).

### D4: Realistic streaming mock in sem-mock.el

Add a mock helper that drives the callback with a scripted sequence (chunks, reasoning
cons, sentinel), mirroring the gptel contract verified against the pinned sources. The
existing single-string helper stays for non-streaming-shaped tests. Tests target the
contract (values and invocation counts), not gptel internals, so a Docker-side gptel
version drift does not break them.

### D5: Regression tests at both levels

- `sem-llm-test.el`: full chunk sequence delivered once; reasoning conses never
  delivered; `t` sentinel triggers delivery; failure sentinel delivers `nil` and
  preserves the cause; empty stream delivers `nil` once; non-streaming shape unchanged.
- `sem-router-test.el`: partial chunks followed by the sentinel result in exactly one
  router callback with the full text, and no premature cursor mark/DLQ from partial
  validation.

## Addendum (integration run 2026-09-03)

Post-fix integration run exposed one more caller-side defect in the same family:
`sem-router.el` restored sensitive content unconditionally, so a nil response
(e.g. upstream 429) for a task with security blocks crashed the callback
(`wrong-type-argument arrayp nil` inside `replace-regexp-in-string`) before the
retry branch ran. The crashed callback also never fired the batch-completion
callback, leaving the batch barrier at pending=1 and blocking the commit of all
successfully written tasks. Fixed by restoring only when the response is a
string; regression test added. Follow-up decisions for the second run findings: (1) upstream 429 rate
limits are now handled by an in-process backoff retry in the task pipeline
(D3a) - the operator is a paid OpenRouter user, so 429s are transient burst
limits rather than a hard quota; (2) the ESC byte polluting the harness
`container_epoch` value (via `sh -lc` on the rebuilt `master` base image) is
fixed by stripping non-digit characters during collection.

### D3a: In-process 429 backoff retry in the task pipeline

Rate-limited failures are detected from the gptel error plist (`:code 429`) or
the error string, and the request is rescheduled via `run-at-time` with a
backoff delay (base `SEM_TASK_RATE_LIMIT_RETRY_DELAY`, default 20s, doubling
per attempt, capped at 300s). The existing retry counter and DLQ semantics are
reused: budget exhausted -> DLQ; the completion callback fires exactly once, on
the terminal outcome, so batch-barrier accounting is unchanged. Alternative
considered: transparent retries inside `sem-llm.el` - rejected because the
spec delegates retry-vs-DLQ policy to caller modules, and caller-level
accounting (cursor/DLQ) must stay authoritative.

### D3b: Per-request watchdog timeout and dispatch staggering (third run)

The third integration run proved the full pipeline (retries, backoff, DLQ,
sensitive restore, 5 tasks written) but one hung stream never produced a
callback event, holding the batch barrier at pending=1 for the whole test
window - gptel sets no curl timeout, and the batch watchdog (30 minutes) is
far outside any reasonable window. Fixes: (1) `sem-llm.el` arms a per-request
watchdog (default 180s, env-overridable) that delivers a timeout failure once;
the delivery guard discards late responses; (2) task dispatches are staggered
per batch index to avoid tripping upstream shared-pool limits with 7
simultaneous requests. Staggering was preferred over raising the retry budget
because it prevents the burst instead of absorbing it.

### D3c: URL-capture retry + success-path barrier decrement (fourth run)

Fourth run: all task fixtures landed; the only failure was URL-capture - its
request hit a 429 and failed immediately (no in-process retry), and after the
earlier restructure its success path also lacked the batch-barrier decrement.
Fixes: URL captures classified as rate-limited are rescheduled in-process with
the same backoff (D3a schedule); the URL success path now fires the barrier
decrement explicitly. The RSS digest path shares the same retry semantics.

## Risks / Trade-offs

- [Reasoning conses arrive despite `:reasoning (:exclude t)`] -> Wrapper skips them
  defensively and logs; verified as no-op in reproduction.
- [Docker image pins a different gptel build with a drifted contract] -> Tests assert
  the documented contract shapes (conses, sentinels, chunks), not internals; any drift
  surfaces as an explicit test failure, not silent data loss.
- [Once-only guard could hide a genuine duplicate terminal event] -> Such events are
  logged as anomalies for diagnosis instead of being acted on.
- [Transport failures on very long streams persist] -> Out of scope here; failures now
  carry their real cause, and caller retry policy is unchanged and applies to them.

## Migration Plan

1. Merge wrapper + mock + test changes; run `sh dev/elisplint.sh` and the ERT suite.
2. Redeploy the daemon image. No data or state migration (stateless wrapper change).
3. Observe one run: expect exactly one `RESPONSE OK` per completed request, no
   `Callback error: Wrong type argument` entries, and `errors.org` entries carrying real
   causes on genuine failures.
4. Rollback: redeploy the previous image; the wrapper change is self-contained.

## Open Questions

None blocking. (Prompt-size/cost optimization for the RSS digest is a separate change.)
