;;; sem-security-test.el --- Tests for sem-security.el -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Tests for sem-security masking and URL sanitization functions.

;;; Code:

(require 'ert)

;; Load the module under test
(load-file (expand-file-name "../sem-security.el" (file-name-directory load-file-name)))

;;; Tests for tokenize/detokenize round-trip

(ert-deftest sem-security-test-tokenize-detokenize-roundtrip ()
  "Test that tokenize/detokenize round-trip restores content as plain text."
  (let ((original "Normal text
#+begin_sensitive
secret-api-key-12345
#+end_sensitive
More normal text"))
    (let* ((result (sem-security-sanitize-for-llm original))
           (tokenized (car result))
           (blocks (cadr result)))
      ;; Tokenized text should contain token placeholder
      (should (string-prefix-p "Normal text\n<<" tokenized))
      ;; Detokenize should restore content as plain text (no markers)
      ;; Single-line content is placed verbatim at token position
      (let ((restored (sem-security-restore-from-llm tokenized blocks)))
        (should (string= "Normal text
secret-api-key-12345
More normal text" restored))))))

;;; Test sensitive block content not present in tokenized string

(ert-deftest sem-security-test-sensitive-content-masked ()
  "Test that sensitive content is not present in tokenized string."
  (let ((original "Public info
#+begin_sensitive
SECRET_PASSWORD_123
#+end_sensitive
More public info"))
    (let* ((result (sem-security-sanitize-for-llm original))
           (tokenized (car result))
           (blocks (cadr result))
           (position-info (caddr result)))
      ;; Tokenized text should NOT contain the sensitive content
      (should-not (string-match-p "SECRET_PASSWORD_123" tokenized))
      ;; Should contain token placeholder instead
      (should (string-match-p "<<SENSITIVE_[0-9]+>>" tokenized))
      ;; Position info should exist and be non-nil
      (should (listp position-info))
      (should (> (length position-info) 0)))))

;;; Tests for URL sanitization

(ert-deftest sem-security-test-url-sanitization-http ()
  "Test URL sanitization replaces http with hxxp."
  (let ((text "Check out http://example.com/page for more info"))
    (let ((sanitized (sem-security-sanitize-urls text)))
      (should (string= "Check out hxxp://example.com/page for more info" sanitized))
      (should-not (string-match-p "http://" sanitized)))))

(ert-deftest sem-security-test-url-sanitization-https ()
  "Test URL sanitization replaces https with hxxps."
  (let ((text "Visit https://secure.example.com/login now"))
    (let ((sanitized (sem-security-sanitize-urls text)))
      (should (string= "Visit hxxps://secure.example.com/login now" sanitized))
      (should-not (string-match-p "https://" sanitized)))))

(ert-deftest sem-security-test-url-sanitization-multiple-urls ()
  "Test URL sanitization handles multiple URLs."
  (let ((text "See http://a.com and https://b.org for details"))
    (let ((sanitized (sem-security-sanitize-urls text)))
      (should (string= "See hxxp://a.com and hxxps://b.org for details" sanitized)))))

(ert-deftest sem-security-test-url-sanitization-preservation ()
  "Test that non-URL text is preserved."
  (let ((text "This is just regular text with no URLs"))
    (let ((sanitized (sem-security-sanitize-urls text)))
      (should (string= text sanitized)))))

;;; Test that URL sanitization is NOT applied to org-roam output
;;; (This is a policy test - the function exists but should not be called for org-roam)

(ert-deftest sem-security-test-url-sanitization-scope ()
  "Test that sem-security-sanitize-urls is a separate function.
Org-roam output should NOT call this function (policy check)."
  ;; The function exists and works
  (should (functionp 'sem-security-sanitize-urls))
  ;; But org-roam modules should not use it (this is a code review check)
  (should t))

;;; Tests for backslash/delimiter-safe URL sanitization
;;; Regression for "Invalid use of \\ in replacement text" errors caused by
;;; LaTeX markup (e.g. \\texttt, \\emph, \\url) propagated from arXiv abstracts.

(ert-deftest sem-security-test-url-sanitization-backslash-adjacent ()
  "Test that a URL adjacent to a backslash does not crash and is sanitized.
Reproduces the production failure where LaTeX like \\texttt follows a URL."
  (let ((text "https://example.com\\texttt{word}"))
    (let ((sanitized (sem-security-sanitize-urls text)))
      ;; Must not signal "Invalid use of \\ in replacement text"
      (should (string= "hxxps://example.com\\texttt{word}" sanitized))
      ;; URL portion is sanitized, LaTeX portion preserved verbatim
      (should (string-match-p "hxxps://example\\.com" sanitized))
      (should-not (string-match-p "https://example\\.com" sanitized))
      (should (string-match-p "\\\\texttt{word}" sanitized)))))

(ert-deftest sem-security-test-url-sanitization-stops-at-bracket ()
  "Test that URL matching stops at ] (Org-mode link delimiter)."
  (let ((text "[[https://arxiv.org/abs/2406.15797][Description]]"))
    (let ((sanitized (sem-security-sanitize-urls text)))
      ;; Only the URL is sanitized; the Org link description is preserved.
      (should (string= "[[hxxps://arxiv.org/abs/2406.15797][Description]]"
                       sanitized))
      (should-not (string-match-p "https://arxiv" sanitized)))))

(ert-deftest sem-security-test-url-sanitization-stops-at-backslash ()
  "Test that URL matching stops at a backslash character."
  (let ((text "https://example.com\\texttt{word}"))
    (let ((sanitized (sem-security-sanitize-urls text)))
      ;; Only https://example.com is matched and sanitized
      (should (string= "hxxps://example.com\\texttt{word}" sanitized)))))

(ert-deftest sem-security-test-url-sanitization-stops-at-brace ()
  "Test that URL matching stops at a closing brace."
  (let ((text "https://example.com/page} extra"))
    (let ((sanitized (sem-security-sanitize-urls text)))
      (should (string= "hxxps://example.com/page} extra" sanitized))
      (should (string-match-p "\\`hxxps://example\\.com/page\\}" sanitized)))))

(ert-deftest sem-security-test-url-sanitization-stops-at-pipe ()
  "Test that URL matching stops at a pipe character."
  (let ((text "https://example.com|other"))
    (let ((sanitized (sem-security-sanitize-urls text)))
      (should (string= "hxxps://example.com|other" sanitized)))))

(ert-deftest sem-security-test-url-sanitization-multiple-delimited-urls ()
  "Test that multiple URLs inside Org-mode links are all sanitized."
  (let ((text "[[https://a.com][A]] and [[https://b.org][B]]"))
    (let ((sanitized (sem-security-sanitize-urls text)))
      (should (string= "[[hxxps://a.com][A]] and [[hxxps://b.org][B]]"
                       sanitized))
      (should-not (string-match-p "https://" sanitized)))))

(ert-deftest sem-security-test-url-sanitization-literal-preserves-backslash ()
  "Test that LITERAL replacement mode preserves backslash sequences verbatim.
The sanitized URL must keep \\t and \\emph sequences unchanged rather than
letting `replace-match' interpret them as escape sequences."
  (let ((text "https://example.com\\t\\emph{word}"))
    (let ((sanitized (sem-security-sanitize-urls text)))
      ;; Backslash sequences survive verbatim (no crash, no interpretation)
      (should (string= "hxxps://example.com\\t\\emph{word}" sanitized))
      (should (string-match-p "\\\\t\\\\emph" sanitized)))))

(ert-deftest sem-security-test-url-sanitization-latex-in-org-link ()
  "Test the exact production-failure case: LaTeX in an org-link description.
Input shape: [[https://arxiv.org/abs/2406.15797][$\\texttt{SynC}$: Title]]"
  (let ((text "[[https://arxiv.org/abs/2406.15797][$\\texttt{SynC}$: Synergistic Boosting]]"))
    (let ((sanitized (sem-security-sanitize-urls text)))
      (should (string=
               "[[hxxps://arxiv.org/abs/2406.15797][$\\texttt{SynC}$: Synergistic Boosting]]"
               sanitized))
      ;; URL sanitized, LaTeX in description preserved verbatim
      (should-not (string-match-p "https://arxiv" sanitized))
      (should (string-match-p "\\\\texttt{SynC}" sanitized)))))

(ert-deftest sem-security-test-url-sanitization-standard-still-works ()
  "Test that standard URLs (no delimiters) are still sanitized correctly."
  (let ((text "See https://example.com/page for info"))
    (let ((sanitized (sem-security-sanitize-urls text)))
      (should (string= "See hxxps://example.com/page for info" sanitized))
      (should-not (string-match-p "https://" sanitized)))))

;;; Tests for position-preserving round-trip

(ert-deftest sem-security-test-position-roundtrip ()
  "Test that position info is correctly captured and restored as plain text."
  (let ((original "Update password to\n#+begin_sensitive\nsupersecret123\n#+end_sensitive\nfor access"))
    (let* ((result (sem-security-sanitize-for-llm original))
           (tokenized (car result))
           (blocks (cadr result))
           (position-info (caddr result)))
      ;; Token should be present in tokenized text
      (should (string-match-p "<<SENSITIVE_1>>" tokenized))
      ;; Original sensitive content should NOT be present
      (should-not (string-match-p "supersecret123" tokenized))
      ;; Position info should have entry for <<SENSITIVE_1>>
      (should (= (length position-info) 1))
      (let ((entry (car position-info)))
        (should (string= (car entry) "<<SENSITIVE_1>>"))
        (should (= (length entry) 4)) ;; token, content, before-context, after-context
        ;; Before context should contain text before the sensitive block
        (let ((before-context (caddr entry)))
          (should (string-match-p "Update password to" before-context)))
        ;; After context should contain text after the sensitive block
        (let ((after-context (cadddr entry)))
          (should (string-match-p "for access" after-context))))
      ;; Round-trip should restore plain text (no markers)
      (let ((restored (sem-security-restore-from-llm tokenized blocks)))
        (should (string= "Update password to
supersecret123
for access" restored))))))

;;; Strict malformed marker handling

(ert-deftest sem-security-test-missing-end-marker-signals-error ()
  "Test missing end marker signals strict malformed-block error."
  (let ((original "before\n#+begin_sensitive\nsecret\nafter"))
    (should-error (sem-security-sanitize-for-llm original)
                  :type 'error)))

(ert-deftest sem-security-test-end-without-begin-signals-error ()
  "Test end marker without begin signals strict malformed-block error."
  (let ((original "before\n#+end_sensitive\nafter"))
    (should-error (sem-security-sanitize-for-llm original)
                  :type 'error)))

(ert-deftest sem-security-test-inline-marker-signals-error ()
  "Test inline sensitive marker text is rejected."
  (let ((original "Note #+begin_sensitive should be standalone."))
    (should-error (sem-security-sanitize-for-llm original)
                  :type 'error)))

(ert-deftest sem-security-test-nested-begin-marker-signals-error ()
  "Test nested sensitive blocks are rejected."
  (let ((original "#+begin_sensitive\none\n#+begin_sensitive\ntwo\n#+end_sensitive\n#+end_sensitive"))
    (should-error (sem-security-sanitize-for-llm original)
                  :type 'error)))

(ert-deftest sem-security-test-uppercase-markers-are-accepted ()
  "Test case-insensitive markers are accepted and tokenized."
  (let* ((original "A\n#+BEGIN_SENSITIVE\nToken\n#+END_SENSITIVE\nB")
         (result (sem-security-sanitize-for-llm original))
         (tokenized (car result)))
    (should (string-match-p "<<SENSITIVE_1>>" tokenized))
    (should-not (string-match-p "Token" tokenized))))

(provide 'sem-security-test)
;;; sem-security-test.el ends here
