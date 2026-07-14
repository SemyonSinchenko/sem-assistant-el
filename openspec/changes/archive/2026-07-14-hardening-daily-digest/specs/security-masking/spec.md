## ADDED Requirements

### Requirement: URL sanitization uses literal replacement mode
The function `sem-security-sanitize-urls` SHALL pass a non-nil `literal` argument to `replace-regexp-in-string` so that the replacement text returned by the sanitization lambda is inserted verbatim. The replacement text SHALL NOT be interpreted for backslash escape sequences by `replace-match`. This ensures that backslash characters present in LLM output (e.g., LaTeX markup propagated from arXiv abstracts) do not cause "Invalid use of '\\' in replacement text" errors.

#### Scenario: Backslash in replacement text does not crash
- **WHEN** `sem-security-sanitize-urls` is called on text containing a URL adjacent to a backslash (e.g., `https://arxiv.org/abs/2406.15797][$\texttt{SynC}$`)
- **THEN** the function returns without signaling an error
- **AND** the URL portion is sanitized to `hxxps://...`

#### Scenario: Literal mode preserves replacement verbatim
- **WHEN** the sanitization lambda returns a string containing backslash sequences (e.g., `\t`, `\emph`)
- **THEN** those sequences appear unchanged in the output
- **AND** no "Invalid use of '\\' in replacement text" error is signaled

#### Scenario: Standard URLs still sanitized correctly
- **WHEN** `sem-security-sanitize-urls` is called on text with normal URLs (e.g., `See https://example.com/page`)
- **THEN** `https://` is replaced with `hxxps://`
- **AND** the rest of the text is preserved

### Requirement: URL regex stops at Org-mode link delimiters
The URL matching regex in `sem-security-sanitize-urls` SHALL stop matching at characters that are never part of a valid URL in Org-mode output: `]`, `}`, `\`, and `|`. This prevents the regex from greedily consuming LaTeX markup, org-link closing brackets, or pipe characters that follow a URL in malformed LLM output. The regex SHALL be `https?://[^ \t\n\"\]\}\\|]+`.

#### Scenario: URL followed by closing bracket stops at bracket
- **WHEN** text contains `[[https://arxiv.org/abs/2406.15797][Description]]`
- **THEN** only `https://arxiv.org/abs/2406.15797` is matched and sanitized
- **AND** the trailing `][Description]]` is preserved unchanged

#### Scenario: URL followed by backslash stops at backslash
- **WHEN** text contains `https://example.com\texttt{word}`
- **THEN** only `https://example.com` is matched and sanitized
- **AND** the `\texttt{word}` portion is preserved unchanged

#### Scenario: URL followed by closing brace stops at brace
- **WHEN** text contains `https://example.com/page}` extra text
- **THEN** only `https://example.com/page` is matched and sanitized
- **AND** the `}` and remaining text are preserved unchanged

#### Scenario: URL followed by pipe stops at pipe
- **WHEN** text contains `https://example.com|other`
- **THEN** only `https://example.com` is matched and sanitized
- **AND** `|other` is preserved unchanged

#### Scenario: Multiple URLs with delimiters all sanitized
- **WHEN** text contains `[[https://a.com][A]] and [[https://b.org][B]]`
- **THEN** both `https://a.com` and `https://b.org` are sanitized to `hxxps://a.com` and `hxxps://b.org`
- **AND** the Org-mode link structure is preserved
