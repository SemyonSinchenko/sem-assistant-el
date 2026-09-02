## 1. Security layer: whitelist-aware URL sanitization

- [x] 1.1 Add optional TRUSTED-HOSTS argument to `sem-security-sanitize-urls` plus an internal host-extraction/base-domain helper in `app/elisp/sem-security.el`; nil (default) must keep byte-identical mask-all behavior. Verify: new unit tests in `app/elisp/tests/sem-security-test.el` cover trusted URL preserved, untrusted URL defanged, case-insensitive host match, base-domain match (`rss.arxiv.org` feed → `arxiv.org` link), and nil-argument mask-all.
- [x] 1.2 Verify the backslash-safety contract still holds with a non-nil trusted set (literal replacement). Verify: extend the existing "Backslash in replacement text does not crash" test in `app/elisp/tests/sem-security-test.el` to pass a trusted-hosts argument.

## 2. Digest layer: derive trusted hosts from elfeed sources

- [x] 2.1 Add a `sem-rss` helper that derives the trusted host set from `elfeed-feeds` entries (string and `(URL . tags)` forms), returning feed hosts plus their base domains, and returning nil-safe empty set when `elfeed-feeds` is empty. Verify: unit tests in `app/elisp/tests/sem-rss-test.el` with mocked feed lists cover string entries, list entries, duplicates, and empty feeds.
- [x] 2.2 In `sem-rss--generate-file`, compute the trusted host set per digest run, pass it through the callback context to the sanitize call, and log the trusted-host count via `sem-core-log`. Verify: updated digest tests in `app/elisp/tests/sem-rss-test.el` show a trusted source URL (`arxiv.org`) written verbatim and an untrusted URL (`example.com`) written as `hxxps://`; empty-feeds case writes all URLs defanged.

## 3. Regression guards

- [x] 3.1 Confirm tasks.org masking is untouched: existing `sem-router` sanitize tests in `app/elisp/tests/sem-router-test.el` pass without modification. Verify: run the router test file.
- [x] 3.2 Check docs for stale digest defanging claims (README, module commentary in `sem-security.el` docstring) and update wording to whitelist-aware masking. Verify: grep for "hxxp" and "defang" across README and `app/elisp` commentary shows no contradicting statements.

## 4. Full validation

- [x] 4.1 Run the parenthesis linter on touched files. Verify: `sh dev/elisplint.sh app/elisp/sem-security.el app/elisp/sem-rss.el` reports no unmatched delimiters.
- [x] 4.2 Run the full unit suite. Verify: `eask test ert app/elisp/tests/sem-test-runner.el` passes with no new failures.
