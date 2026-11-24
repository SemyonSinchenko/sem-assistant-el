;;; sem-rules.el --- User scheduling preferences -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; This module provides access to user-defined scheduling preferences
;; stored in /data/tasks/rules.org. The rules file contains natural language
;; guidance for the LLM about when and how to schedule tasks.

;;; Code:

(defconst sem-rules-file "/data/tasks/rules.org"
  "Path to the user scheduling preferences file.")

(defun sem-rules-read ()
  "Read and return the contents of the rules file.
Returns nil if the file does not exist or is empty.
Returns the rules text as a string if the file exists and has content."
  (when (file-exists-p sem-rules-file)
    (with-temp-buffer
      (insert-file-contents sem-rules-file)
      (goto-char (point-min))
      (when (re-search-forward "[[:graph:]]" nil t)
        (goto-char (point-min))
        (string-trim (buffer-string))))))

(provide 'sem-rules)
;;; sem-rules.el ends here
