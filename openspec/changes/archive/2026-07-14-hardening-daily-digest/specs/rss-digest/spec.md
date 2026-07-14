## ADDED Requirements

### Requirement: RSS digest callback processes backslash-containing LLM output without crashing
The `sem-rss--generate-file` callback SHALL process LLM responses containing backslash characters (e.g., LaTeX markup from arXiv paper titles) without signaling an error. The callback SHALL call `sem-security-sanitize-urls` on the raw LLM response, and the sanitization SHALL complete without raising "Invalid use of '\\' in replacement text". The digest file SHALL be written successfully when the LLM response is non-empty, regardless of whether the response contains backslashes.

#### Scenario: LaTeX in org-link description does not crash digest
- **WHEN** the LLM returns a response containing an org-link with LaTeX in the description (e.g., `[[https://arxiv.org/abs/2406.15797][$\texttt{SynC}$: Synergistic Boosting]]`)
- **THEN** `sem-rss--generate-file` callback processes the response without signaling an error
- **AND** the digest file is written to the target path
- **AND** the file contains the sanitized content

#### Scenario: Backslash escape in replacement text does not crash
- **WHEN** the LLM returns a response containing a URL immediately followed by backslash sequences (e.g., `https://example.com\texttt{word}`)
- **THEN** the callback completes without raising "Invalid use of '\\' in replacement text"
- **AND** the digest file is written successfully

#### Scenario: Normal response still processed correctly
- **WHEN** the LLM returns a normal Org-mode response without backslashes
- **THEN** the callback processes the response as before
- **AND** the digest file is written with sanitized URLs
