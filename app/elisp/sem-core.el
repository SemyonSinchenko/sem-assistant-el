;;; sem-core.el --- Core logging and inbox processing functions -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; This module provides the core logging infrastructure and inbox processing
;; entry points for the SEM Assistant daemon.
;;
;; All other modules depend on this module being loaded first.

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'json)
(require 'sem-time)

;;; Constants

(defconst sem-core-log-file "/data/sem-log.org"
  "Path to the structured log file.")

(defconst sem-core-errors-file "/data/errors.org"
  "Path to the errors Dead Letter Queue file.")

(defconst sem-core-cursor-file "/data/.sem-cursor.el"
  "Path to the cursor tracking file for processed headlines.")

(defconst sem-core-retries-file "/data/.sem-retries.el"
  "Path to the retry tracking file for failed LLM requests.")

(defconst sem-core-inbox-file "/data/inbox-mobile.org"
  "Path to the inbox file synced by Orgzly.")

(defvar sem-core-cron-guard-dir (format "/tmp/data/cron-guards/%s" (emacs-pid))
  "Directory containing per-job cron overlap guard lock files.")

(defvar sem-core-cron-guard-default-policy 'skip
  "Default overlap policy for cron-guarded jobs.
Supported values are `skip' and `serialize'.")

(defvar sem-core-cron-guard-default-stale-ttl-seconds 3600
  "Default stale lock TTL in seconds for cron-guarded jobs.")

(defvar sem-core-cron-guard-serialize-poll-seconds 2
  "Polling interval in seconds used by `serialize' overlap policy.")

(defvar sem-core-cron-guard-max-serialize-wait-seconds 5
  "Maximum wait time in seconds for `serialize' overlap policy.")

(defconst sem-core-cron-guard-job-config
  '(("inbox-processing" :policy skip :stale-ttl-seconds 5400)
    ("inbox-purge" :policy skip :stale-ttl-seconds 5400)
    ("rss-morning-digest" :policy skip :stale-ttl-seconds 7200)
    ("rss-morning-archive" :policy skip :stale-ttl-seconds 900)
    ("daily-plan" :policy skip :stale-ttl-seconds 1800)
    ("git-sync-org-roam" :policy serialize :stale-ttl-seconds 3600)
    ("git-sync-org-roam-prepull" :policy skip :stale-ttl-seconds 900))
  "Per-job cron overlap policy and stale-lock TTL settings.")

(defun sem-core--cron-guard-config (guard-key)
  "Return effective overlap guard config plist for GUARD-KEY." 
  (let ((configured (cdr (assoc guard-key sem-core-cron-guard-job-config))))
    (list :policy (or (plist-get configured :policy)
                      sem-core-cron-guard-default-policy)
          :stale-ttl-seconds (or (plist-get configured :stale-ttl-seconds)
                                 sem-core-cron-guard-default-stale-ttl-seconds))))

(defun sem-core--cron-guard-lock-file (guard-key)
  "Return lock file path for GUARD-KEY."
  (expand-file-name (format "%s.lock" guard-key) sem-core-cron-guard-dir))

(defun sem-core--cron-guard-holder-metadata (guard-key policy)
  "Build holder metadata alist for GUARD-KEY and POLICY."
  (let* ((now (float-time))
         (pid (emacs-pid))
         (host (system-name))
         (nonce (secure-hash 'sha256 (format "%s|%s|%s|%s" guard-key pid now (random))))
         (holder-id (format "%s:%s:%s" host pid nonce)))
    `((guard-key . ,guard-key)
      (policy . ,(symbol-name policy))
      (pid . ,pid)
      (host . ,host)
      (holder-id . ,holder-id)
      (created-at . ,now)
      (updated-at . ,now))))

(defun sem-core--cron-guard-write-lock-atomic (lock-file metadata &optional must-be-new)
  "Write METADATA to LOCK-FILE atomically.
When MUST-BE-NEW is non-nil, fail if LOCK-FILE already exists."
  (let* ((tmp-file (concat lock-file ".tmp"))
         (serialized (concat (prin1-to-string metadata) "\n")))
    (make-directory (file-name-directory lock-file) t)
    (with-temp-file tmp-file
      (insert serialized))
    (if must-be-new
        (condition-case _err
            (progn
              (write-region serialized nil lock-file nil 'silent nil 'excl)
              (delete-file tmp-file)
              t)
          (file-already-exists
           (ignore-errors (delete-file tmp-file))
           nil)
          (error
           (ignore-errors (delete-file tmp-file))
           nil))
      (condition-case _err
          (progn
            (rename-file tmp-file lock-file t)
            t)
        (error
         (ignore-errors (delete-file tmp-file))
         nil)))))

(defun sem-core--cron-guard-read-lock (lock-file)
  "Read and return lock metadata alist from LOCK-FILE, or nil." 
  (when (file-exists-p lock-file)
    (with-temp-buffer
      (condition-case _err
          (progn
            (insert-file-contents lock-file)
            (goto-char (point-min))
            (let ((content (read (current-buffer))))
              (when (listp content)
                content)))
        (error nil)))))

(defun sem-core--cron-guard-lock-age (metadata lock-file now-float)
  "Return lock age evaluation plist for METADATA at LOCK-FILE.
NOW-FLOAT is the current timestamp as float seconds." 
  (let ((created-at (cdr (assoc 'created-at metadata))))
    (cond
     ((numberp created-at)
      (if (< created-at now-float)
          (list :age-seconds (- now-float created-at)
                :uncertain nil
                :reason "from-created-at")
        (list :age-seconds nil
              :uncertain t
              :reason "future-created-at")))
     (t
      (let* ((attrs (ignore-errors (file-attributes lock-file 'string)))
             (mtime (and (consp attrs) (nth 5 attrs))))
        (if (and (listp mtime) (>= now-float (float-time mtime)))
            (list :age-seconds (- now-float (float-time mtime))
                  :uncertain nil
                  :reason "from-mtime")
          (list :age-seconds nil
                :uncertain t
                :reason "mtime-unavailable")))))))

(defun sem-core--cron-guard-holder-liveness (metadata)
  "Return holder liveness plist derived from METADATA." 
  (let ((pid (cdr (assoc 'pid metadata)))
        (host (cdr (assoc 'host metadata))))
    (cond
     ((not (and (integerp pid) (> pid 0)))
      (list :alive nil :certain nil :reason "missing-pid"))
     ((and (stringp host) (not (string= host (system-name))))
      (list :alive nil :certain nil :reason "foreign-host"))
     (t
      (condition-case _err
          (progn
            (signal-process pid 0)
            (list :alive t :certain t :reason "holder-process-alive"))
        (error
         (list :alive nil :certain t :reason "holder-process-dead")))))))

(defun sem-core--cron-guard-log (module event-type status payload)
  "Emit structured guard log with MODULE, EVENT-TYPE, STATUS, and PAYLOAD." 
  (condition-case _err
      (sem-core-log module event-type status (json-encode payload) nil)
    (error nil)))

(defun sem-core--cron-guard-release (lock-file holder-id module event-type guard-key policy)
  "Release LOCK-FILE for HOLDER-ID.
Logs release outcome using MODULE, EVENT-TYPE, GUARD-KEY, and POLICY." 
  (let ((metadata (sem-core--cron-guard-read-lock lock-file)))
    (if (and metadata
             (string= holder-id (or (cdr (assoc 'holder-id metadata)) "")))
        (condition-case _err
            (progn
              (delete-file lock-file)
              (sem-core--cron-guard-log
               module event-type "OK"
               `((guard_action . "release")
                 (guard_key . ,guard-key)
                 (policy . ,(symbol-name policy))
                 (decision . "released")))
              t)
          (error
           (sem-core--cron-guard-log
            module event-type "FAIL"
            `((guard_action . "release")
              (guard_key . ,guard-key)
              (policy . ,(symbol-name policy))
              (decision . "release_failed")))
           nil))
      (progn
        (sem-core--cron-guard-log
         module event-type "SKIP"
         `((guard_action . "release")
           (guard_key . ,guard-key)
           (policy . ,(symbol-name policy))
           (decision . "release_skipped_not_holder")))
        nil))))

(defun sem-core--cron-guard-acquire (guard-key module event-type policy stale-ttl-seconds)
  "Attempt to acquire overlap guard for GUARD-KEY.
Returns plist with :decision, :holder-id, :age-seconds, and :reason."
  (let* ((lock-file (sem-core--cron-guard-lock-file guard-key))
         (holder (sem-core--cron-guard-holder-metadata guard-key policy))
         (holder-id (cdr (assoc 'holder-id holder)))
         (now-float (float-time)))
    (if (condition-case _err
            (progn
              (make-directory sem-core-cron-guard-dir t)
              t)
          (error nil))
        (if (sem-core--cron-guard-write-lock-atomic lock-file holder t)
            (list :decision 'acquire
                  :holder-id holder-id
                  :age-seconds 0
                  :reason "fresh-lock")
          (let ((metadata (sem-core--cron-guard-read-lock lock-file)))
            (if (null metadata)
                (list :decision 'skip
                      :holder-id nil
                      :age-seconds nil
                      :reason "lock-unreadable-fail-closed")
              (let* ((age-info (sem-core--cron-guard-lock-age metadata lock-file now-float))
                     (age-seconds (plist-get age-info :age-seconds))
                     (age-uncertain (plist-get age-info :uncertain))
                     (age-reason (plist-get age-info :reason)))
                (cond
                 (age-uncertain
                  (list :decision 'skip
                        :holder-id nil
                        :age-seconds nil
                        :reason (format "uncertain-age-%s-fail-closed" age-reason)))
                 ((< age-seconds stale-ttl-seconds)
                  (list :decision 'skip
                        :holder-id nil
                        :age-seconds age-seconds
                        :reason "active-lock"))
                 (t
                  (sem-core--cron-guard-log
                   module event-type "OK"
                   `((guard_action . "reclaim_attempt")
                     (guard_key . ,guard-key)
                     (policy . ,(symbol-name policy))
                     (lock_age_seconds . ,age-seconds)
                     (reason . "stale-lock-candidate")))
                  (let* ((liveness (sem-core--cron-guard-holder-liveness metadata))
                         (alive (plist-get liveness :alive))
                         (certain (plist-get liveness :certain))
                         (liveness-reason (plist-get liveness :reason)))
                    (cond
                     (alive
                      (list :decision 'skip
                            :holder-id nil
                            :age-seconds age-seconds
                            :reason "stale-candidate-holder-still-alive"))
                     ((not certain)
                      (list :decision 'skip
                            :holder-id nil
                            :age-seconds age-seconds
                            :reason (format "stale-candidate-liveness-uncertain-%s" liveness-reason)))
                     ((not (sem-core--cron-guard-write-lock-atomic lock-file holder nil))
                      (list :decision 'skip
                            :holder-id nil
                            :age-seconds age-seconds
                            :reason "stale-reclaim-write-failed"))
                     (t
                      (let* ((post-write (sem-core--cron-guard-read-lock lock-file))
                             (post-holder-id (cdr (assoc 'holder-id post-write))))
                        (if (and (stringp post-holder-id)
                                 (string= post-holder-id holder-id))
                            (list :decision 'reclaim
                                  :holder-id holder-id
                                  :age-seconds age-seconds
                                  :reason "stale-reclaimed")
                          (list :decision 'skip
                                :holder-id nil
                                :age-seconds age-seconds
                                :reason "stale-reclaim-race-lost"))))))))))))
        (list :decision 'skip
              :holder-id nil
              :age-seconds nil
              :reason "guard-dir-unavailable"))))

(defun sem-core-run-cron-guarded (guard-key module event-type thunk)
  "Run THUNK under a cron overlap guard identified by GUARD-KEY.
MODULE and EVENT-TYPE define the operational log channel.
Returns THUNK result on execution, or nil when skipped/deferred." 
  (cl-block sem-core-run-cron-guarded
    (let* ((config (sem-core--cron-guard-config guard-key))
           (policy (plist-get config :policy))
           (stale-ttl-seconds (plist-get config :stale-ttl-seconds))
           (lock-file (sem-core--cron-guard-lock-file guard-key))
           (poll-seconds (max 0.1 (or sem-core-cron-guard-serialize-poll-seconds 2)))
           (max-wait (max 0 (or sem-core-cron-guard-max-serialize-wait-seconds 600)))
           (max-attempts (max 1 (ceiling (/ (max 1.0 max-wait) poll-seconds))))
           (waited 0)
           (attempts 0)
           (acquired nil)
           (holder-id nil)
           (result nil))
      (while (not acquired)
        (setq attempts (1+ attempts))
        (let* ((acquire-result
                (sem-core--cron-guard-acquire guard-key module event-type policy stale-ttl-seconds))
               (decision (plist-get acquire-result :decision))
               (reason (plist-get acquire-result :reason))
               (age-seconds (plist-get acquire-result :age-seconds)))
          (cond
           ((memq decision '(acquire reclaim))
            (setq acquired t)
            (setq holder-id (plist-get acquire-result :holder-id))
            (sem-core--cron-guard-log
             module event-type "OK"
             `((guard_action . "acquire")
               (guard_key . ,guard-key)
               (policy . ,(symbol-name policy))
               (decision . ,(if (eq decision 'reclaim) "reclaim_success" "acquired"))
               (lock_age_seconds . ,age-seconds)
               (reason . ,reason))))
           ((eq policy 'skip)
            (sem-core--cron-guard-log
             module event-type "SKIP"
             `((guard_action . "acquire")
               (guard_key . ,guard-key)
               (policy . ,(symbol-name policy))
               (decision . "skip")
               (lock_age_seconds . ,age-seconds)
               (reason . ,reason)))
            (cl-return-from sem-core-run-cron-guarded nil))
           (t
            (if (or (string-match-p
                     "\\`\\(uncertain-age\\|lock-unreadable\\|stale-candidate-liveness-uncertain\\)"
                     (or reason ""))
                    (>= waited max-wait)
                    (>= attempts max-attempts))
                (progn
                  (sem-core--cron-guard-log
                   module event-type "SKIP"
                   `((guard_action . "defer")
                     (guard_key . ,guard-key)
                     (policy . ,(symbol-name policy))
                     (decision . ,(if (string-match-p
                                       "\\`\\(uncertain-age\\|lock-unreadable\\|stale-candidate-liveness-uncertain\\)"
                                       (or reason ""))
                                      "serialize-fail-closed"
                                    "serialize-timeout"))
                     (lock_age_seconds . ,age-seconds)
                     (reason . ,reason)))
                  (cl-return-from sem-core-run-cron-guarded nil))
              (sem-core--cron-guard-log
               module event-type "RETRY"
               `((guard_action . "defer")
                 (guard_key . ,guard-key)
                 (policy . ,(symbol-name policy))
                 (decision . "serialize-wait")
                  (lock_age_seconds . ,age-seconds)
                  (reason . ,reason)))
              (sleep-for poll-seconds)
              (setq waited (+ waited poll-seconds)))))))
      (unwind-protect
          (setq result (funcall thunk))
        (when (and acquired holder-id)
          (sem-core--cron-guard-release lock-file holder-id module event-type guard-key policy)))
      result)))

;;; Structured Logging

(defun sem-core--ensure-log-headings ()
  "Ensure the log file has the required heading structure.
Creates /data/sem-log.org with year/month headings as needed.
Returns t on success, nil on failure."
  (condition-case _err
      (progn
        (let* ((now (current-time))
               (year (sem-time-format-string "%Y" now))
               (month (sem-time-format-string "%m" now))
               (month-name (sem-time-format-string "%B" now))
               (day (sem-time-format-string "%Y-%m-%d" now))
               (log-file sem-core-log-file))

          ;; Ensure directory exists
          (make-directory (file-name-directory log-file) t)

          ;; Create or open log file
          (unless (file-exists-p log-file)
            (with-temp-file log-file
              (insert "* " year "\n")))

          ;; Headings are only ever appended, so append missing ones instead of
          ;; rewriting the whole (ever-growing) log file on each call.
          (let ((missing ""))
            (with-temp-buffer
              (insert-file-contents log-file)
              (goto-char (point-min))
              (if (not (re-search-forward (format "^\\* %s$" year) nil t))
                  (setq missing (concat "* " year "\n"
                                        "** " month " (" month-name ")\n"
                                        "*** " day "\n"))
                ;; Month and day headings are looked up inside the current
                ;; year subtree only, so last year's months do not match.
                (unless (re-search-forward
                         (format "^\\*\\* %s (%s)$" month month-name) nil t)
                  (setq missing (concat "** " month " (" month-name ")\n")))
                (unless (re-search-forward (format "^\\*\\*\\* %s" day) nil t)
                  (setq missing (concat missing "*** " day "\n"))))
              (unless (or (string-empty-p missing)
                          (= (point-max) (point-min))
                          (eq (char-before (point-max)) ?\n))
                (setq missing (concat "\n" missing))))
            (unless (string-empty-p missing)
              (write-region missing nil log-file t 'silent))))
        t)
    (error nil)))  ; Silently fail on read-only filesystems

(defun sem-core-log (module event-type status message &optional tokens)
  "Write a structured log entry to `sem-core-log-file'.

MODULE is one of: core, router, rss, url-capture, security, llm, elfeed, purge, init.
EVENT-TYPE is one of: INBOX-ITEM, URL-CAPTURE, RSS-DIGEST, ARXIV-DIGEST, ELFEED-UPDATE, PURGE, STARTUP, ERROR.
STATUS is one of: OK, RETRY, DLQ, SKIP, FAIL.
MESSAGE is a free-form string (max 200 chars, no newlines).
TOKENS is optional approximate input character count divided by 4.

Format: - [HH:MM:SS] [MODULE] [EVENT-TYPE] [STATUS] tokens=NNN | message"
  (cl-block sem-core-log
    ;; Check if log file initialized successfully before proceeding
    (let ((ensure-result (sem-core--ensure-log-headings)))
      (unless ensure-result
        (condition-case _fallback-err
            (message "SEM-STDERR: Failed to initialize %s [%s/%s/%s]"
                     sem-core-log-file module event-type status)
          (error nil))
        (cl-return-from sem-core-log nil)))

    (condition-case err
        (let* ((now (current-time))
               (timestamp (sem-time-format-string "%H:%M:%S" now))
               (log-file sem-core-log-file)
               (tokens-str (if tokens (format " tokens=%d |" tokens) " |"))
                ;; Truncate message to 200 chars and remove newlines
                (clean-message (substring (replace-regexp-in-string "\n" " " (or message ""))
                                          0
                                          (min 200 (length (or message "")))))
               (line (concat "- [" timestamp "] [" module "] [" event-type "] [" status "]"
                             tokens-str " " clean-message "\n")))
          (write-region line nil log-file t 'silent))
      (error
       (condition-case _fallback-err
           (message "SEM-STDERR: Failed to write %s [%s/%s/%s]: %s"
                    sem-core-log-file module event-type status (error-message-string err))
         (error nil))))))
  ; Never crash on logging errors

(defun sem-core-log-error (module event-type error-msg input &optional raw-output metadata)
  "Append an error entry to both `sem-core-log-file' and `sem-core-errors-file'.

MODULE, EVENT-TYPE as in `sem-core-log'.
ERROR-MSG is the error description.
INPUT is the original input text or URL that caused the failure.
RAW-OUTPUT is the raw LLM response, or nil if LLM was not called.
METADATA is an optional plist supporting:
- :priority Org headline priority token string (for example [#A])
- :tags list of Org tag strings (for example security and dlq)

This calls `sem-core-log' with STATUS=FAIL or STATUS=DLQ, and appends
detailed error info to errors.org."
  (condition-case err
      (progn
        ;; Log to sem-log.org with FAIL status
        (sem-core-log module event-type (if raw-output "DLQ" "FAIL") (or error-msg "Unknown error") nil)

        ;; Append to errors.org
        (let* ((now (current-time))
                (timestamp (sem-time-format-string "%Y-%m-%d %H:%M:%S" now))
                (errors-file sem-core-errors-file)
                (created (sem-time-format-string "[%Y-%m-%d %H:%M:%S]" now))
                (deadline (sem-time-format-string "<%Y-%m-%d %a %H:%M>" now))
                (priority (plist-get metadata :priority))
                (tags (plist-get metadata :tags))
                (tags-suffix (if tags (format " :%s:" (mapconcat #'identity tags ":")) "")))

          (make-directory (file-name-directory errors-file) t)

          ;; errors.org is also edited from mobile/web clients, so write the
          ;; full new content to a temp file and rename it into place.
          (with-temp-buffer
            (when (file-exists-p errors-file)
              (insert-file-contents errors-file))

            ;; Insert error entry
            (goto-char (point-max))
            (unless (or (bobp) (eq (char-before) ?\n))
              (insert "\n"))
            (insert (format "* TODO %s[%s] [%s] [%s] FAIL%s\n"
                            (if priority (format "%s " priority) "")
                            timestamp
                            module
                            event-type
                            tags-suffix))
            (insert (format "DEADLINE: %s\n" deadline))
            (insert ":PROPERTIES:\n")
            (insert ":CREATED: " created "\n")
            (insert ":END:\n")
            (insert "Error: " (or error-msg "Unknown error") "\n\n")
            (insert "** Input\n")
            (insert (or input "N/A") "\n\n")
            (insert "** Raw LLM Output\n")
            (insert (or raw-output "N/A") "\n\n")

            (let ((tmp-file (concat errors-file ".tmp")))
              (write-region (point-min) (point-max) tmp-file nil 'silent)
              (condition-case _rename-err
                  (rename-file tmp-file errors-file t)
                ;; Fall back to a direct write so the error is never lost.
                (error
                 (ignore-errors (delete-file tmp-file))
                 (write-region (point-min) (point-max) errors-file nil 'silent)))))))
    (error
     (condition-case _fallback-err
         (message "SEM-STDERR: Failed to write %s [%s/%s]: %s"
                  sem-core-errors-file module event-type (error-message-string err))
       (error nil))
     nil)))  ; Never crash on logging errors

;;; Messages Persistence

(defvar sem-core--last-flush-date ""
  "Date of the last message buffer flush (YYYY-MM-DD format).
Used to detect date rollover for daily log rotation.
Initial value is empty string to force first flush to detect as new day.
Module-level variable that resets on daemon restart.")

(defvar sem-core--last-flushed-messages-hash nil
  "Hash of the last successfully flushed *Messages* snapshot.
Used by `sem-core--flush-messages-daily' to skip duplicate appends.")

(defvar sem-core--last-flushed-messages-hash-date nil
  "Client-local date (YYYY-MM-DD) associated with last flushed messages hash.
Used to keep hash dedup independent across daily log rollovers.")

(defvar sem-core--batch-id 0
  "Monotonically increasing batch ID for inbox processing.
Incremented at the start of each cron-triggered inbox processing run.
Not incremented during planning phase - creates implicit lock.")

(defvar sem-core--pending-callbacks 0
  "Counter for pending async callbacks in the current batch.
Incremented when a callback is registered, decremented when it completes.
When it reaches 0, the batch barrier fires and planning step is triggered.")

(defvar sem-core--batch-start-time nil
  "Time when the current batch started.
Used for the 30-minute watchdog timeout.
Nil when no batch is in progress.")

(defvar sem-core--batch-watchdog-timer nil
  "Timer for the batch watchdog.
Cancels the previous timer before setting a new one.")

(defconst sem-core-batch-watchdog-seconds (* 25 60)
  "Seconds after which a batch is force-closed and planning runs.
Kept below the 30-minute inbox cron interval so a stuck batch is closed
before the next cron run would otherwise skip or supersede it.")

(defvar sem-core--planning-fired-batch nil
  "Batch ID for which the planning step has already been triggered.
Planning runs at most once per batch; late callbacks arriving after the
barrier or watchdog fired must not trigger it again.")

(defun sem-core--batch-open-p (batch-id)
  "Return non-nil when BATCH-ID is the active batch and still accepts results.
A batch closes once its planning step has been triggered."
  (and (integerp batch-id)
       (= batch-id sem-core--batch-id)
       (not (eql sem-core--planning-fired-batch batch-id))))

(defun sem-core--fire-planning-once (batch-id reason)
  "Trigger the planning step for BATCH-ID unless it already ran.
REASON is a short string used for diagnostics."
  (if (eql sem-core--planning-fired-batch batch-id)
      (sem-core-log "core" "INBOX-ITEM" "SKIP"
                    (format "Planning already triggered for batch=%d (%s)" batch-id reason)
                    nil)
    (setq sem-core--planning-fired-batch batch-id)
    (sem-core--cancel-batch-watchdog)
    (message "SEM: Batch %d complete, firing planning step (%s)" batch-id reason)
    (when (fboundp 'sem-planner-run-planning-step)
      (sem-planner-run-planning-step batch-id))))

(defun sem-core--batch-barrier-check (&optional callback-batch-id)
  "Check batch barrier and trigger planning for CALLBACK-BATCH-ID.
CALLBACK-BATCH-ID defaults to `sem-core--batch-id' when nil.
Only the owning, still-open batch is allowed to decrement pending callbacks
or trigger planning. Stale and late callbacks are logged and ignored."
  (let ((batch-id (or callback-batch-id sem-core--batch-id)))
    (if (not (sem-core--batch-open-p batch-id))
        (sem-core-log "core" "INBOX-ITEM" "SKIP"
                      (format "Ignoring stale barrier callback: callback-batch=%d active-batch=%d"
                              batch-id sem-core--batch-id)
                      nil)
      (when (> sem-core--pending-callbacks 0)
        (setq sem-core--pending-callbacks (1- sem-core--pending-callbacks)))
      (sem-core-log "core" "INBOX-ITEM" "OK"
                    (format "Batch barrier check: batch=%d pending=%d"
                            batch-id sem-core--pending-callbacks)
                    nil)
      (when (= sem-core--pending-callbacks 0)
        (sem-core--fire-planning-once batch-id "barrier")))))

(defun sem-core--batch-watchdog-fired (watchdog-batch-id)
  "Watchdog callback for WATCHDOG-BATCH-ID.
Only the owning batch may mutate barrier state or trigger planning."
  (condition-case err
      (if (not (sem-core--batch-open-p watchdog-batch-id))
          (sem-core-log "core" "INBOX-ITEM" "SKIP"
                        (format "Ignoring stale watchdog: watchdog-batch=%d active-batch=%d"
                                watchdog-batch-id sem-core--batch-id)
                        nil)
        (progn
          (message "SEM: Batch watchdog fired for batch %d" watchdog-batch-id)
          (sem-core-log "core" "INBOX-ITEM" "OK"
                        (format "Batch watchdog fired: batch=%d pending=%d"
                                watchdog-batch-id sem-core--pending-callbacks)
                        nil)
          (setq sem-core--pending-callbacks 0)
          (sem-core--fire-planning-once watchdog-batch-id "watchdog")))
    (error
     (message "SEM: Watchdog error: %s" (error-message-string err)))))

(defun sem-core--start-batch-watchdog (&optional batch-id)
  "Start or reset the batch watchdog timer for BATCH-ID.
The watchdog fires after `sem-core-batch-watchdog-seconds' if the barrier
hasn't fired.  Cancels any existing watchdog before starting a new one."
  (let ((owner-batch-id (or batch-id sem-core--batch-id)))
    (setq sem-core--batch-start-time (current-time))
    (when sem-core--batch-watchdog-timer
      (cancel-timer sem-core--batch-watchdog-timer))
    (setq sem-core--batch-watchdog-timer
          (run-with-timer sem-core-batch-watchdog-seconds nil
                          (lambda () (sem-core--batch-watchdog-fired owner-batch-id))))
    (message "SEM: Batch watchdog started (%ds timeout) for batch %d"
             sem-core-batch-watchdog-seconds owner-batch-id)))

(defun sem-core--cancel-batch-watchdog ()
  "Cancel the batch watchdog timer if running."
  (when sem-core--batch-watchdog-timer
    (cancel-timer sem-core--batch-watchdog-timer)
    (setq sem-core--batch-watchdog-timer nil)
    (message "SEM: Batch watchdog cancelled")))

(defun sem-core--flush-messages-daily ()
  "Append *Messages* buffer content to daily log file.
Writes to /var/log/sem/messages-YYYY-MM-DD.log.
On date rollover, erases the *Messages* buffer before writing to prevent
old content from bleeding into the new day's file.
Called via post-command-hook after every emacsclient invocation.
Wrapped in condition-case to never crash the daemon."
  (condition-case _err
      (let* ((now (current-time))
             (today (sem-time-format-string "%Y-%m-%d" now))
             (log-dir "/var/log/sem")
             (log-path (format "%s/messages-%s.log" log-dir today)))

        ;; Check for date rollover - if new day, erase buffer first
        (when (and (not (string-empty-p sem-core--last-flush-date))
                   (not (string= today sem-core--last-flush-date)))
          ;; Date has changed - erase *Messages* buffer before writing
          (with-current-buffer "*Messages*"
            (erase-buffer)))

        ;; Get current buffer content (may be empty after erase)
        (let ((content (with-current-buffer "*Messages*"
                         (buffer-string))))

            (let ((current-hash (secure-hash 'sha256 content)))
            ;; Skip unchanged snapshots only within the same client-local day.
            (unless (and sem-core--last-flushed-messages-hash
                          (string= today (or sem-core--last-flushed-messages-hash-date ""))
                          (string= current-hash sem-core--last-flushed-messages-hash))

              ;; Ensure log directory exists
              (make-directory log-dir t)

              ;; Write content in append mode (t = append)
              (write-region content nil log-path t 'silent)

              ;; Update hash state only after successful append.
              (setq sem-core--last-flushed-messages-hash current-hash)
              (setq sem-core--last-flushed-messages-hash-date today))))

        ;; Update last flush date after successful write
        (setq sem-core--last-flush-date today))
    (error nil)))

;;; Cursor Tracking

(defun sem-core--read-cursor ()
  "Read the cursor file and return an alist of headline hashes.
Returns nil if file doesn't exist or is empty."
  (let ((cursor-file sem-core-cursor-file))
    (if (file-exists-p cursor-file)
        (with-temp-buffer
          (insert-file-contents cursor-file)
          (goto-char (point-min))
          (condition-case nil
              (let ((content (read (current-buffer))))
                (when (listp content)
                  (cl-remove-if-not (lambda (entry)
                                      (and (consp entry) (stringp (car entry))))
                                    content)))
            (end-of-file nil)
            (error nil)))
      nil)))

(defun sem-core--write-cursor (cursor-alist)
  "Write CURSOR-ALIST to the cursor file.
Uses atomic write via temp file and rename."
  (let* ((cursor-file sem-core-cursor-file)
         (tmp-file (concat cursor-file ".tmp")))
    (make-directory (file-name-directory cursor-file) t)
    (with-temp-file tmp-file
      (insert "(")
      (dolist (entry cursor-alist)
        (insert "\n  (\"" (car entry) "\" . t)"))
      (insert "\n)\n"))
    (rename-file tmp-file cursor-file t)))

(defun sem-core--purge-cursor-to-active-hashes (active-hashes)
  "Drop cursor entries whose hash is not in ACTIVE-HASHES.
ACTIVE-HASHES is the list of headline hashes still present in the inbox.
Only hashes that were already marked processed are kept: a retained but
unprocessed headline must stay unprocessed so it is still routed."
  (let ((cursor (sem-core--read-cursor)))
    (sem-core--write-cursor
     (cl-remove-if-not (lambda (entry) (member (car entry) active-hashes))
                       cursor))))

(defun sem-core--purge-retries-to-active-hashes (active-hashes)
  "Drop retry counters whose hash is not in ACTIVE-HASHES."
  (sem-core--write-retries
   (cl-remove-if-not (lambda (entry) (member (car entry) active-hashes))
                     (sem-core--read-retries))))

(defun sem-core--compute-headline-hash (headline)
  "Compute a content hash for HEADLINE.
Uses the headline title and properties for deterministic hashing."
  (let ((title (or (plist-get headline :title) ""))
        (tags-str (if (plist-get headline :tags)
                      (string-join (plist-get headline :tags) " ")
                    ""))
        (body (or (plist-get headline :body) "")))
    (secure-hash 'sha256 (json-encode (vector title tags-str body)))))

(defun sem-core--mark-processed (hash)
  "Mark a headline HASH as processed in the cursor file.
If HASH is nil, this is a no-op (for RSS digest which has no per-entry tracking)."
  (when hash
    (let ((cursor (sem-core--read-cursor)))
      (unless (assoc hash cursor)
        (push (cons hash t) cursor))
      (sem-core--write-cursor cursor))))

(defun sem-core--is-processed (hash)
  "Check if a headline HASH is already processed."
  (let ((cursor (sem-core--read-cursor)))
    (when (assoc hash cursor) t)))

;;; Retry Tracking

(defun sem-core--read-retries ()
  "Read the retries file and return an alist of (hash . count).
Returns nil if file doesn't exist or is empty."
  (let ((retries-file sem-core-retries-file))
    (if (file-exists-p retries-file)
        (with-temp-buffer
          (insert-file-contents retries-file)
          (goto-char (point-min))
          (condition-case nil
              (let ((content (read (current-buffer))))
                (when (listp content)
                  (cl-remove-if-not (lambda (entry)
                                      (and (consp entry) 
                                           (stringp (car entry))
                                           (numberp (cdr entry))))
                                    content)))
            (end-of-file nil)
            (error nil)))
      nil)))

(defun sem-core--write-retries (retries-alist)
  "Write RETRIES-ALIST to the retries file.
Uses atomic write via temp file and rename."
  (let* ((retries-file sem-core-retries-file)
         (tmp-file (concat retries-file ".tmp")))
    (make-directory (file-name-directory retries-file) t)
    (with-temp-file tmp-file
      (insert "(")
      (dolist (entry retries-alist)
        (insert "\n  (\"" (car entry) "\" . " (number-to-string (cdr entry)) ")"))
      (insert "\n)\n"))
    (rename-file tmp-file retries-file t)))

(defun sem-core--purge-retries ()
  "Reset retries tracking file to an empty alist."
  (sem-core--write-retries '()))

(defun sem-core--get-retry-count (hash)
  "Get the retry count for HASH.
Returns 0 if hash has no recorded retries."
  (when hash
    (let ((retries (sem-core--read-retries)))
      (or (cdr (assoc hash retries)) 0))))

(defun sem-core--increment-retry (hash)
  "Increment the retry count for HASH.
Returns the new retry count."
  (when hash
    (let* ((retries (sem-core--read-retries))
           (current (or (cdr (assoc hash retries)) 0))
           (new-count (1+ current)))
      ;; Remove old entry if exists
      (setq retries (cl-remove hash retries :key #'car :test #'equal))
      ;; Add new entry
      (push (cons hash new-count) retries)
      ;; Write back
      (sem-core--write-retries retries)
      new-count)))

(defun sem-core--clear-retry (hash)
  "Clear the retry count for HASH.
Call this when an item succeeds or is moved to DLQ."
  (when hash
    (let ((retries (sem-core--read-retries)))
      (setq retries (cl-remove hash retries :key #'car :test #'equal))
      (sem-core--write-retries retries))))

(defun sem-core--should-retry-p (hash)
  "Check if HASH should be retried.
Returns t if retry count is less than max (3), nil otherwise."
  (when hash
    (let ((count (sem-core--get-retry-count hash)))
      (< count 3))))

(defun sem-core--mark-dlq (hash &optional title response)
  "Mark HASH as moved to DLQ (Dead Letter Queue).
Clears retry count and optionally logs to errors.org.
TITLE and RESPONSE are optional for error logging."
  (when hash
    ;; Clear retry count
    (sem-core--clear-retry hash)
    ;; Mark as processed so it's not retried
    (sem-core--mark-processed hash)
    ;; Log to errors.org if title provided
    (when title
      (sem-core-log-error "core" "INBOX-ITEM"
                          (format "Moved to DLQ after 3 retries: %s" title)
                          title
                          response))))

;;; Org Planning Lines

(defconst sem-core--planning-token-regexp
  "\\(SCHEDULED\\|DEADLINE\\):[ \t]*\\(<[^>\n]+>\\)"
  "Regexp matching one SCHEDULED/DEADLINE keyword with its timestamp.")

(defun sem-core-normalize-planning-line (entry &optional scheduled)
  "Return ENTRY with its planning info on the line right after the headline.

Org only recognizes SCHEDULED/DEADLINE as planning when they are on the line
directly below the headline; LLM output often puts them after the property
drawer or in the body, where agenda and org-element ignore them.  All
SCHEDULED/DEADLINE timestamps on standalone lines of the first entry are
collected (the first of each kind wins) and rewritten as one planning line.
When SCHEDULED is a timestamp string, it replaces any existing SCHEDULED.
ENTRY must start with its headline; text of child headlines is untouched."
  (with-temp-buffer
    (insert entry)
    (goto-char (point-min))
    (if (not (re-search-forward "^\\*+[ \t]" nil t))
        entry
      (let* ((body-start (progn (forward-line 1) (point)))
             (body-end (save-excursion
                         (if (re-search-forward "^\\*+[ \t]" nil t)
                             (match-beginning 0)
                           (point-max))))
             (found-scheduled nil)
             (found-deadline nil))
        (save-restriction
          (narrow-to-region body-start body-end)
          (goto-char (point-min))
          (while (re-search-forward
                  (concat "^[ \t]*\\(?:" sem-core--planning-token-regexp
                          "[ \t]*\\)+$")
                  nil t)
            (let ((line (match-string 0))
                  (line-start (match-beginning 0))
                  (line-end (match-end 0))
                  (start 0))
              (while (string-match sem-core--planning-token-regexp line start)
                (if (string= (match-string 1 line) "SCHEDULED")
                    (unless found-scheduled
                      (setq found-scheduled (match-string 2 line)))
                  (unless found-deadline
                    (setq found-deadline (match-string 2 line))))
                (setq start (match-end 0)))
              (delete-region line-start (min (point-max) (1+ line-end)))))
          (let ((new-scheduled (or scheduled found-scheduled)))
            (goto-char (point-min))
            (when (or new-scheduled found-deadline)
              (insert (string-join
                       (delq nil (list (and new-scheduled
                                            (concat "SCHEDULED: " new-scheduled))
                                       (and found-deadline
                                            (concat "DEADLINE: " found-deadline))))
                       " ")
                      "\n"))))
        (buffer-string)))))

(defun sem-core-repair-planning-lines (file)
  "Move misplaced SCHEDULED/DEADLINE lines in FILE under their headlines.
Manual maintenance command for task files written before planning lines
were normalized:
  emacsclient -s sem-server -e \"(sem-core-repair-planning-lines \\\"/data/tasks.org\\\")\"
Writes atomically and returns the number of entries changed."
  (let ((changed 0)
        (chunks '()))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (let ((starts '()))
        (while (re-search-forward "^\\*+[ \t]" nil t)
          (push (match-beginning 0) starts))
        (setq starts (nreverse starts))
        (push (buffer-substring-no-properties
               (point-min) (or (car starts) (point-max)))
              chunks)
        (while starts
          (let* ((start (car starts))
                 (end (or (cadr starts) (point-max)))
                 (entry (buffer-substring-no-properties start end))
                 (fixed (sem-core-normalize-planning-line entry)))
            (unless (string= entry fixed)
              (setq changed (1+ changed)))
            (push fixed chunks)
            (setq starts (cdr starts))))))
    (when (> changed 0)
      (let ((tmp-file (concat file ".tmp")))
        (with-temp-file tmp-file
          (insert (apply #'concat (nreverse chunks))))
        (rename-file tmp-file file t)))
    (sem-core-log "core" "PURGE" "OK"
                  (format "Repaired planning lines in %d entries of %s" changed file))
    changed))

;;; Inbox Processing Entry Point

(defun sem-core--cleanup-stale-temp-files ()
  "Remove stale tasks-tmp-*.org files older than 24 hours.
Called at startup and after each batch to clean up orphaned temp files.
Never crashes - errors are silently ignored."
  (ignore-errors
    (let ((tmp-dir "/tmp/data")
          (cutoff-time (- (float-time) (* 24 60 60))))
      (when (file-directory-p tmp-dir)
        (dolist (file (directory-files tmp-dir t "tasks-tmp-.*\\.org$"))
          (when (and (file-regular-p file)
                     (> cutoff-time (float-time (nth 5 (file-attributes file 'string)))))
            (message "SEM: Cleaning up stale temp file: %s" file)
            (delete-file file)))))))

(defun sem-core-process-inbox ()
  "Cron entry point for inbox processing.
Reads unprocessed headlines from inbox-mobile.org and routes them
to the appropriate handler (url-capture or LLM task generation).
Initializes batch state for tracking callbacks and triggering planning step."
  (sem-core-run-cron-guarded
   "inbox-processing" "core" "INBOX-ITEM"
   (lambda ()
     (condition-case err
         (if (and (> sem-core--batch-id 0)
                  (sem-core--batch-open-p sem-core--batch-id)
                  (> sem-core--pending-callbacks 0))
             ;; Async work of the previous batch is still in flight.  Starting
             ;; a new batch would orphan its results, so let it finish (the
             ;; batch watchdog bounds how long that can take).
             (progn
               (sem-core-log "core" "INBOX-ITEM" "SKIP"
                             (format "Previous batch %d still in flight (pending=%d)"
                                     sem-core--batch-id sem-core--pending-callbacks)
                             nil)
               (message "SEM: Previous batch %d still in flight, skipping this run"
                        sem-core--batch-id))
           (message "SEM: sem-core-process-inbox called")
           (sem-core--cleanup-stale-temp-files)
           (setq sem-core--batch-id (1+ sem-core--batch-id))
           ;; The dispatch loop itself holds one pending slot so that callbacks
           ;; completing synchronously during dispatch cannot close the batch
           ;; before every item has been dispatched.
           (setq sem-core--pending-callbacks 1)
           (sem-core--start-batch-watchdog sem-core--batch-id)
           (unwind-protect
               (when (fboundp 'sem-router-process-inbox)
                 (message "SEM: Calling sem-router-process-inbox...")
                 (sem-router-process-inbox sem-core--batch-id)
                 (message "SEM: sem-router-process-inbox returned"))
             ;; Release the dispatch slot; fires planning when nothing is pending.
             (sem-core--batch-barrier-check sem-core--batch-id))
           (message "SEM: sem-core-process-inbox done"))
       (error
        (sem-core-log-error "core" "INBOX-ITEM" (error-message-string err) nil)
        (message "SEM: Inbox processing error: %s" (error-message-string err)))))))

;;; Inbox Purge

(defconst sem-core-purge-max-attempts 3
  "Maximum purge attempts when the inbox changes concurrently (WebDAV upload).")

(defun sem-core--purge-plan (content processed-p)
  "Compute the purge result for inbox CONTENT.
PROCESSED-P is a predicate on headline hashes.
Return a plist with :content (new inbox text), :purged (count of removed
processed headlines) and :retained-hashes (hashes of every headline that
remains in the new content, processed or not).

Text before the first headline is preserved.  A retained headline keeps its
whole subtree, so nested headlines inside it are not emitted twice; an
unprocessed child of a purged parent is kept on its own."
  (with-temp-buffer
    (insert content)
    (org-mode)
    (let* ((ast (org-element-parse-buffer))
           (first-headline (org-element-map ast 'headline #'identity nil t))
           (preamble (buffer-substring-no-properties
                      (point-min)
                      (if first-headline
                          (org-element-property :begin first-headline)
                        (point-max))))
           (kept-end 0)
           (chunks '())
           (retained '())
           (purged 0))
      (org-element-map ast 'headline
        (lambda (headline-element)
          (let* ((begin (org-element-property :begin headline-element))
                 (end (org-element-property :end headline-element))
                 (title (org-element-property :raw-value headline-element))
                 (tags (org-element-property :tags headline-element))
                 (body (sem-router--extract-headline-body headline-element))
                 (hash (secure-hash 'sha256
                                    (json-encode
                                     (vector title
                                             (if tags (string-join tags " ") "")
                                             (or body ""))))))
            (cond
             ;; Inside an already retained subtree: it stays with its parent.
             ((< begin kept-end)
              (push hash retained))
             ((funcall processed-p hash)
              (setq purged (1+ purged)))
             (t
              (push hash retained)
              (setq kept-end end)
              (push (buffer-substring-no-properties begin end) chunks))))))
      (list :content (concat preamble
                             (mapconcat (lambda (chunk)
                                          (if (string-suffix-p "\n" chunk)
                                              chunk
                                            (concat chunk "\n")))
                                        (nreverse chunks)
                                        ""))
            :purged purged
            :retained-hashes retained))))

(defun sem-core--purge-state-to-retained-hashes (retained)
  "Prune cursor and retry state to the RETAINED inbox headline hashes.
Cursor and retries are pruned independently so one failure does not block
the other."
  (condition-case purge-cursor-err
      (progn
        (sem-core--purge-cursor-to-active-hashes retained)
        (sem-core-log "purge" "PURGE" "OK"
                      (format "Cursor pruned to %d retained hashes" (length retained))))
    (error
     (sem-core-log-error "purge" "PURGE"
                         (format "Cursor purge failed: %s"
                                 (error-message-string purge-cursor-err))
                         nil
                         nil)))
  (condition-case purge-retries-err
      (progn
        (sem-core--purge-retries-to-active-hashes retained)
        (sem-core-log "purge" "PURGE" "OK"
                      (format "Retries pruned to %d retained hashes" (length retained))))
    (error
     (sem-core-log-error "purge" "PURGE"
                         (format "Retries purge failed: %s"
                                 (error-message-string purge-retries-err))
                         nil
                         nil))))

(defun sem-core--read-file-string (file)
  "Return the contents of FILE as a string."
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(defun sem-core-purge-inbox ()
  "Atomic purge of processed headlines from inbox-mobile.org.
Only runs at 4AM window. Uses temp file + rename-file for atomicity.
Hash computation matches sem-router--parse-headlines format:
(json-encode (vector title space-joined-tags body)).

Unprocessed headlines are kept and stay unprocessed: their cursor and retry
state survives the purge.  If the inbox changes while the purge is being
computed (a concurrent WebDAV upload), the purge is recomputed."
  (sem-core-run-cron-guarded
   "inbox-purge" "purge" "PURGE"
   (lambda ()
     (condition-case err
         (let* ((inbox-file sem-core-inbox-file)
                (tmp-file (concat inbox-file ".purge.tmp"))
                (hour (string-to-number (sem-time-format-string "%H"))))
           (cond
            ((/= hour 4)
             (sem-core-log "purge" "PURGE" "SKIP" "Not in 4AM window")
             (message "SEM: Purge only runs at 4AM, current hour: %d" hour))
            ((not (file-exists-p inbox-file))
             (sem-core-log "purge" "PURGE" "SKIP" "inbox-mobile.org does not exist")
             (message "SEM: inbox-mobile.org does not exist, skipping inbox purge")
             ;; Nothing is retained, so no cursor or retry state is needed.
             (sem-core--purge-state-to-retained-hashes '()))
            (t
             (require 'sem-router)
             (let* ((cursor (sem-core--read-cursor))
                    (processed-p (lambda (hash) (assoc hash cursor)))
                    (attempt 0)
                    (plan nil)
                    (done nil))
               (while (and (not done) (< attempt sem-core-purge-max-attempts))
                 (setq attempt (1+ attempt))
                 (let ((original (sem-core--read-file-string inbox-file)))
                   (setq plan (sem-core--purge-plan original processed-p))
                   (with-temp-file tmp-file
                     (insert (plist-get plan :content)))
                   ;; Re-read right before the rename: abort this attempt when a
                   ;; client uploaded a new inbox version in the meantime.
                   (if (string= original (sem-core--read-file-string inbox-file))
                       (progn
                         (rename-file tmp-file inbox-file t)
                         (setq done t))
                     (ignore-errors (delete-file tmp-file))
                     (sem-core-log "purge" "PURGE" "RETRY"
                                   (format "Inbox changed during purge (attempt %d/%d)"
                                           attempt sem-core-purge-max-attempts)))))
               (if (not done)
                   (sem-core-log "purge" "PURGE" "FAIL"
                                 "Inbox kept changing during purge; skipped until next run")
                 (let ((retained (plist-get plan :retained-hashes)))
                   (sem-core-log "purge" "PURGE" "OK"
                                 (format "Removed %d nodes from inbox-mobile.org"
                                         (plist-get plan :purged)))
                   (message "SEM: Purged %d processed headlines" (plist-get plan :purged))
                   (sem-core--purge-state-to-retained-hashes retained)))))))
       (error
        (message "SEM: Purge error: %s" (error-message-string err)))))))

(provide 'sem-core)
;;; sem-core.el ends here
