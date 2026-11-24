# AGENTS.md — SEM Assistant Elisp Daemon

Guidance for agentic coding agents operating in this repository.

---

## Project Overview

A self-hosted Emacs daemon (Docker) that autonomously processes Org inbox notes
and RSS feeds via LLM (DeepSeek by default, OpenRouter as legacy; via gptel). All logic is written in Emacs Lisp.
Source lives in `app/elisp/`. Tests live in `app/elisp/tests/`.

---

## Commands

### Run all tests

```sh
eask test ert app/elisp/tests/sem-test-runner.el
```

### Run a single test file

```sh
eask emacs --batch \
  --load app/elisp/tests/sem-mock.el \
  --load app/elisp/tests/sem-core-test.el \
  --eval "(ert-run-tests-batch-and-exit)"
```

Replace `sem-core-test.el` with the file under test. Always load
`sem-mock.el` first so behavioral mocks are available.

### Run a single named test

```sh
eask emacs --batch \
  --load app/elisp/tests/sem-mock.el \
  --load app/elisp/tests/sem-core-test.el \
  --eval "(ert-run-tests-batch-and-exit 'sem-core-test-cursor-roundtrip)"
```

### Check unmatched parentheses / brackets

```sh
sh dev/elisplint.sh app/elisp/sem-core.el
```

Pass multiple files at once:

```sh
sh dev/elisplint.sh app/elisp/sem-core.el app/elisp/sem-router.el
```

The linter uses `scan-sexps` via Emacs batch mode and reports the line of the
first unmatched delimiter. Run this before committing any elisp change.

### Start the daemon (Docker)

```sh
docker-compose up -d
docker-compose logs -f emacs
```

---

## Repository Layout

```
Eask                    Dependency manifest for Emacs packages
app/elisp/              Source modules (load order matters — see init.el)
  init.el               Daemon startup sequence
  sem-core.el           Logging, cursor tracking, retry, inbox purge
  sem-security.el       Sensitive-block masking, URL sanitization
  sem-llm.el            gptel wrapper (all LLM calls go here)
  sem-prompts.el        Prompt templates and cheat-sheets
  sem-router.el         Inbox parsing and routing
  sem-url-capture.el    URL → org-roam pipeline
  sem-rss.el            RSS/arXiv digest generation
  sem-planner.el        Pass 2 scheduling of new tasks
  sem-daily-plan.el     Morning day plan (/data/tasks/daily-plan.org)
  sem-migrate.el        One-time migration to the /data/tasks + org-roam split
  sem-orgnote.el        orgnote-cli sync of /data/org-roam (+ read-only task copies)
  sem-git-sync.el       Automated org-roam → GitHub sync
  tests/                ERT test suite
    sem-mock.el         Shared mock helpers (load first)
    sem-test-runner.el  Full suite runner
dev/
  elisplint.sh          Parenthesis linter
```

---

## Elisp Code Style

### File Header

Every source file must start with:

```elisp
;;; filename.el --- Short description -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; One or two paragraphs describing the module.

;;; Code:
```

And end with:

```elisp
(provide 'module-name)
;;; filename.el ends here
```

### Lexical Binding

All files use `lexical-binding: t` in the file-local variables line. Never omit
this. Dynamic binding bugs are subtle and hard to trace.

### Requires / Imports

- `require` statements appear at the top of `;;; Code:`, one per line.
- Modules required only inside specific functions use `(require 'foo)` locally
  (lazy loading pattern used in `sem-router.el` and `sem-core.el`).
- Do not use `load` or `load-file` in source modules — only in test runners.

### Naming Conventions

| Pattern | Example | Usage |
|---|---|---|
| `module-name-public-fn` | `sem-core-log` | Public API, callable from other modules |
| `module-name--private-fn` | `sem-core--read-cursor` | Private, internal only |
| `module-name-constant` | `sem-core-log-file` | `defconst`, module-level constant |
| `module-name--var` | `sem-router--tasks-write-lock` | `defvar`, mutable state |

- Use `defconst` for values that never change at runtime.
- Use `defvar` for mutable module-level state; always provide a docstring.
- Function names are lowercase, hyphen-separated. No camelCase.

### Formatting

- 2-space indentation for body forms inside `let`, `progn`, `when`, `cond`, etc.
- Closing parentheses are never on their own line (Lisp style, not Allman).
- `let*` is preferred over nested `let` when bindings are sequential.
- Keep lines under ~100 characters. Long strings (prompts) may exceed this.
- Leave one blank line between top-level forms. Use section comments (`;;; Section`).

### Docstrings

- All `defun`, `defvar`, `defconst` must have docstrings.
- First line is a complete sentence ending with a period.
- Document all parameters by name in ALL-CAPS (Emacs convention).
- For callbacks, document the callback signature inline (see `sem-router.el`).

### Types and Data

- Plists are used for headline data: `(list :title "..." :tags '("task") :hash "...")`.
- Alists are used for cursor/retry tracking: `'(("hash" . t))`.
- Prefer `plist-get` / `plist-put` over positional list access.
- Use `cl-lib` functions (`cl-block`, `cl-return-from`, `cl-remove-if-not`,
  `cl-letf`, etc.) — `cl-lib` is always required in source files.

---

## Error Handling

### The golden rule: never let the daemon crash

- Every public entry point and every cron-callable function must be wrapped in
  `(condition-case err ... (error ...))`.
- Logging functions themselves are wrapped in `(ignore-errors ...)` or
  `(condition-case _err ... (t nil))` — they must never propagate errors.
- Catch errors at the outermost layer; log with `sem-core-log-error`, then
  continue. Do not re-signal.

### Error logging

Use `sem-core-log` for informational events:

```elisp
(sem-core-log "router" "INBOX-ITEM" "OK" "Task written to tasks.org")
(sem-core-log "router" "INBOX-ITEM" "SKIP" (format "Already processed: %s" title))
(sem-core-log "router" "INBOX-ITEM" "RETRY" "LLM API error")
```

Use `sem-core-log-error` for failures (also writes to `errors.org`):

```elisp
(sem-core-log-error "router" "INBOX-ITEM" error-message input-text raw-llm-output)
```

Valid MODULE values: `core`, `router`, `rss`, `url-capture`, `security`, `llm`,
`elfeed`, `purge`, `init`, `git-sync`, `planner`, `orgnote`.

Valid STATUS values: `OK`, `RETRY`, `DLQ`, `SKIP`, `FAIL`.

---

## `cl-block` / `cl-return-from` — Important Caveat

This codebase uses `cl-block` + `cl-return-from` for early exit from named
blocks. Agents frequently introduce bugs here, so read carefully.

**Correct pattern:**

```elisp
(defun sem-router-process-inbox ()
  (cl-block sem-router-process-inbox     ; block name is a symbol
    (unless (file-exists-p inbox-file)
      (cl-return-from sem-router-process-inbox nil))  ; same symbol
    ...rest of function...))
```

**Rules:**
1. The `cl-block` name and `cl-return-from` name must be **identical symbols**.
2. `cl-return-from` only works inside the lexically enclosing `cl-block` with
   that exact name. It does **not** work across function call boundaries.
3. Do not use `cl-return-from` without a matching `cl-block`. This signals a
   `no-catch` error at runtime.
4. Inside a `dolist` or `cl-loop`, use `cl-return` (no name) to exit the loop,
   or `cl-return-from outer-block` to exit an enclosing named block.
5. `cl-return-from` is **not** a general early-return from `defun`. You need the
   surrounding `cl-block`. Alternatively, restructure with `when`/`unless`/`cond`.

**Common agent mistake — do NOT do this:**

```elisp
;; WRONG: cl-return-from with no enclosing cl-block
(defun my-fn ()
  (when bad-condition
    (cl-return-from my-fn nil))   ; ERROR at runtime
  ...)
```

---

## Writing Tests

### Framework

Tests use ERT (Emacs' built-in test framework). No external test library needed.

### File structure

```elisp
;;; sem-foo-test.el --- Tests for sem-foo.el -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Tests for <what this file tests>.

;;; Code:

(require 'ert)
(require 'sem-mock)

;; Load source under test
(load-file (expand-file-name "../sem-foo.el" (file-name-directory load-file-name)))

;;; Tests

(ert-deftest sem-foo-test-something ()
  "Test that something works as expected."
  ...)

(provide 'sem-foo-test)
;;; sem-foo-test.el ends here
```

### Test naming

`<module>-test-<what-is-tested>` — e.g., `sem-core-test-cursor-roundtrip`.

### Using mocks

Always use `sem-mock.el` helpers. Never make real network calls or touch real
filesystem paths in tests.

```elisp
;; Mock gptel (LLM)
(sem-mock-gptel-request-success "LLM response text")
;; ... test code ...
(sem-mock-gptel-reset)

;; Mock trafilatura CLI
(sem-mock-trafilatura-success "extracted article text")
;; ... test code ...
(sem-mock-trafilatura-reset)
```

Use `cl-letf` to override arbitrary functions inline:

```elisp
(cl-letf (((symbol-function 'write-region) (lambda (&rest _) nil))
          ((symbol-function 'make-directory) (lambda (&rest _) nil)))
  ...body...)
```

### Temp files

Use `sem-mock-temp-file` to create temp files with content, and always clean up:

```elisp
(let ((tmp (sem-mock-temp-file "* Heading :tag:\n")))
  (unwind-protect
      (let ((sem-core-log-file tmp))
        ... test ...)
    (sem-mock-cleanup-temp-file tmp)))
```

### Assertions

```elisp
(should EXPR)          ; passes if EXPR is non-nil
(should-not EXPR)      ; passes if EXPR is nil
(should (string= ...)) ; string equality
(should (equal ...))   ; structural equality
```

### Registering new test files

No manual registration is required for full-suite runs via
`eask test ert app/elisp/tests/sem-test-runner.el`.
If you use `app/elisp/tests/sem-test-runner.el`, test files ending in
`-test.el` are auto-discovered.

---

## Emacs-Lisp Best Practices

- **Prefer `with-temp-buffer`** for all buffer manipulation. Never use
  `find-file` or `get-buffer-create` in daemon code — side effects persist.
- **Atomic file writes:** Write to a `.tmp` file first, then `rename-file` to
  the target. This prevents partial writes visible to concurrent readers.
- **`write-region` with `'silent`:** Use `(write-region ... nil 'silent)` to
  suppress "Wrote file" messages that would pollute `*Messages*`.
- **`condition-case` vs `ignore-errors`:** Use `condition-case` when you need
  the error object for logging. Use `ignore-errors` only for truly disposable
  errors (e.g., inside logging itself).
- **`unwind-protect` for cleanup:** Any lock acquisition, temp buffer creation,
  or resource allocation must use `unwind-protect` to guarantee release.
- **`string-empty-p` not `(= (length s) 0)`:** Use `string-empty-p` or
  `(zerop (length s))` — more readable and nil-safe when combined with `or`.
- **`secure-hash` for content hashing:** Use `(secure-hash 'sha256 str)` for
  deterministic content fingerprints. The hash format for inbox headlines is
  `title|space-joined-tags|body` — do not change this without updating
  `sem-core-purge-inbox` and `sem-router--parse-headlines` together.
- **No `interactive` in daemon code:** All functions are called programmatically.
  Never add `(interactive)` to daemon functions.
- **Read env vars at call time, not load time:** Use `(getenv "VAR")` inside
  functions, not in `defconst` initialisers, except for config constants that
  read env at module load (see `sem-rss.el` pattern with `when-let`).
- **`message` for runtime diagnostics:** Use `(message "SEM: ...")` for
  operator-visible output. These appear in `*Messages*` and are persisted to
  daily log files via `sem-core--flush-messages-daily`.

---

## Integration Tests — DO NOT RUN

**Agents must never execute the integration test suite.**

The integration test suite (`dev/integration/run-integration-tests.sh`) makes **real LLM API calls**
via OpenRouter that **cost money**. It is designed to be run **only by human operators** who
explicitly intend to incur these costs.

**What agents must not do:**
- Execute `dev/integration/run-integration-tests.sh`
- Run `podman-compose` commands referencing `docker-compose.test.yml`
- Modify or delete integration test artifacts in `test-results/` or `test-data/`

**What agents may do:**
- Read integration test files for context
- Suggest improvements to integration test code
- Update integration test documentation

**IMPORTANT: When adding a new test task to the integration test inbox** (`dev/integration/testing-resources/inbox-tasks.org`), the `EXPECTED_TASK_COUNT` is derived **automatically** from the inbox file at script runtime (via `grep -c '^\* TODO .*:task:'`). No manual update is needed for the count itself.

However, if you add new keyword assertions (Assertion 2) or change the number of sensitive content checks (Assertion 4), you **must** update the corresponding hardcoded arrays/constants in `run-integration-tests.sh` and in `openspec/specs/assertions/spec.md`.

If a human operator asks you to run the integration tests, clarify that you cannot do so and
suggest they run it manually with:

```sh
bash dev/integration/run-integration-tests.sh
```
