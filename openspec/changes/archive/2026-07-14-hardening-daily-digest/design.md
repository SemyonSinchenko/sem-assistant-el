## Context

The daily arXiv/RSS digest pipeline (`sem-rss.el`) intermittently fails with
the error **"Callback error: Invalid use of '\\' in replacement text"**,
occurring roughly once every two weeks. Three error log entries (2026-05-19,
2026-06-11, 2026-07-01) were captured in the proposal, each containing the
full LLM input and output.

**Root cause chain:**

1. arXiv paper abstracts in the LLM input contain LaTeX markup
   (`\texttt{...}`, `\emph{...}`, `\url{...}`, `$...$`).
2. The LLM sometimes propagates this LaTeX into its Org-mode output —
   particularly inside org-link descriptions, e.g.
   `[[https://arxiv.org/abs/2406.15797][$\texttt{SynC}$: ...]]`.
3. The RSS callback (`sem-rss--generate-file`, sem-rss.el:435) calls
   `sem-security-sanitize-urls` on the raw LLM response.
4. `sem-security-sanitize-urls` (sem-security.el:184-192) uses
   `replace-regexp-in-string` with the regex `https?://[^ \t\n\"]+` and a
   lambda. The character class `[^ \t\n\"]+` matches everything except
   spaces, tabs, newlines, and double-quotes — so it greedily consumes
   adjacent `]`, `[`, `$`, `\`, `{`, `}` characters from the LaTeX.
5. The lambda returns a sanitized string (e.g.
   `hxxps://arxiv.org/abs/2406.15797][$\texttt{SynC}$:`) that still
   contains backslashes.
6. `replace-regexp-in-string` passes the lambda's return value to
   `replace-match` as the replacement string. Since the `literal` argument
   is nil (not passed), `replace-match` interprets backslash sequences.
   When it encounters `\t` (not a valid escape — only `\0`-`\9`, `\&`, `\\`
   are valid), it signals "Invalid use of '\\' in replacement text".
7. The error is caught by the `condition-case` in `sem-llm.el:88` and
   logged as a callback error, causing the digest to fail for that day.

**Current state of prompts:**
- `arxiv-prompt.example.txt` and `general-prompt.example.txt` contain
  "CRITICAL OUTPUT RULES" (raw Org-mode only, no markdown) but say nothing
  about LaTeX or backslash characters.
- Prompt files are stored at `/data/prompts/*.txt` (Docker volume), not in
  the repository. The `.example.txt` files are the version-controlled
  templates.
- The system prompt in `sem-rss--generate-file` (sem-rss.el:416) adds
  "Never use markdown code fences" but does not mention LaTeX.

**Stakeholders:** The operator relies on daily digests for research
monitoring. Each failure means a missing digest for that day.

## Goals / Non-Goals

**Goals:**
- Eliminate the "Invalid use of '\\' in replacement text" error by addressing
  both the prompt (prevent LaTeX in LLM output) and the code (make URL
  sanitization backslash-safe).
- Harden `arxiv-prompt.example.txt` and `general-prompt.example.txt` with
  concise, targeted anti-LaTeX instructions and a small number of examples.
- Add a code-level defense in `sem-security-sanitize-urls` so that even if
  the LLM emits backslashes, the daemon does not crash.
- Add regression tests covering backslash-containing LLM output.

**Non-Goals:**
- Rewriting the URL sanitization regex from scratch (minimal change only).
- Changing the LLM model or provider.
- Modifying the input data pipeline (arXiv abstracts will always contain
  LaTeX — we handle it on the output side).
- Adding LaTeX-to-Org conversion (the LLM should simply omit LaTeX).
- Updating `sem-prompts.el` constants (those are for the router/task
  pipeline, not for RSS digest prompts).

## Decisions

### D1: Fix `sem-security-sanitize-urls` to use `literal` non-nil

**Decision:** Pass `t` for the `literal` argument in the
`replace-regexp-in-string` call inside `sem-security-sanitize-urls`.

```elisp
;; Before
(replace-regexp-in-string
 "https?://[^ \t\n\"]+"
 (lambda (match) (sem-security--sanitize-url match))
 text)

;; After
(replace-regexp-in-string
 "https?://[^ \t\n\"]+"
 (lambda (match) (sem-security--sanitize-url match))
 text nil t)  ; fixedcase=nil, literal=t
```

**Rationale:** The lambda already returns the exact replacement text. There
is no reason for `replace-match` to interpret backslash sequences in it.
Setting `literal` to `t` makes the replacement pass through verbatim,
eliminating the crash regardless of what characters the LLM emits.

**Alternatives considered:**
- *Tighten the regex* (e.g., stop at `]`, `}`, `|`, `\\`): Reduces over-match
  but is fragile — there are many characters that could appear adjacent to
  a URL in malformed output. The `literal` fix is more robust.
- *Escape backslashes in the lambda return*: Would require
  `(replace-regexp-in-string "\\\\" "\\\\\\\\" result)` before returning —
  error-prone and indirect.

### D2: Tighten the URL regex as a secondary defense

**Decision:** Also narrow the regex to stop at common delimiters that should
never be part of a URL in Org-mode output:

```elisp
;; Before
"https?://[^ \t\n\"]+"

;; After
"https?://[^ \t\n\"\]\}\\|]+"
```

**Rationale:** In well-formed Org-mode, URLs inside `[[url][desc]]` links are
terminated by `]`. Backslashes, braces, and pipes are never part of valid
URLs in this context. This prevents the regex from consuming LaTeX that
follows a URL, even if the `literal` fix is somehow bypassed.

**Alternatives considered:**
- *Only fix the regex, not `literal`*: Insufficient — other characters could
  still cause issues. Both fixes together provide defense-in-depth.

### D3: Harden prompt templates with anti-LaTeX rules

**Decision:** Add a concise "LaTeX / Backslash Prohibition" section to both
`arxiv-prompt.example.txt` and `general-prompt.example.txt`. Keep it short
(5-8 lines) with 2-3 concrete examples. Do NOT paste the 1000-line error
log into the prompt.

**Proposed addition** (appended to the CRITICAL OUTPUT RULES section):

```
- NEVER use LaTeX commands or backslash escapes in output.
  BAD: $\texttt{SynC}$ → GOOD: SynC
  BAD: \emph{word} → GOOD: /word/
  BAD: \url{https://...} → GOOD: [[https://...][description]]
- Strip ALL LaTeX markup from paper titles. Use plain text only.
- If a title contains math notation (e.g., $O(n \log n)$), replace with
  plain-text approximation: O(n log n).
```

**Rationale:** The LLM needs explicit, concrete guidance. Abstract
instructions like "output raw Org-mode" are insufficient — the LLM does not
realize that LaTeX inside Org-mode is problematic. Short examples are more
effective than long explanations.

**Alternatives considered:**
- *Add a system prompt constant in `sem-prompts.el`*: The RSS digest prompts
  are loaded from external files (`/data/prompts/*.txt`), not from
  `sem-prompts.el` constants. Adding to `sem-prompts.el` would not affect
  the RSS pipeline.
- *Post-process LLM output to strip LaTeX*: Adds complexity and could
  damage valid content. Better to prevent at the source (prompt) and
  survive at the code level (D1/D2).

### D4: Add regression tests for backslash-containing output

**Decision:** Add tests to `sem-security-test.el` and `sem-rss-test.el`:

1. **`sem-security-test.el`**: Test that `sem-security-sanitize-urls`
   handles strings with backslashes without error.
2. **`sem-rss-test.el`**: Test that `sem-rss--generate-file` callback
   processes an LLM response containing LaTeX backslashes without crashing
   and writes the file successfully.

**Rationale:** The current test suite has no coverage for backslash-in-URL
scenarios. These tests directly reproduce the production error and verify
the fix.

## Risks / Trade-offs

- **[Prompt bloat]** Adding anti-LaTeX rules increases prompt token count.
  → Mitigation: Keep the addition under 10 lines. The rules are high-value
  (prevent crashes) relative to their token cost (~50 tokens).

- **[Regex narrowing breaks edge case]** Narrowing the URL regex (D2) could
  theoretically fail to match a valid URL that contains `]` or `}` (e.g.,
  query parameters with encoded brackets). → Mitigation: In Org-mode link
  syntax `[[url][desc]]`, the URL is always terminated by `]`. URLs with
  literal `]` should be percent-encoded anyway. The existing tests verify
  common URL patterns still match.

- **[LLM still emits LaTeX despite prompt]** The prompt fix may not
  eliminate 100% of LaTeX occurrences — LLMs are probabilistic.
  → Mitigation: The code-level fix (D1+D2) ensures the daemon never crashes
  even if LaTeX slips through. The prompt fix reduces frequency; the code
  fix guarantees survival.

- **[Example files vs deployed prompts]** The `.example.txt` files are
  version-controlled templates. The actual deployed prompts live in the
  Docker volume at `/data/prompts/*.txt`. The operator must manually update
  the deployed files after the example files change. → Mitigation: Document
  this in the change tasks. The example files are the source of truth.

- **[No migration needed]** This change does not alter data formats, file
  layouts, or APIs. No migration plan or rollback strategy is required.
  Rollback is simply reverting the prompt and code changes.
