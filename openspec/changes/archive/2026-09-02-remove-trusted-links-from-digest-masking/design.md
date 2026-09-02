## Context

The digest pipeline (`sem-rss.el`) requests a summary via `sem-llm-request` and, in the
response callback, runs `sem-security-sanitize-urls` over the whole LLM response before
writing the digest file. That function defangs every `http(s)://` URL and also guarantees
literal replacement so LaTeX backslashes in LLM output cannot crash the write.

`sem-security-sanitize-urls` has exactly two callers: the digest callback and
`sem-router.el` (tasks.org output). The tasks.org caller must keep masking everything.

Trusted sources already exist as data: `sem-rss-refresh-feeds` parses the feeds Org file
(`/data/feeds.org`) and loads the result into `elfeed-feeds`. Feed entries are either URL
strings or `(URL . tags)` lists. See proposal.md for motivation and the specs delta for
the required behavior.

## Goals / Non-Goals

**Goals:**
- Digest output keeps links to trusted source hosts in plain `https://` form (clickable).
- The trusted set is derived automatically from the elfeed feed sources (zero extra config).
- Untrusted URLs keep being defanged; backslash-safety of sanitization is unchanged.
- Mask-all behavior stays the default wherever a trusted set is not provided.

**Non-Goals:**
- No change to tasks.org sanitization (`sem-router.el`), url-capture output, or sensitive-block masking.
- No per-feed manual domain overrides in the feeds Org file.
- No Public Suffix List dependency or exact registrable-domain computation.

## Decisions

### 1. Whitelist-aware masking lives in `sem-security-sanitize-urls` via an optional argument

Add an optional `trusted-hosts` argument (default nil). With nil, behavior is byte-identical
to today (mask everything), so `sem-router.el` and all existing callers are unaffected. The
per-match lambda keeps the URL when its host is trusted, otherwise defangs it.

*Why not a separate function?* Two sanitize entry points would drift (the literal-replacement
and regex contracts are specified in `security-masking`). *Why not filter in `sem-rss.el`?*
It would re-implement the URL regex and the backslash-safe replacement locally.

### 2. Matching rule: host equality plus base-domain (last two labels) equality

A URL is trusted when its host equals a trusted source host, or when the last two labels of
its host equal the last two labels of a trusted source host (case-insensitive, host component
only). Rationale: arXiv feeds are hosted at `rss.arxiv.org` / `export.arxiv.org` while paper
links point at `arxiv.org` — exact-host matching would defang every paper link and defeat the
feature. Base-domain matching covers that case without config.

*Alternatives considered:* exact host only (breaks arXiv); Public Suffix List suffix matching
(no PSL dependency wanted in the daemon); hand-maintained overrides (rejected by the proposal).

### 3. Trusted hosts are derived from `elfeed-feeds` at digest time

A small helper in `sem-rss.el` maps `elfeed-feeds` entries (strings or `(URL . tags)` lists)
through the shared host-extraction helper, and returns the distinct set of feed hosts plus
their base domains. It is computed per digest generation and passed to the sanitize call.
Empty/missing `elfeed-feeds` yields an empty set, and empty set means mask-all: fail-safe to
current behavior.

*Why not re-parse `/data/feeds.org`?* `sem-rss-refresh-feeds` already owns feed loading and
caching; `elfeed-feeds` is the refreshed source of truth.

### 4. Plumbing through the digest callback

The trusted host set is computed when the digest request is built, stored in the callback
context plist, and handed to `sem-security-sanitize-urls` in the success branch. The count of
trusted hosts is logged once per digest run via `sem-core-log` for operator visibility.

## Risks / Trade-offs

- [Hallucinated path on a trusted domain passes unmasked] → Accepted: host-level trust is the
  agreed trade-off; links to wrong domains are still defanged, which covers the realistic
  hallucination case.
- [Base-domain rule widens trust across free-host domains (e.g. any `*.github.io`)] →
  Acceptable for a single-user threat model; if it ever matters, an exact-host mode can be
  added without spec changes to the digest contract.
- [Last-two-labels heuristic mis-scopes multi-part suffixes (e.g. `example.co.uk`)] →
  Documented limitation; current feeds use `arxiv.org` / `github.io` style hosts.
- [Feed host differs from article host (link shorteners, canonical domains)] → Such article
  links stay masked; revisit with a manual override only if a real feed hits this.

## Migration Plan

No data or config migration. Deploy = restart the daemon (reloads feeds on the next elfeed
update). Rollback = revert the change; callers without the new argument behave exactly as
before (mask-all).
