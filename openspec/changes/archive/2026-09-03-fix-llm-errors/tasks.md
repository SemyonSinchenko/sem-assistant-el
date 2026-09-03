## 1. Wrapper normalization (sem-llm.el)

- [x] 1.1 Rewrite the `sem-llm-request` callback wrapper: accumulate string chunks, skip `(reasoning . ...)` conses with a log line, deliver once on the `t` success sentinel, deliver `nil` on the failure sentinel; in non-streaming mode deliver on the first string. Verify with a manual batch-eval driving a scripted callback sequence
- [x] 1.2 Add the per-request once-only delivery guard; log (not act on) any terminal callback event arriving after delivery. Verify: scripted sequence with a duplicate sentinel results in exactly one caller invocation
- [x] 1.3 Preserve the failure cause: forward `(plist-get info :error)` to the caller error context and to `sem-core-log-error`; use the generic literal only when the transport reported nothing. Verify: scripted failure sentinel with `:error "Curl failed with exit code 18"` reaches the caller context unchanged

## 2. Streaming mock (tests/sem-mock.el)

- [x] 2.1 Add `sem-mock-gptel-request-stream` (or equivalent) that drives the callback with a scripted sequence of chunks / reasoning conses / sentinels, following the existing mock naming and reset conventions. Verify: existing `sem-mock-gptel-reset` clears it and `eask emacs --batch` loads cleanly

## 3. Regression tests

- [x] 3.1 `tests/sem-llm-test.el`: streaming chunk sequence delivers exactly once with the concatenated full text; reasoning conses are never delivered; `t` sentinel triggers delivery; empty stream delivers `nil` once. Verify: `eask emacs --batch --load app/elisp/tests/sem-mock.el --load app/elisp/tests/sem-llm-test.el --eval "(ert-run-tests-batch-and-exit)"`
- [x] 3.2 `tests/sem-llm-test.el`: failure sentinel delivers `nil` with the transport cause preserved, and logs use documented statuses. Verify: same command, new tests pass
- [x] 3.3 `tests/sem-router-test.el`: partial chunks plus success sentinel produce exactly one router callback with the full text and no premature cursor mark/DLQ from partial validation. Verify: `eask emacs --batch --load app/elisp/tests/sem-mock.el --load app/elisp/tests/sem-router-test.el --eval "(ert-run-tests-batch-and-exit)"`

## 3b. Additional fix from integration run 2026-09-03

- [x] 3.4 `sem-router.el`: guard sensitive-content restore with `(stringp response)` so failed LLM responses (nil) for tasks with security blocks take the retry path instead of crashing the callback on `replace-regexp-in-string` with nil (wrong-type-argument arrayp) and stranding the batch barrier at pending>0 (which blocked the batch commit of all successfully written tasks). Regression test: `sem-router-test-task-api-error-with-security-blocks-still-retries`. Verify: full ERT suite passes

## 3c. Additional fixes from second integration run (2026-09-03)

- [x] 3.5 `sem-router.el`: handle HTTP 429 rate limits specifically - rate-limited task requests are rescheduled in-process with exponential backoff (base `SEM_TASK_RATE_LIMIT_RETRY_DELAY`, default 20s, doubling, capped 300s) instead of waiting for the next inbox cycle; completion callback deferred to the terminal outcome; exhausted 429s still route to DLQ. New helpers `sem-router--rate-limit-p`, `sem-router--rate-limit-retry-delay`, `sem-router--schedule-task-llm-retry`. Verify: `sem-router-test-rate-limit-detector`, `sem-router-test-rate-limit-delay-backoff`, `sem-router-test-task-429-schedules-in-process-retry`, `sem-router-test-task-429-exhausted-goes-to-dlq`
- [x] 3.6 `dev/integration/run-integration-tests.sh`: strip non-digit characters from `container_epoch` collection (ESC byte from the login shell broke timezone-offset parsing, Assertion 9). Operator-run only; agents do not execute the suite

## 3d. Additional fixes from third integration run (2026-09-03)

- [x] 3.7 `sem-llm.el`: per-request watchdog timeout (default 180s, `SEM_LLM_REQUEST_TIMEOUT_SECONDS`) - a hung stream now delivers a timeout failure exactly once (late responses discarded via the delivery guard), so one stalled request can no longer hold the batch barrier open and block the commit of all other completed tasks. Verify: `sem-llm-test-request-timeout-delivers-once`, `sem-llm-test-request-timeout-configurable`
- [x] 3.8 `sem-router.el`: stagger task dispatches across a batch (first immediate, then `SEM_TASK_DISPATCH_STAGGER_SECONDS` per task, default 2s, capped 30s, 0 disables) to avoid upstream 429 bursts. Verify: `sem-router-test-task-dispatch-stagger-delays`

## 3e. Additional fix from fourth integration run (2026-09-03)

- [x] 3.9 URL-capture 429 handling: `sem-llm.el` gains the shared `sem-llm-rate-limit-p` detector (router delegates to it); `sem-url-capture.el` classifies 429 failures as `:failure-kind 'rate-limited`; `sem-router.el` reschedules rate-limited captures in-process with the same backoff schedule as tasks (deferred completion callback, barrier accounting unchanged; exhausted 429s still route to DLQ). Verify: `sem-url-capture-test-429-failure-kind-rate-limited`, full suite

- [x] 3.10 `sem-router.el`: URL-capture success path fires the batch-barrier decrement (the earlier restructure left it only on the failure path, so a successful capture stranded the barrier at pending=1 and blocked the batch commit of all 7 written tasks; found via integration run 4). Verify: full suite + integration run
- [x] 3.11 `sem-rss.el`: digest generation retries rate-limited (429) LLM requests in-process with the same backoff schedule (cl-labels run-attempt loop, max 3 attempts, deferred completion callback). Verify: `sem-rss-test-generate-file-429-retries-in-process`

## 4. Validation

- [x] 4.1 Run the parenthesis linter on changed elisp files: `sh dev/elisplint.sh app/elisp/sem-llm.el app/elisp/tests/sem-mock.el`
- [x] 4.2 Run the full suite: `eask test ert app/elisp/tests/sem-test-runner.el` and confirm no regressions
- [x] 4.3 Run `openspec validate fix-llm-errors` and confirm the change validates
