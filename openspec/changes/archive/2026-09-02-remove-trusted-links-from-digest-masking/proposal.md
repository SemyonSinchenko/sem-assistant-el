## Why

Digest URL masking (`sem-security-sanitize-urls` in the `sem-rss--generate-file` callback) was introduced to guard against bad links inserted by the automated summary. It now defangs every URL in RSS/ArXiv digests, including links to the subscribed sources themselves — the blog and arXiv links that are the whole point of the digest arrive as non-clickable `hxxps://` forms. The set of trusted source domains is already known from the elfeed feed configuration, so source links can be preserved while keeping the protection for anything else.

## What Changes

- Digest URL masking becomes whitelist-aware: URLs whose domain matches a trusted source domain are written verbatim (plain `http://` / `https://`), while all other URLs are still defanged (`hxxp://` / `hxxps://`).
- Trusted domains are derived from the configured elfeed feed sources (the feed URLs parsed from the feeds Org file / `elfeed-feeds`), not from a second hand-maintained list.
- Scope is digest output only. Task normalization sanitization (`sem-router.el`), url-capture output, and sensitive-block masking are unchanged.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `rss-digest`: the digest callback SHALL still sanitize LLM output, but URLs on trusted source domains (derived from the elfeed feed configuration) SHALL be preserved in plain `http://`/`https://` form; URLs on other domains SHALL remain defanged. Backslash-safety of the sanitization is unchanged.

## Impact

- Code: `app/elisp/sem-rss.el` (digest callback); likely `app/elisp/sem-security.el` (whitelist-aware sanitize variant or optional trusted-domains argument).
- Specs: delta for `openspec/specs/rss-digest/spec.md` (URL sanitization requirement and its scenarios). `security-masking` requirement on literal replacement stays valid; if the design introduces a new public sanitize API in `sem-security.el` with its own contract, a `security-masking` delta can be added at the specs stage.
- Tests: `app/elisp/tests/sem-rss-test.el` (digest tests currently assert `hxxps://` forms, including for `arxiv.org` source links), `sem-security-test.el`, `sem-url-sanitize-test.el`.
- Integration: verify no digest-related assertion in `dev/integration/run-integration-tests.sh` depends on defanged source links (the `hxxp` check at line ~1591 belongs to url-capture org-roam output and is unaffected).
