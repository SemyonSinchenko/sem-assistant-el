;;; sem-planner-test.el --- Tests for sem-planner.el -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Tests for sem-planner functions: anonymization, barrier, retry, atomic update.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'sem-mock)

(load-file (expand-file-name "../sem-core.el" (file-name-directory load-file-name)))
(load-file (expand-file-name "../sem-rules.el" (file-name-directory load-file-name)))
(load-file (expand-file-name "../sem-prompts.el" (file-name-directory load-file-name)))
(load-file (expand-file-name "../sem-planner.el" (file-name-directory load-file-name)))

;;; Helpers

(defun sem-planner-test--create-temp-tasks-file (content)
  "Create a temp tasks.org file with CONTENT and set sem-planner-tasks-file."
  (let ((tmp (sem-mock-temp-file content)))
    (setq sem-planner-tasks-file tmp)
    tmp))

;;; Anonymization Tests

(ert-deftest sem-planner-test-schedule-context-returns-empty-when-no-file ()
  "Test that schedule context is empty when tasks file does not exist."
  (let ((sem-planner-tasks-file "/nonexistent/tasks.org"))
    (should (string-empty-p (sem-planner--schedule-context)))))

(ert-deftest sem-planner-test-schedule-context-includes-titles-not-ids-or-bodies ()
  "Test schedule context carries title, time, priority and category only."
  (let* ((now (encode-time 0 0 8 15 3 2024 "Etc/UTC"))
         (content "* TODO [#A] Prepare board deck :work:
:PROPERTIES:
:ID: abc-123
:END:
SCHEDULED: <2024-03-15 Fri 14:00-16:00>
Secret body text")
         (result (cl-letf (((symbol-function 'sem-time-client-timezone)
                            (lambda () "Etc/UTC")))
                   (sem-planner--schedule-context-content content now))))
    (should (string-match-p "2024-03-15 14:00-16:00 busy PRIORITY:A TAG:work | Prepare board deck"
                            result))
    (should-not (string-match-p "abc-123" result))
    (should-not (string-match-p "Secret body" result))))

(ert-deftest sem-planner-test-schedule-context-skips-done-and-out-of-window ()
  "Test schedule context keeps only open tasks from today to +14 days."
  (let* ((now (encode-time 0 0 8 15 3 2024 "Etc/UTC"))
         (content "* TODO Yesterday task :routine:
SCHEDULED: <2024-03-14 Thu 10:00-11:00>
* DONE Finished today :routine:
SCHEDULED: <2024-03-15 Fri 09:00-10:00>
* TODO Later today :routine:
SCHEDULED: <2024-03-15 Fri 07:00-07:30>
* TODO Far future :work:
SCHEDULED: <2024-04-20 Sat 10:00-11:00>
* TODO Deadline soon :work:
DEADLINE: <2024-03-20 Wed>
")
         (result (cl-letf (((symbol-function 'sem-time-client-timezone)
                            (lambda () "Etc/UTC")))
                   (sem-planner--schedule-context-content content now))))
    (should (string-match-p "Later today" result))
    (should (string-match-p "(deadline) | Deadline soon" result))
    (should-not (string-match-p "Yesterday task" result))
    (should-not (string-match-p "Finished today" result))
    (should-not (string-match-p "Far future" result))))

(ert-deftest sem-planner-test-temp-tasks-context-includes-state-priority-title ()
  "Test that Pass 2 task lines include state, priority, effort and title."
  (let* ((temp-tasks (concat "* TODO Existing scheduled task :routine:\n"
                             ":PROPERTIES:\n"
                             ":ID: existing-scheduled-123\n"
                             ":SCHEDULED: <2026-03-20 Fri 09:00-10:00>\n"
                             ":END:\n"
                             "\n"
                             "* TODO Existing unscheduled task :work:\n"
                             ":PROPERTIES:\n"
                             ":ID: existing-unscheduled-123\n"
                             ":END:\n"
                             "\n"
                             "* TODO [#A] New task\n"
                             ":PROPERTIES:\n"
                             ":ID: new-123\n"
                             ":FILETAGS: :family:\n"
                             ":EFFORT: 1:30\n"
                             ":SEM_FIXED_SCHEDULE: t\n"
                             ":END:\n"
                             "Body that must not leak\n"))
         (existing-index (make-hash-table :test #'equal)))
    (puthash "existing-scheduled-123" '(:id "existing-scheduled-123") existing-index)
    (puthash "existing-unscheduled-123" '(:id "existing-unscheduled-123") existing-index)
    (let ((result (sem-planner--temp-tasks-context temp-tasks existing-index)))
      (should (string-match-p "ID: existing-scheduled-123" result))
      (should (string-match-p "STATE:pre-existing-scheduled" result))
      (should (string-match-p "ID: existing-unscheduled-123" result))
      (should (string-match-p "STATE:pre-existing-unscheduled" result))
      (should (string-match-p "ID: new-123 | TAG:family | PRIORITY:A" result))
      (should (string-match-p "STATE:newly-generated (fixed by user) | EFFORT:1:30" result))
      (should (string-match-p "TITLE: New task" result))
      (should-not (string-match-p "must not leak" result)))))

(ert-deftest sem-planner-test-merge-scheduling-preserves-preexisting-tasks ()
  "Test that merge preserves pre-existing task schedule states."
  (let* ((temp-tasks (concat "* TODO Existing scheduled task :routine:\n"
                             ":PROPERTIES:\n"
                             ":ID: existing-scheduled-456\n"
                             ":SCHEDULED: <2026-03-20 09:00-10:00>\n"
                             ":END:\n"
                             "\n"
                             "* TODO Existing unscheduled task :work:\n"
                             ":PROPERTIES:\n"
                             ":ID: existing-unscheduled-456\n"
                             ":END:\n"
                             "\n"
                             "* TODO New task :work:\n"
                             ":PROPERTIES:\n"
                             ":ID: new-456\n"
                             ":END:\n"))
         (decisions '(("existing-scheduled-456" . "<2099-01-01 10:00-11:00>")
                      ("existing-unscheduled-456" . "<2099-01-01 11:00-12:00>")
                      ("new-456" . "<2099-01-02 12:00-13:00>")))
         (task-metadata (make-hash-table :test #'equal))
         (merged nil))
    (puthash "existing-scheduled-456"
             '(:id "existing-scheduled-456" :state pre-existing-scheduled :priority nil)
             task-metadata)
    (puthash "existing-unscheduled-456"
             '(:id "existing-unscheduled-456" :state pre-existing-unscheduled :priority nil)
             task-metadata)
    (puthash "new-456"
             '(:id "new-456" :state newly-generated :priority nil)
             task-metadata)
    (setq merged
          (sem-planner--merge-scheduling-into-tasks
           temp-tasks decisions task-metadata '() "2026-03-24T13:00:00Z"))
    (should (string-match-p "SCHEDULED: <2026-03-20 09:00-10:00>" merged))
    (should-not (string-match-p "SCHEDULED: <2099-01-01 10:00-11:00>" merged))
    (should-not (string-match-p "SCHEDULED: <2099-01-01 11:00-12:00>" merged))
    (should (string-match-p "SCHEDULED: <2099-01-02 12:00-13:00>" merged))))

(ert-deftest sem-planner-test-merge-scheduling-enforces-overlap-policy ()
  "Test that overlap is blocked for non-high priority new tasks."
  (let* ((temp-tasks (concat "* TODO New low-priority task :work:\n"
                             ":PROPERTIES:\n"
                             ":ID: low-789\n"
                             ":END:\n"
                             "\n"
                             "* TODO New high-priority task [#A] :work:\n"
                             ":PROPERTIES:\n"
                             ":ID: high-789\n"
                             ":END:\n"))
         (decisions '(("low-789" . "<2099-01-02 09:30-10:00>")
                      ("high-789" . "<2099-01-02 09:45-10:15>")))
         (task-metadata (make-hash-table :test #'equal))
         (occupied-windows
          (list (list :id "existing-occupied"
                      :title "Existing window"
                      :scheduled "<2099-01-02 Fri 09:00-10:30>"
                      :range (cons
                              (float-time (encode-time 0 0 9 2 1 2099 t))
                              (float-time (encode-time 0 30 10 2 1 2099 t))))))
         (merged nil))
    (puthash "low-789"
             '(:id "low-789" :state newly-generated :priority nil)
             task-metadata)
    (puthash "high-789"
             '(:id "high-789" :state newly-generated :priority ?A)
             task-metadata)
    (setq merged
          (sem-planner--merge-scheduling-into-tasks
           temp-tasks decisions task-metadata occupied-windows "2026-03-24T13:00:00Z"))
    (should-not (string-match-p "SCHEDULED: <2099-01-02 09:30-10:00>" merged))
    (should (string-match-p "SCHEDULED: <2099-01-02 09:45-10:15>" merged))))

(ert-deftest sem-planner-test-merge-scheduling-replaces-existing-scheduled-line ()
  "Test that merge replaces preexisting SCHEDULED in a generated task section." 
  (let* ((temp-tasks (concat "* TODO Generated task :work:\n"
                             ":PROPERTIES:\n"
                             ":ID: generated-001\n"
                             ":FILETAGS: :work:\n"
                             ":END:\n"
                             "Body text\n"
                             "SCHEDULED: <2024-06-01 09:00-10:00>\n"))
         (decisions '(("generated-001" . "<2099-01-02 16:00-17:00>")))
         (task-metadata (make-hash-table :test #'equal))
         (merged nil))
    (puthash "generated-001"
             '(:id "generated-001" :state newly-generated :priority nil)
             task-metadata)
    (setq merged
          (sem-planner--merge-scheduling-into-tasks
           temp-tasks decisions task-metadata '() "2026-03-24T13:00:00Z"))
    (should (string-match-p "SCHEDULED: <2099-01-02 16:00-17:00>" merged))
    (should-not (string-match-p "SCHEDULED: <2024-06-01 09:00-10:00>" merged))))

(ert-deftest sem-planner-test-merge-scheduling-skips-user-fixed-schedule ()
  "Test a task whose capture carried its own schedule keeps it unchanged."
  (let* ((temp-tasks (concat "* TODO [#C] process quarterly financial reports :routine:\n"
                             ":PROPERTIES:\n"
                             ":ID: fixed-001\n"
                             ":FILETAGS: :routine:\n"
                             ":END:\n"
                             "SCHEDULED: <2026-03-20 Fri>\n"
                             "Body\n"))
         (decisions '(("fixed-001" . "<2099-01-02 16:00-17:00>")))
         (task-metadata (make-hash-table :test #'equal))
         (merged nil))
    (puthash "fixed-001"
             '(:id "fixed-001"
               :title "[#C] process quarterly financial reports"
               :fixed t
               :state newly-generated
               :priority ?C)
             task-metadata)
    (setq merged
          (sem-planner--merge-scheduling-into-tasks
           temp-tasks decisions task-metadata '() "2026-03-24T13:00:00Z"))
    (should (string-match-p "SCHEDULED: <2026-03-20 Fri>" merged))
    (should-not (string-match-p "SCHEDULED: <2099-01-02 16:00-17:00>" merged))))

(ert-deftest sem-planner-test-append-merged-strips-tasks-heading ()
  "Test that append strips a leading '* Tasks' heading from merged content."
  (let* ((tmp-dir (make-temp-file "sem-test-" t))
         (tasks-file (expand-file-name "tasks.org" tmp-dir))
         (sem-planner-tasks-file tasks-file))
    (unwind-protect
        (progn
          (write-region "* TODO Existing\n:PROPERTIES:\n:ID: existing-1\n:END:\n"
                        nil tasks-file nil 'silent)
          (should (sem-planner--append-merged-to-tasks-org
                   "* Tasks\n\n* TODO New\n:PROPERTIES:\n:ID: new-1\n:END:\n"))
          (with-temp-buffer
            (insert-file-contents tasks-file)
            (let ((content (buffer-string)))
              (should-not (string-match-p "^\\* Tasks$" content))
              (should (string-match-p "\\* TODO Existing" content))
              (should (string-match-p "\\* TODO New" content)))))
      (delete-directory tmp-dir t))))

(ert-deftest sem-planner-test-merge-scheduling-uses-runtime-min-start-without-utc-suffix ()
  "Test that runtime-min-start is passed directly to `date-to-time'."
  (let* ((temp-tasks (concat "* TODO New task :work:\n"
                             ":PROPERTIES:\n"
                             ":ID: new-runtime-123\n"
                             ":END:\n"))
         (decisions '(("new-runtime-123" . "<2099-01-02 12:00-13:00>")))
         (task-metadata (make-hash-table :test #'equal))
         (runtime-min-start "2026-03-24T16:09:59Z")
         (runtime-min-start-arg nil)
         (merged nil))
    (puthash "new-runtime-123"
             '(:id "new-runtime-123" :state newly-generated :priority nil)
             task-metadata)
    (cl-letf (((symbol-function 'date-to-time)
               (lambda (arg)
                 (setq runtime-min-start-arg arg)
                 (encode-time 0 0 0 1 1 2026 t))))
      (setq merged
            (sem-planner--merge-scheduling-into-tasks
             temp-tasks decisions task-metadata '() runtime-min-start)))
    (should (string= runtime-min-start-arg runtime-min-start))
    (should (string-match-p "SCHEDULED: <2099-01-02 12:00-13:00>" merged))))

(ert-deftest sem-planner-test-build-pass2-prompt-includes-runtime-bounds-and-strict-rule ()
  "Test that Pass 2 prompt includes runtime bounds and strict greater-than semantics."
  (cl-letf (((symbol-function 'sem-time-client-timezone)
             (lambda () "Europe/Belgrade")))
    (let ((prompt (sem-planner--build-pass2-prompt
                   "Tasks to schedule:\n- ID: abc | TAG:work | PRIORITY:none | STATE:newly-generated | (unscheduled)\n"
                   "(No existing tasks)"
                   "- OCCUPIED: <2026-03-24 Tue 16:00-17:00> | SOURCE_ID:existing-123"
                   ""
                   "2026-03-24T12:00:00+0100"
                   "2026-03-24T13:00:00+0100")))
      (should (string-match-p "RUNTIME SCHEDULING BOUNDS (Europe/Belgrade)" prompt))
      (should (string-match-p "runtime_now: 2026-03-24T12:00:00\\+0100" prompt))
      (should (string-match-p "runtime_min_start: 2026-03-24T13:00:00\\+0100" prompt))
      (should (string-match-p "strictly greater than runtime_min_start" prompt))
      (should (string-match-p "SCHEDULED equal to runtime_min_start is NOT allowed" prompt))
      (should (string-match-p "Avoid overlap with pre-existing occupied windows by default" prompt))
      (should (string-match-p "PRE-EXISTING OCCUPIED WINDOWS" prompt)))))

(ert-deftest sem-planner-test-run-with-retry-uses-medium-tier ()
  "Test Pass 2 planner requests sem-llm medium tier intent."
  (let ((captured-tier nil)
        (callback-result 'unset))
    (cl-letf (((symbol-function 'sem-llm-request)
               (lambda (_prompt _system callback _context &optional tier)
                 (setq captured-tier tier)
                 (funcall callback "ok" (list :status 200) nil)
                 nil)))
      (sem-planner--run-with-retry
       "rules"
       "existing"
       "occupied"
       "temp"
       "2026-03-24T12:00:00Z"
       "2026-03-24T13:00:00Z"
       (lambda (success response)
         (setq callback-result (list success response))))
      (should (eq captured-tier 'medium))
      (should (equal callback-result '(t "ok"))))))

;;; Temp File Path Tests

(ert-deftest sem-planner-test-temp-file-path-format ()
  "Test that temp file path follows expected format."
  (let ((sem-core--batch-id 42))
    (should (string-match-p "tasks-tmp-42.org" (sem-planner--temp-file-path)))))

(ert-deftest sem-planner-test-temp-file-path-explicit-batch-id ()
  "Test temp file path supports explicit batch id argument." 
  (let ((sem-core--batch-id 42))
    (should (string-match-p "tasks-tmp-99.org" (sem-planner--temp-file-path 99)))))

(ert-deftest sem-planner-test-run-planning-step-uses-owning-batch-temp-file ()
  "Test planner reads and deletes temp file for provided owning batch id." 
  (let ((read-batch nil)
        (delete-batch nil))
    (cl-letf (((symbol-function 'sem-planner--read-temp-file)
               (lambda (&optional batch-id)
                 (setq read-batch batch-id)
                 nil))
              ((symbol-function 'sem-planner--delete-temp-file)
               (lambda (&optional batch-id)
                 (setq delete-batch batch-id)))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil)))
      (sem-planner-run-planning-step 55)
      (should (= read-batch 55))
      (should-not delete-batch))))

;;; Validation Tests

(ert-deftest sem-planner-test-validate-planned-tasks-accepts-valid-simple-format ()
  "Test that validation passes for valid simple scheduling format."
  (let ((valid-response "ID: 5e7bc77c-0f40-41c8-b5a4-dcfeb28de8be | SCHEDULED: <2024-06-01 09:00-10:00>
ID: b96db7b3-e2cd-4983-ba79-5dd26a6d5215 | (unscheduled)"))
    (should (sem-planner--validate-planned-tasks valid-response))))

(ert-deftest sem-planner-test-validate-planned-tasks-rejects-invalid-response ()
  "Test that validation fails for invalid response."
  (let ((invalid-response "This is not org-mode"))
    (should-not (sem-planner--validate-planned-tasks invalid-response))))

(ert-deftest sem-planner-test-validate-planned-tasks-rejects-empty-response ()
  "Test that validation fails for empty response."
  (should-not (sem-planner--validate-planned-tasks ""))
  (should-not (sem-planner--validate-planned-tasks nil)))

(ert-deftest sem-planner-test-parse-scheduling-decisions-line-scoped-mixed-outcomes ()
  "Test parser maps adjacent mixed outcomes independently per line."
  (let* ((response
          (string-join
           '("ID: 11111111-1111-1111-1111-111111111111 | SCHEDULED: <2026-03-24 10:00-11:00>"
             "ID: 22222222-2222-2222-2222-222222222222 | (unscheduled)")
           "\n"))
         (parsed (sem-planner--parse-scheduling-decisions response)))
    (should (equal parsed
                   '(("11111111-1111-1111-1111-111111111111" . "<2026-03-24 10:00-11:00>")
                     ("22222222-2222-2222-2222-222222222222" . nil))))))

(ert-deftest sem-planner-test-parse-scheduling-decisions-ignores-unknown-lines ()
  "Test parser ignores non-decision lines and keeps valid line decisions."
  (let* ((response
          (string-join
           '("notes: this line is commentary"
             "ID: 33333333-3333-3333-3333-333333333333 | SCHEDULED: <2026-03-24 12:00-13:00>"
             "ID: 44444444-4444-4444-4444-444444444444 | maybe later"
             "ID: 55555555-5555-5555-5555-555555555555 | (unscheduled)")
           "\n"))
         (parsed (sem-planner--parse-scheduling-decisions response)))
    (should (equal parsed
                   '(("33333333-3333-3333-3333-333333333333" . "<2026-03-24 12:00-13:00>")
                     ("55555555-5555-5555-5555-555555555555" . nil))))))

(ert-deftest sem-planner-test-no-end-time-does-not-overlap-distant-same-day-task ()
  "Test no-end-time timestamp defaults to 30 minutes, not full-day overlap."
  (let* ((task-a "<2026-04-01 Wed 09:00>")
         (task-b "<2026-04-01 Wed 14:00>")
         (windows (list (list :id "existing"
                              :title "Existing"
                              :range (sem-planner--timestamp-to-epoch-range task-a)))))
    (should-not (sem-planner--overlapping-window task-b windows))))

(ert-deftest sem-planner-test-no-end-time-overlaps-within-thirty-minutes ()
  "Test no-end-time timestamp overlaps another task within 30 minutes."
  (let* ((task-a "<2026-04-01 Wed 09:00>")
         (task-b "<2026-04-01 Wed 09:15>")
         (windows (list (list :id "existing"
                              :title "Existing"
                              :range (sem-planner--timestamp-to-epoch-range task-a)))))
    (should (sem-planner--overlapping-window task-b windows))))

;;; Atomic Update Tests

(ert-deftest sem-planner-test-atomic-update-creates-file-if-nonexistent ()
  "Test that atomic update creates tasks.org if it doesn't exist."
  (let* ((tmp-dir (make-temp-file "sem-test-" t))
         (tasks-file (expand-file-name "tasks.org" tmp-dir))
         (planned-tasks "* TODO New task :routine:
:PROPERTIES:
:ID: new-123
:END:")
         (sem-planner-tasks-file tasks-file))
    (unwind-protect
        (progn
          (should-not (file-exists-p tasks-file))
          (should (sem-planner--atomic-tasks-org-update planned-tasks))
          (should (file-exists-p tasks-file))
          (with-temp-buffer
            (insert-file-contents tasks-file)
            (goto-char (point-min))
            (should (re-search-forward "TODO" nil t))))
      (delete-directory tmp-dir t))))

;;; Fallback Tests

(ert-deftest sem-planner-test-fallback-reads-temp-file ()
  "Test that fallback reads content from temp file."
  (let* ((sem-core--batch-id 99)
         (temp-file (sem-planner--temp-file-path))
         (content "* TODO Fallback task :work:\n:PROPERTIES:\n:ID: fb-123\n:END:"))
    (unwind-protect
        (progn
          (make-directory (file-name-directory temp-file) t)
          (write-region content nil temp-file nil 'silent)
          (should (stringp (sem-planner--read-temp-file)))
          (should (string-match-p "Fallback task" (sem-planner--read-temp-file))))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

(ert-deftest sem-planner-test-conflict-mismatch-retries-with-fresh-context ()
  "Test that hash mismatch triggers replanning and eventual append success."
  (let* ((temp-tasks (concat "* TODO New task :work:\n"
                             ":PROPERTIES:\n"
                             ":ID: 5e7bc77c-0f40-41c8-b5a4-dcfeb28de8be\n"
                             ":END:\n"))
         (llm-response "ID: 5e7bc77c-0f40-41c8-b5a4-dcfeb28de8be | SCHEDULED: <2099-01-02 10:00-11:00>")
         (run-count 0)
         (append-count 0)
         (delete-called nil)
         (base-hashes '("base-a" "base-b"))
         (pre-append-hashes '("mismatch" "base-b"))
         (conflict-retry-logs 0))
    (cl-letf (((symbol-function 'sem-planner--read-temp-file)
               (lambda (&optional _batch-id) temp-tasks))
              ((symbol-function 'sem-rules-read)
               (lambda () ""))
              ((symbol-function 'sem-planner--content-hash)
               (lambda (_content)
                 (prog1 (car base-hashes)
                   (setq base-hashes (cdr base-hashes)))))
              ((symbol-function 'sem-planner--tasks-file-hash)
               (lambda ()
                 (prog1 (car pre-append-hashes)
                   (setq pre-append-hashes (cdr pre-append-hashes)))))
              ((symbol-function 'sem-planner--run-with-retry)
               (lambda (&rest args)
                 (let ((callback (nth 6 args)))
                   (setq run-count (1+ run-count))
                   (funcall callback t llm-response))))
              ((symbol-function 'sem-planner--append-merged-to-tasks-org)
               (lambda (_merged)
                 (setq append-count (1+ append-count))
                 t))
              ((symbol-function 'sem-planner--delete-temp-file)
               (lambda (&optional _batch-id)
                 (setq delete-called t)))
              ((symbol-function 'sem-core-log)
               (lambda (_module _event status message _raw)
                 (when (and (string= status "RETRY")
                            (string-match-p "Conflict detected before append" message))
                   (setq conflict-retry-logs (1+ conflict-retry-logs))))))
      (sem-planner-run-planning-step)
      (should (= run-count 2))
      (should (= append-count 1))
      (should delete-called)
      (should (= conflict-retry-logs 1)))))

(ert-deftest sem-planner-test-conflict-retry-exhaustion-returns-non-success ()
  "Test that repeated hash mismatches end with explicit non-success and no append."
  (let* ((temp-tasks (concat "* TODO New task :work:\n"
                             ":PROPERTIES:\n"
                             ":ID: b96db7b3-e2cd-4983-ba79-5dd26a6d5215\n"
                             ":END:\n"))
         (llm-response "ID: b96db7b3-e2cd-4983-ba79-5dd26a6d5215 | SCHEDULED: <2099-01-02 11:00-12:00>")
         (run-count 0)
         (append-count 0)
         (fallback-called nil)
         (base-hashes '("base-1" "base-2" "base-3"))
         (pre-append-hashes '("x-1" "x-2" "x-3"))
         (error-logs 0)
         (sem-planner--conflict-max-attempts 3))
    (cl-letf (((symbol-function 'sem-planner--read-temp-file)
               (lambda (&optional _batch-id) temp-tasks))
              ((symbol-function 'sem-rules-read)
               (lambda () ""))
              ((symbol-function 'sem-planner--content-hash)
               (lambda (_content)
                 (prog1 (car base-hashes)
                   (setq base-hashes (cdr base-hashes)))))
              ((symbol-function 'sem-planner--tasks-file-hash)
               (lambda ()
                 (prog1 (car pre-append-hashes)
                   (setq pre-append-hashes (cdr pre-append-hashes)))))
              ((symbol-function 'sem-planner--run-with-retry)
               (lambda (&rest args)
                 (let ((callback (nth 6 args)))
                   (setq run-count (1+ run-count))
                   (funcall callback t llm-response))))
              ((symbol-function 'sem-planner--append-merged-to-tasks-org)
               (lambda (_merged)
                 (setq append-count (1+ append-count))
                 t))
              ((symbol-function 'sem-planner--fallback-to-pass1)
               (lambda (&optional _batch-id)
                 (setq fallback-called t)
                 t))
              ((symbol-function 'sem-core-log-error)
               (lambda (_module _event _message _input _raw)
                 (setq error-logs (1+ error-logs)))))
      (sem-planner-run-planning-step)
      (should (= run-count sem-planner--conflict-max-attempts))
      (should (= append-count 0))
      (should fallback-called)
      (should (> error-logs 0)))))

(ert-deftest sem-planner-test-explicit-non-success-preserves-pass1-via-fallback ()
  "Test explicit non-success triggers Pass 1 fallback preservation."
  (let ((fallback-batch nil))
    (cl-letf (((symbol-function 'sem-planner--read-temp-file)
               (lambda (&optional _batch-id)
                 "* TODO Preserved fallback task\n:PROPERTIES:\n:ID: preserve-1\n:END:\n"))
              ((symbol-function 'sem-rules-read)
               (lambda () ""))
              ((symbol-function 'sem-planner--run-with-retry)
               (lambda (&rest args)
                 (let ((callback (nth 6 args)))
                   (funcall callback nil nil))))
              ((symbol-function 'sem-planner--fallback-to-pass1)
               (lambda (&optional batch-id)
                 (setq fallback-batch batch-id)
                 t))
              ((symbol-function 'sem-core-log-error)
               (lambda (&rest _) nil)))
      (sem-planner-run-planning-step 77)
      (should (= fallback-batch 77)))))

(ert-deftest sem-planner-test-explicit-non-success-fallback-failure-keeps-temp-file ()
  "Test fallback failure does not trigger temp-file deletion in failure branch."
  (let ((delete-called nil))
    (cl-letf (((symbol-function 'sem-planner--read-temp-file)
               (lambda (&optional _batch-id)
                 "* TODO Pending fallback task\n:PROPERTIES:\n:ID: preserve-2\n:END:\n"))
              ((symbol-function 'sem-rules-read)
               (lambda () ""))
              ((symbol-function 'sem-planner--run-with-retry)
               (lambda (&rest args)
                 (let ((callback (nth 6 args)))
                   (funcall callback nil nil))))
              ((symbol-function 'sem-planner--fallback-to-pass1)
               (lambda (&optional _batch-id)
                 nil))
              ((symbol-function 'sem-planner--delete-temp-file)
               (lambda (&optional _batch-id)
                 (setq delete-called t)))
              ((symbol-function 'sem-core-log-error)
               (lambda (&rest _) nil)))
      (sem-planner-run-planning-step 88)
      (should-not delete-called))))

;;; Planning line placement

(ert-deftest sem-planner-test-merge-puts-scheduled-on-planning-line ()
  "Test merged SCHEDULED lands directly under the headline, where Org reads it."
  (let* ((temp-tasks (concat "* TODO New task :work:\n"
                             ":PROPERTIES:\n"
                             ":ID: plan-001\n"
                             ":END:\n"
                             "Body\n"
                             "DEADLINE: <2099-01-05 Mon>\n"))
         (task-metadata (make-hash-table :test #'equal)))
    (puthash "plan-001" '(:id "plan-001" :state newly-generated :priority nil) task-metadata)
    (let ((merged (sem-planner--merge-scheduling-into-tasks
                   temp-tasks '(("plan-001" . "<2099-01-02 12:00-13:00>"))
                   task-metadata '() "2026-03-24T13:00:00Z")))
      (should (string-prefix-p
               "* TODO New task :work:\nSCHEDULED: <2099-01-02 12:00-13:00> DEADLINE: <2099-01-05 Mon>\n:PROPERTIES:"
               merged)))))

(ert-deftest sem-planner-test-planning-reads-legacy-misplaced-lines ()
  "Test SCHEDULED written after the drawer by older versions is still read."
  (with-temp-buffer
    (insert "* TODO Legacy :work:\n:PROPERTIES:\n:ID: x\n:END:\nSCHEDULED: <2026-03-20 Fri 09:00-10:00>\n* TODO Next\n")
    (org-mode)
    (let ((headlines (org-element-map (org-element-parse-buffer) 'headline #'identity)))
      (should (equal (sem-planner--planning (car headlines) 'scheduled)
                     "<2026-03-20 Fri 09:00-10:00>"))
      (should-not (sem-planner--planning (cadr headlines) 'scheduled)))))

(provide 'sem-planner-test)
;;; sem-planner-test.el ends here
