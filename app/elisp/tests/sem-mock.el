;;; sem-mock.el --- Mock helpers for ERT tests -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; This module provides reusable mock helpers for testing SEM modules.
;; All tests should use these mocks to avoid real network/LLM calls.

;;; Code:

(require 'ert)
(require 'gptel)
(require 'org-roam)
(require 'cl-lib)

(setenv "CLIENT_TIMEZONE" (or (getenv "CLIENT_TIMEZONE") "Etc/UTC"))

;;; Mock Data

(defconst sem-mock-valid-org-response
  ":PROPERTIES:
:ID:          mock-test-id-12345
:END:
#+title: Test Article
#+ROAM_REFS: https://example.com/article
#+filetags: :article:

* Summary
Source: [[https://example.com/article][https://example.com/article]]
This is a test summary.

* Key Takeaways
- Point 1
- Point 2"
  "Valid org-roam node response for testing validation.")

(defconst sem-mock-invalid-org-response
  "This is not valid org-mode content.
It lacks :PROPERTIES: and #+title:."
  "Invalid org-roam node response for testing validation.")

(defconst sem-mock-article-content
  "<html><body><h1>Test Article</h1><p>This is test content.</p></body></html>"
  "Sample HTML content for testing text cleaning.")

(defconst sem-mock-cleaned-content
  "Test Article This is test content."
  "Expected cleaned text output.")

;;; gptel Mocks

(defvar sem-mock-gptel-response nil
  "Response to return from mocked gptel-request.")

(defvar sem-mock-gptel-error nil
  "Error to simulate from mocked gptel-request.")

(defvar sem-mock-gptel-stream-steps nil
  "Scripted callback steps for the streaming gptel mock.
Each step is a (RESPONSE . INFO) cons, e.g. partial string chunks,
`\'(reasoning . TEXT)' conses, and the `t'/`nil' terminal sentinels,
mirroring gptel's streaming callback contract.")

(defun sem-mock-gptel-request-success (response)
  "Setup gptel-request mock to return RESPONSE on success."
  (setq sem-mock-gptel-response response)
  (setq sem-mock-gptel-error nil)
  (advice-add 'gptel-request :override #'sem-mock--gptel-request-mock))

(defun sem-mock-gptel-request-error (error-msg)
  "Setup gptel-request mock to simulate ERROR-MSG failure."
  (setq sem-mock-gptel-response nil)
  (setq sem-mock-gptel-error error-msg)
  (advice-add 'gptel-request :override #'sem-mock--gptel-request-mock))

(defun sem-mock-gptel-request-stream (steps)
  "Setup gptel-request mock to replay STEPS as streaming callback events.
STEPS is a list of (RESPONSE . INFO) conses.  Each RESPONSE is delivered to
the request callback in order, mirroring gptel's streaming contract:
partial string chunks, `\'(reasoning . TEXT)' conses, and the `t'/`nil'
terminal sentinels."
  (setq sem-mock-gptel-response nil)
  (setq sem-mock-gptel-error nil)
  (setq sem-mock-gptel-stream-steps steps)
  (advice-add 'gptel-request :override #'sem-mock--gptel-request-mock))

(defun sem-mock--gptel-request-mock (prompt &rest args)
  "Mock implementation of gptel-request.
Uses `sem-mock-gptel-response' and `sem-mock-gptel-error'.
ARGS is a plist containing :callback, :system, :stream, etc."
  (let ((callback (plist-get args :callback)))
    (if sem-mock-gptel-stream-steps
        (progn
          (dolist (step sem-mock-gptel-stream-steps)
            (when callback
              (funcall callback (car step) (cdr step))))
          nil)
      (if sem-mock-gptel-error
          (progn
            (when callback
              (funcall callback nil (list :error sem-mock-gptel-error)))
            nil)
        (when callback
          (funcall callback sem-mock-gptel-response (list :status "success")))
        sem-mock-gptel-response))))

(defun sem-mock-gptel-reset ()
  "Reset gptel mocks to original behavior."
  (setq sem-mock-gptel-response nil)
  (setq sem-mock-gptel-error nil)
  (setq sem-mock-gptel-stream-steps nil)
  (when (advice-member-p #'sem-mock--gptel-request-mock 'gptel-request)
    (advice-remove 'gptel-request #'sem-mock--gptel-request-mock)))

;;; Trafilatura Mocks

(defvar sem-mock-trafilatura-output nil
  "Output to return from mocked trafilatura CLI.")

(defvar sem-mock-trafilatura-exit-code 0
  "Exit code to return from mocked trafilatura CLI.")

(defun sem-mock-trafilatura-success (output)
  "Setup trafilatura mock to return OUTPUT on success."
  (setq sem-mock-trafilatura-output output)
  (setq sem-mock-trafilatura-exit-code 0)
  (advice-add 'call-process :override #'sem-mock--call-process-mock))

(defun sem-mock-trafilatura-failure (exit-code)
  "Setup trafilatura mock to simulate EXIT-CODE failure."
  (setq sem-mock-trafilatura-output "")
  (setq sem-mock-trafilatura-exit-code exit-code)
  (advice-add 'call-process :override #'sem-mock--call-process-mock))

(defun sem-mock--call-process-mock (command &rest args)
  "Mock implementation of call-process for trafilatura.
Intercepts calls to 'trafilatura' and returns mocked output.
For non-trafilatura calls, passes through to original call-process."
  (if (string= command "trafilatura")
      (let ((buffer (nth 1 args)))
        (when (bufferp buffer)
          (with-current-buffer buffer
            (insert sem-mock-trafilatura-output)))
        sem-mock-trafilatura-exit-code)
    (apply #'call-process--original command args)))

(defun sem-mock-trafilatura-reset ()
  "Reset trafilatura mocks to original behavior."
  (setq sem-mock-trafilatura-output nil)
  (setq sem-mock-trafilatura-exit-code 0)
  (advice-remove 'call-process #'sem-mock--call-process-mock))

;;; Org-Roam Mocks

(defvar sem-mock-org-roam-db-result nil
  "Result to return from mocked org-roam-db-query.")

(defun sem-mock-org-roam-db-query (result)
  "Setup org-roam-db-query mock to return RESULT."
  (setq sem-mock-org-roam-db-result result)
  (advice-add 'org-roam-db-query :override #'sem-mock--org-roam-db-query-mock))

(defun sem-mock--org-roam-db-query-mock (_query &rest _args)
  "Mock implementation of org-roam-db-query."
  sem-mock-org-roam-db-result)

(defun sem-mock-org-roam-reset ()
  "Reset org-roam mocks to original behavior."
  (setq sem-mock-org-roam-db-result nil)
  (advice-remove 'org-roam-db-query #'sem-mock--org-roam-db-query-mock))

;;; Utility Functions

(defun sem-mock-reset-all ()
  "Reset all mocks to original behavior."
  (sem-mock-gptel-reset)
  (sem-mock-trafilatura-reset)
  (sem-mock-org-roam-reset))

(defun sem-mock-temp-file (content)
  "Create a temporary file with CONTENT.
Returns the file path. Caller is responsible for cleanup."
  (let ((tmp-file (make-temp-file "sem-test-")))
    (with-temp-file tmp-file (insert content))
    tmp-file))

(defun sem-mock-cleanup-temp-file (file)
  "Cleanup temporary FILE if it exists."
  (when (and file (file-exists-p file))
    (delete-file file)))

(defun sem-mock-setup-test-data-paths ()
  "Redirect core and RSS runtime file paths to a temporary directory.
Returns a plist snapshot used by `sem-mock-teardown-test-data-paths'.
Tests must never write to the real /data volume used by the daemon."
  (let* ((dir (make-temp-file "sem-test-data-" t))
         (tracked-vars
          '(sem-core-log-file
            sem-core-errors-file
            sem-core-cursor-file
            sem-core-retries-file
            sem-core-inbox-file
            sem-core-cron-guard-dir
            sem-rss-dir
            sem-rss-archive-dir
            sem-rss-feeds-file
            sem-rss-feeds-cache-file))
         (snapshot
          (mapcar (lambda (sym)
                    (cons sym (if (boundp sym) (symbol-value sym) :unbound)))
                  tracked-vars)))
    (setq sem-core-log-file (expand-file-name "sem-log.org" dir))
    (setq sem-core-errors-file (expand-file-name "errors.org" dir))
    (setq sem-core-cursor-file (expand-file-name ".sem-cursor.el" dir))
    (setq sem-core-retries-file (expand-file-name ".sem-retries.el" dir))
    (setq sem-core-inbox-file (expand-file-name "inbox-mobile.org" dir))
    (setq sem-core-cron-guard-dir (expand-file-name "cron-guards" dir))
    (setq sem-rss-dir (expand-file-name "rss" dir))
    (setq sem-rss-archive-dir (expand-file-name "rss-archive" dir))
    (setq sem-rss-feeds-file (expand-file-name "feeds.org" dir))
    (setq sem-rss-feeds-cache-file (expand-file-name ".sem-feeds-cache.el" dir))
    (list :dir dir :snapshot snapshot)))

(defun sem-mock-teardown-test-data-paths (state)
  "Restore runtime file path variables and clean temporary files from STATE."
  (let ((dir (plist-get state :dir))
        (snapshot (plist-get state :snapshot)))
    (dolist (entry snapshot)
      (if (eq (cdr entry) :unbound)
          (makunbound (car entry))
        (set (car entry) (cdr entry))))
    (when (and (stringp dir) (file-directory-p dir))
      (delete-directory dir t))))

(provide 'sem-mock)
;;; sem-mock.el ends here
