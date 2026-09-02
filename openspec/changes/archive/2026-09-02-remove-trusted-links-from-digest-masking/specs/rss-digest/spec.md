## MODIFIED Requirements

### Requirement: RSS digest callback processes backslash-containing LLM output without crashing
The `sem-rss--generate-file` callback SHALL process LLM responses containing backslash characters (e.g., LaTeX markup from arXiv paper titles) without signaling an error. The callback SHALL apply whitelist-aware URL sanitization to the raw LLM response: URLs whose host matches a trusted source domain are preserved verbatim, all other URLs are defanged (`http://` becomes `hxxp://`, `https://` becomes `hxxps://`). The sanitization SHALL complete without raising "Invalid use of '\\' in replacement text". The digest file SHALL be written successfully when the LLM response is non-empty, regardless of whether the response contains backslashes.

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
- **AND** the digest file is written with URLs sanitized according to the trusted source whitelist

## ADDED Requirements

### Requirement: Digest preserves trusted source URLs
The system SHALL derive trusted source hosts from the configured elfeed feed sources (the feed URLs loaded from the feeds Org file); no second hand-maintained list of trusted hosts SHALL be required. When writing a digest file, the system SHALL preserve URLs whose host matches a trusted source host in their plain `http://`/`https://` form, and SHALL defang all other URLs (`http://` becomes `hxxp://`, `https://` becomes `hxxps://`). A URL SHALL be treated as trusted when its host equals a trusted source host, or when the base domain of its host (the last two labels of the host) equals the base domain of a trusted source host. Host comparison SHALL be case-insensitive and SHALL consider only the host component of the URL, ignoring scheme, port, path, and query. If no trusted source hosts are available, the system SHALL defang all URLs.

#### Scenario: Trusted source URL is preserved
- **WHEN** the configured feeds include a feed at `https://arxiv.org/rss/cs.LG`
- **AND** the LLM response contains a link to `https://arxiv.org/abs/2406.15797`
- **THEN** the digest file contains `https://arxiv.org/abs/2406.15797` unchanged

#### Scenario: Link host shares base domain with feed host
- **WHEN** the configured feeds include a feed at `https://rss.arxiv.org/rss/cs.DB`
- **AND** the LLM response contains a link to `https://arxiv.org/abs/2406.15797`
- **THEN** the digest file contains `https://arxiv.org/abs/2406.15797` unchanged

#### Scenario: Untrusted URL is still defanged
- **WHEN** the LLM response contains a URL whose host does not match any trusted source host or trusted base domain
- **THEN** the digest file contains the URL in defanged form (`hxxp://` or `hxxps://`)

#### Scenario: Trusted hosts derived from elfeed feed sources
- **WHEN** the feeds Org file defines feed URLs for multiple hosts
- **THEN** each distinct feed URL host, and the base domain of each feed URL host, is treated as trusted
- **AND** no hand-maintained second list of trusted hosts is required

#### Scenario: Host match ignores scheme and path
- **WHEN** a feed is configured at `http://example.org/feed.xml`
- **AND** the LLM response contains `https://example.org/post/1`
- **THEN** the digest file contains `https://example.org/post/1` unchanged

#### Scenario: No trusted hosts available
- **WHEN** no feed sources are configured or loaded
- **AND** the LLM response contains URLs
- **THEN** all URLs in the digest file are defanged
