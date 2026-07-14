;;; sem-security.el --- Security masking and URL sanitization -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; This module provides security masking for sensitive content before
;; sending to LLM APIs, and URL sanitization for human-readable outputs.

;;; Code:

;;; Constants

(defconst sem-security-token-prefix "<<SENSITIVE_"
  "Prefix for sensitive content tokens.")

(defconst sem-security-token-suffix ">>"
  "Suffix for sensitive content tokens.")

(defconst sem-security-sensitive-marker-regexp
  "^[ \t]*#\\+\\(begin\\|end\\)_sensitive[ \t]*$"
  "Regexp for standalone sensitive block markers.")

(defconst sem-security-sensitive-marker-anywhere-regexp
  "#\\+\\(begin\\|end\\)_sensitive\\b"
  "Regexp for any sensitive marker occurrence in a line.")

;;; Sensitive Block Detection and Tokenization

(defun sem-security--collect-sensitive-block-ranges (text)
  "Return sensitive block ranges in TEXT as ((START . END) ...).
Signals an error when markers are malformed.

Validation rules:
- Markers are case-insensitive.
- Markers must be on standalone lines.
- Nested sensitive blocks are not allowed.
- Every begin marker must have a matching end marker."
  (let ((ranges '())
        (open-start nil)
        (case-fold-search t))
    (with-temp-buffer
      (insert text)

      ;; Reject inline/partial markers anywhere in the text.
      (goto-char (point-min))
      (while (re-search-forward sem-security-sensitive-marker-anywhere-regexp nil t)
        (let ((line (buffer-substring-no-properties (line-beginning-position)
                                                    (line-end-position))))
          (unless (string-match-p sem-security-sensitive-marker-regexp line)
            (error "Malformed sensitive marker: markers must be on standalone lines"))))

      ;; Parse balanced, non-nested marker pairs.
      (goto-char (point-min))
      (while (re-search-forward sem-security-sensitive-marker-regexp nil t)
        (let ((marker (downcase (match-string 1))))
          (if (string= marker "begin")
              (if open-start
                  (error "Malformed sensitive block: nested begin marker is not allowed")
                (setq open-start (match-beginning 0)))
            (unless open-start
              (error "Malformed sensitive block: end marker without begin marker"))
            (push (cons open-start (match-end 0)) ranges)
            (setq open-start nil))))

      (when open-start
        (error "Malformed sensitive block: missing #+end_sensitive marker")))
    (nreverse ranges)))

(defun sem-security--detect-sensitive-blocks (text &optional ranges)
  "Detect all sensitive blocks in TEXT.
Returns an alist of (token . content) pairs where content includes the markers.
RANGES can be provided as output of `sem-security--collect-sensitive-block-ranges'."
  (let ((blocks '())
        (counter 0)
        (effective-ranges (or ranges (sem-security--collect-sensitive-block-ranges text))))
    (with-temp-buffer
      (insert text)
      (dolist (range effective-ranges)
        (setq counter (1+ counter))
        (let ((token (format "%s%d%s" sem-security-token-prefix counter sem-security-token-suffix))
              (content (buffer-substring-no-properties (car range) (cdr range))))
          (push (cons token content) blocks))))
    (nreverse blocks)))

(defun sem-security--detect-sensitive-blocks-with-position (text &optional ranges)
  "Detect sensitive blocks in TEXT with surrounding context for position tracking.
Returns an alist of (token . (before-context . after-context)) where:
- token is the <<SENSITIVE_N>> placeholder
- before-context is up to 20 chars preceding the block
- after-context is up to 20 chars following the block

Note: This function only returns position info, not the full block content.
Use `sem-security--detect-sensitive-blocks` for the blocks-alist used in tokenization.
RANGES can be provided as output of `sem-security--collect-sensitive-block-ranges'."
  (let ((position-info '())
        (counter 0)
        (context-chars 20)
        (effective-ranges (or ranges (sem-security--collect-sensitive-block-ranges text))))
    (with-temp-buffer
      (insert text)
      (dolist (range effective-ranges)
        (let* ((block-start (car range))
               (block-end (cdr range))
               (before-start (max (point-min) (- block-start context-chars)))
               (after-end (min (point-max) (+ block-end context-chars)))
               (before-context (string-trim
                                (buffer-substring-no-properties before-start block-start)))
               (after-context (string-trim
                               (buffer-substring-no-properties block-end after-end)))
               (block-content (buffer-substring-no-properties block-start block-end)))
          (setq counter (1+ counter))
          (let ((token (format "%s%d%s" sem-security-token-prefix counter sem-security-token-suffix)))
            (push (list token block-content before-context after-context) position-info)))))
    (nreverse position-info)))

(defun sem-security--tokenize (text blocks)
  "Replace sensitive content in TEXT with tokens from BLOCKS.
Returns the tokenized text."
  (let ((result text))
    (dolist (block blocks)
      (let ((token (car block))
            (content (cdr block)))
        (setq result (replace-regexp-in-string (regexp-quote content) token result t))))
    result))

(defun sem-security--detokenize (text blocks)
  "Replace tokens in TEXT with original content from BLOCKS.
Returns the restored text with sensitive content as plain text.

Multi-line content is indented 2 spaces per line with leading/trailing
newlines. Single-line content is placed at token position verbatim."
  (let ((result text))
    (dolist (block blocks)
      (let ((token (car block))
            (content (cdr block)))
        (let ((plain-text (sem-security--extract-block-content content)))
          (setq result (replace-regexp-in-string
                        (regexp-quote token)
                        plain-text
                        result
                        t)))))
    result))

(defun sem-security--extract-block-content (block)
  "Extract plain text content from BLOCK (which includes markers).
Multi-line content gets exactly 2-space indentation per line with leading/trailing
newlines. Single-line content is returned verbatim."
  (let* ((lines (split-string block "\n"))
         (content-lines (butlast (cdr lines))) ; drop first (begin marker) and last (end marker)
         (trimmed (string-trim (mapconcat 'identity content-lines "\n"))))
    (if (string-match-p "\n" trimmed)
        (concat "\n" (mapconcat (lambda (line) (concat "  " (replace-regexp-in-string "^[ \t]+" "" line))) (split-string trimmed "\n") "\n") "\n")
      trimmed)))

(defun sem-security-sanitize-for-llm (text)
  "Sanitize TEXT before sending to LLM.
Replaces sensitive blocks with opaque tokens.
Signals an error if sensitive markers are malformed.
Returns (tokenized-text blocks-alist position-info-alist) as a list of three elements:
- tokenized-text: the text with sensitive content replaced by tokens
- blocks-alist: alist mapping tokens to original sensitive content
- position-info-alist: alist mapping tokens to (before-context . after-context) pairs"
  (let* ((ranges (sem-security--collect-sensitive-block-ranges text))
         (blocks (sem-security--detect-sensitive-blocks text ranges))
          (tokenized (sem-security--tokenize text blocks))
          (position-info (sem-security--detect-sensitive-blocks-with-position text ranges)))
    (list tokenized blocks position-info)))

(defun sem-security-restore-from-llm (text blocks)
  "Restore original content in TEXT using BLOCKS.
Replaces tokens with original sensitive content."
  (sem-security--detokenize text blocks))

;;; URL Sanitization

(defun sem-security--sanitize-url (url)
  "Sanitize a single URL by replacing http/https with hxxp/hxxps."
  (cond
   ((string-prefix-p "https://" url)
    (concat "hxxps://" (substring url 8)))
   ((string-prefix-p "http://" url)
    (concat "hxxp://" (substring url 7)))
   (t url)))

(defun sem-security-sanitize-urls (text)
  "Sanitize all URLs in TEXT.
Replaces http:// with hxxp:// and https:// with hxxps://.
Use this for tasks.org and morning-read output only.
Do NOT use for org-roam output.

The matching regex stops at Org-mode link delimiters (], }, \\, and |)
so it never greedily consumes LaTeX markup or org-link brackets that
follow a URL in malformed LLM output.  The replacement text is inserted
verbatim (LITERAL non-nil) so backslash sequences in the sanitized URL
are not interpreted by `replace-match'."
  (replace-regexp-in-string
   "https?://[^] \t\n\"}|\\\\]+"
   (lambda (match) (sem-security--sanitize-url match))
   text nil t))

(provide 'sem-security)
;;; sem-security.el ends here
