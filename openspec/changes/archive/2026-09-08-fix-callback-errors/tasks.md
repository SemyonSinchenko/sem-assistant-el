## 1. Regression Tests (write first — expect the 429 case to fail)

- [x] 1.1 Add ERT test in `app/elisp/tests/sem-router-test.el`: URL-capture completion with `(:failure-kind (quote rate-limited))` context schedules the in-process retry without signalling, captures the same (`eq`) callback object registered with `sem-url-capture-process`, and does not resolve the batch barrier (deferred path). Verify: test fails today with `void-variable callback` via `eask emacs --batch --load app/elisp/tests/sem-mock.el --load app/elisp/tests/sem-router-test.el --eval "(ert-run-tests-batch-and-exit \'<new-test-name>)"`
- [x] 1.2 Add ERT test: retry budget exhausted (3rd cumulative retryable failure) routes to DLQ, fires the completion callback, and resolves the batch barrier exactly once. Verify: new test passes against current code (behavior unchanged) and still passes after the fix
- [x] 1.3 Add ERT test: stale-batch guard with a rate-limited failure kind — STALE skip, no retry scheduled, no DLQ; barrier resolves for the old batch id only (matches existing stale-callback contract). Verify: new test passes via the single-file test command above

## 2. Router Fix

- [x] 2.1 In `sem-router-process-inbox`'s URL-capture branch, `let`-bind the completion callback (mirroring the task branch's `completion-callback`) and pass that one binding to both `sem-url-capture-process` and `sem-router--schedule-url-capture-retry`; no signature changes. Verify: the 1.1 test turns green; run `sh dev/elisplint.sh app/elisp/sem-router.el` with no unmatched delimiters

## 3. Verification Sweep

- [x] 3.1 Run the full suite `eask test ert app/elisp/tests/sem-test-runner.el` — all tests pass with no new failures
- [x] 3.2 Byte-compile sweep: `eask emacs --batch --eval "(add-to-list \'load-path (expand-file-name \"app/elisp\" default-directory))" -f batch-byte-compile app/elisp/sem-*.el app/elisp/init.el` reports zero `reference to free variable` warnings; remove any generated `.elc` files afterwards
- [x] 3.3 Confirm the delta requirement matches implementation: `openspec validate fix-callback-errors --type change` passes
