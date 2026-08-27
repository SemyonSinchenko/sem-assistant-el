## 1. Fix URL sanitization in sem-security.el

- [x] 1.1 Pass `literal` non-nil to `replace-regexp-in-string` in `sem-security-sanitize-urls` (sem-security.el:189-192) so replacement text is inserted verbatim and backslash sequences are not interpreted by `replace-match`
- [x] 1.2 Tighten the URL regex from `https?://[^ \t\n\"]+` to `https?://[^ \t\n\"\]\}\\|]+` so it stops at `]`, `}`, `\`, and `|` characters that delimit Org-mode links or LaTeX markup

## 2. Harden prompt templates with anti-LaTeX rules

- [x] 2.1 Append a concise LaTeX/backslash prohibition (under 10 lines) with at least two BAD/GOOD example pairs to the CRITICAL OUTPUT RULES section of `arxiv-prompt.example.txt`, covering command stripping (`\emph{word}` → `/word/`, `$\texttt{SynC}$` → `SynC`) and URL markup stripping (`\url{...}` → `[[...][desc]]`), plus a math-notation plain-text replacement instruction
- [x] 2.2 Append the same concise LaTeX/backslash prohibition (under 10 lines) with at least two BAD/GOOD example pairs to the CRITICAL OUTPUT RULES section of `general-prompt.example.txt`

## 3. Add regression tests for backslash-containing LLM output

- [x] 3.1 Add tests to `sem-security-test.el` verifying `sem-security-sanitize-urls` does not crash on URLs adjacent to backslashes (e.g., `https://example.com\texttt{word}`), stops at Org-mode link delimiters (`]`, `}`, `\`, `|`), preserves replacement text verbatim, and still sanitizes standard URLs correctly
- [x] 3.2 Add a test to `sem-rss-test.el` verifying `sem-rss--generate-file` callback processes an LLM response containing LaTeX backslashes inside an org-link (e.g., `[[https://arxiv.org/abs/2406.15797][$\texttt{SynC}$: Title]]`) without signaling "Invalid use of '\\' in replacement text" and writes the digest file successfully

## 4. Verify

- [x] 4.1 Run `sh dev/elisplint.sh app/elisp/sem-security.el` and confirm no unmatched delimiters
- [x] 4.2 Run `eask test ert app/elisp/tests/sem-test-runner.el` and confirm all tests (including new regression tests) pass
