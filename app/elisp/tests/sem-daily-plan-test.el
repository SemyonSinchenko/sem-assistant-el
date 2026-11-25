;;; sem-daily-plan-test.el --- Tests for sem-daily-plan.el -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Tests for daily plan task collection, recurring busy slots, response
;; parsing and validation, in-place edits of tasks.org and the hash-checked
;; commit with restart on conflicts.

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
  "#+TITLE: Tasks

* TODO [#B] Overdue report :work:
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
* TODO Buy milk :routine:
SCHEDULED: <2026-11-24 Tue>
* TODO Tax form :routine:
DEADLINE: <2026-11-27 Fri>
* TODO [#C] Low backlog :routine:
* TODO [#A] Urgent backlog :work:
:PROPERTIES:
:ID: id-urgent
:END:
** Child note
Child body stays.
* TODO Old idea :routine:drop_suggested:
* DONE Finished thing :work:
SCHEDULED: <2026-11-19 Thu>
* TODO Far future :work:
SCHEDULED: <2026-12-20 Sun>
"
  "Task file fixture relative to 2026-11-24 08:00 UTC.")

(defconst sem-daily-plan-test--rec-tasks
  "* TODO Gym :routine:
SCHEDULED: <2026-11-03 Tue 18:00-19:00 +1w>
* TODO Standup :work:
SCHEDULED: <2026-11-01 Sun 09:30-09:45 +1d>
* TODO Monthly bills :routine:
SCHEDULED: <2026-11-05 Thu 10:00 +1m>
"
  "Recurring tasks fixture: Gym and Standup occur on 2026-11-24.")

(defun sem-daily-plan-test--now ()
  "Return the fixture time."
  (encode-time 0 0 8 24 11 2026 "Etc/UTC"))

(defmacro sem-daily-plan-test--with-utc (&rest body)
  "Run BODY with the client timezone forced to UTC."
  `(cl-letf (((symbol-function 'sem-time-client-timezone) (lambda () "Etc/UTC")))
     ,@body))

(defmacro sem-daily-plan-test--with-files (&rest body)
  "Run BODY with tasks, rec-tasks and backup paths in a temp directory."
  `(let* ((dir (make-temp-file "sem-daily-plan-" t))
          (sem-planner-tasks-file (expand-file-name "tasks.org" dir))
          (sem-daily-plan-rec-tasks-file (expand-file-name "rec-tasks.org" dir))
          (sem-daily-plan-backup-dir (expand-file-name "backups/" dir)))
     (unwind-protect
         (sem-daily-plan-test--with-utc
          (write-region sem-daily-plan-test--tasks nil sem-planner-tasks-file nil 'silent)
          (write-region sem-daily-plan-test--rec-tasks nil sem-daily-plan-rec-tasks-file
                        nil 'silent)
          (cl-letf (((symbol-function 'sem-rules-read) (lambda () nil))
                    ((symbol-function 'sem-core-log) (lambda (&rest _) nil))
                    ((symbol-function 'sem-core-log-error) (lambda (&rest _) nil)))
            ,@body))
       (delete-directory dir t))))

(defun sem-daily-plan-test--titles (items)
  "Return titles of ITEMS."
  (mapcar (lambda (item) (plist-get item :title)) items))

(defun sem-daily-plan-test--ref (tasks title)
  "Return the ref of the task called TITLE in classified TASKS."
  (plist-get (cl-find title (sem-daily-plan--movable tasks)
                      :key (lambda (i) (plist-get i :title)) :test #'string=)
             :ref))

(defun sem-daily-plan-test--read-tasks ()
  "Return the current content of the test tasks file."
  (with-temp-buffer
    (insert-file-contents sem-planner-tasks-file)
    (buffer-string)))

(ert-deftest sem-daily-plan-test-collect-classifies-tasks ()
  "Test open tasks are split into movable categories and busy slots."
  (sem-daily-plan-test--with-utc
   (let ((tasks (sem-daily-plan--collect sem-daily-plan-test--tasks
                                         (sem-daily-plan-test--now))))
     (should (equal (sem-daily-plan-test--titles (plist-get tasks :overdue))
                    '("Overdue report" "Legacy misplaced")))
     (should (equal (sem-daily-plan-test--titles (plist-get tasks :untimed))
                    '("Buy milk")))
     (should (equal (sem-daily-plan-test--titles (plist-get tasks :upcoming))
                    '("Tax form")))
     ;; Priority A before C; DONE, future and drop-suggested tasks are excluded.
     (should (equal (sem-daily-plan-test--titles (plist-get tasks :backlog))
                    '("Urgent backlog" "Low backlog")))
     (should (equal (plist-get tasks :busy)
                    '((:start "12:00" :end "12:30" :title "Fixed call")))))))

(ert-deftest sem-daily-plan-test-recurring-busy-expands-repeaters ()
  "Test recurring tasks occurring today become busy slots."
  (sem-daily-plan-test--with-utc
   (let ((busy (sem-daily-plan--recurring-busy sem-daily-plan-test--rec-tasks
                                               (sem-daily-plan-test--now))))
     (should (equal (sem-daily-plan-test--titles busy) '("Gym" "Standup")))
     (should (equal (plist-get (car busy) :start) "18:00")))))

(ert-deftest sem-daily-plan-test-prompt-excludes-sensitive-content ()
  "Test the prompt lists busy slots and drops sensitive blocks and drawers."
  (sem-daily-plan-test--with-utc
   (let* ((now (sem-daily-plan-test--now))
          (tasks (sem-daily-plan--collect sem-daily-plan-test--tasks now))
          (prompt (sem-daily-plan--build-prompt
                   tasks '((:start "09:30" :end "09:45" :title "Standup")) "Work 9-18" now)))
     (should (string-match-p "Draft the summary" prompt))
     (should (string-match-p "09:30-09:45 Standup" prompt))
     (should-not (string-match-p "secret-token-123" prompt))
     (should-not (string-match-p ":PROPERTIES:" prompt))
     (should (string-match-p "Work 9-18" prompt)))))

(ert-deftest sem-daily-plan-test-parse-response ()
  "Test unknown refs, malformed lines and duplicate refs are dropped."
  (let ((decisions (sem-daily-plan--parse-response
                    (concat "- PLAN: T2 | 14:00-15:00\n"
                            "PLAN: T1 | 09:00 - 10:00 | extra reason\n"
                            "DEFER: T1 | 2026-11-28\n"
                            "PLAN: T9 | 10:00-11:00\n"
                            "DEFER: T4 | tomorrow\n"
                            "DROP: T5\n"
                            "chatter that is ignored\n")
                    '("T1" "T2" "T3" "T4" "T5"))))
    (should (equal (mapcar (lambda (d) (list (plist-get d :ref) (plist-get d :action)))
                           decisions)
                   '(("T2" plan) ("T1" plan) ("T5" drop))))
    (should (string= (plist-get (cadr decisions) :end) "10:00"))))

(ert-deftest sem-daily-plan-test-validate-rejects-unsafe-decisions ()
  "Test overlaps, past times, past dates and non-overdue drops are rejected."
  (sem-daily-plan-test--with-utc
   (let* ((now (sem-daily-plan-test--now))
          (tasks (sem-daily-plan--collect sem-daily-plan-test--tasks now))
          (ref (lambda (title) (sem-daily-plan-test--ref tasks title)))
          (busy (plist-get tasks :busy))
          (accepted
           (sem-daily-plan--validate
            (list (list :ref (funcall ref "Overdue report") :action 'plan
                        :start "09:00" :end "10:00")
                  (list :ref (funcall ref "Legacy misplaced") :action 'plan
                        :start "09:30" :end "10:30")   ; overlaps previous block
                  (list :ref (funcall ref "Buy milk") :action 'plan
                        :start "12:15" :end "12:45")   ; overlaps busy slot
                  (list :ref (funcall ref "Urgent backlog") :action 'plan
                        :start "07:00" :end "07:30")   ; before now
                  (list :ref (funcall ref "Tax form") :action 'defer
                        :date "2026-11-30")            ; after its deadline
                  (list :ref (funcall ref "Low backlog") :action 'drop)
                  (list :ref (funcall ref "Low backlog") :action 'defer
                        :date "2026-11-24"))           ; not in the future
            tasks busy now)))
     (should (equal (mapcar (lambda (d) (plist-get d :ref)) accepted)
                    (list (funcall ref "Overdue report")))))))

(ert-deftest sem-daily-plan-test-apply-edits-only-planning ()
  "Test applying decisions rewrites planning lines and leaves the rest intact."
  (sem-daily-plan-test--with-utc
   (let* ((now (sem-daily-plan-test--now))
          (tasks (sem-daily-plan--collect sem-daily-plan-test--tasks now))
          (ref (lambda (title) (sem-daily-plan-test--ref tasks title)))
          (result
           (sem-daily-plan--apply
            sem-daily-plan-test--tasks tasks
            (list (list :ref (funcall ref "Overdue report") :action 'plan
                        :start "09:00" :end "10:00")
                  (list :ref (funcall ref "Legacy misplaced") :action 'defer
                        :date "2026-11-26")
                  (list :ref (funcall ref "Urgent backlog") :action 'plan
                        :start "14:00" :end "15:00")
                  (list :ref (funcall ref "Tax form") :action 'plan
                        :start "16:00" :end "16:30"))
            now)))
     (should (string-match-p
              (concat "^\\* TODO \\[#B\\] Overdue report :work:\n"
                      "SCHEDULED: <2026-11-24 Tue 09:00-10:00>\n"
                      ":PROPERTIES:\n:ID: id-overdue\n:EFFORT: 1:00\n"
                      ":SEM_DAILY_PLAN: 2026-11-24 plan\n:END:\n")
              result))
     ;; The misplaced planning line is moved under the headline.
     (should (string-match-p
              "^\\* TODO Legacy misplaced :work:\nSCHEDULED: <2026-11-26 Thu>\n" result))
     (should-not (string-match-p "2026-11-22" result))
     ;; DEADLINE is kept next to the new SCHEDULED.
     (should (string-match-p
              "SCHEDULED: <2026-11-24 Tue 16:00-16:30> DEADLINE: <2026-11-27 Fri>" result))
     ;; Unscheduled backlog gets a planning line; the child heading is untouched.
     (should (string-match-p
              (concat "^\\* TODO \\[#A\\] Urgent backlog :work:\n"
                      "SCHEDULED: <2026-11-24 Tue 14:00-15:00>\n")
              result))
     (should (string-match-p "^\\*\\* Child note\nChild body stays.\n" result))
     ;; Untouched entries and the sensitive block are byte-identical.
     (should (string-match-p "#\\+begin_sensitive\nsecret-token-123\n#\\+end_sensitive" result))
     (should (string-match-p "^\\* TODO Fixed call :family:\nSCHEDULED: <2026-11-24 Tue 12:00-12:30>"
                             result))
     (should (string-prefix-p "#+TITLE: Tasks\n\n" result)))))

(ert-deftest sem-daily-plan-test-apply-drop-unschedules-and-tags ()
  "Test DROP removes SCHEDULED and adds the drop tag."
  (sem-daily-plan-test--with-utc
   (let* ((now (sem-daily-plan-test--now))
          (tasks (sem-daily-plan--collect sem-daily-plan-test--tasks now))
          (result (sem-daily-plan--apply
                   sem-daily-plan-test--tasks tasks
                   (list (list :ref (sem-daily-plan-test--ref tasks "Overdue report")
                               :action 'drop))
                   now)))
     (should (string-match-p
              (concat "^\\* TODO \\[#B\\] Overdue report :work:drop_suggested:\n"
                      ":PROPERTIES:\n")
              result))
     (should-not (string-match-p "2026-11-20" result)))))

(ert-deftest sem-daily-plan-test-generate-writes-tasks-org ()
  "Test an LLM-backed plan is written into tasks.org with a backup."
  (sem-daily-plan-test--with-files
   (let ((status :unset) (prompt-seen nil))
     (cl-letf (((symbol-function 'sem-llm-request)
                (lambda (prompt _system callback context &optional tier)
                  (should (eq tier 'medium))
                  (setq prompt-seen prompt)
                  (funcall callback
                           (concat "PLAN: T1 | 10:00-11:00\n"
                                   "DEFER: T3 | 2026-11-26\n"
                                   "PLAN: T4 | 09:30-10:00\n")   ; overlaps Standup
                           nil context))))
       (sem-daily-plan--generate (sem-daily-plan-test--now)
                                 (lambda (s) (setq status s))))
     (should (eq status 'written))
     (should (string-match-p "09:30-09:45 Standup" prompt-seen))
     (let ((content (sem-daily-plan-test--read-tasks)))
       (should (string-match-p "SCHEDULED: <2026-11-24 Tue 10:00-11:00>" content))
       (should (string-match-p "Legacy misplaced :work:\nSCHEDULED: <2026-11-26 Thu>" content))
       (should (string-match-p "Buy milk :routine:\nSCHEDULED: <2026-11-24 Tue>" content)))
     (let ((backups (directory-files sem-daily-plan-backup-dir t "\\.org\\'")))
       (should (= (length backups) 1))
       (should (string= (with-temp-buffer
                          (insert-file-contents (car backups))
                          (buffer-string))
                        sem-daily-plan-test--tasks))))))

(ert-deftest sem-daily-plan-test-generate-restarts-on-conflict ()
  "Test a tasks.org change during the LLM call restarts with fresh content."
  (sem-daily-plan-test--with-files
   (let ((status :unset) (calls 0))
     (cl-letf (((symbol-function 'sem-llm-request)
                (lambda (prompt _system callback context &optional _tier)
                  (setq calls (1+ calls))
                  (when (= calls 1)
                    ;; A phone edit lands while the first request is in flight.
                    (write-region (concat sem-daily-plan-test--tasks "* TODO Phone task\n")
                                  nil sem-planner-tasks-file nil 'silent))
                  (when (= calls 2)
                    (should (string-match-p "Phone task" prompt)))
                  (funcall callback "PLAN: T1 | 10:00-11:00\n" nil context))))
       (sem-daily-plan--generate (sem-daily-plan-test--now)
                                 (lambda (s) (setq status s))))
     (should (= calls 2))
     (should (eq status 'written))
     (let ((content (sem-daily-plan-test--read-tasks)))
       (should (string-match-p "^\\* TODO Phone task" content))
       (should (string-match-p "SCHEDULED: <2026-11-24 Tue 10:00-11:00>" content)))
     (should-not (file-exists-p (concat sem-planner-tasks-file ".daily-plan.tmp"))))))

(ert-deftest sem-daily-plan-test-generate-gives-up-after-max-conflicts ()
  "Test the run stops after the conflict budget and keeps the latest file."
  (sem-daily-plan-test--with-files
   (let ((status :unset) (calls 0) (sem-planner--conflict-max-attempts 2))
     (cl-letf (((symbol-function 'sem-llm-request)
                (lambda (_prompt _system callback context &optional _tier)
                  (setq calls (1+ calls))
                  (write-region (format "* TODO Edit %d\n" calls)
                                nil sem-planner-tasks-file t 'silent)
                  (funcall callback "PLAN: T1 | 10:00-11:00\n" nil context))))
       (sem-daily-plan--generate (sem-daily-plan-test--now)
                                 (lambda (s) (setq status s))))
     (should (= calls 2))
     (should (eq status 'conflict))
     (should-not (string-match-p "2026-11-24 Tue 10:00-11:00" (sem-daily-plan-test--read-tasks))))))

(ert-deftest sem-daily-plan-test-llm-failure-leaves-tasks-unchanged ()
  "Test an LLM failure does not touch tasks.org."
  (sem-daily-plan-test--with-files
   (let ((status :unset))
     (cl-letf (((symbol-function 'sem-llm-request)
                (lambda (_prompt _system callback context &optional _tier)
                  (funcall callback nil (list :error "HTTP 500") context))))
       (sem-daily-plan--generate (sem-daily-plan-test--now)
                                 (lambda (s) (setq status s))))
     (should (eq status 'failed))
     (should (string= (sem-daily-plan-test--read-tasks) sem-daily-plan-test--tasks)))))

(provide 'sem-daily-plan-test)
;;; sem-daily-plan-test.el ends here
