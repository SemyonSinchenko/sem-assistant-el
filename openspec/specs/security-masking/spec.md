## Purpose

This capability defines the security masking system that protects sensitive content from being exposed to the LLM API and sanitizes URLs in appropriate outputs.

## Requirements

### Requirement: Sensitive blocks replaced with tokens before LLM call
The system SHALL parse sensitive delimiters before any LLM request and SHALL fail closed when delimiter structure is malformed. Delimiter matching SHALL be case-insensitive (`#+begin_sensitive` and `#+BEGIN_SENSITIVE` are both valid) but delimiters MUST appear on standalone lines. The parser SHALL reject malformed forms including missing end marker, end marker without begin marker, nested begin markers, and inline markers embedded in non-delimiter text. On malformed input, sanitization SHALL raise an error and SHALL NOT return tokenized content for LLM transmission. For valid delimiters, the system SHALL replace all `#+begin_sensitive` / `#+end_sensitive` blocks with opaque tokens before any content is sent to the LLM API. The original text SHALL be stored in a token map for restoration. The function `sem-security-sanitize-for-llm` SHALL return a three-element list: `(tokenized-text blocks-alist position-info-alist)`. The function SHALL be called in `sem-url-capture-process` on the sanitized article text before passing it to `sem-llm-request`. The returned `blocks-alist` SHALL be stored in the context plist under `:security-blocks`.

#### Scenario: Sensitive content tokenized
- **WHEN** content contains `#+begin_sensitive...#+end_sensitive` blocks
- **THEN** the sensitive content is replaced with `<<SENSITIVE_xxx>>` tokens

#### Scenario: Case-insensitive standalone delimiters are accepted
- **WHEN** content contains uppercase or mixed-case standalone sensitive delimiters
- **THEN** sensitive blocks are tokenized successfully

#### Scenario: Inline begin marker is rejected
- **WHEN** content contains `#+begin_sensitive` not on its own line
- **THEN** sanitization fails before any LLM request

#### Scenario: Missing end marker is rejected
- **WHEN** content contains a begin marker without a matching end marker
- **THEN** sanitization fails before any LLM request

#### Scenario: End marker without begin is rejected
- **WHEN** content contains an end marker that is not inside an open sensitive block
- **THEN** sanitization fails before any LLM request

#### Scenario: Nested begin marker is rejected
- **WHEN** content opens a second sensitive block before closing the first
- **THEN** sanitization fails before any LLM request

#### Scenario: Original content preserved in token map
- **WHEN** content is tokenized
- **THEN** the original sensitive text is stored in a map keyed by token

#### Scenario: Sensitive content tokenized in url-capture
- **WHEN** `sem-url-capture-process` processes content with `#+begin_sensitive...#+end_sensitive` blocks
- **THEN** `sem-security-sanitize-for-llm` is called before `sem-llm-request`

#### Scenario: Security blocks stored in context
- **WHEN** content is tokenized for url-capture
- **THEN** the blocks alist is stored in the context plist under `:security-blocks`

#### Scenario: Sanitize returns three-element list
- **WHEN** `sem-security-sanitize-for-llm` is called
- **THEN** it returns a list of three elements: `(tokenized-text blocks-alist position-info-alist)`
- **AND** `tokenized-text` is the body with sensitive content replaced by tokens
- **AND** `blocks-alist` maps tokens to original content
- **AND** `position-info-alist` maps tokens to `(before-context . after-context)` pairs

#### Scenario: Position info captured for each block
- **WHEN** content contains multiple sensitive blocks
- **THEN** each block contributes an entry to position-info-alist
- **AND** each entry contains up to 20 chars of surrounding context

### Requirement: Tokens restored in output before writing
The system SHALL restore original sensitive content from the token map after receiving LLM output and before writing to disk. The detokenization SHALL use the same token map from the input phase. For `sem-url-capture-process`, `sem-security-restore-from-llm` SHALL be called on the raw LLM response string, using the `:security-blocks` from context, before passing the result to `sem-url-capture--validate-and-save`.

Sensitive content SHALL be restored as plain text without any block markers. Multi-line content SHALL be indented by 2 spaces per line with a leading newline before content and trailing newline after content. One-line content SHALL be placed at the token position verbatim. After successful restoration and write, the blocks-alist SHALL be cleared to avoid stale data.

#### Scenario: Tokens restored as plain text after LLM response
- **WHEN** LLM output contains `{{SEC_ID_xxx}}` or `<<SENSITIVE_xxx>>` tokens
- **THEN** tokens are replaced with original sensitive content as plain text
- **AND** no `#begin_sensitive` / `#end_sensitive` markers are present in output

#### Scenario: Multi-line content indented correctly
- **WHEN** original sensitive content spans multiple lines
- **THEN** each line is indented by 2 spaces
- **AND** a leading newline precedes the content
- **AND** a trailing newline follows the content

#### Scenario: Single-line content placed verbatim at token position
- **WHEN** original sensitive content is a single line
- **THEN** the content is placed at the token position without indentation or surrounding newlines

#### Scenario: Round-trip preserves original text
- **WHEN** content is tokenized, sent to LLM, and detokenized
- **THEN** the original sensitive text appears unchanged in the output

#### Scenario: restore-from-llm called before validate-and-save in url-capture
- **WHEN** `sem-url-capture-process` receives LLM response
- **THEN** `sem-security-restore-from-llm` is called before `sem-url-capture--validate-and-save`
- **AND** the `blocks` argument is `(plist-get context :security-blocks)`

#### Scenario: blocks-alist cleared after successful write
- **WHEN** sensitive content is restored and written to disk
- **THEN** the blocks-alist is cleared to avoid stale data

### Requirement: No sensitive content reaches LLM API
The system SHALL ensure sensitive plaintext never reaches the LLM API. This guarantee SHALL be enforced by preflight-sensitive parsing and tokenization only; malformed delimiter inputs SHALL be rejected as terminal failures before any LLM call is attempted.

#### Scenario: Tokenized content sent to LLM
- **WHEN** content with sensitive blocks is prepared for LLM
- **THEN** only tokens (not original sensitive text) are in the request

#### Scenario: Malformed delimiter prevents LLM call
- **WHEN** preflight-sensitive parsing detects malformed delimiters
- **THEN** no LLM request is issued

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

## REMOVED Requirements

### Requirement: URL sanitization for url-capture output
**Reason**: URL sanitization is NOT applied to url-capture output (org-roam). org-roam requires real URLs for link resolution and backlink functionality. URL sanitization is only applied to tasks.org and morning-read outputs.

**Migration**: This requirement is removed. URL sanitization for org-roam (url-capture) output is explicitly excluded.

### Requirement: Local variable blocks disabled
**Reason**: This security requirement is handled by Emacs configuration at the daemon level, not within this capability.

**Migration**: This requirement is removed from security-masking spec.

### Requirement: org-babel evaluation disabled
**Reason**: This security requirement is handled by Emacs configuration at the daemon level, not within this capability.

**Migration**: This requirement is removed from security-masking spec.
