## ADDED Requirements

### Requirement: General digest includes AI Consciousness category from consciousness-tagged feeds
The general morning digest SHALL include a dedicated "AI Consciousness" category whose entries come from Elfeed entries whose feed is tagged `consciousness` in the feeds Org file. Entries from `consciousness`-tagged feeds SHALL appear only in the AI Consciousness category and SHALL NOT appear in any other category of the general digest. The AI Consciousness category SHALL contain at most 10 entries, presented as a «Топ-10 категории» section, and SHALL NOT use the per-category «Топ-3 категории» subsection used by other categories. The category SHALL be written in Russian, like the rest of the general digest, and SHALL follow the general digest prompt conventions (Org-mode structure, CRITICAL OUTPUT RULES, LaTeX prohibition rules). The category SHALL be produced as part of the existing general digest LLM request; no separate digest file, cron entry, or LLM request SHALL be introduced.

#### Scenario: Consciousness entries grouped into the AI Consciousness category
- **WHEN** the general morning digest is generated and entries from feeds tagged `consciousness` exist in the last 24 hours
- **THEN** the digest contains an "AI Consciousness" category containing those entries

#### Scenario: Consciousness entries are exclusive to the new category
- **WHEN** an entry from a feed tagged `consciousness` is included in the general digest
- **THEN** it does not appear in any other general-digest category

#### Scenario: Category contains at most 10 entries
- **WHEN** more than 10 entries from `consciousness`-tagged feeds exist in the last 24 hours
- **THEN** the AI Consciousness category contains at most 10 entries

#### Scenario: Category with fewer than 10 entries lists them all
- **WHEN** 10 or fewer entries from `consciousness`-tagged feeds exist in the last 24 hours
- **THEN** the AI Consciousness category contains all of them

#### Scenario: Category uses Топ-10 presentation instead of Топ-3
- **WHEN** the AI Consciousness category is present in the general digest
- **THEN** it is presented as «Топ-10 категории»
- **AND** it has no «Топ-3 категории» subsection

#### Scenario: Category output is in Russian
- **WHEN** the AI Consciousness category is generated
- **THEN** its titles, summaries, and reasoning text are in Russian, matching the rest of the general digest

#### Scenario: Category omitted when no consciousness entries exist
- **WHEN** no entries from `consciousness`-tagged feeds exist in the last 24 hours
- **THEN** the general digest is generated without an AI Consciousness category
- **AND** the general digest file is still written when other entries exist
