## ADDED Requirements

### Requirement: Prompt templates prohibit LaTeX commands and backslash escapes
The version-controlled prompt template files `arxiv-prompt.example.txt` and `general-prompt.example.txt` SHALL include explicit rules prohibiting LaTeX commands and backslash escapes in LLM output. The rules SHALL be appended to the existing "CRITICAL OUTPUT RULES" section and SHALL occupy fewer than 10 lines combined. The rules SHALL instruct the LLM to strip all LaTeX markup from paper titles and replace math notation with plain-text approximations.

#### Scenario: arXiv prompt contains LaTeX prohibition
- **WHEN** the content of `arxiv-prompt.example.txt` is examined
- **THEN** it contains a rule stating that LaTeX commands and backslash escapes MUST NOT appear in output
- **AND** the rule is located within or adjacent to the "CRITICAL OUTPUT RULES" section

#### Scenario: General prompt contains LaTeX prohibition
- **WHEN** the content of `general-prompt.example.txt` is examined
- **THEN** it contains a rule stating that LaTeX commands and backslash escapes MUST NOT appear in output
- **AND** the rule is located within or adjacent to the "CRITICAL OUTPUT RULES" section

#### Scenario: Math notation replacement instruction present
- **WHEN** the prompt template content is examined
- **THEN** it instructs the LLM to replace math notation (e.g., `$O(n \log n)$`) with plain-text approximation (e.g., `O(n log n)`)

### Requirement: Prompt templates include concrete BAD/GOOD LaTeX examples
The prompt template files SHALL include at least two concrete BAD/GOOD example pairs showing incorrect LaTeX output and the correct plain-text alternative. Examples SHALL cover backslash command stripping (e.g., `\emph{word}` to `/word/`) and URL command stripping (e.g., `\url{https://...}` to `[[https://...][description]]`). The full error log SHALL NOT be pasted into the prompt.

#### Scenario: Backslash command example present
- **WHEN** the prompt template content is examined
- **THEN** it contains at least one BAD/GOOD pair showing a LaTeX command (e.g., `\emph{word}` or `$\texttt{SynC}$`) and its plain-text replacement

#### Scenario: URL command example present
- **WHEN** the prompt template content is examined
- **THEN** it contains at least one BAD/GOOD pair showing `\url{...}` or similar LaTeX URL markup and its Org-mode link replacement

#### Scenario: Prompt remains concise
- **WHEN** the total line count of the LaTeX prohibition rules and examples is measured
- **THEN** it occupies fewer than 10 lines
- **AND** the raw error log content is not included in the prompt
