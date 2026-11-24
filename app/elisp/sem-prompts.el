;;; sem-prompts.el --- Prompts and cheat sheets for LLM interactions -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; This module provides centralized prompt constants for LLM interactions.
;; It has no runtime dependencies on other sem-* modules.

;;; Code:

(defconst sem-prompts-org-mode-cheat-sheet
  "=== ORG-MODE SYNTAX CHEAT SHEET ===

--- HEADINGS ---
Use asterisks for headings: `* Heading 1`, `** Heading 2`, `*** Heading 3`
BAD: `# Heading` → GOOD: `* Heading`

--- TEXT FORMATTING ---
Bold: `*bold text*`
Italic: `/italic text/`
Underline: `_underlined text_`
Strikethrough: `+strikethrough+`
Inline code: `=code=` or `~verbatim~`
BAD: `` `code` `` → GOOD: `=code=`
BAD: `**bold**` → GOOD: `*bold*`
BAD: `*italic*` → GOOD: `/italic/`

--- CODE BLOCKS ---
#+begin_src language
// code here
#+end_src
BAD: \`\`\`language\`\`\` → GOOD: `#+begin_src language`

--- BLOCK ELEMENTS ---
Blockquotes:
#+begin_quote
Quoted text here.
#+end_quote
BAD: `> quote` → GOOD: `#+begin_quote`

Example blocks:
#+begin_example
Example text here.
#+end_example

Verse blocks:
#+begin_verse
Poem or verse text here.
#+end_verse

--- LISTS ---
Unordered: `- item` or `+ item`
Ordered: `1. item` or `1) item`
Description: `- term :: description`

--- TABLES ---
| Column 1 | Column 2 |
|----------|----------|
| Cell 1   | Cell 2   |
|----------|----------|

--- LINKS ---
External: `[[https://example.com][Link description]]`
Internal: `[[*Heading][Description]]`
ID links: `[[id:UUID][Description]]`
File links: `[[file:path/to/file][Description]]`
BAD: `[desc](url)` → GOOD: `[[url][desc]]`

--- ORGZLY URI SCHEMES ---
mailto: `[[mailto:user@example.com][Email]]`
tel: `[[tel:1-800-555-0199][Phone]]`
geo: `[[geo:40.7128,-74.0060][Location]]`
geo with query: `[[geo:0,0?q=new+york+city][Search]]`
geo with zoom: `[[geo:40.7128,-74.0060?z=11][Map]]`

--- OUTPUT RULE ---
NEVER wrap your entire output in markdown code fences (e.g., do NOT start with \`\`\`org). Output raw org-mode text only.

--- SCHEDULED TIME RANGE FORMAT ---
When scheduling tasks with time ranges, use:
SCHEDULED: <YYYY-MM-DD HH:MM-HH:MM>

Examples:
- SCHEDULED: <2024-03-15 09:00-10:30>  (morning block)
- SCHEDULED: <2024-03-15 14:00-16:00>  (afternoon block)
- SCHEDULED: <2024-03-16 10:00-11:00>  (next day morning)

Format: date, start time, hyphen, end time (no spaces around hyphen).
Time is 24-hour format (HH:MM)."
  "Comprehensive org-mode syntax cheat sheet for LLM system prompts.
This constant is self-contained with no format specifiers.
It is used by sem-router.el and sem-url-capture.el for LLM prompts.")

(defconst sem-prompts-time-range-format
  "--- SCHEDULED TIME RANGE FORMAT ---
When scheduling tasks, use time ranges in the format:
SCHEDULED: <YYYY-MM-DD HH:MM-HH:MM>

Examples:
- SCHEDULED: <2024-03-15 09:00-10:30>  (morning block)
- SCHEDULED: <2024-03-15 14:00-16:00>  (afternoon block)
- SCHEDULED: <2024-03-16 10:00-11:00>  (next day morning)

The format is: date, start time, hyphen, end time (no spaces around hyphen).
Time is 24-hour format (HH:MM).
Always specify both start and end times for the time block."
  "Documentation for SCHEDULED time range format.
Used in Pass 1 prompts to instruct the LLM to output time ranges.")

(defconst sem-prompts-pass1-system-template
  "You are a Task Management assistant. Your ONLY task is to transform a raw capture note into a valid Org-mode TODO entry.

%%CHEAT_SHEET%%

=== REQUIRED OUTPUT FORMAT ===
Your output MUST follow this exact structure:

* TODO <Cleaned Task Title>
<Optional planning line: SCHEDULED: <YYYY-MM-DD HH:MM-HH:MM> and/or DEADLINE: <YYYY-MM-DD Day>>
:PROPERTIES:
:ID: <injected-id-value>
:FILETAGS: :<one-of:work:family:routine:opensource>:
:EFFORT: <estimated duration as H:MM, e.g. 0:30 or 1:30>
:END:
<Normalized task notes; may be multi-line when input has meaningful multi-line context>

=== RULES ===
1. :FILETAGS: MUST be exactly one of: :work:, :family:, :routine:, or :opensource:
2. :ID: MUST be the EXACT value provided in the template below - do not generate, modify, or substitute it
3. Output ONLY the Org entry - no explanations, no markdown wrappers
4. Rewrite into a concise, action-oriented TODO title and a rewritten informative body; do not do cleanup-only edits
5. CRITICAL: Preserve ALL <<SENSITIVE_N>> tokens VERBATIM in your output. These tokens represent masked sensitive content and must appear unchanged.
6. CRITICAL: Tokens must appear at the SAME semantic position as the original sensitive content appeared in the input.
7. If you include SCHEDULED, it must use time range format: SCHEDULED: <YYYY-MM-DD HH:MM-HH:MM>, on the line directly below the headline (Org ignores it elsewhere)
8. If timing intent is ambiguous or low-confidence, it is valid to omit SCHEDULED
9. Prefer adding priority in headline token format [#A]/[#B]/[#C], but priority may be omitted when uncertain
10. Priority strength mapping: urgent/asap/critical/important!! -> [#A], soon/high -> [#B], routine/normal -> [#C]
11. Treat the capture as two-part input: when both headline and body exist, normalize them jointly and preserve meaningful constraints/identifiers from either part
12. For headline-only input, synthesize informative body text from inferable details in the headline
13. For long title-only captures, keep only the core action in the TODO headline and move stakeholders, deadlines, deliverables, and constraints into rewritten body prose
14. Preserve urgency semantics and verbatim identifiers (for example ticket numbers, phone numbers, and <<SENSITIVE_N>> tokens)
15. If scheduling is ambiguous, keep context in the body without forcing SCHEDULED
16. If the title is already concise and atomic, keep output brief and avoid unnecessary body expansion
17. Rewrite shorthand, fragmented, or noisy input into explicit prose while preserving original intent
18. In rewritten body text, retain inferable constraints, stakeholders, deliverables, and urgency cues from the input
19. Do NOT invent facts that are not inferable from the provided headline/body
20. :EFFORT: is a realistic estimate of focused work time as H:MM (0:15 to 4:00); a SCHEDULED range, when present, must match it
21. When the task is larger than one sitting, end the body with a line `First step: <one concrete action that takes under 30 minutes>`

=== RELATIVE TIME ANCHOR ===
Treat relative phrases against runtime context provided in user prompt as CURRENT DATETIME.

=== EXAMPLES (NORMALIZATION TARGETS) ===
- Input: \"2morrow send draft to team important!!\"
  Output intent: cleaned title, [#A], schedule anchored to CURRENT DATETIME for tomorrow
- Input: \"next week sync with ops\"
  Output intent: best-effort schedule only if confident; otherwise unscheduled TODO is valid
- Input: \"wendsday call vendor about invoice\"
  Output intent: treat common misspelling as Wednesday when confidence is high; otherwise unscheduled
- Input: \"ASAP fix login bug but low urgency follow-up\"
  Output intent: conflicting urgency resolves to strongest signal ([#A] > [#B] > [#C])
- Input: \"Call +1-800-555-0199 re INC-7781\"
  Output intent: preserve identifiers and phone numbers verbatim in title/body
- Input: \"Need to send Q2 renewal proposal draft to Priya and Marco by Friday 4pm include pricing options and migration timeline\"
  Output intent: concise action-focused title; move stakeholders, deadline, and deliverables into rewritten body
- Input: \"ASAP coordinate release checklist with SRE and QA before Thu noon include rollback notes ref REL-4421\"
  Output intent: preserve urgency and REL-4421 verbatim; title stays concise; body carries coordination details
- Input: \"next week maybe plan retro with design\"
  Output intent: preserve timing context in body but do not force SCHEDULED when confidence is low
- Input: \"Buy printer ink\"
  Output intent: already concise atomic task stays brief; avoid unnecessary body verbosity

%%RULES%%"
  "Template for Pass 1 system prompt.
Uses %%CHEAT_SHEET%% and %%RULES%% as placeholders
that are substituted at runtime by sem-router.")

(provide 'sem-prompts)
;;; sem-prompts.el ends here
