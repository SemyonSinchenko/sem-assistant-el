## Why

The daemon currently loses LLM responses that OpenRouter successfully generates and bills.
Since switching the model to `qwen/qwen3.8-flash` (a reasoning model), task routing, RSS
digest, and URL capture fail with `Empty response from LLM` / `Callback error: Wrong type
argument`, items end up in DLQ or are silently dropped, and every retry re-bills the same
generation (visible in OpenRouter logs as repeated completed generations with
`finish_reason: stop` while the daemon reports failure).

Root cause (reproduced against the real modules in batch Emacs): `init.el` configures the
gptel OpenRouter backend with `:stream t`, but `sem-llm-request` implements gptel's
NON-streaming callback contract. Under streaming, gptel invokes the callback multiple
times per request — with `(reasoning . TEXT)` conses, `(reasoning . t)`, partial string
chunks, and a final `t` (success) or `nil` (failure) sentinel. `sem-llm-request` treats
every non-nil invocation as a complete response string:

- `(length (reasoning . TEXT))` signals `wrong-type-argument listp` → logged as
  `Callback error` → counted as API failure → DLQ after retries (reproduced).
- The final success sentinel `t` reaches `(length t)` → `wrong-type-argument sequencep`
  (reproduced); production additionally shows `arrayp, nil` from the same class of
  non-string shapes.
- Partial string chunks are passed to the router as if complete → UUID validation fails →
  item is marked processed and lost, or retried with another billed call (reproduced).
- On `nil`, the wrapper replaces gptel's real error info (`(plist-get info :error)`, e.g.
  a curl exit code or HTTP error) with the literal string "Empty response", making the
  true transport/API failure invisible in `errors.org`.

Reasoning models trigger this because their responses arrive as reasoning chunks first
(OpenRouter generation data shows `native_tokens_reasoning: 1345` of `1476` completion
tokens) and take far longer (27s-143s streams), increasing exposure to mid-stream
transport failures that surface as `nil`. The existing tests never catch this because
`sem-mock.el` invokes the callback exactly once with one complete string — a contract
that production never provides.

## What Changes

- Rewrite the `sem-llm-request` callback wrapper to honor gptel's streaming callback
  contract: accumulate string chunks into the full response, ignore/collect
  `(reasoning . ...)` conses and the `t` success sentinel, and invoke the caller's
  callback exactly once with the final response string (or `nil` on real failure).
- Preserve the original failure cause: pass gptel's `(plist-get info :error)` (status,
  curl exit code, HTTP error) through to the caller instead of overwriting it with the
  literal "Empty response"; log `Empty response` only when the stream truly produced no
  content.
- Make streaming explicit and testable: the backend request keeps `:stream t` (lower
  latency, reasoning-friendly), but the wrapper's contract becomes "one call, one final
  string", matching what callers already implement.
- Standardize failure logging in the llm module: failure entries keep the documented
  `FAIL`/`RETRY` statuses and record the real failure cause (transport/HTTP/API error
  detail from gptel) instead of a generic literal.
- Update `sem-mock.el` with a streaming-sequence gptel mock (chunks + reasoning cons +
  sentinels) and add regression tests covering each response shape; keep the existing
  single-string mock for the non-streaming path.
- No changes to retry/DLQ decision logic in `sem-router.el` — it already delegates to
  retry counters; only the shape of what `sem-llm` delivers to it changes.

## Capabilities

### New Capabilities

### Modified Capabilities

- `sem-llm`: The callback wrapper requirement changes from "passes gptel response to
  callback" to "delivers exactly one callback invocation with the complete response text
  per request, honoring gptel streaming semantics (chunk accumulation, reasoning conses,
  success/failure sentinels)"; the failure-logging requirement changes to preserve the
  underlying gptel error info and use valid log statuses.

## Impact

- **Code:** `app/elisp/sem-llm.el` (callback wrapper, error propagation, log statuses),
  `app/elisp/tests/sem-mock.el` (streaming mock), `app/elisp/tests/sem-llm-test.el` and
  `app/elisp/tests/sem-router-test.el` (regression tests). `app/elisp/init.el` gptel
  configuration stays as-is (`:stream t`, `:reasoning (:exclude t)`).
- **Specs:** delta spec for `openspec/specs/sem-llm/spec.md`.
- **Behavioral impact:** no more billed-but-discarded generations; reasoning-model
  responses (qwen3.8-flash) are consumed correctly; `errors.org` entries show the real
  transport/API failure cause; no code changes needed in router/rss/url-capture callers.
- **Risk:** low — callers keep the existing `(response info context)` signature; only the
  delivery semantics inside the wrapper change.
