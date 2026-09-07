## Why

The operator follows AI-consciousness content via feeds tagged `consciousness` in
`/data/feeds.org`, but the general morning digest has no dedicated category for
this topic, so relevant entries get scattered across content-based categories or
drowned out by the rest of the feed volume. A dedicated, compact section makes
this topic scannable at a glance each morning.

## What Changes

- Add a new "AI Consciousness" category to the general morning digest (the daily
  `YYYY-MM-DD.org` file), driven by the `consciousness` tag on feeds in
  `/data/feeds.org`.
- The category is written in Russian, matching the existing general digest
  prompt (`Language: Russian` stays in effect for the whole digest).
- Unlike other categories, it contains up to 10 entries presented as
  «Топ-10 категории» instead of the standard unlimited listing plus a
  «Топ-3 категории» subsection.
- Entries from `consciousness`-tagged feeds are exclusive to the new category:
  they do not appear in any other general-digest category.
- The category follows the current general-prompt conventions otherwise:
  Org-mode structure, CRITICAL OUTPUT RULES, and the existing LaTeX/backslash
  prohibition rules carry over unchanged.
- No new digest file, cron entry, or LLM call pattern is introduced; the
  category lives inside the existing general digest generation flow. The arXiv
  digest is unchanged.

## Capabilities

### New Capabilities

<!-- None. -->

### Modified Capabilities

- `rss-digest`: The general morning digest gains a tag-driven "AI Consciousness"
  category with a category-specific size limit (up to 10 entries) and a
  «Топ-10 категории» presentation instead of the standard category listing with
  «Топ-3 категории».

## Impact

- `app/elisp/sem-rss.el` — `sem-rss-categories` gains a
  `("consciousness" . "AI Consciousness")` mapping; the general prompt builder
  passes the extended category list to the template.
- `data/prompts/general-prompt.txt` and `general-prompt.example.txt` — new
  rules for the AI Consciousness category (up to 10 items, «Топ-10 категории»).
- `app/elisp/tests/sem-rss-test.el` — category-list assertions updated for the
  new category.
- No changes to cron scheduling, digest file naming, retry/error handling, URL
  sanitization, or the arXiv digest. Integration tests are unaffected (they only
  reference the `morning-read` directory, not digest content).
Decided: entries from `consciousness`-tagged feeds are exclusive to the
  "AI Consciousness" category; they are not duplicated into other general-digest
  categories.
