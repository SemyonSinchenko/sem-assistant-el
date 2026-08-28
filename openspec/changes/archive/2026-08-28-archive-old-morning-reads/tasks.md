## 1. Core Implementation (`app/elisp/sem-rss.el`)

- [x] 1.1 Add `sem-rss-archive-dir` defconst (`/data/archive/`) with docstring and run `sh dev/elisplint.sh app/elisp/sem-rss.el` to confirm balanced parens
- [x] 1.2 Implement private helper `sem-rss--archive-month-from-filename` returning the `YYYY-MM` prefix of a digest filename or nil for non-matching names; verify with unit assertions for valid (`2026-03-15.org`, `2026-03-15-arxiv.org`) and invalid names
- [x] 1.3 Implement `sem-rss-archive-old-digests (&optional now)` per design D2-D5: `condition-case` wrapper, current month from injected time, per-file `rename-file` into `/data/archive/YYYY-MM/`, `make-directory` on demand, `SKIP` + log for non-matching filenames, `sem-core-log` OK per move, `sem-core-log-error` on failure without aborting the batch; verify the function loads in batch Emacs without errors

## 2. Tests (`app/elisp/tests/sem-rss-test.el`)

- [x] 2.1 Add test: previous-month digest files move into their month subdirectory, current-month file stays in place, moved content is byte-identical (temp dirs via `make-temp-file`, no real `/data`)
- [x] 2.2 Add tests: idempotent second run moves nothing, and a run over an empty folder completes without error
- [x] 2.3 Add tests: archive directory and month subdirectory are created on demand, and a multi-month backlog lands in the respective `YYYY-MM` subdirectories in one run
- [x] 2.4 Add tests: filename not matching the date pattern is skipped and logged, and an injected move failure is logged to `errors.org` without signaling (use `cl-letf` on `rename-file`)
- [x] 2.5 Run the full suite with `eask test ert app/elisp/tests/sem-test-runner.el` and confirm all tests pass

## 3. Scheduling & Verification

- [x] 3.1 Add the `30 2 * * *` cron line calling `sem-rss-archive-old-digests` to the committed `crontab` and verify the file matches the schedule table in the cron-scheduling delta spec
- [x] 3.2 Simulate a month rollover end-to-end: temp-bind `sem-rss-dir`/`sem-rss-archive-dir`, create prior-month fixtures, call `sem-rss-archive-old-digests`, and assert `/data/morning-read/` holds only current-month files
- [x] 3.3 Final checks: `sh dev/elisplint.sh app/elisp/sem-rss.el` and full `eask test ert app/elisp/tests/sem-test-runner.el` pass; note in the task that the crontab change requires a container rebuild to take effect
