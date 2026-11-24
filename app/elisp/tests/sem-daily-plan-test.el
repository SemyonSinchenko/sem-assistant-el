;;; sem-daily-plan-test.el --- Tests for sem-daily-plan.el -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Tests for daily plan task collection, response parsing, rendering and the
;; LLM-failure fallback.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'sem-mock)

(load-file (expand-file-name "../sem-core.el" (file-name-directory load-file-name)))
(load-file (expand-file-name "../sem-rules.el" (file-name-directory load-file-name)))
(load-file (expand-file-name "../sem-prompts.el" (file-name-directory load-file-name)))
(load-file (expand-file-name "../sem-planner.el" (file-name-directory load-file-name)))
(load-file (expand-file-name "../sem-daily-plan.el" (file-name-directory load-file-name)))

(defconst sem-daily-plan-test--tasks
  "* TODO [#B] Overdue report :work:
SCHEDULED: <2026-11-20 Fri 10:00-11:00>
:PROPERTIES:
:ID: id-overdue
:EFFORT: 1:00
:END:
Draft the summary.
#+begin_sensitive
secret-token-123
#+end_sensitive
* TODO Fixed call :family:
SCHEDULED: <2026-11-24 Tue 12:00-12:30>
:PROPERTIES:
:ID: id-today
:END:
* TODO Legacy misplaced :work:
:PROPERTIES:
:ID: id-legacy
:END:
SCHEDULED: <2026-11-22 Sun 09:00-10:00>
* TODO Tax form :routine:
DEADLINE: <2026-11-27 Fri>
* TODO [#C] Low backlog :routine:
* TODO [#A] Urgent backlog :work:
:PROPERTIES:
:ID: id-urgent
:END:
* DONE Finished thing :work:
SCHEDULED: <2026-11-19 Thu>
* TODO Far future :work:
SCHEDULED: <2026-12-20 Sun>
"
  "Task file fixture relative to 2026-11-24 08:00 UTC.")

(defun sem-daily-plan-test--now ()
  "Return the fixture time."
  (encode-time 0 0 8 24 11 2026 "Etc/UTC"))

(defmacro sem-daily-plan-test--with-utc (&rest body)
  "Run BODY with the client timezone forced to UTC."
  `(cl-letf (((symbol-function 'sem-time-client-timezone) (lambda () "Etc/UTC")))
     ,@body))

(defun sem-daily-plan-test--titles (items)
  "Return titles of ITEMS."
  (mapcar (lambda (item) (plist-get item :title)) items))

(ert-deftest sem-daily-plan-test-collect-classifies-tasks ()
  "Test open tasks are split into overdue, today, upcoming and backlog."
  (sem-daily-plan-test--with-utc
   (let ((tasks (sem-daily-plan--collect sem-daily-plan-test--tasks
                                         (sem-daily-plan-test--now))))
     (should (equal (sem-daily-plan-test--titles (plist-get tasks :overdue))
                    '("Overdue report" "Legacy misplaced")))
     (should (equal (sem-daily-plan-test--titles (plist-get tasks :today))
                    '("Fixed call")))
     (should (equal (sem-daily-plan-test--titles (plist-get tasks :upcoming))
                    '("Tax form")))
     ;; Priority A before C; DONE and future-scheduled tasks are excluded.
     (should (equal (sem-daily-plan-test--titles (plist-get tasks :backlog))
                    '("Urgent backlog" "Low backlog"))))))

(ert-deftest sem-daily-plan-test-prompt-excludes-sensitive-content ()
  "Test task excerpts drop sensitive blocks and drawers."
  (sem-daily-plan-test--with-utc
   (let* ((now (sem-daily-plan-test--now))
          (tasks (sem-daily-plan--collect sem-daily-plan-test--tasks now))
          (prompt (sem-daily-plan--build-prompt tasks "Work 9-18" now)))
     (should (string-match-p "Draft the summary" prompt))
     (should-not (string-match-p "secret-token-123" prompt))
     (should-not (string-match-p ":PROPERTIES:" prompt))
     (should (string-match-p "Work 9-18" prompt)))))

(ert-deftest sem-daily-plan-test-parse-response-validates-lines ()
  "Test unknown refs, malformed times and duplicates are dropped."
  (let ((parsed (sem-daily-plan--parse-response
                 (concat "FOCUS: Ship the report\n"
                         "PLAN: T2 | 14:00-15:00 | second | open doc\n"
                         "PLAN: T1 | 09:00-10:00 | overdue first | open the draft\n"
                         "PLAN: T1 | 11:00-12:00 | duplicate | x\n"
                         "PLAN: T9 | 10:00-11:00 | unknown ref | x\n"
                         "PLAN: T3 | 11:00-10:00 | reversed | x\n"
                         "DEFER: T4 | not urgent | 2026-11-28\n"
                         "DEFER: T5 | obsolete | drop\n"
                         "chatter that is ignored\n")
                 '("T1" "T2" "T3" "T4" "T5"))))
    (should (string= (plist-get parsed :focus) "Ship the report"))
    (should (equal (mapcar (lambda (p) (plist-get p :ref)) (plist-get parsed :plan))
                   '("T1" "T2")))
    (should (equal (mapcar (lambda (d) (plist-get d :date)) (plist-get parsed :defer))
                   '("2026-11-28" "drop")))))

(ert-deftest sem-daily-plan-test-generate-writes-plan-file ()
  "Test an LLM-backed plan is rendered with links, time blocks and steps."
  (let* ((dir (make-temp-file "sem-daily-plan-" t))
         (sem-daily-plan-file (expand-file-name "daily-plan.org" dir))
         (sem-planner-tasks-file (expand-file-name "tasks.org" dir))
         (success :unset))
    (unwind-protect
        (sem-daily-plan-test--with-utc
         (write-region sem-daily-plan-test--tasks nil sem-planner-tasks-file nil 'silent)
         (cl-letf (((symbol-function 'sem-rules-read) (lambda () nil))
                   ((symbol-function 'sem-core-log) (lambda (&rest _) nil))
                   ((symbol-function 'sem-llm-request)
                    (lambda (_prompt _system callback context &optional tier)
                      (should (eq tier 'medium))
                      (funcall callback
                               (concat "FOCUS: Clear the overdue report\n"
                                       "PLAN: T1 | 09:00-10:00 | overdue since Friday | open the draft\n"
                                       "DEFER: T3 | waiting on input | 2026-11-26\n")
                               nil context))))
           (sem-daily-plan--generate (sem-daily-plan-test--now)
                                     (lambda (ok) (setq success ok))))
         (should (eq success t))
         (let ((plan (with-temp-buffer
                       (insert-file-contents sem-daily-plan-file)
                       (buffer-string))))
           (should (string-match-p "^#\\+TITLE: Daily plan 2026-11-24 Tue" plan))
           (should (string-match-p "Clear the overdue report" plan))
           (should (string-match-p
                    "- \\[ \\] <2026-11-24 Tue 09:00-10:00> \\[#B\\] \\[\\[id:id-overdue\\]\\[Overdue report\\]\\] :work:"
                    plan))
           (should (string-match-p "First step: open the draft" plan))
           (should (string-match-p "Legacy misplaced.*-> \\[2026-11-26\\]" plan))
           (should (string-match-p "Fixed call" plan))
           (should (string-match-p "Tax form" plan))
           (should-not (string-match-p "secret-token-123" plan))))
      (delete-directory dir t))))

(ert-deftest sem-daily-plan-test-llm-failure-writes-fallback-plan ()
  "Test an LLM failure still writes a plan listing the tasks."
  (let* ((dir (make-temp-file "sem-daily-plan-" t))
         (sem-daily-plan-file (expand-file-name "daily-plan.org" dir))
         (sem-planner-tasks-file (expand-file-name "tasks.org" dir))
         (success :unset))
    (unwind-protect
        (sem-daily-plan-test--with-utc
         (write-region sem-daily-plan-test--tasks nil sem-planner-tasks-file nil 'silent)
         (cl-letf (((symbol-function 'sem-rules-read) (lambda () nil))
                   ((symbol-function 'sem-core-log) (lambda (&rest _) nil))
                   ((symbol-function 'sem-llm-request)
                    (lambda (_prompt _system callback context &optional _tier)
                      (funcall callback nil (list :error "HTTP 500") context))))
           (sem-daily-plan--generate (sem-daily-plan-test--now)
                                     (lambda (ok) (setq success ok))))
         (should (null success))
         (let ((plan (with-temp-buffer
                       (insert-file-contents sem-daily-plan-file)
                       (buffer-string))))
           (should (string-match-p "Planning request failed (HTTP 500)" plan))
           (should (string-match-p "\\* Other overdue" plan))
           (should (string-match-p "Overdue report" plan))))
      (delete-directory dir t))))

(provide 'sem-daily-plan-test)
;;; sem-daily-plan-test.el ends here
