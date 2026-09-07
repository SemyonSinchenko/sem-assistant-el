;;; sem-router.el --- Inbox routing and cursor tracking -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; This module parses headlines from inbox-mobile.org and routes them
;; to the appropriate handler (url-capture, deterministic journal, or LLM task generation).
;; It also manages cursor tracking via content hashes.
;;
;; URL contract: task output written to tasks files is operator-facing and
;; uses defanged URL forms via `sem-security-sanitize-urls`.

;;; Code:

(require 'org)
(require 'json)
(require 'cl-lib)
(require 'sem-core)
(require 'sem-prompts)
(require 'sem-time)

;;; Constants

(defconst sem-router-inbox-file "/data/inbox-mobile.org"
  "Path to the inbox file to process.")

(defconst sem-router-tasks-file "/data/tasks.org"
  "Path to the tasks file where processed @task headlines are written.")

(defconst sem-router-journal-file "/data/journal.org"
  "Path to the journal file where processed :journal: headlines are written.")

(defconst sem-router-task-tags '("work" "family" "routine" "opensource")
  "Allowed tags for task headlines. Must be one of these values.")

(defvar sem-router--task-api-max-retries 3
  "Default maximum API-failure retries for task LLM requests.
Can be overridden by environment variable `SEM_TASK_API_MAX_RETRIES'.")

(defconst sem-router-message-hash-prefix-length 8
  "Number of SHA-256 characters used in runtime message item identifiers.
This short hash prefix balances operator readability with correlation safety.")

(defun sem-router--task-api-max-retries ()
  "Return effective max retries for task LLM API failures.
Reads `SEM_TASK_API_MAX_RETRIES' at call time and falls back to
`sem-router--task-api-max-retries' when unset/invalid."
  (let* ((raw (getenv "SEM_TASK_API_MAX_RETRIES"))
         (parsed (and raw (string-match-p "^[0-9]+$" raw)
                      (string-to-number raw))))
    (if (and (integerp parsed) (> parsed 0))
        parsed
      sem-router--task-api-max-retries)))

(defun sem-router--output-language ()
  "Return effective OUTPUT_LANGUAGE with deterministic English fallback.
Returns `English' when the environment variable is unset or empty."
  (let ((output-language (getenv "OUTPUT_LANGUAGE")))
    (if (or (null output-language) (string-empty-p output-language))
        "English"
      output-language)))

(defun sem-router--hash-prefix (hash)
  "Return a short deterministic HASH prefix for runtime diagnostics."
  (let* ((safe-hash (or hash "unknown"))
         (prefix-len sem-router-message-hash-prefix-length))
    (if (>= (length safe-hash) prefix-len)
        (substring safe-hash 0 prefix-len)
      safe-hash)))

(defun sem-router--runtime-message (action status &optional metadata)
  "Emit a metadata-only runtime message for ACTION and STATUS.
METADATA is an alist of string key/value pairs included as key=value fields."
  (let* ((fields
          (delq nil
                (mapcar (lambda (entry)
                          (let ((key (car entry))
                                (value (cdr entry)))
                            (when (and key value)
                              (format "%s=%s" key value))))
                        metadata)))
         (suffix (if fields
                     (concat " " (string-join fields " "))
                   "")))
    (message "SEM: module=router action=%s status=%s%s" action status suffix)))

(defun sem-router--runtime-correlation-fields (batch-id hash)
  "Return metadata fields for BATCH-ID and item HASH correlation."
  (list (cons "batch" (or batch-id sem-core--batch-id 0))
        (cons "item" (sem-router--hash-prefix hash))))

;;; Mutex for tasks.org writes

(defvar sem-router--tasks-write-lock nil
  "Boolean flag to serialize concurrent writes to tasks.org.
When non-nil, another callback is currently writing to tasks.org.
Each callback must acquire this lock before writing and release after.
Lock is never held across retries - each attempt acquires/releases independently.")

(defvar sem-router--max-write-retries 10
  "Maximum number of retry attempts for tasks.org write lock.")

(defvar sem-router--write-retry-delay 0.5
  "Delay in seconds between retries for tasks.org write lock.")

(defun sem-router--acquire-tasks-write-lock ()
  "Attempt to acquire the tasks.org write lock.
Returns t if lock acquired, nil if already held."
  (if sem-router--tasks-write-lock
      nil
    (setq sem-router--tasks-write-lock t)
    t))

(defun sem-router--release-tasks-write-lock ()
  "Release the tasks.org write lock.
Always sets the lock to nil."
  (setq sem-router--tasks-write-lock nil))

(defun sem-router--with-tasks-write-lock (headline callback retry-count &optional dlq-callback batch-id)
  "Execute CALLBACK with tasks.org write lock held.
If lock is held, re-schedules with 0.5s delay up to 10 retries.
After 10 retries, routes to DLQ via sem-core-log-error.
HEADLINE is the headline plist for error logging.
RETRY-COUNT is the current retry attempt number.
DLQ-CALLBACK is an optional function called when lock contention hits DLQ.
BATCH-ID is the dispatch batch id used for stale-safe retries."
  (if (sem-router--acquire-tasks-write-lock)
      ;; Lock acquired - execute callback with unwind-protect
      (unwind-protect
          (funcall callback)
        (sem-router--release-tasks-write-lock))
    ;; Lock held - retry or DLQ
    (if (>= retry-count sem-router--max-write-retries)
        ;; Max retries reached - route to DLQ
        (progn
          (sem-router--runtime-message "task-lock" "DLQ"
                                       (append (sem-router--runtime-correlation-fields
                                                batch-id (plist-get headline :hash))
                                               (list (cons "retries" sem-router--max-write-retries))))
          (sem-core-log-error "router" "INBOX-ITEM"
                              (format "Tasks.org write failed after %d retries (lock contention)"
                                      sem-router--max-write-retries)
                              (plist-get headline :title)
                              nil)
          ;; Mark as processed to prevent infinite retry
          (sem-router--mark-processed (plist-get headline :hash))
          (when dlq-callback
            (funcall dlq-callback)))
      ;; Schedule retry
      (sem-router--runtime-message "task-lock" "RETRY"
                                   (append (sem-router--runtime-correlation-fields
                                            batch-id (plist-get headline :hash))
                                           (list (cons "attempt" (1+ retry-count))
                                                 (cons "max" sem-router--max-write-retries))))
      (run-with-timer sem-router--write-retry-delay nil
                      (lambda ()
                        (sem-router--with-tasks-write-lock
                         headline callback (1+ retry-count) dlq-callback batch-id))))))

;;; Headline Parsing

(defun sem-router--extract-headline-body (headline-element)
  "Extract body text from HEADLINE-ELEMENT.
Returns the concatenated text of all non-headline child elements,
or nil if no body content exists. Nested sub-headlines are excluded."
  (let ((contents-begin (org-element-property :contents-begin headline-element))
        (contents-end (org-element-property :contents-end headline-element))
        (body-text nil))
    (when (and contents-begin contents-end (> contents-end contents-begin))
      ;; Extract text between contents-begin and contents-end
      ;; but stop at any nested headline
      (setq body-text
            (save-excursion
              (save-restriction
                (narrow-to-region contents-begin contents-end)
                (goto-char (point-min))
                ;; Skip any nested headlines at the start
                (while (and (not (eobp)) (looking-at "^\\*+"))
                  (forward-line 1))
                ;; If we're not at end, extract the body
                (if (eobp)
                    nil
                  (let ((start (point))
                        (end (point-max)))
                    ;; Find where nested headline starts (if any)
                    (when (re-search-forward "^\\*+" nil t)
                      (setq end (match-beginning 0)))
                    (string-trim (buffer-substring-no-properties start end))))))))
    (if (and body-text (not (string-empty-p body-text)))
        body-text
      nil)))

(defun sem-router--extract-headline-body-raw (headline-element)
  "Extract raw body text from HEADLINE-ELEMENT without trimming.
Returns nil if no body content exists. Nested sub-headlines are excluded."
  (let ((contents-begin (org-element-property :contents-begin headline-element))
        (contents-end (org-element-property :contents-end headline-element))
        (body-text nil))
    (when (and contents-begin contents-end (> contents-end contents-begin))
      (setq body-text
            (save-excursion
              (save-restriction
                (narrow-to-region contents-begin contents-end)
                (goto-char (point-min))
                (while (and (not (eobp)) (looking-at "^\\*+"))
                  (forward-line 1))
                (if (eobp)
                    nil
                  (let ((start (point))
                        (end (point-max)))
                    (when (re-search-forward "^\\*+" nil t)
                      (setq end (match-beginning 0)))
                    (buffer-substring-no-properties start end)))))))
    (if (and body-text (> (length body-text) 0))
        body-text
      nil)))

(defun sem-router--parse-headlines ()
  "Parse all headlines from inbox-mobile.org using org-element.
Returns a list of headline plists with :title, :tags, :body, :link, :point, :hash."
  (cl-block sem-router--parse-headlines
    (unless (file-exists-p sem-router-inbox-file)
      (sem-router--runtime-message "parse" "SKIP" '(("reason" . "missing-inbox")))
      (sem-core-log "router" "INBOX-ITEM" "SKIP" "inbox-mobile.org does not exist")
      (cl-return-from sem-router--parse-headlines nil))

    (sem-router--runtime-message "parse" "START" nil)
    (let ((headlines '()))
      (with-temp-buffer
        (insert-file-contents sem-router-inbox-file)
        (sem-router--runtime-message "parse" "READ"
                                     (list (cons "chars" (point-max))))
        (org-mode)
        (let ((ast (org-element-parse-buffer)))
          (sem-router--runtime-message "parse" "AST"
                                       (list (cons "root" (org-element-type ast))))
          (org-element-map ast 'headline
            (lambda (headline-element)
              (let* ((begin (org-element-property :begin headline-element))
                     (title (org-element-property :raw-value headline-element))
                     (tags (org-element-property :tags headline-element))
                     (body (sem-router--extract-headline-body headline-element))
                     (journal-body (sem-router--extract-headline-body-raw headline-element))
                     (link (when (string-match-p "^https?://" title)
                             (substring-no-properties title)))
                      (tags-str (if tags (string-join tags " ") ""))
                       (body-str (or body ""))
                       (hash (secure-hash 'sha256
                                          (json-encode (vector title tags-str body-str)))))
                (sem-router--runtime-message
                 "parse-item" "OK"
                 (list (cons "item" (sem-router--hash-prefix hash))
                       (cons "tags" (length tags))
                       (cons "has-body" (if body 1 0))
                       (cons "has-link" (if link 1 0))))
                (push (list :title title
                            :tags tags
                            :body body
                            :journal-body journal-body
                            :link link
                            :point begin
                            :hash hash)
                      headlines))))))

      (sem-router--runtime-message "parse" "OK"
                                   (list (cons "count" (length headlines))))
      (nreverse headlines))))

;;; Tag Detection

(defun sem-router--is-link-headline (headline)
  "Check if HEADLINE is a link headline (has @link tag or URL as title).
Returns the URL if it's a link headline, nil otherwise."
  (let ((tags (plist-get headline :tags))
        (link (plist-get headline :link))
        (title (plist-get headline :title)))
    (cond
     ;; Check for @link tag - return link if available, otherwise check title
     ((member "link" tags)
      (or link (when (string-match-p "^https?://" title) title)))
     ;; Check if title is a URL (no @link tag needed)
     ((string-match-p "^https?://" title) title)
     (t nil))))

(defun sem-router--is-task-headline (headline)
  "Check if HEADLINE is a task headline (has @task tag).
Returns non-nil if it's a task headline."
  (member "task" (plist-get headline :tags)))

(defun sem-router--is-journal-headline (headline)
  "Check if HEADLINE is a journal headline (has :journal: tag).
Returns non-nil if it's a journal headline."
  (member "journal" (plist-get headline :tags)))

(defun sem-router--journal-extract-mentions (text)
  "Extract deduplicated mention values from TEXT.
Matches `@[A-Za-z0-9_-]+', strips leading `@', and preserves first-seen order."
  (let ((start 0)
        (seen (make-hash-table :test 'equal))
        (mentions '()))
    (while (and text (string-match "@[A-Za-z0-9_-]+" text start))
      (let* ((token (match-string 0 text))
             (mention (substring token 1)))
        (unless (gethash mention seen)
          (puthash mention t seen)
          (push mention mentions)))
      (setq start (match-end 0)))
    (nreverse mentions)))

(defun sem-router--journal-non-routing-tags (tags)
  "Return TAGS excluding the routing tag `journal'."
  (cl-remove-if (lambda (tag) (string= tag "journal")) (or tags '())))

(defun sem-router--journal-tags-inbox-value (tags)
  "Return formatted `TAGS_INBOX' property value from TAGS.
Returns ":tag1:tag2:" when tags are present, otherwise an empty string."
  (let ((non-routing-tags (sem-router--journal-non-routing-tags tags)))
    (if non-routing-tags
        (format ":%s:" (string-join non-routing-tags ":"))
      "")))

(defun sem-router--journal-heading-exists-p (content heading)
  "Return non-nil when CONTENT contains exact HEADING line."
  (and content
       (string-match-p (format "^%s$" (regexp-quote heading)) content)))

(defun sem-router--journal-next-item-number (content day-heading)
  "Return next numeric `**** N' index for DAY-HEADING within CONTENT."
  (with-temp-buffer
    (insert (or content ""))
    (goto-char (point-min))
    (if (not (re-search-forward (format "^%s$" (regexp-quote day-heading)) nil t))
        1
      (let ((day-start (point))
            (day-end nil)
            (max-number 0))
        (save-excursion
          (goto-char day-start)
          (setq day-end
                (if (re-search-forward "^\\*\\*\\* " nil t)
                    (match-beginning 0)
                  (point-max))))
        (goto-char day-start)
        (while (re-search-forward "^\\*\\*\\*\\* \\([0-9]+\\)$" day-end t)
          (setq max-number (max max-number (string-to-number (match-string 1)))))
        (1+ max-number)))))

;;; Cursor Tracking

(defun sem-router--is-processed (hash)
  "Check if a headline with HASH is already processed."
  (sem-core--is-processed hash))

(defun sem-router--mark-processed (hash)
  "Mark a headline with HASH as processed."
  (sem-core--mark-processed hash))

;;; Routing Logic

(defun sem-router--build-task-llm-prompts (title tags sanitized-body injected-id)
  "Build Pass 1 USER and SYSTEM prompts for task normalization.

TITLE is the headline title string.
TAGS is the headline tag list.
SANITIZED-BODY is optional task body text after security masking.
INJECTED-ID is the pre-generated UUID string to embed verbatim.

Returns a plist with keys :user-prompt and :system-prompt."
  (let* ((output-language (sem-router--output-language))
         (client-timezone (sem-time-client-timezone))
         (current-datetime (sem-time-format-iso-local (current-time)))
         (language-instruction
          (format "OUTPUT LANGUAGE REQUIREMENT: You MUST write the entire response in %s only. Do not use any other language."
                  output-language))
         (rules-text (if (fboundp 'sem-rules-read)
                         (or (sem-rules-read) "")
                       ""))
         (rules-section (if (string-empty-p rules-text)
                            ""
                          (format "\n\n=== USER SCHEDULING RULES ===\n%s\n" rules-text)))
         (system-prompt-base
          (replace-regexp-in-string
           "%%CHEAT_SHEET%%" sem-prompts-org-mode-cheat-sheet
           (replace-regexp-in-string
            "%%RULES%%" rules-section
            sem-prompts-pass1-system-template t t)))
         (system-prompt (concat system-prompt-base "\n\n" language-instruction))
         (user-prompt
          (concat
           (format "Convert this task headline into a structured Org TODO entry:

HEADLINE: * %s %s"
                   title
                   (if tags
                       (format ":%s:" (string-join tags ":"))
                     ""))
           (format "\nCURRENT DATETIME (%s): %s" client-timezone current-datetime)
           (when sanitized-body
             (format "\n\nBODY:\n%s" sanitized-body))
           (format "\n\nUse this EXACT :ID: value in your output: %s
\nGenerate the complete Org TODO entry following the required format above."
                   injected-id))))
    (list :user-prompt user-prompt :system-prompt system-prompt)))

(defun sem-router--rate-limit-p (api-error)
  "Return non-nil when API-ERROR reports an HTTP 429 rate limit.
Delegates to `sem-llm-rate-limit-p'."
  (require 'sem-llm)
  (sem-llm-rate-limit-p api-error))

(defun sem-router--rate-limit-retry-delay (attempt)
  "Return the backoff delay in seconds before rate-limit retry ATTEMPT.
Delegates to `sem-llm-rate-limit-retry-delay'."
  (require 'sem-llm)
  (sem-llm-rate-limit-retry-delay attempt))

(defun sem-router--schedule-task-llm-retry (headline callback batch-id retry-count max-retries)
  "Schedule an in-process delayed retry for a rate-limited task LLM request.

HEADLINE CALLBACK and BATCH-ID describe the pending task dispatch and
RETRY-COUNT MAX-RETRIES the retry accounting.  The delay grows
exponentially with RETRY-COUNT.  The downstream CALLBACK is not invoked
here; it fires when the retried attempt reaches a terminal outcome, so
batch-barrier accounting is unchanged."
  (let* ((delay (sem-router--rate-limit-retry-delay retry-count))
         (title (plist-get headline :title)))
    (sem-core-log "router" "INBOX-ITEM" "RETRY"
                  (format "Task LLM rate limited (429), attempt %d/%d scheduled in %ds: %s"
                          retry-count max-retries delay title)
                  nil)
    (sem-router--runtime-message
     "task-api" "RETRY"
     (append (sem-router--runtime-correlation-fields batch-id (plist-get headline :hash))
             (list (cons "attempt" retry-count)
                   (cons "max" max-retries)
                   (cons "delay-seconds" delay)
                   (cons "reason" "rate-limited"))))
    (run-at-time delay nil
                 (function sem-router--route-to-task-llm)
                 headline callback batch-id)))

(defun sem-router--schedule-url-capture-retry (url callback batch-id hash retry-count)
  "Schedule an in-process delayed retry for a rate-limited URL capture.

URL CALLBACK and BATCH-ID describe the pending URL-capture dispatch,
HASH the inbox headline hash, and RETRY-COUNT the retry accounting.
The delay grows exponentially with RETRY-COUNT.  The downstream
CALLBACK is not invoked here; it fires when the retried attempt
reaches a terminal outcome, so batch-barrier accounting is unchanged."
  (require 'sem-url-capture)
  (let* ((delay (sem-router--rate-limit-retry-delay retry-count))
         (max-retries (sem-router--task-api-max-retries)))
    (sem-core-log "router" "URL-CAPTURE" "RETRY"
                  (format "URL capture rate limited (429), attempt %d/%d scheduled in %ds: %s"
                          retry-count max-retries delay url)
                  nil)
    (sem-router--runtime-message
     "url-callback" "RETRY"
     (append (sem-router--runtime-correlation-fields batch-id hash)
             (list (cons "attempt" retry-count)
                   (cons "max" max-retries)
                   (cons "delay-seconds" delay)
                   (cons "reason" "rate-limited"))))
    (run-at-time delay nil
                 (function sem-url-capture-process)
                 url callback)))

(defun sem-router--task-dispatch-delay (task-index)
  "Return the dispatch stagger delay in seconds for TASK-INDEX (1-based).
Staggers concurrent task LLM dispatches across a batch so simultaneous
requests do not trip upstream provider rate limits.  The base delay is
read from `SEM_TASK_DISPATCH_STAGGER_SECONDS' at call time (default 2
seconds).  The first task dispatches immediately; the delay is capped at
30 seconds.  A non-positive base disables staggering."
  (let* ((raw (getenv "SEM_TASK_DISPATCH_STAGGER_SECONDS"))
         (base (if (and raw (not (string-empty-p raw)))
                   (string-to-number raw)
                 2.0)))
    (if (<= base 0)
        0
      (min (* base (max 0 (1- task-index))) 30.0))))

(defun sem-router--route-to-task-llm (headline callback &optional batch-id)
  "Route a task HEADLINE to LLM for task generation.
CALLBACK is called with (success context).  When the failure is a
transient rate limit (HTTP 429) and retry budget remains, the request is
rescheduled in-process after a backoff delay and CALLBACK is deferred
until the final outcome."
  (cl-block sem-router--route-to-task-llm
    (let ((dispatch-batch-id (or batch-id sem-core--batch-id)))
      (condition-case err
          (let* ((title (plist-get headline :title))
                 (hash (plist-get headline :hash))
                 (tags (plist-get headline :tags))
                 (body (plist-get headline :body))
                 (injected-id (org-id-new))
                 (security-blocks nil)
                 (sanitized-body nil))
            (when body
              (require 'sem-security)
              (condition-case sanitize-err
                  (let ((sanitize-result (sem-security-sanitize-for-llm body)))
                    (setq sanitized-body (car sanitize-result))
                    (setq security-blocks (cadr sanitize-result)))
                (error
                 (sem-core-log "router" "INBOX-ITEM" "DLQ"
                               (format "Security preflight failed, moved to DLQ: %s" title)
                               nil)
                 (sem-core-log-error "security" "INBOX-ITEM"
                                     (error-message-string sanitize-err)
                                     body
                                     nil
                                     (list :priority "[#A]" :tags '("security")))
                 (sem-router--runtime-message
                  "task-preflight" "DLQ"
                  (append (sem-router--runtime-correlation-fields dispatch-batch-id hash)
                          (list (cons "reason" "security-sanitize"))))
                 (sem-core--mark-dlq hash)
                 (when callback
                   (funcall callback t (list :hash hash :title title :batch-id dispatch-batch-id)))
                 (cl-return-from sem-router--route-to-task-llm t))))

            (let* ((prompt-pair (sem-router--build-task-llm-prompts title tags sanitized-body injected-id))
                   (user-prompt (plist-get prompt-pair :user-prompt))
                   (system-prompt (plist-get prompt-pair :system-prompt)))
              (require 'sem-llm)
              (sem-llm-request
               user-prompt system-prompt
               (lambda (response info context)
                 (let* ((headline-hash (plist-get context :hash))
                        (headline-title (plist-get context :title))
                        (injected-uuid (plist-get context :injected-id))
                        (callback-batch-id (plist-get context :batch-id))
                        (stored-security-blocks (plist-get context :security-blocks))
                        (restored-response response)
                        (success nil)
                        (headline-context context)
                        (response-valid nil))
                   (if (/= callback-batch-id sem-core--batch-id)
                       (progn
                         (sem-router--runtime-message
                          "task-callback" "STALE"
                          (append (sem-router--runtime-correlation-fields callback-batch-id headline-hash)
                                  (list (cons "active-batch" sem-core--batch-id))))
                         (sem-core-log "router" "INBOX-ITEM" "SKIP"
                                       (format "Ignoring stale task callback: callback-batch=%d active-batch=%d title=%s"
                                               callback-batch-id sem-core--batch-id headline-title)
                                       nil)
                         (when (fboundp 'sem-core--batch-barrier-check)
                           (sem-core--batch-barrier-check callback-batch-id)))
                     (progn
                       (when (and stored-security-blocks (stringp response))
                         (require 'sem-security)
                         (setq restored-response
                               (sem-security-restore-from-llm response stored-security-blocks)))
                       (cond
                        ((and restored-response (not (string-empty-p restored-response)))
                         (setq response-valid
                               (sem-router--validate-task-response restored-response injected-uuid))
                         (if response-valid
                             (let ((normalized-response
                                    (sem-router--normalize-task-title-lowercase restored-response)))
                               (sem-router--with-tasks-write-lock
                                (plist-get context :headline)
                                (lambda ()
                                  (if (sem-router--write-task-to-file normalized-response
                                                                      (sem-router--temp-file-path callback-batch-id)
                                                                      callback-batch-id)
                                      (progn
                                        (sem-core-log "router" "INBOX-ITEM" "OK"
                                                      (format "Task written to temp file: %s" headline-title)
                                                      nil)
                                        (sem-router--mark-processed headline-hash)
                                        (setq headline-context (plist-put headline-context :security-blocks nil))
                                        (setq success t))
                                    (progn
                                      (sem-core-log-error "router" "INBOX-ITEM"
                                                          "Failed to write task to temp file"
                                                          headline-title
                                                          normalized-response)
                                      (setq success nil)))
                                  (when callback
                                    (funcall callback success headline-context)))
                                0
                                (lambda ()
                                  (when callback
                                    (funcall callback t headline-context)))
                                callback-batch-id))
                           (sem-core-log-error "router" "INBOX-ITEM"
                                               "Malformed LLM output for task (UUID mismatch or missing)"
                                               headline-title
                                               restored-response)
                           (sem-router--runtime-message
                            "task-validate" "FAIL"
                            (sem-router--runtime-correlation-fields callback-batch-id headline-hash))
                           (sem-router--mark-processed headline-hash)
                           (setq headline-context (plist-put headline-context :security-blocks nil))
                           (setq success t)))
                        (t
                         (let* ((api-error (or (plist-get info :error) "Unknown API error"))
                                (max-retries (sem-router--task-api-max-retries))
                                (retry-count (sem-core--increment-retry headline-hash))
                                (rate-limited (sem-router--rate-limit-p api-error))
                                (callback-fired nil))
                           (if (>= retry-count max-retries)
                               (progn
                                 (sem-core-log "router" "INBOX-ITEM" "DLQ"
                                               (format "Task LLM API failure exhausted retries (%d/%d): %s"
                                                       retry-count max-retries headline-title)
                                               nil)
                                 (sem-router--runtime-message
                                  "task-api" "DLQ"
                                  (append (sem-router--runtime-correlation-fields callback-batch-id headline-hash)
                                          (list (cons "attempt" retry-count)
                                                (cons "max" max-retries))))
                                 (sem-core-log-error "router" "INBOX-ITEM"
                                                     (format "Task LLM API terminal failure after %d retries: %s"
                                                             max-retries api-error)
                                                     headline-title
                                                     api-error)
                                 (sem-core--mark-dlq headline-hash)
                                 (setq success t)
                                 (setq callback-fired t))
                             (if rate-limited
                                 (sem-router--schedule-task-llm-retry
                                  headline callback dispatch-batch-id retry-count max-retries)
                               (progn
                                 (sem-core-log "router" "INBOX-ITEM" "RETRY"
                                               (format "Task LLM API failure (attempt %d/%d): %s"
                                                       retry-count max-retries api-error)
                                               nil)
                                 (sem-router--runtime-message
                                  "task-api" "RETRY"
                                  (append (sem-router--runtime-correlation-fields callback-batch-id headline-hash)
                                          (list (cons "attempt" retry-count)
                                                (cons "max" max-retries))))
                                 (setq success nil)
                                 (setq callback-fired t))))
                           (unless response-valid
                             (when (and callback callback-fired)
                               (funcall callback success headline-context))))))))))
               (list :hash hash
                     :title title
                     :headline headline
                     :injected-id injected-id
                     :batch-id dispatch-batch-id
                     :security-blocks security-blocks)
               'weak))
            t)
        (error
         (sem-core-log-error "router" "INBOX-ITEM"
                             (error-message-string err)
                             (plist-get headline :title)
                             nil)
         (sem-router--runtime-message
          "task-route" "FAIL"
          (sem-router--runtime-correlation-fields dispatch-batch-id (plist-get headline :hash)))
         (when callback
           (funcall callback nil
                    (list :hash (plist-get headline :hash)
                          :title (plist-get headline :title))))
         nil)))))

(defun sem-router--validate-task-response (response injected-id)
  "Validate LLM RESPONSE for task processing.

INJECTED-ID is the UUID that was pre-generated and injected into the prompt.
The response must contain this exact ID in the :ID: field.

Checks for required elements:
- :PROPERTIES: drawer
- :ID: field with exact match to INJECTED-ID
- :FILETAGS: field with valid tag

Returns t if valid, nil if malformed or UUID mismatch."
  (when (and response (not (string-empty-p response)) injected-id)
    (with-temp-buffer
      (insert response)
      (goto-char (point-min))
      (let ((has-properties (re-search-forward "^:PROPERTIES:" nil t))
            (has-id nil)
            (id-matches nil)
            (has-filetags (progn
                            (goto-char (point-min))
                            (re-search-forward "^:FILETAGS:" nil t)))
            (valid-tag nil))
        ;; Extract and validate ID using exact string match
        (goto-char (point-min))
        (when (re-search-forward "^:ID:[ \t]*\\([^[:space:]]+\\)" nil t)
          (setq has-id t)
          (let ((extracted-id (match-string 1)))
            ;; Exact string match comparison as per spec
            (setq id-matches (string= extracted-id injected-id))))
        ;; Check for valid tag
        (goto-char (point-min))
        (when (re-search-forward "^:FILETAGS:[ \t]*:\\([[:word:]]+\\):" nil t)
          (let ((tag (match-string 1)))
            (setq valid-tag (member tag sem-router-task-tags))))
        ;; All checks must pass including UUID match
        (and has-properties has-id has-filetags valid-tag id-matches)))))

(defun sem-router--validate-and-normalize-tag (response)
  "Validate and normalize the :FILETAGS: tag in RESPONSE.

If tag is absent or invalid, adds/substitutes :routine:.
Returns the normalized response string."
  (with-temp-buffer
    (insert response)
    (goto-char (point-min))
    (if (re-search-forward "^:FILETAGS:[ \t]*:\\([[:word:]]+\\):" nil t)
        ;; Tag exists - check if valid
        (let ((tag (match-string 1)))
          (if (member tag sem-router-task-tags)
              response
            ;; Invalid tag - substitute with routine (replace entire line)
            (goto-char (point-min))
            (when (re-search-forward "^:FILETAGS:[ \t]*:[^:]+:" nil t)
              (replace-match ":FILETAGS: :routine:"))
            (buffer-string)))
      ;; No tag found - add :routine: before :END:
      (goto-char (point-min))
      (when (re-search-forward "^:PROPERTIES:" nil t)
        (forward-line 1)
        (when (re-search-forward "^:END:" nil t)
          (beginning-of-line)
          (insert ":FILETAGS: :routine:\n")))
      (buffer-string))))

(defun sem-router--normalize-todo-headline (response)
  "Normalize first Org headline in RESPONSE to use canonical TODO form.

Ensures the first headline uses `* TODO <title>` ordering, removing misplaced
`TODO` tokens and priority tokens from the title area. If no headline is found,
returns RESPONSE unchanged."
  (with-temp-buffer
    (insert response)
    (goto-char (point-min))
    (when (re-search-forward "^\\(\\*+\\)[ \t]*\\(.*\\)$" nil t)
      (let* ((line-start (match-beginning 0))
             (line-end (match-end 0))
             (stars (match-string 1))
             (rest (match-string 2))
             (cleaned-title
              (string-trim
               (replace-regexp-in-string
                "[ \t]+" " "
                (replace-regexp-in-string "\\_<TODO\\_>" " " rest))))
             (title (if (string-empty-p cleaned-title)
                        "Task"
                      cleaned-title)))
        (delete-region line-start line-end)
        (goto-char line-start)
        (insert (format "%s TODO %s" stars title))))
    (buffer-string)))

(defun sem-router--normalize-task-title-lowercase (response)
  "Lowercase the first TODO headline title in RESPONSE.

Only the title text after the TODO keyword and optional priority marker is
lowercased. Non-title content remains unchanged."
  (with-temp-buffer
    (insert response)
    (goto-char (point-min))
    (when (re-search-forward
           "^\\(\\*+[ \t]+TODO\\(?:[ \t]+\\[#\\([A-Za-z]\\)\\]\\)?[ \t]+\\)\\(.*\\)$"
           nil t)
      (let ((line-start (match-beginning 0))
            (line-end (match-end 0))
            (headline-prefix (match-string 1))
            (headline-title (match-string 3)))
        (delete-region line-start line-end)
        (goto-char line-start)
        (insert (concat headline-prefix (downcase headline-title)))))
    (buffer-string)))

(defun sem-router--validate-and-normalize-priority (response)
  "Validate and normalize headline priority token in RESPONSE.

If priority is absent, inserts fallback `[#C]`. If priority is invalid,
replaces it with `[#C]`. Returns normalized response string."
  (with-temp-buffer
    (insert response)
    (goto-char (point-min))
    (when (re-search-forward "^\\(\\*+[ \t]+TODO\\)\\(.*\\)$" nil t)
      (let* ((line-start (match-beginning 0))
             (line-end (match-end 0))
             (todo-prefix (match-string 1))
             (headline-rest (match-string 2))
             (scan-start 0)
             (has-a nil)
             (has-b nil)
             (has-c nil)
             normalized-priority
             cleaned-rest)
        (while (string-match "\\[#\\([A-Za-z]\\)\\]" headline-rest scan-start)
          (let ((priority (upcase (match-string 1 headline-rest))))
            (cond
             ((string= priority "A") (setq has-a t))
             ((string= priority "B") (setq has-b t))
             ((string= priority "C") (setq has-c t))))
          (setq scan-start (match-end 0)))

        (setq normalized-priority
              (cond
               (has-a "[#A]")
               (has-b "[#B]")
               (has-c "[#C]")
               (t "[#C]")))

        (setq cleaned-rest
              (string-trim
               (replace-regexp-in-string
                "[ \t]+" " "
                (replace-regexp-in-string "[ \t]*\\[#\\([A-Za-z]\\)\\][ \t]*" " " headline-rest))))

        (delete-region line-start line-end)
        (goto-char line-start)
        (insert
         (if (string-empty-p cleaned-rest)
             (format "%s %s" todo-prefix normalized-priority)
           (format "%s %s %s" todo-prefix normalized-priority cleaned-rest)))))
    (buffer-string)))

(defun sem-router--normalize-scheduled-duration (response)
  "Normalize SCHEDULED duration in RESPONSE when end time is absent.

When SCHEDULED has a start time but no end time, inject a 30-minute end time.
Unsupported or already-ranged SCHEDULED lines are preserved unchanged."
  (with-temp-buffer
    (insert response)
    (goto-char (point-min))
    (when (re-search-forward "^SCHEDULED:[ \t]*<\\([^>]+\\)>" nil t)
      (let ((timestamp-content (match-string 1))
            (line-start (match-beginning 0))
            (line-end (match-end 0)))
        (when (and (not (string-match-p "[0-9]\\{2\\}:[0-9]\\{2\\}-[0-9]\\{2\\}:[0-9]\\{2\\}" timestamp-content))
                   (string-match
                    "^\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)\\(?:[ \t]+\\([A-Za-z]\\{3\\}\\)\\)?[ \t]+\\([0-9]\\{2\\}\\):\\([0-9]\\{2\\}\\)$"
                    timestamp-content))
          (let* ((date-part (match-string 1 timestamp-content))
                 (day-part (match-string 2 timestamp-content))
                 (start-hour (string-to-number (match-string 3 timestamp-content)))
                 (start-minute (string-to-number (match-string 4 timestamp-content)))
                 (year (string-to-number (substring date-part 0 4)))
                 (month (string-to-number (substring date-part 5 7)))
                 (day (string-to-number (substring date-part 8 10)))
                 (start-time (encode-time 0 start-minute start-hour day month year t))
                 (end-time (time-add start-time (seconds-to-time (* 30 60))))
                 (end-hour (format-time-string "%H" end-time t))
                 (end-minute (format-time-string "%M" end-time t))
                 (normalized-content
                  (if day-part
                      (format "%s %s %02d:%02d-%s:%s"
                              date-part day-part start-hour start-minute end-hour end-minute)
                    (format "%s %02d:%02d-%s:%s"
                            date-part start-hour start-minute end-hour end-minute))))
            (delete-region line-start line-end)
            (goto-char line-start)
            (insert (format "SCHEDULED: <%s>" normalized-content))))))
    (buffer-string)))

(defun sem-router--normalize-task-response (response)
  "Apply all task-response normalization rules to RESPONSE.

Normalizes tag, priority, and scheduled duration fallbacks before planner input.
Returns normalized response string."
  (let* ((headline-normalized (sem-router--normalize-todo-headline response))
         (tag-normalized (sem-router--validate-and-normalize-tag headline-normalized))
         (priority-normalized (sem-router--validate-and-normalize-priority tag-normalized))
         (schedule-normalized (sem-router--normalize-scheduled-duration priority-normalized)))
    schedule-normalized))

(defun sem-router--temp-file-path (&optional batch-id)
  "Compute the temp file path for a batch.
BATCH-ID is the batch identifier. Defaults to sem-core--batch-id.
Returns /tmp/data/tasks-tmp-{batch-id}.org"
  (let ((id (or batch-id sem-core--batch-id 0)))
    (format "/tmp/data/tasks-tmp-%d.org" id)))

(defun sem-router--temp-file-batch-id (temp-file)
  "Extract batch id from TEMP-FILE path.
Returns integer batch id or nil when TEMP-FILE is not a batch temp path."
  (when (and (stringp temp-file)
             (string-match "tasks-tmp-\\([0-9]+\\)\\.org\\'" temp-file))
    (string-to-number (match-string 1 temp-file))))

(defun sem-router--write-task-to-file (response &optional temp-file expected-batch-id)
  "Validate and write task RESPONSE to tasks.org or TEMP-FILE.

If TEMP-FILE is provided, writes to that file instead of tasks.org.
When EXPECTED-BATCH-ID is non-nil, TEMP-FILE must match that batch id.
Normalizes tag, priority fallback, and schedule duration fallback.
Creates the target file if it doesn't exist.
Appends the task entry to the file.

Returns t on success, nil on failure."
  (condition-case err
      (let* ((normalized (sem-router--normalize-task-response response))
             (_ (require 'sem-security))
             (sanitized (sem-security-sanitize-urls normalized))
             (target-file (or temp-file sem-router-tasks-file))
             (target-batch-id (and temp-file (sem-router--temp-file-batch-id temp-file))))

        (when (and temp-file expected-batch-id (/= expected-batch-id (or target-batch-id -1)))
          (sem-core-log "router" "INBOX-ITEM" "SKIP"
                        (format "Dropped stale temp write: expected-batch=%d target-file=%s"
                                expected-batch-id temp-file)
                        nil)
          (cl-return-from sem-router--write-task-to-file nil))

        ;; Create file if it doesn't exist
        (unless (file-exists-p target-file)
          (make-directory (file-name-directory target-file) t)
          (with-temp-file target-file
            (unless temp-file
              (insert "* Tasks\n"))))

        ;; Append task to file
        (with-temp-buffer
          (when (file-exists-p target-file)
            (insert-file-contents target-file))
          (goto-char (point-max))
          (insert "\n" sanitized "\n")
          (write-region (point-min) (point-max) target-file nil 'silent))

        t)
    (error
     (sem-core-log-error "router" "INBOX-ITEM"
                         (format "Failed to write task: %s" (error-message-string err))
                         response
                         nil)
     nil)))

(defun sem-router--build-journal-entry (headline ingested-at)
  "Build an intermediate journal entry from HEADLINE and INGESTED-AT.
Signals an error when required headline metadata is missing."
  (let* ((hash (plist-get headline :hash))
         (title (plist-get headline :title))
         (body (or (plist-get headline :journal-body)
                   (plist-get headline :body)
                   ""))
         (tags (plist-get headline :tags))
         (tags-inbox (sem-router--journal-tags-inbox-value tags))
         (mentions (sem-router--journal-extract-mentions body)))
    (unless (and (stringp hash) (not (string-empty-p hash)))
      (error "Journal headline missing hash"))
    (unless (stringp title)
      (error "Journal headline missing title"))
    (list :hash hash
          :title title
          :body body
          :ingested-at ingested-at
          :tags-inbox tags-inbox
          :mentions-raw (string-join mentions ", "))))

(defun sem-router--journal-entry-fragment (entry item-number)
  "Build one journal item fragment from ENTRY using ITEM-NUMBER."
  (let ((body (or (plist-get entry :body) ""))
        (ingested-at (or (plist-get entry :ingested-at) ""))
        (tags-inbox (or (plist-get entry :tags-inbox) ""))
        (mentions-raw (or (plist-get entry :mentions-raw) "")))
    (concat (format "**** %d\n" item-number)
            ":PROPERTIES:\n"
            (format ":INGESTED_AT: %s\n" ingested-at)
            (format ":TAGS_INBOX: %s\n" tags-inbox)
            (format ":MENTIONS_RAW: %s\n" mentions-raw)
            ":END:\n\n"
            body
            (unless (string-suffix-p "\n" body)
              "\n"))))

(defun sem-router--journal-build-append-payload (entries ingest-time existing-content)
  "Build one append payload for ENTRIES at INGEST-TIME.
Uses EXISTING-CONTENT to add missing date-tree headings once and continue day numbering."
  (let* ((year (format-time-string "%Y" ingest-time))
         (month (format-time-string "%Y-%m" ingest-time))
         (day (format-time-string "%Y-%m-%d" ingest-time))
         (year-heading (format "* %s" year))
         (month-heading (format "** %s" month))
         (day-heading (format "*** %s" day))
         (year-exists (sem-router--journal-heading-exists-p existing-content year-heading))
         (month-exists (sem-router--journal-heading-exists-p existing-content month-heading))
         (day-exists (sem-router--journal-heading-exists-p existing-content day-heading))
         (next-number (sem-router--journal-next-item-number existing-content day-heading))
         (payload ""))
    (when (and (not (string-empty-p (or existing-content "")))
               (not (string-suffix-p "\n" existing-content)))
      (setq payload (concat payload "\n")))
    (unless year-exists
      (setq payload (concat payload year-heading "\n")))
    (unless month-exists
      (setq payload (concat payload month-heading "\n")))
    (unless day-exists
      (setq payload (concat payload day-heading "\n")))
    (dolist (entry entries)
      (setq payload
            (concat payload (sem-router--journal-entry-fragment entry next-number)))
      (setq next-number (1+ next-number)))
    payload))

(defun sem-router--journal-atomic-append (append-payload)
  "Append APPEND-PAYLOAD to `sem-router-journal-file' using temp-file + rename.
Returns t on success, nil on error."
  (condition-case err
      (let* ((journal-file sem-router-journal-file)
             (tmp-file (concat journal-file ".tmp"))
             (existing-content ""))
        (when (file-exists-p journal-file)
          (with-temp-buffer
            (insert-file-contents journal-file)
            (setq existing-content (buffer-string))))
        (make-directory (file-name-directory journal-file) t)
        (with-temp-file tmp-file
          (insert existing-content)
          (insert append-payload))
        (rename-file tmp-file journal-file t)
        t)
    (error
     (sem-core-log-error "router" "INBOX-ITEM"
                         (format "Journal append failed: %s" (error-message-string err))
                         append-payload
                         nil)
     nil)))

(defun sem-router--journal-pending-headlines (headlines)
  "Return unprocessed journal HEADLINES from HEADLINES."
  (cl-remove-if-not
   (lambda (headline)
     (and (sem-router--is-journal-headline headline)
          (not (sem-router--is-processed (plist-get headline :hash)))))
   headlines))

(defun sem-router--process-journal-batch (headlines dispatch-batch-id)
  "Process all pending journal HEADLINES for DISPATCH-BATCH-ID in one batch.
Returns plist with :processed count and :failed non-nil on batch failure."
  (cl-block sem-router--process-journal-batch
    (condition-case err
        (let ((journal-headlines (sem-router--journal-pending-headlines headlines)))
          (if (null journal-headlines)
              (cl-return-from sem-router--process-journal-batch
                (list :processed 0 :failed nil :attempted 0))
            (let* ((ingest-time (current-time))
                   (ingested-at (sem-time-format-iso-local ingest-time))
                   (existing-content (if (file-exists-p sem-router-journal-file)
                                         (with-temp-buffer
                                           (insert-file-contents sem-router-journal-file)
                                           (buffer-string))
                                       ""))
                   (entries '()))
              (sem-router--runtime-message
               "journal-batch" "START"
               (list (cons "batch" dispatch-batch-id)
                     (cons "count" (length journal-headlines))))
              (condition-case transform-err
                  (dolist (headline journal-headlines)
                    (push (sem-router--build-journal-entry headline ingested-at) entries))
                (error
                 (sem-router--runtime-message
                  "journal-batch" "RETRY"
                  (list (cons "batch" dispatch-batch-id)
                        (cons "reason" "transform-failed")))
                 (sem-core-log "router" "INBOX-ITEM" "RETRY"
                               (format "Journal batch transform failed: %s"
                                       (error-message-string transform-err))
                               nil)
                 (sem-core-log-error "router" "INBOX-ITEM"
                                     (error-message-string transform-err)
                                     "journal-batch-transform"
                                     nil)
                 (cl-return-from sem-router--process-journal-batch
                   (list :processed 0 :failed t :attempted (length journal-headlines)))))

              (let* ((prepared-entries (nreverse entries))
                     (append-payload (sem-router--journal-build-append-payload
                                      prepared-entries ingest-time existing-content)))
                (if (sem-router--journal-atomic-append append-payload)
                    (progn
                      (dolist (entry prepared-entries)
                        (sem-router--mark-processed (plist-get entry :hash)))
                      (sem-core-log "router" "INBOX-ITEM" "OK"
                                    (format "Journal batch appended entries=%d"
                                            (length prepared-entries))
                                    nil)
                      (sem-router--runtime-message
                       "journal-batch" "OK"
                       (list (cons "batch" dispatch-batch-id)
                             (cons "count" (length prepared-entries))))
                      (list :processed (length prepared-entries)
                            :failed nil
                            :attempted (length prepared-entries)))
                  (progn
                    (sem-router--runtime-message
                     "journal-batch" "FAIL"
                     (list (cons "batch" dispatch-batch-id)
                           (cons "reason" "append-failed")))
                    (sem-core-log "router" "INBOX-ITEM" "FAIL"
                                  "Journal batch append failed"
                                  nil)
                    (list :processed 0 :failed t :attempted (length journal-headlines))))))))
      (error
       (sem-core-log-error "router" "INBOX-ITEM"
                           (error-message-string err)
                           "journal-batch"
                           nil)
       (sem-router--runtime-message
        "journal-batch" "FAIL"
        (list (cons "batch" dispatch-batch-id)
              (cons "reason" "unexpected-error")))
       (list :processed 0 :failed t :attempted 0)))))

;;; Main Processing Entry Point

(defun sem-router-process-inbox (&optional batch-id)
  "Process all unprocessed headlines from inbox-mobile.org.
Routes each headline to the appropriate handler:
 - :journal: headlines -> deterministic batch journal append path
 - @link or URL headlines -> sem-url-capture-process
 - @task headlines -> LLM task generation
 - Unknown tags -> skip with log

This is called by sem-core-process-inbox."
  (cl-block sem-router-process-inbox
    (condition-case err
        (let* ((headlines (sem-router--parse-headlines))
               (dispatch-batch-id (or batch-id sem-core--batch-id))
               (processed-count 0)
               (skipped-count 0)
               (task-dispatch-index 0)
               (journal-result (sem-router--process-journal-batch headlines dispatch-batch-id))
               (journal-processed (or (plist-get journal-result :processed) 0))
               (journal-failed (plist-get journal-result :failed))
               (non-journal-headlines (cl-remove-if #'sem-router--is-journal-headline headlines)))

          (sem-router--runtime-message "process" "START"
                                       (list (cons "batch" dispatch-batch-id)
                                             (cons "total" (length headlines))))
          (unless headlines
            (sem-router--runtime-message "process" "SKIP"
                                         (list (cons "batch" dispatch-batch-id)
                                               (cons "reason" "empty")))
            (cl-return-from sem-router-process-inbox nil))

          (sem-router--runtime-message "process" "RUN"
                                       (list (cons "batch" dispatch-batch-id)))

          (setq processed-count (+ processed-count journal-processed))

          (dolist (headline non-journal-headlines)
            (let ((hash (plist-get headline :hash))
                  (title (plist-get headline :title)))
              (sem-router--runtime-message
               "item" "SEEN"
               (append
                (sem-router--runtime-correlation-fields dispatch-batch-id hash)
                (list (cons "tags" (length (or (plist-get headline :tags) '()))))))
              (if (sem-router--is-processed hash)
                  (progn
                    (sem-router--runtime-message "item" "SKIP"
                                                 (append
                                                  (sem-router--runtime-correlation-fields dispatch-batch-id hash)
                                                  (list (cons "reason" "already-processed"))))
                    (setq skipped-count (1+ skipped-count)))
                ;; Route based on tag/type
                (let ((url (sem-router--is-link-headline headline)))
                  (cond
                   ;; Link headline -> URL capture (async)
                   (url
                    (sem-router--runtime-message "route" "URL"
                                                 (sem-router--runtime-correlation-fields dispatch-batch-id hash))
                    (setq sem-core--pending-callbacks (1+ sem-core--pending-callbacks))
                    (sem-url-capture-process
                     url
                     (lambda (filepath context)
                       "Callback for async URL capture.
Handles success, retry, and DLQ escalation."
                       (let ((deferred nil))
                         (if (/= dispatch-batch-id sem-core--batch-id)
                             (progn
                              (sem-router--runtime-message
                               "url-callback" "STALE"
                               (append (sem-router--runtime-correlation-fields dispatch-batch-id hash)
                                       (list (cons "active-batch" sem-core--batch-id))))
                              (sem-core-log "router" "INBOX-ITEM" "SKIP"
                                            (format "Ignoring stale URL callback: callback-batch=%d active-batch=%d url=%s"
                                                    dispatch-batch-id sem-core--batch-id url)
                                            nil)
                              (when (fboundp 'sem-core--batch-barrier-check)
                                (sem-core--batch-barrier-check dispatch-batch-id)))
                          (if filepath
                             (progn
                               (sem-core--clear-retry hash)
                               (sem-router--mark-processed hash)
                               (setq processed-count (1+ processed-count))
                               (sem-router--runtime-message "url-callback" "OK"
                                                            (sem-router--runtime-correlation-fields dispatch-batch-id hash))
                               (when (fboundp 'sem-core--batch-barrier-check)
                                 (sem-core--batch-barrier-check dispatch-batch-id)))
                           (let ((failure-kind (plist-get context :failure-kind)))
                             (if (eq failure-kind 'security-malformed)
                                 (progn
                                   (sem-core-log "router" "URL-CAPTURE" "DLQ"
                                                 (format "URL capture security preflight failed, moved to DLQ: %s" url)
                                                 nil)
                                   (sem-core--mark-dlq hash title nil)
                                   (sem-router--runtime-message "url-callback" "DLQ"
                                                                (append (sem-router--runtime-correlation-fields dispatch-batch-id hash)
                                                                        (list (cons "reason" "security-malformed")))))
                               (let ((retry-count (sem-core--increment-retry hash)))
                                 (if (>= retry-count 3)
                                     (progn
                                       (sem-core--mark-dlq hash title nil)
                                       (sem-router--runtime-message "url-callback" "DLQ"
                                                                    (append (sem-router--runtime-correlation-fields dispatch-batch-id hash)
                                                                            (list (cons "reason" "retry-exhausted")
                                                                                  (cons "attempt" retry-count)
                                                                                  (cons "max" 3)))))
                                   (if (eq failure-kind 'rate-limited)
                                       (progn
                                         (setq deferred t)
                                         (sem-router--schedule-url-capture-retry
                                          url callback dispatch-batch-id hash retry-count))
                                     (progn
                                       (when (eq failure-kind 'timeout)
                                         (sem-core-log "router" "URL-CAPTURE" "FAIL"
                                                       (format "URL capture timeout (attempt %d/3): %s"
                                                               retry-count url)
                                                       nil))
                                       (sem-router--runtime-message "url-callback" "RETRY"
                                                                    (append (sem-router--runtime-correlation-fields dispatch-batch-id hash)
                                                                            (list (cons "attempt" retry-count)
                                                                                  (cons "max" 3))))))))
                             (when (and (not deferred) (fboundp 'sem-core--batch-barrier-check))
                               (sem-core--batch-barrier-check dispatch-batch-id))))))))))
                    ;; Task headline -> LLM task generation (async)
                   ((sem-router--is-task-headline headline)
                    (sem-router--runtime-message "route" "TASK"
                                                 (sem-router--runtime-correlation-fields dispatch-batch-id hash))
                    (setq sem-core--pending-callbacks (1+ sem-core--pending-callbacks))
                    (setq task-dispatch-index (1+ task-dispatch-index))
                    (let ((completion-callback
                           (lambda (success context)
                             "Callback for async task LLM processing."
                             (let ((callback-batch-id (or (plist-get context :batch-id) dispatch-batch-id)))
                               (if (/= callback-batch-id sem-core--batch-id)
                                   (progn
                                     (sem-router--runtime-message
                                      "task-callback" "STALE"
                                      (append (sem-router--runtime-correlation-fields callback-batch-id hash)
                                              (list (cons "active-batch" sem-core--batch-id))))
                                     (sem-core-log "router" "INBOX-ITEM" "SKIP"
                                                   (format "Ignoring stale task completion callback: callback-batch=%d active-batch=%d title=%s"
                                                           callback-batch-id sem-core--batch-id
                                                           (plist-get context :title))
                                                   nil))
                                 (if success
                                     (sem-router--runtime-message "task-callback" "OK"
                                                                  (sem-router--runtime-correlation-fields
                                                                   callback-batch-id hash))
                                   (sem-router--runtime-message "task-callback" "FAIL"
                                                                (sem-router--runtime-correlation-fields
                                                                 callback-batch-id hash))))
                               (when (fboundp 'sem-core--batch-barrier-check)
                                 (sem-core--batch-barrier-check callback-batch-id)))))
                          (stagger (sem-router--task-dispatch-delay
                                    task-dispatch-index)))
                      (if (<= stagger 0)
                          (sem-router--route-to-task-llm
                           headline completion-callback dispatch-batch-id)
                        (run-at-time
                         stagger nil
                         (function sem-router--route-to-task-llm)
                         headline completion-callback dispatch-batch-id)))
                    (setq processed-count (1+ processed-count)))
                    ;; Unknown - skip
                    (t
                     (sem-router--runtime-message "route" "SKIP"
                                                  (append (sem-router--runtime-correlation-fields dispatch-batch-id hash)
                                                          (list (cons "reason" "no-rule"))))
                     (sem-core-log "router" "INBOX-ITEM" "SKIP"
                                   (format "Unknown tag, skipping: %s" title)
                                   nil)
                     (setq skipped-count (1+ skipped-count))
                      ;; Mark as processed to avoid infinite loop
                      (sem-router--mark-processed hash)))))))

          (when journal-failed
            (sem-core-log "router" "INBOX-ITEM" "RETRY"
                          "Journal batch failed; journal entries left unprocessed"
                          nil))

          (sem-core-log "router" "INBOX-ITEM" "OK"
                        (format "Processed=%d, Skipped=%d"
                                processed-count skipped-count)
                        nil)
          (sem-router--runtime-message "process" "OK"
                                       (list (cons "batch" dispatch-batch-id)
                                             (cons "processed" processed-count)
                                             (cons "skipped" skipped-count))))
      (error
       (sem-core-log-error "router" "INBOX-ITEM"
                           (error-message-string err)
                           nil
                           nil)
       (sem-router--runtime-message "process" "FAIL"
                                    (list (cons "batch" sem-core--batch-id)))))))

(provide 'sem-router)
;;; sem-router.el ends here
