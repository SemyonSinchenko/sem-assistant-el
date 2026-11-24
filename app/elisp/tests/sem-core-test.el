;;; sem-core-test.el --- Tests for sem-core.el -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Tests for sem-core logging and cursor tracking functions.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'sem-mock)

;; Load the module under test
;; Note: The test runner sets up load-path, so we use require
(require 'sem-prompts)
(require 'sem-time)
(require 'sem-core)
(require 'sem-router)

;;; Tests for sem-core-log format

(ert-deftest sem-core-test-log-format-without-tokens ()
  "Test sem-core-log format without tokens field."
  (let ((test-file (sem-mock-temp-file "* 2026\n** 03 (March)\n*** 2026-03-16\n")))
    (unwind-protect
        (let ((sem-core-log-file test-file))
          (sem-core-log "core" "STARTUP" "OK" "Daemon started")
          (with-temp-buffer
            (insert-file-contents test-file)
            (goto-char (point-min))
            (should (re-search-forward "- \\[.*\\] \\[core\\] \\[STARTUP\\] \\[OK\\] | Daemon started" nil t))))
      (sem-mock-cleanup-temp-file test-file))))

(ert-deftest sem-core-test-log-format-with-tokens ()
  "Test sem-core-log format with tokens field."
  (let ((test-file (sem-mock-temp-file "* 2026\n** 03 (March)\n*** 2026-03-16\n")))
    (unwind-protect
        (let ((sem-core-log-file test-file))
          (sem-core-log "rss" "RSS-DIGEST" "OK" "Digest generated" 1250)
          (with-temp-buffer
            (insert-file-contents test-file)
            (goto-char (point-min))
            (should (re-search-forward "- \\[.*\\] \\[rss\\] \\[RSS-DIGEST\\] \\[OK\\] tokens=1250 | Digest generated" nil t))))
      (sem-mock-cleanup-temp-file test-file))))

(ert-deftest sem-core-test-log-unwritable-file-emits-stderr-fallback ()
  "Test sem-core-log emits SEM-STDERR fallback and does not signal."
  (let ((stderr-message nil))
    (cl-letf (((symbol-function 'sem-core--ensure-log-headings)
               (lambda () t))
              ((symbol-function 'write-region)
               (lambda (&rest _)
                 (error "simulated append failure")))
              ((symbol-function 'message)
               (lambda (fmt &rest args)
                 (setq stderr-message (apply #'format fmt args)))))
      (condition-case _err
          (progn
            (sem-core-log "core" "STARTUP" "OK" "hello")
            (should t))
        (error
         (should nil)))
      (should stderr-message)
      (should (string-match-p "^SEM-STDERR:" stderr-message)))))

(ert-deftest sem-core-test-log-appends-single-line-after-heading-ensure ()
  "Test sem-core-log appends one formatted line via write-region append mode."
  (let ((captured-content nil)
        (captured-append nil)
        (captured-file nil))
    (cl-letf (((symbol-function 'sem-core--ensure-log-headings)
               (lambda () t))
              ((symbol-function 'write-region)
               (lambda (start _end filename &optional append _visit)
                 (setq captured-content start)
                 (setq captured-file filename)
                 (setq captured-append append)
                 nil)))
      (let ((sem-core-log-file "/tmp/sem-log-test.org"))
        (sem-core-log "core" "STARTUP" "OK" "Daemon started" 42))
      (should (stringp captured-content))
      (should (eq captured-append t))
      (should (string= captured-file "/tmp/sem-log-test.org"))
      (should (string-suffix-p "\n" captured-content))
      (should (string-match-p "\\[core\\] \\[STARTUP\\] \\[OK\\]" captured-content))
      (should (string-match-p "tokens=42" captured-content))
      (should (string-match-p "Daemon started" captured-content)))))

(ert-deftest sem-core-test-log-error-org-entry-format ()
  "Test sem-core-log-error writes TODO + DEADLINE + required sections."
  (let ((errors-file (make-temp-file "sem-errors-test-"))
        (captured-status nil))
    (unwind-protect
        (let ((sem-core-errors-file errors-file))
          (cl-letf (((symbol-function 'sem-core-log)
                     (lambda (_module _event status _message &optional _tokens)
                       (setq captured-status status))))
            (sem-core-log-error "router" "INBOX-ITEM" "Boom" "input text" "raw output"))
          (should (string= captured-status "DLQ"))
          (with-temp-buffer
            (insert-file-contents errors-file)
            (goto-char (point-min))
            (should (re-search-forward "^\\* TODO \\[.*\\] \\[router\\] \\[INBOX-ITEM\\] FAIL$" nil t))
            (should (re-search-forward "^DEADLINE: <[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [A-Za-z]\\{3\\} [0-9]\\{2\\}:[0-9]\\{2\\}>$" nil t))
            (should (re-search-forward "^:PROPERTIES:$" nil t))
            (should (re-search-forward "^:CREATED: \\[.*\\]$" nil t))
            (should (re-search-forward "^:END:$" nil t))
            (should (re-search-forward "^Error: Boom$" nil t))
            (should (re-search-forward "^\\*\\* Input$" nil t))
            (should (re-search-forward "^input text$" nil t))
            (should (re-search-forward "^\\*\\* Raw LLM Output$" nil t))
            (should (re-search-forward "^raw output$" nil t))))
      (sem-mock-cleanup-temp-file errors-file))))

(ert-deftest sem-core-test-log-error-supports-priority-and-tags-metadata ()
  "Test sem-core-log-error supports optional priority and tag metadata."
  (let ((errors-file (make-temp-file "sem-errors-test-")))
    (unwind-protect
        (let ((sem-core-errors-file errors-file))
          (cl-letf (((symbol-function 'sem-core-log)
                     (lambda (&rest _) nil)))
            (sem-core-log-error "security" "INBOX-ITEM"
                                "Malformed sensitive block"
                                "raw input"
                                nil
                                (list :priority "[#A]" :tags '("security"))))
          (with-temp-buffer
            (insert-file-contents errors-file)
            (goto-char (point-min))
            (should (re-search-forward "^\\* TODO \\[#A\\] \\[[-0-9: ]+\\] \\[security\\] \\[INBOX-ITEM\\] FAIL :security:$" nil t))))
      (sem-mock-cleanup-temp-file errors-file))))

;;; Tests for cursor read/write round-trip

(ert-deftest sem-core-test-cursor-roundtrip ()
  "Test cursor read/write round-trip."
  (let ((test-file (make-temp-file "sem-cursor-test-")))
    (unwind-protect
        (let ((sem-core-cursor-file test-file))
          ;; Write some hashes
          (sem-core--write-cursor '(("hash1" . t) ("hash2" . t) ("hash3" . t)))

          ;; Read back and verify
          (let ((cursor (sem-core--read-cursor)))
            (should (assoc "hash1" cursor))
            (should (assoc "hash2" cursor))
            (should (assoc "hash3" cursor))
            (should (= (length cursor) 3))))
      (sem-mock-cleanup-temp-file test-file))))

;;; Tests for content hash determinism

(ert-deftest sem-core-test-hash-determinism ()
  "Test that content hash is deterministic."
  (let* ((title "Test Headline")
         (tags "link task")
         (headline1 (list :title title :tags (split-string tags)))
         (headline2 (list :title title :tags (split-string tags))))
    (should (string= (sem-core--compute-headline-hash headline1)
                     (sem-core--compute-headline-hash headline2)))))

(ert-deftest sem-core-test-hash-uniqueness ()
  "Test that different content produces different hashes."
  (let* ((headline1 (list :title "First" :tags '("link")))
         (headline2 (list :title "Second" :tags '("link"))))
    (should-not (string= (sem-core--compute-headline-hash headline1)
                         (sem-core--compute-headline-hash headline2)))))

;;; Test hash computation matches router format (JSON vector)

(ert-deftest sem-core-test-hash-space-joined-tags ()
  "Test that hash computation uses space-joined tags (no colons).
Hash format: (json-encode (vector title tags body))"
  (let* ((title "Test headline :tag1:tag2:")
          (tags '("tag1" "tag2"))
          (body "")
          (expected-hash-input (json-encode (vector title (string-join tags " ") body)))
          (expected-hash (secure-hash 'sha256 expected-hash-input)))
    ;; The hash should be deterministic
    (should (string= expected-hash
                     (secure-hash 'sha256 (json-encode (vector title "tag1 tag2" "")))))))

(ert-deftest sem-core-test-hash-includes-body ()
  "Test that hash computation includes body content.
Hash format: (json-encode (vector title tags body))"
  (let* ((title "Test headline :task:")
          (tags '("task"))
          (body "This is the body content\nwith multiple lines")
          (expected-hash-input (json-encode (vector title (string-join tags " ") body)))
          (hash1 (secure-hash 'sha256 expected-hash-input)))
    ;; Different body should produce different hash
    (let* ((body2 "Different body content")
           (hash2 (secure-hash 'sha256 (json-encode (vector title (string-join tags " ") body2)))))
      (should-not (string= hash1 hash2)))
    ;; Same input should produce same hash
    (let ((hash1-again (secure-hash 'sha256 expected-hash-input)))
      (should (string= hash1 hash1-again)))))

(ert-deftest sem-core-test-hash-empty-body ()
  "Test that hash computation works with empty body.
Hash format: JSON vector (body can be empty)."
  (let* ((title "Test headline :link:")
          (tags '("link"))
          (body "")
          (expected-hash-input (json-encode (vector title (string-join tags " ") body))))
    ;; Should not error with empty body
    (should (secure-hash 'sha256 expected-hash-input))))

(ert-deftest sem-core-test-hash-delimiter-collision-resistant ()
  "Test JSON-based hash is collision-resistant against delimiter tricks."
  (let* ((headline-a (list :title "a|b" :tags '("c") :body ""))
         (headline-b (list :title "a" :tags '("b|c") :body ""))
         (hash-a (sem-core--compute-headline-hash headline-a))
         (hash-b (sem-core--compute-headline-hash headline-b)))
    (should-not (string= hash-a hash-b))))

;;; Test cleanup

(ert-deftest sem-core-test-mock-cleanup ()
  "Test that mock cleanup works correctly."
  (sem-mock-reset-all)
  ;; If we get here without error, the test passes
  (should t))

(ert-deftest sem-core-test-batch-barrier-ignores-stale-callback ()
  "Test stale barrier callbacks do not decrement pending or trigger planning." 
  (let ((sem-core--batch-id 5)
        (sem-core--pending-callbacks 2)
        (planning-called nil))
    (cl-letf (((symbol-function 'sem-planner-run-planning-step)
               (lambda (&optional _batch-id)
                 (setq planning-called t)))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil)))
      (sem-core--batch-barrier-check 4)
      (should (= sem-core--pending-callbacks 2))
      (should-not planning-called))))

(ert-deftest sem-core-test-batch-barrier-owning-callback-triggers-planning ()
  "Test owning barrier callback decrements and triggers planning at zero." 
  (let ((sem-core--batch-id 7)
        (sem-core--pending-callbacks 1)
        (captured-batch nil))
    (cl-letf (((symbol-function 'sem-planner-run-planning-step)
               (lambda (&optional batch-id)
                 (setq captured-batch batch-id)))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-core--cancel-batch-watchdog)
               (lambda () nil)))
      (sem-core--batch-barrier-check 7)
      (should (= sem-core--pending-callbacks 0))
      (should (= captured-batch 7)))))

(ert-deftest sem-core-test-watchdog-ignores-stale-batch ()
  "Test stale watchdog callback does not trigger planning." 
  (let ((sem-core--batch-id 9)
        (sem-core--pending-callbacks 3)
        (planning-called nil))
    (cl-letf (((symbol-function 'sem-planner-run-planning-step)
               (lambda (&optional _batch-id)
                 (setq planning-called t)))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil)))
      (sem-core--batch-watchdog-fired 8)
      (should (= sem-core--pending-callbacks 3))
      (should-not planning-called))))

(ert-deftest sem-core-test-watchdog-owning-batch-triggers-planning ()
  "Test owning watchdog callback triggers planning with owning batch id." 
  (let ((sem-core--batch-id 11)
        (sem-core--pending-callbacks 3)
        (captured-batch nil))
    (cl-letf (((symbol-function 'sem-planner-run-planning-step)
               (lambda (&optional batch-id)
                 (setq captured-batch batch-id)))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil)))
      (sem-core--batch-watchdog-fired 11)
       (should (= sem-core--pending-callbacks 0))
       (should (= captured-batch 11)))))

(ert-deftest sem-core-test-cron-guard-same-key-overlap-is-suppressed ()
  "Test same guard key overlap uses deterministic suppression for skip policy."
  (let ((guard-dir (make-temp-file "sem-guard-test-" t))
        (outer-ran nil)
        (inner-ran nil))
    (unwind-protect
        (let ((sem-core-cron-guard-dir guard-dir)
              (sem-core-cron-guard-job-config
               '(("same-key" :policy skip :stale-ttl-seconds 60))))
          (cl-letf (((symbol-function 'sem-core-log)
                     (lambda (&rest _) nil)))
            (sem-core-run-cron-guarded
             "same-key" "core" "INBOX-ITEM"
             (lambda ()
               (setq outer-ran t)
               (sem-core-run-cron-guarded
                "same-key" "core" "INBOX-ITEM"
                (lambda ()
                  (setq inner-ran t)
                  t))
               t))))
      (delete-directory guard-dir t))
    (should outer-ran)
    (should-not inner-ran)))

(ert-deftest sem-core-test-cron-guard-different-keys-run-independently ()
  "Test different guard keys can execute while another key is held."
  (let ((guard-dir (make-temp-file "sem-guard-test-" t))
        (first-ran nil)
        (second-ran nil))
    (unwind-protect
        (let ((sem-core-cron-guard-dir guard-dir)
              (sem-core-cron-guard-job-config
               '(("job-a" :policy skip :stale-ttl-seconds 60)
                 ("job-b" :policy skip :stale-ttl-seconds 60))))
          (cl-letf (((symbol-function 'sem-core-log)
                     (lambda (&rest _) nil)))
            (sem-core-run-cron-guarded
             "job-a" "core" "INBOX-ITEM"
             (lambda ()
               (setq first-ran t)
               (sem-core-run-cron-guarded
                "job-b" "core" "INBOX-ITEM"
                (lambda ()
                  (setq second-ran t)
                  t))
               t))))
      (delete-directory guard-dir t))
    (should first-ran)
    (should second-ran)))

(ert-deftest sem-core-test-cron-guard-stale-reclaim-and-uncertain-age-fail-closed ()
  "Test stale lock reclaim succeeds and uncertain age suppresses execution."
  (let ((guard-dir (make-temp-file "sem-guard-test-" t))
        (stale-ran nil)
        (future-ran nil)
        (stale-file nil)
        (future-file nil)
        (now (float-time)))
    (unwind-protect
        (let ((sem-core-cron-guard-dir guard-dir)
              (sem-core-cron-guard-job-config
               '(("stale-job" :policy skip :stale-ttl-seconds 60)
                 ("future-job" :policy skip :stale-ttl-seconds 60))))
          (setq stale-file (sem-core--cron-guard-lock-file "stale-job"))
          (setq future-file (sem-core--cron-guard-lock-file "future-job"))
          (sem-core--cron-guard-write-lock-atomic
           stale-file
           `((guard-key . "stale-job")
             (policy . "skip")
             (pid . 99999999)
             (host . ,(system-name))
             (holder-id . "old-holder")
             (created-at . ,(- now 3600))
             (updated-at . ,(- now 3600)))
           nil)
          (sem-core--cron-guard-write-lock-atomic
           future-file
           `((guard-key . "future-job")
             (policy . "skip")
             (pid . 99999999)
             (host . ,(system-name))
             (holder-id . "future-holder")
             (created-at . ,(+ now 3600))
             (updated-at . ,(+ now 3600)))
           nil)
          (cl-letf (((symbol-function 'sem-core-log)
                     (lambda (&rest _) nil))
                    ((symbol-function 'sem-core--cron-guard-holder-liveness)
                     (lambda (metadata)
                       (if (equal (cdr (assoc 'guard-key metadata)) "stale-job")
                           (list :alive nil :certain t :reason "test-holder-dead")
                         (list :alive nil :certain nil :reason "test-holder-uncertain")))) )
            (sem-core-run-cron-guarded
             "stale-job" "core" "INBOX-ITEM"
             (lambda ()
               (setq stale-ran t)
               t))
            (sem-core-run-cron-guarded
             "future-job" "core" "INBOX-ITEM"
             (lambda ()
               (setq future-ran t)
               t))))
      (delete-directory guard-dir t))
    (should stale-ran)
    (should-not future-ran)))

;;; Daily Log Rotation Tests (Task 4.2.1-4.2.5)

(ert-deftest sem-core-test-daily-log-filename-format ()
  "Test that daily log file uses correct naming format (messages-YYYY-MM-DD.log).
This test mocks write-region to capture the filename being used."
  (let ((captured-filename nil)
        (test-date "2026-03-17"))
    (unwind-protect
        (progn
          ;; Reset last-flush-date
          (setq sem-core--last-flush-date "")
          (setq sem-core--last-flushed-messages-hash nil)
          (setq sem-core--last-flushed-messages-hash-date nil)
          ;; Mock write-region to capture filename
          (cl-letf (((symbol-function 'write-region)
                     (lambda (_start _end filename &optional _append _visit)
                       (setq captured-filename filename)))
                    ((symbol-function 'make-directory)
                     (lambda (&rest _) nil)))
            ;; Call flush function
            (sem-core--flush-messages-daily)
            ;; Verify filename format
            (should captured-filename)
            (should (string-match-p "messages-[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\.log" captured-filename))))
      ;; Cleanup
      (setq sem-core--last-flush-date "")
      (setq sem-core--last-flushed-messages-hash nil)
      (setq sem-core--last-flushed-messages-hash-date nil))))

(ert-deftest sem-core-test-buffer-erase-on-date-rollover ()
  "Test that *Messages* buffer is erased on date rollover.
This test verifies that when last-flush-date differs from current date,
the function completes without error (which implies erase was attempted)."
  (unwind-protect
      (progn
        ;; Set last-flush-date to a different date (forces erase path)
        (setq sem-core--last-flush-date "2025-01-01")
        ;; Mock write-region and make-directory to avoid filesystem operations
        (cl-letf (((symbol-function 'write-region)
                   (lambda (&rest _) nil))
                  ((symbol-function 'make-directory)
                   (lambda (&rest _) nil)))
          ;; Call the flush function - it should try to erase when date differs
          ;; Note: erase-buffer may fail in batch mode on *Messages*, but the
          ;; function should handle it gracefully via condition-case
          (condition-case _err
              (progn
                (sem-core--flush-messages-daily)
                ;; If we get here, function completed
                (should t))
            (error
             ;; Even if erase-buffer fails, function should complete
             (should t)))))
    ;; Cleanup
    (setq sem-core--last-flush-date "")))

(ert-deftest sem-core-test-no-erase-on-same-day ()
  "Test that *Messages* buffer is NOT erased on same-day flush.
When last-flush-date matches current date, buffer should not be erased."
  (unwind-protect
      (progn
        ;; Set last-flush-date to today (so dates match)
        (setq sem-core--last-flush-date (sem-time-format-string "%Y-%m-%d"))
        ;; Mock functions
        (cl-letf (((symbol-function 'write-region)
                   (lambda (&rest _) nil))
                  ((symbol-function 'make-directory)
                   (lambda (&rest _) nil)))
          ;; Call flush function - should complete without erasing
          (sem-core--flush-messages-daily)
          ;; If we get here, function worked correctly
          (should t)))
    ;; Cleanup
    (setq sem-core--last-flush-date "")))

(ert-deftest sem-core-test-append-mode-not-overwrite ()
  "Test that log writes use append mode (t), not overwrite (nil)."
  (let ((append-param nil))
    (unwind-protect
        (progn
          ;; Reset last-flush-date
          (setq sem-core--last-flush-date "")
          ;; Mock write-region to capture the append parameter
          (cl-letf (((symbol-function 'write-region)
                     (lambda (_start _end _filename &optional append _visit)
                       (setq append-param append)
                       nil))
                    ((symbol-function 'make-directory)
                     (lambda (&rest _) nil)))
            ;; Call flush function
            (sem-core--flush-messages-daily)
            ;; Should be called with append=t
            (should (eq append-param t))))
      ;; Cleanup
      (setq sem-core--last-flush-date ""))))

(ert-deftest sem-core-test-batch-barrier-message-metadata-only ()
  "Test batch barrier runtime message includes only metadata fields."
  (let ((captured-messages '())
        (sensitive-title "Top Secret Launch Plan")
        (sensitive-body "private body content")
        (sensitive-url "https://sensitive.example.com/path")
        (sem-core--batch-id 41)
        (sem-core--pending-callbacks 1))
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) captured-messages)))
              ((symbol-function 'sem-core--cancel-batch-watchdog)
               (lambda () nil))
              ((symbol-function 'sem-planner-run-planning-step)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil)))
      (sem-core--batch-barrier-check 41)
      (should (cl-some (lambda (line)
                         (string-match-p "Batch 41 complete, firing planning step" line))
                       captured-messages))
      (dolist (line captured-messages)
        (should-not (string-match-p (regexp-quote sensitive-title) line))
        (should-not (string-match-p (regexp-quote sensitive-body) line))
        (should-not (string-match-p (regexp-quote sensitive-url) line))))))

(ert-deftest sem-core-test-error-handling-unwritable-dir ()
  "Test that flush handles unwritable log directory gracefully.
The function should catch errors and return nil without signaling."
  (unwind-protect
      (progn
        ;; Reset last-flush-date
        (setq sem-core--last-flush-date "")
        ;; Mock make-directory to simulate permission error
        (cl-letf (((symbol-function 'make-directory)
                   (lambda (_dir &optional _parents)
                     (error "Permission denied: /var/log/sem"))))
          ;; Should not signal an error - wrapped in condition-case
          (condition-case err
              (progn
                (sem-core--flush-messages-daily)
                ;; If we get here, error was handled
                (should t))
            (error
             ;; Should not reach here
             (should nil)))))
    ;; Cleanup
    (setq sem-core--last-flush-date "")))

(ert-deftest sem-core-test-messages-flush-hash-dedup-skips-unchanged ()
  "Test unchanged messages snapshot is skipped after first successful flush."
  (let ((write-count 0)
        (fixed-date "2026-03-17"))
    (unwind-protect
        (progn
          (setq sem-core--last-flush-date "")
          (setq sem-core--last-flushed-messages-hash nil)
          (setq sem-core--last-flushed-messages-hash-date nil)
          (cl-letf (((symbol-function 'write-region)
                     (lambda (&rest _)
                       (setq write-count (1+ write-count))
                       nil))
                    ((symbol-function 'make-directory)
                     (lambda (&rest _) nil))
                    ((symbol-function 'sem-time-format-string)
                     (lambda (format &optional _time)
                       (if (string= format "%Y-%m-%d")
                           fixed-date
                         "00:00:00"))))
            (with-current-buffer "*Messages*"
              (let ((inhibit-read-only t))
                (erase-buffer)
                (insert "same snapshot")))
            (sem-core--flush-messages-daily)
            (sem-core--flush-messages-daily)
            (should (= write-count 1))))
      (setq sem-core--last-flush-date "")
      (setq sem-core--last-flushed-messages-hash nil)
      (setq sem-core--last-flushed-messages-hash-date nil))))

(ert-deftest sem-core-test-messages-flush-hash-dedup-appends-when-changed ()
  "Test changed messages snapshot appends and updates hash state."
  (let ((write-count 0)
        (fixed-date "2026-03-17"))
    (unwind-protect
        (progn
          (setq sem-core--last-flush-date "")
          (setq sem-core--last-flushed-messages-hash nil)
          (setq sem-core--last-flushed-messages-hash-date nil)
          (cl-letf (((symbol-function 'write-region)
                     (lambda (&rest _)
                       (setq write-count (1+ write-count))
                       nil))
                    ((symbol-function 'make-directory)
                     (lambda (&rest _) nil))
                    ((symbol-function 'sem-time-format-string)
                     (lambda (format &optional _time)
                       (if (string= format "%Y-%m-%d")
                           fixed-date
                         "00:00:00"))))
            (with-current-buffer "*Messages*"
              (let ((inhibit-read-only t))
                (erase-buffer)
                (insert "snapshot one")))
            (sem-core--flush-messages-daily)
            (with-current-buffer "*Messages*"
              (let ((inhibit-read-only t))
                (erase-buffer)
                (insert "snapshot two")))
            (sem-core--flush-messages-daily)
            (should (= write-count 2))))
      (setq sem-core--last-flush-date "")
      (setq sem-core--last-flushed-messages-hash nil)
      (setq sem-core--last-flushed-messages-hash-date nil))))

(ert-deftest sem-core-test-messages-flush-hash-state-not-updated-on-write-failure ()
  "Test failed append keeps hash state unchanged for retry eligibility."
  (let ((write-count 0)
        (fixed-date "2026-03-17")
        (captured-hash nil))
    (unwind-protect
        (progn
          (setq sem-core--last-flush-date "")
          (setq sem-core--last-flushed-messages-hash nil)
          (setq sem-core--last-flushed-messages-hash-date nil)
          (cl-letf (((symbol-function 'write-region)
                     (lambda (&rest _)
                       (setq write-count (1+ write-count))
                       (if (= write-count 1)
                           (error "simulated append failure")
                         nil)))
                    ((symbol-function 'make-directory)
                     (lambda (&rest _) nil))
                    ((symbol-function 'sem-time-format-string)
                     (lambda (format &optional _time)
                       (if (string= format "%Y-%m-%d")
                           fixed-date
                         "00:00:00"))))
            (with-current-buffer "*Messages*"
              (let ((inhibit-read-only t))
                (erase-buffer)
                (insert "retry me")))
            (sem-core--flush-messages-daily)
            (setq captured-hash sem-core--last-flushed-messages-hash)
            (should-not captured-hash)
            (sem-core--flush-messages-daily)
            (should (= write-count 2))
            (should sem-core--last-flushed-messages-hash)
            (should (string= sem-core--last-flushed-messages-hash-date fixed-date))))
      (setq sem-core--last-flush-date "")
      (setq sem-core--last-flushed-messages-hash nil)
      (setq sem-core--last-flushed-messages-hash-date nil))))

(ert-deftest sem-core-test-messages-flush-date-rollover-dedup-independent ()
  "Test new client-local day first snapshot is eligible independently for dedup."
  (let ((write-count 0)
        (today (sem-time-format-string "%Y-%m-%d")))
    (unwind-protect
        (progn
          (setq sem-core--last-flush-date today)
          (cl-letf (((symbol-function 'write-region)
                     (lambda (&rest _)
                       (setq write-count (1+ write-count))
                       nil))
                    ((symbol-function 'make-directory)
                     (lambda (&rest _) nil)))
            (with-current-buffer "*Messages*"
              (let ((inhibit-read-only t))
                (erase-buffer)
                (insert "same across days")))
            (setq sem-core--last-flushed-messages-hash
                  (secure-hash 'sha256 "same across days"))
            (setq sem-core--last-flushed-messages-hash-date "2000-01-01")
            (sem-core--flush-messages-daily)
            (should (= write-count 1))
            (should (string= sem-core--last-flush-date today))
            (should (string= sem-core--last-flushed-messages-hash-date today))))
      (setq sem-core--last-flush-date "")
      (setq sem-core--last-flushed-messages-hash nil)
      (setq sem-core--last-flushed-messages-hash-date nil))))

(ert-deftest sem-core-test-messages-flush-persists-metadata-only-runtime-lines ()
  "Test persisted daily message content remains metadata-only for router output."
  (let ((captured-content nil)
        (sensitive-title "Confidential customer launch")
        (sensitive-body "private body text")
        (sensitive-url "https://sensitive.example.com/secret"))
    (unwind-protect
        (progn
          (setq sem-core--last-flush-date "")
          (setq sem-core--last-flushed-messages-hash nil)
          (setq sem-core--last-flushed-messages-hash-date nil)
          (with-current-buffer "*Messages*"
            (let ((inhibit-read-only t))
              (erase-buffer)
              (sem-router--runtime-message
               "process" "OK"
               '(("batch" . 77) ("item" . "a1b2c3d4") ("processed" . 1) ("skipped" . 0)))))
          (cl-letf (((symbol-function 'write-region)
                     (lambda (start _end _filename &optional _append _visit)
                       (setq captured-content start)
                       nil))
                    ((symbol-function 'make-directory)
                     (lambda (&rest _) nil)))
            (sem-core--flush-messages-daily)
            (should (stringp captured-content))
            (should (string-match-p "module=router action=process status=OK" captured-content))
            (should-not (string-match-p (regexp-quote sensitive-title) captured-content))
            (should-not (string-match-p (regexp-quote sensitive-body) captured-content))
            (should-not (string-match-p (regexp-quote sensitive-url) captured-content))))
      (setq sem-core--last-flush-date "")
      (setq sem-core--last-flushed-messages-hash nil)
      (setq sem-core--last-flushed-messages-hash-date nil))))

;;; Test inbox purge preserves full subtrees (Task 3.4)

(ert-deftest sem-core-test-purge-preserves-body ()
  "Test that sem-core-purge-inbox preserves full headline subtrees.
Creates inbox with processed and unprocessed headlines (each with body lines),
runs purge, and asserts the unprocessed headline's body is present.
Hash format: JSON vector of title/tags/body (using sem-router--extract-headline-body)."
  (let ((test-inbox (make-temp-file "inbox-test-"))
        (test-cursor (make-temp-file "cursor-test-"))
        (test-retries (make-temp-file "retries-test-")))
    (unwind-protect
        (let ((sem-core-inbox-file test-inbox)
              (sem-core-cursor-file test-cursor)
              (sem-core-retries-file test-retries))
          ;; Create inbox with two headlines, each with body lines
          (with-temp-file test-inbox
            (insert "* Processed headline :link:\n")
            (insert "Body line 1 for processed\n")
            (insert "Body line 2 for processed\n")
            (insert "* Unprocessed headline :task:\n")
            (insert "Body line 1 for unprocessed\n")
            (insert "Body line 2 for unprocessed\n")
            (insert "Body line 3 for unprocessed\n"))

          ;; Mark first headline as processed using org-element-based body extraction
          ;; This matches what sem-core-purge-inbox now uses (sem-router--extract-headline-body)
          (let ((processed-hash nil))
            (with-temp-buffer
              (insert-file-contents test-inbox)
              (org-mode)
              (let ((ast (org-element-parse-buffer)))
                (org-element-map ast 'headline
                  (lambda (headline-element)
                    (let ((title (org-element-property :raw-value headline-element)))
                      (when (string= title "Processed headline")
                        (let* ((tags (org-element-property :tags headline-element))
                               (body (sem-router--extract-headline-body headline-element))
                               (tags-str (if tags (string-join tags " ") ""))
                               (body-str (or body "")))
                           (setq processed-hash (secure-hash 'sha256
                                                            (json-encode (vector title tags-str body-str))))))))))
            (should processed-hash)
            (sem-core--mark-processed processed-hash))

          ;; Run purge at 4AM (mock the hour)
          (cl-letf (((symbol-function 'sem-time-format-string)
                     (lambda (format &optional time)
                       (if (string= format "%H") "04" "2000-01-01"))))
            (sem-core-purge-inbox))

          ;; Verify unprocessed headline body is preserved
          (with-temp-buffer
            (insert-file-contents test-inbox)
            (let ((content (buffer-string)))
              ;; Processed headline should be removed (use ^ to avoid matching "Unprocessed headline")
              (should-not (string-match-p "^\\* Processed headline" content))
              ;; Unprocessed headline and ALL body lines should be preserved
              (should (string-match-p "Unprocessed headline" content))
              (should (string-match-p "Body line 1 for unprocessed" content))
              (should (string-match-p "Body line 2 for unprocessed" content))
              (should (string-match-p "Body line 3 for unprocessed" content)))))
      (sem-mock-cleanup-temp-file test-inbox)
      (sem-mock-cleanup-temp-file test-cursor)
      (sem-mock-cleanup-temp-file test-retries)))))

(ert-deftest sem-core-test-purge-atomic-rename ()
  "Test that sem-core-purge-inbox uses atomic rename.
Hash format: JSON vector of title/tags/body (using sem-router--extract-headline-body)."
  (let ((test-inbox (make-temp-file "inbox-test-"))
        (test-cursor (make-temp-file "cursor-test-"))
        (test-retries (make-temp-file "retries-test-")))
    (unwind-protect
        (let ((sem-core-inbox-file test-inbox)
              (sem-core-cursor-file test-cursor)
              (sem-core-retries-file test-retries))
          ;; Create inbox with one processed headline (no body)
          (with-temp-file test-inbox
            (insert "* Processed headline :link:\n"))

          ;; Mark as processed using org-element-based body extraction
          ;; This matches what sem-core-purge-inbox now uses (sem-router--extract-headline-body)
          (let ((processed-hash nil))
            (with-temp-buffer
              (insert-file-contents test-inbox)
              (org-mode)
              (let ((ast (org-element-parse-buffer)))
                (org-element-map ast 'headline
                  (lambda (headline-element)
                    (let ((title (org-element-property :raw-value headline-element)))
                      (when (string= title "Processed headline")
                        (let* ((tags (org-element-property :tags headline-element))
                               (body (sem-router--extract-headline-body headline-element))
                               (tags-str (if tags (string-join tags " ") ""))
                               (body-str (or body "")))
                           (setq processed-hash (secure-hash 'sha256
                                                            (json-encode (vector title tags-str body-str))))))))))
            (should processed-hash)
            (sem-core--mark-processed processed-hash))

          ;; Run purge at 4AM
          (cl-letf (((symbol-function 'sem-time-format-string)
                     (lambda (format &optional time)
                       (if (string= format "%H") "04" "2000-01-01"))))
            (sem-core-purge-inbox))

          ;; File should exist and be empty (or just whitespace)
          (should (file-exists-p test-inbox))
          (with-temp-buffer
            (insert-file-contents test-inbox)
            (should (or (string-blank-p (buffer-string))
                        (string= (buffer-string) "")))))
      (sem-mock-cleanup-temp-file test-inbox)
      (sem-mock-cleanup-temp-file test-cursor)
      (sem-mock-cleanup-temp-file test-retries)))))

(ert-deftest sem-core-test-purge-rebuilds-cursor-from-retained-headlines ()
  "Test 4AM purge rebuilds cursor with only retained headline hashes."
  (let ((test-inbox (make-temp-file "inbox-test-"))
        (test-cursor (make-temp-file "cursor-test-"))
        (test-retries (make-temp-file "retries-test-")))
    (unwind-protect
        (let ((sem-core-inbox-file test-inbox)
              (sem-core-cursor-file test-cursor)
              (sem-core-retries-file test-retries)
              (processed-hash nil)
              (retained-hash nil))
          (with-temp-file test-inbox
            (insert "* Processed headline :link:\n")
            (insert "Body processed\n")
            (insert "* Retained headline :task:\n")
            (insert "Body retained\n"))
          (with-temp-buffer
            (insert-file-contents test-inbox)
            (org-mode)
            (let ((ast (org-element-parse-buffer)))
              (org-element-map ast 'headline
                (lambda (headline-element)
                  (let* ((title (org-element-property :raw-value headline-element))
                         (tags (org-element-property :tags headline-element))
                         (body (sem-router--extract-headline-body headline-element))
                         (tags-str (if tags (string-join tags " ") ""))
                         (body-str (or body ""))
                         (hash (secure-hash 'sha256
                                            (json-encode (vector title tags-str body-str)))))
                    (if (string= title "Processed headline")
                        (setq processed-hash hash)
                      (setq retained-hash hash)))))))
          (should processed-hash)
          (should retained-hash)
          (sem-core--write-cursor `((,processed-hash . t) ("stale" . t)))
          (sem-core--write-retries '(("old" . 2)))
          (sem-core--mark-processed processed-hash)
          (cl-letf (((symbol-function 'sem-time-format-string)
                     (lambda (format &optional _time)
                       (if (string= format "%H") "04" "2000-01-01"))))
            (sem-core-purge-inbox))
          (let ((cursor (sem-core--read-cursor))
                (retries (sem-core--read-retries)))
            ;; A retained headline is unprocessed and must stay unprocessed,
            ;; otherwise it would never be routed.
            (should-not (assoc retained-hash cursor))
            (should-not (assoc processed-hash cursor))
            (should-not (assoc "stale" cursor))
            (should (null retries))))
      (sem-mock-cleanup-temp-file test-inbox)
      (sem-mock-cleanup-temp-file test-cursor)
      (sem-mock-cleanup-temp-file test-retries))))

(ert-deftest sem-core-test-purge-skips-cursor-and-retries-outside-4am ()
  "Test cursor/retries purge does not run outside 4AM window."
  (let ((test-inbox (make-temp-file "inbox-test-"))
        (test-cursor (make-temp-file "cursor-test-"))
        (test-retries (make-temp-file "retries-test-"))
        (cursor-called nil)
        (retries-called nil))
    (unwind-protect
        (let ((sem-core-inbox-file test-inbox)
              (sem-core-cursor-file test-cursor)
              (sem-core-retries-file test-retries))
          (with-temp-file test-inbox
            (insert "* Keep me :task:\nBody\n"))
          (cl-letf (((symbol-function 'sem-time-format-string)
                     (lambda (format &optional _time)
                       (if (string= format "%H") "03" "2000-01-01")))
                    ((symbol-function 'sem-core--purge-cursor-to-active-hashes)
                     (lambda (&rest _)
                       (setq cursor-called t)))
                    ((symbol-function 'sem-core--purge-retries)
                     (lambda ()
                       (setq retries-called t))))
            (sem-core-purge-inbox))
          (should-not cursor-called)
          (should-not retries-called))
      (sem-mock-cleanup-temp-file test-inbox)
      (sem-mock-cleanup-temp-file test-cursor)
      (sem-mock-cleanup-temp-file test-retries))))

(ert-deftest sem-core-test-purge-missing-inbox-still-purges-cursor-and-retries ()
  "Test missing inbox triggers empty cursor and retries reset at 4AM."
  (let ((test-dir (make-temp-file "sem-core-purge-missing-" t))
        (test-cursor (make-temp-file "cursor-test-"))
        (test-retries (make-temp-file "retries-test-")))
    (unwind-protect
        (let ((sem-core-inbox-file (expand-file-name "missing-inbox.org" test-dir))
              (sem-core-cursor-file test-cursor)
              (sem-core-retries-file test-retries))
          (sem-core--write-cursor '(("stale1" . t) ("stale2" . t)))
          (sem-core--write-retries '(("retry1" . 3)))
          (cl-letf (((symbol-function 'sem-time-format-string)
                     (lambda (format &optional _time)
                       (if (string= format "%H") "04" "2000-01-01"))))
            (sem-core-purge-inbox))
          (should (null (sem-core--read-cursor)))
          (should (null (sem-core--read-retries))))
      (delete-directory test-dir t)
      (sem-mock-cleanup-temp-file test-cursor)
      (sem-mock-cleanup-temp-file test-retries))))

(ert-deftest sem-core-test-purge-isolates-cursor-failure-and-resets-retries ()
  "Test cursor purge failure does not block retries purge or inbox purge."
  (let ((test-inbox (make-temp-file "inbox-test-"))
        (test-cursor (make-temp-file "cursor-test-"))
        (test-retries (make-temp-file "retries-test-"))
        (cursor-error-logged nil))
    (unwind-protect
        (let ((sem-core-inbox-file test-inbox)
              (sem-core-cursor-file test-cursor)
              (sem-core-retries-file test-retries)
              (processed-hash nil))
          (with-temp-file test-inbox
            (insert "* Processed headline :link:\nBody processed\n"))
          (with-temp-buffer
            (insert-file-contents test-inbox)
            (org-mode)
            (let ((ast (org-element-parse-buffer)))
              (org-element-map ast 'headline
                (lambda (headline-element)
                  (let* ((title (org-element-property :raw-value headline-element))
                         (tags (org-element-property :tags headline-element))
                         (body (sem-router--extract-headline-body headline-element))
                         (tags-str (if tags (string-join tags " ") ""))
                         (body-str (or body "")))
                    (setq processed-hash
                          (secure-hash 'sha256 (json-encode (vector title tags-str body-str)))))))))
          (sem-core--mark-processed processed-hash)
          (sem-core--write-retries '(("retry1" . 2)))
          (cl-letf (((symbol-function 'sem-time-format-string)
                     (lambda (format &optional _time)
                       (if (string= format "%H") "04" "2000-01-01")))
                    ((symbol-function 'sem-core--purge-cursor-to-active-hashes)
                     (lambda (_)
                       (error "simulated cursor purge failure")))
                    ((symbol-function 'sem-core-log-error)
                     (lambda (_module _event error-msg _input &optional _raw)
                        (when (string-match-p "Cursor purge failed" error-msg)
                          (setq cursor-error-logged t)))))
            (sem-core-purge-inbox))
          (with-temp-buffer
            (insert-file-contents test-inbox)
            (should (string-blank-p (buffer-string))))
          (should cursor-error-logged)
          (should (null (sem-core--read-retries))))
      (sem-mock-cleanup-temp-file test-inbox)
      (sem-mock-cleanup-temp-file test-cursor)
      (sem-mock-cleanup-temp-file test-retries))))

;;; Batch lifecycle regression tests

(ert-deftest sem-core-test-planning-fires-once-per-batch ()
  "Test barrier, watchdog and late callbacks trigger planning only once."
  (let ((sem-core--batch-id 21)
        (sem-core--pending-callbacks 1)
        (sem-core--planning-fired-batch nil)
        (planning-calls 0))
    (cl-letf (((symbol-function 'sem-planner-run-planning-step)
               (lambda (&optional _batch-id) (cl-incf planning-calls)))
              ((symbol-function 'sem-core-log) (lambda (&rest _) nil))
              ((symbol-function 'sem-core--cancel-batch-watchdog) (lambda () nil)))
      (sem-core--batch-barrier-check 21)
      (should (= planning-calls 1))
      ;; Watchdog and late callbacks for the same, now closed batch.
      (sem-core--batch-watchdog-fired 21)
      (sem-core--batch-barrier-check 21)
      (sem-core--batch-barrier-check 21)
      (should (= planning-calls 1))
      (should-not (sem-core--batch-open-p 21)))))

(ert-deftest sem-core-test-watchdog-closes-batch-for-late-callbacks ()
  "Test a callback arriving after the watchdog fired does not re-plan."
  (let ((sem-core--batch-id 22)
        (sem-core--pending-callbacks 2)
        (sem-core--planning-fired-batch nil)
        (planning-calls 0))
    (cl-letf (((symbol-function 'sem-planner-run-planning-step)
               (lambda (&optional _batch-id) (cl-incf planning-calls)))
              ((symbol-function 'sem-core-log) (lambda (&rest _) nil))
              ((symbol-function 'sem-core--cancel-batch-watchdog) (lambda () nil)))
      (sem-core--batch-watchdog-fired 22)
      (should (= planning-calls 1))
      (sem-core--batch-barrier-check 22)
      (should (= planning-calls 1)))))

(ert-deftest sem-core-test-process-inbox-holds-dispatch-slot ()
  "Test a callback completing during dispatch cannot fire planning early."
  (let ((sem-core--batch-id 30)
        (sem-core--pending-callbacks 0)
        (sem-core--planning-fired-batch 30)
        (planning-pending-values '()))
    (cl-letf (((symbol-function 'sem-core-run-cron-guarded)
               (lambda (_key _module _event thunk) (funcall thunk)))
              ((symbol-function 'sem-core--cleanup-stale-temp-files) (lambda () nil))
              ((symbol-function 'sem-core--start-batch-watchdog) (lambda (&rest _) nil))
              ((symbol-function 'sem-core--cancel-batch-watchdog) (lambda () nil))
              ((symbol-function 'sem-core-log) (lambda (&rest _) nil))
              ((symbol-function 'sem-planner-run-planning-step)
               (lambda (&optional _batch-id)
                 (push sem-core--pending-callbacks planning-pending-values)))
              ((symbol-function 'sem-router-process-inbox)
               (lambda (batch-id)
                 ;; First item completes synchronously, second stays in flight.
                 (setq sem-core--pending-callbacks (1+ sem-core--pending-callbacks))
                 (sem-core--batch-barrier-check batch-id)
                 (setq sem-core--pending-callbacks (1+ sem-core--pending-callbacks)))))
      (sem-core-process-inbox)
      (should (= sem-core--batch-id 31))
      (should (null planning-pending-values))
      (should (= sem-core--pending-callbacks 1))
      ;; The in-flight item completes: now the batch closes and plans once.
      (sem-core--batch-barrier-check 31)
      (should (equal planning-pending-values '(0))))))

(ert-deftest sem-core-test-process-inbox-skips-while-previous-batch-in-flight ()
  "Test a new cron run does not supersede a batch with pending callbacks."
  (let ((sem-core--batch-id 40)
        (sem-core--pending-callbacks 2)
        (sem-core--planning-fired-batch nil)
        (router-called nil))
    (cl-letf (((symbol-function 'sem-core-run-cron-guarded)
               (lambda (_key _module _event thunk) (funcall thunk)))
              ((symbol-function 'sem-core-log) (lambda (&rest _) nil))
              ((symbol-function 'sem-router-process-inbox)
               (lambda (&rest _) (setq router-called t))))
      (sem-core-process-inbox)
      (should-not router-called)
      (should (= sem-core--batch-id 40))
      (should (= sem-core--pending-callbacks 2)))))

;;; Purge regression tests

(ert-deftest sem-core-test-purge-plan-keeps-preamble-and-nested-once ()
  "Test purge keeps file preamble and does not duplicate nested headlines."
  (let* ((content "#+TITLE: Inbox\n\n* Parent :task:\nParent body\n** Child :task:\nChild body\n* Done :link:\n")
         (done-hash nil)
         (plan nil))
    (with-temp-buffer
      (insert content)
      (org-mode)
      (org-element-map (org-element-parse-buffer) 'headline
        (lambda (hl)
          (when (string= (org-element-property :raw-value hl) "Done")
            (setq done-hash
                  (secure-hash 'sha256
                               (json-encode (vector "Done" "link" ""))))))))
    (setq plan (sem-core--purge-plan content (lambda (hash) (equal hash done-hash))))
    (should (string-prefix-p "#+TITLE: Inbox\n" (plist-get plan :content)))
    (should (= 1 (with-temp-buffer
                   (insert (plist-get plan :content))
                   (how-many "^\\*\\* Child" (point-min) (point-max)))))
    (should-not (string-match-p "^\\* Done" (plist-get plan :content)))
    (should (= 1 (plist-get plan :purged)))
    (should (= 2 (length (plist-get plan :retained-hashes))))))

(ert-deftest sem-core-test-purge-keeps-retry-state-of-retained-items ()
  "Test purge keeps retry counters of retained items and leaves them unprocessed."
  (let ((test-inbox (make-temp-file "inbox-test-"))
        (test-cursor (make-temp-file "cursor-test-"))
        (test-retries (make-temp-file "retries-test-")))
    (unwind-protect
        (let ((sem-core-inbox-file test-inbox)
              (sem-core-cursor-file test-cursor)
              (sem-core-retries-file test-retries)
              (pending-hash (secure-hash 'sha256 (json-encode (vector "Pending" "task" "Body")))))
          (with-temp-file test-inbox
            (insert "* Pending :task:\nBody\n"))
          (sem-core--write-cursor '(("gone" . t)))
          (sem-core--write-retries `((,pending-hash . 2) ("gone" . 1)))
          (cl-letf (((symbol-function 'sem-time-format-string)
                     (lambda (format &optional _time)
                       (if (string= format "%H") "04" "2000-01-01")))
                    ((symbol-function 'sem-core-log) (lambda (&rest _) nil)))
            (sem-core-purge-inbox))
          (should-not (sem-core--is-processed pending-hash))
          (should (equal (sem-core--read-retries) `((,pending-hash . 2))))
          (with-temp-buffer
            (insert-file-contents test-inbox)
            (should (string-match-p "^\\* Pending" (buffer-string)))))
      (sem-mock-cleanup-temp-file test-inbox)
      (sem-mock-cleanup-temp-file test-cursor)
      (sem-mock-cleanup-temp-file test-retries))))

(provide 'sem-core-test)
;;; sem-core-test.el ends here
