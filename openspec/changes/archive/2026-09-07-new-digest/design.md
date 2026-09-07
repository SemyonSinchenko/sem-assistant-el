## Context

See proposal.md for motivation and specs/rss-digest/spec.md for the behavior contract.

The general morning digest is generated in one LLM request: `sem-rss.el` collects
non-arXiv entries from the last 24 hours, renders each entry with its tags into a
flat text block, and formats it into `general-prompt.txt` together with a
comma-separated category list derived from `sem-rss-categories` (tag to display
name). The LLM performs the grouping into categories; the elisp side never parses
the Org output. Prompt templates are loaded from `/data/prompts/`, which is the
bind-mounted repo directory `data/prompts/`; `general-prompt.example.txt` is the
version-controlled mirror asserted on by specs and tests. The general prompt
already pins output to Russian and Org-mode with the CRITICAL OUTPUT RULES.

## Goals / Non-Goals

**Goals:**
- "AI Consciousness" category in the general digest, sourced from the `consciousness` feed tag.
- Exclusive placement: `consciousness` entries never appear in other categories.
- At most 10 entries, presented as «Топ-10 категории», no «Топ-3 категории» subsection.
- Keep the single general-digest LLM request and existing pipeline untouched.

**Non-Goals:**
- No new digest file, cron entry, or separate LLM request.
- No changes to the arXiv digest, entry collection filters, retry policy, or URL sanitization.
- No elisp-side parsing or post-editing of the LLM's Org output.

## Decisions

### D1: Prompt-driven grouping instead of a collection split
Add `("consciousness" . "AI Consciousness")` to `sem-rss-categories` and state the
grouping rule in the prompt template. `sem-rss-collect-entries` already includes
`consciousness`-tagged feeds in the general digest input (they are non-arXiv), and
each rendered entry carries its tags, so the LLM has the information it needs.
- Alternative rejected: splitting collection into a consciousness subset and a rest
  subset and injecting section markers into the entries text. It adds a second
  collection pass and touches the shared entries-text builder for no observable
  benefit; grouping is LLM-driven either way.

### D2: Cap and presentation live in the prompt template
"Up to 10 entries as «Топ-10 категории», no «Топ-3 категории»" is an LLM output
rule, so it is encoded in `general-prompt.txt` (and the `.example.txt` mirror).
Deterministic enforcement would require parsing and rewriting the Org output,
which this pipeline deliberately avoids.
- Alternative rejected: truncating the category in elisp after generation —
  requires category-aware Org parsing and produces silent data loss instead of a
  well-formed top-10 selection.

### D3: Exclusivity is LLM-enforced via an explicit rule
The template gets an imperative rule: entries from feeds tagged `consciousness`
must appear only in the AI Consciousness category and never in other categories.
This is the same mechanism the digest already relies on for category grouping.
- Alternative rejected: elisp post-filtering of duplicated entries — same parsing
  cost as D2 with the same fragility.

### D4: Tests follow the existing assertion patterns
- Extend `sem-rss-test-build-general-prompt-contains-categories` to require
  "AI Consciousness" in the built prompt.
- New test: `sem-rss-categories` contains the `consciousness` mapping.
- New tests on `general-prompt.example.txt`: contains the «Топ-10 категории» rule
  and the exclusivity rule (mirrors how the LaTeX-prohibition rules are asserted).

## Risks / Trade-offs

- [LLM may leak a consciousness entry into another category or exceed 10 items] →
  The rule is stated imperatively and placed adjacent to the CRITICAL OUTPUT
  RULES; entry tags in the input make the rule mechanical to follow. Residual
  risk is accepted and consistent with the existing LLM-driven grouping.
- [Prompt grows longer] → Rules are kept to a few lines; token budget is far from
  exhausted (`sem-rss-max-input-chars` dominates the request size).

## Migration Plan

- `data/prompts/general-prompt.txt` is the runtime file (`./data` is bind-mounted
  to `/data`), so updating the repo file and restarting the daemon is sufficient;
  the lazy template loader also picks it up on a fresh start. Rollback: revert the
  prompt file and the `sem-rss-categories` entry.
- No schema, API, or data migration.

## Open Questions

- None.
