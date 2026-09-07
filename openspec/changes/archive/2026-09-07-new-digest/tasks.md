## 1. Category Mapping

- [x] 1.1 Add `("consciousness" . "AI Consciousness")` to `sem-rss-categories` in `app/elisp/sem-rss.el` and verify `sem-rss-test-build-general-prompt-contains-categories` (updated in 3.1) passes with the new category present

## 2. Prompt Template

- [x] 2.1 Update `data/prompts/general-prompt.txt`: add the AI Consciousness rules (entries from feeds tagged `consciousness` go only into "AI Consciousness"; up to 10 entries as «Топ-10 категории»; no «Топ-3 категории» subsection for this category), placed adjacent to the CRITICAL OUTPUT RULES, and verify the daemon loads the template non-empty (`sem-rss-test-prompt-templates-loaded`)
- [x] 2.2 Mirror the same rules into `general-prompt.example.txt` and verify the file stays within the existing prompt conventions (Org-mode structure and LaTeX prohibition rules unchanged)

## 3. Tests

- [x] 3.1 Extend `sem-rss-test-build-general-prompt-contains-categories` in `app/elisp/tests/sem-rss-test.el` to assert the built general prompt contains "AI Consciousness" and verify it passes via the ERT runner
- [x] 3.2 Add a test asserting `sem-rss-categories` contains the `consciousness` mapping and verify it passes
- [x] 3.3 Add tests asserting `general-prompt.example.txt` contains the «Топ-10 категории» rule and the `consciousness` exclusivity rule, and verify they pass

## 4. Verification

- [x] 4.1 Run `sh dev/elisplint.sh app/elisp/sem-rss.el` and confirm no unmatched delimiters
- [x] 4.2 Run `eask test ert app/elisp/tests/sem-test-runner.el` and confirm the full suite passes
