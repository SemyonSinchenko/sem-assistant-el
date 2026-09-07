## 1. sem-rss.el constants

- [x] 1.1 Add `defconst`s `sem-rss-arxiv-stagger-seconds` (5), `sem-rss-rate-limit-retry-delay-seconds` (300), `sem-rss-rate-limit-max-retries` (3) with docstrings; verify with `sh dev/elisplint.sh app/elisp/sem-rss.el`

## 2. Stagger (arXiv behind general digest)

- [x] 2.1 In `sem-rss-generate-morning-digest`, move the arXiv digest block into a lambda scheduled via `(run-at-time sem-rss-arxiv-stagger-seconds nil ...)`; give the lambda its own `condition-case` logging via `sem-core-log-error`; verify `sh dev/elisplint.sh app/elisp/sem-rss.el` passes
- [x] 2.2 Add test `sem-rss-test-morning-digest-staggers-arxiv`: mock `run-at-time`, run the morning digest, assert the arXiv timer is scheduled with delay 5 and that firing it performs the arXiv collection/generation; verify with `eask emacs --batch --load app/elisp/tests/sem-mock.el --load app/elisp/tests/sem-rss-test.el --eval "(ert-run-tests-batch-and-exit \"sem-rss-test-morning-digest-staggers-arxiv\")"`

## 3. Rate-limit retry policy

- [x] 3.1 In `sem-rss--generate-file` `run-attempt`, change the rate-limit guard to `(< attempt-number (1+ sem-rss-rate-limit-max-retries))` and schedule with fixed `sem-rss-rate-limit-retry-delay-seconds` instead of `sem-llm-rate-limit-retry-delay`; keep the RETRY log line with attempt counter and delay; verify with `sh dev/elisplint.sh app/elisp/sem-rss.el`
- [x] 3.2 Update `sem-rss-test-generate-file-429-retries-in-process`: assert first retry scheduled at 300 (not 20), chain the mocked timers through attempts 2-4, and assert digest written when a retried attempt succeeds
- [x] 3.3 Add test `sem-rss-test-generate-file-429-exhaustion-fails-after-four-attempts`: all 4 attempts return 429; assert exactly 4 `sem-llm-request` calls, 3 scheduled retries each with delay 300, `sem-core-log-error` called once, callback success nil, no file written
- [x] 3.4 Add test `sem-rss-test-generate-file-non-429-error-no-retry`: first attempt returns a non-429 API error; assert no `run-at-time` scheduling, `sem-core-log-error` called once, no file written
- [x] 3.5 Add test `sem-rss-test-generate-file-429-delay-is-fixed`: assert the second and third scheduled retries also use delay 300 (no doubling); verify all three new tests pass via the single-file eask command

## 4. Regression and validation

- [x] 4.1 Run the full suite: `eask test ert app/elisp/tests/sem-test-runner.el` and confirm no regressions (router/url-capture retry tests untouched and passing)
- [x] 4.2 Run `openspec validate --changes` and confirm the change validates with no errors
