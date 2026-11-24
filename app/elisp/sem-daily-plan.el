;;; sem-daily-plan.el --- Morning day plan from the task backlog -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Every morning this module reads tasks.org, collects overdue tasks, tasks
;; already scheduled for today, near deadlines and the unscheduled backlog,
;; and asks the LLM to pick a realistic set of tasks for the day with time
;; blocks, a reason and a concrete first step.  Overdue tasks that do not fit
;; get a reschedule-or-drop suggestion.
;;
;; The LLM only returns short structured lines that reference tasks by a
;; local ref (T1, T2, ...).  The daemon validates them and renders
;; /data/tasks/daily-plan.org deterministically.  tasks.org is never modified:
;; the plan is a proposal the user acts on from the phone or Emacs.  When the
;; LLM call fails, a plan without suggestions is still written.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'sem-core)
(require 'sem-time)
(require 'sem-rules)
(require 'sem-llm)
(require 'sem-planner)

(defconst sem-daily-plan-file "/data/tasks/daily-plan.org"
  "Path to the generated daily plan.")

(defconst sem-daily-plan-deadline-horizon-days 7
  "Deadlines within this many days are listed as upcoming.")

(defconst sem-daily-plan-max-items
  '(:overdue 30 :today 30 :upcoming 20 :backlog 40)
  "Maximum number of tasks per category sent to the LLM.")

(defconst sem-daily-plan-excerpt-chars 200
  "Maximum characters of task body included as context.")

;;; Task Collection

(defun sem-daily-plan--timestamp-date (timestamp)
  "Return the YYYY-MM-DD date of org TIMESTAMP (object or string), or nil."
  (let ((parts (and timestamp (sem-planner--parse-timestamp timestamp))))
    (when parts
      (format "%04d-%02d-%02d" (nth 0 parts) (nth 1 parts) (nth 2 parts)))))

(defun sem-daily-plan--timestamp-string (timestamp)
  "Return TIMESTAMP (object or string) as Org text, or nil."
  (cond
   ((null timestamp) nil)
   ((stringp timestamp) timestamp)
   (t (org-element-interpret-data timestamp))))

(defun sem-daily-plan--excerpt (headline)
  "Return a short single-line body excerpt for org-element HEADLINE.
Property drawers, planning lines and sensitive blocks are removed; the
current buffer must be the parsed buffer."
  (save-excursion
    (goto-char (org-element-property :begin headline))
    (forward-line 1)
    (let* ((start (point))
           (end (save-excursion
                  (if (re-search-forward "^\\*+[ \t]" nil t)
                      (match-beginning 0)
                    (point-max))))
           (text (buffer-substring-no-properties start end)))
      (setq text (replace-regexp-in-string
                  "^[ \t]*#\\+begin_sensitive\\(?:.\\|\n\\)*?#\\+end_sensitive[ \t]*$"
                  "" text))
      (setq text (replace-regexp-in-string
                  "^[ \t]*:PROPERTIES:\\(?:.\\|\n\\)*?:END:[ \t]*$" "" text))
      (setq text (replace-regexp-in-string
                  "^[ \t]*\\(?:SCHEDULED\\|DEADLINE\\|CLOSED\\):.*$" "" text))
      (setq text (sem-planner--one-line text))
      (if (> (length text) sem-daily-plan-excerpt-chars)
          (concat (substring text 0 sem-daily-plan-excerpt-chars) "...")
        text))))

(defun sem-daily-plan--collect (content now)
  "Classify open tasks in tasks CONTENT relative to NOW.
Returns a plist with :overdue, :today, :upcoming and :backlog lists.  Each
task is a plist with :ref, :id, :title, :tag, :priority, :effort,
:scheduled, :deadline, :scheduled-date, :deadline-date and :excerpt."
  (let* ((today (sem-time-format-string "%Y-%m-%d" now))
         (horizon (sem-time-format-string
                   "%Y-%m-%d"
                   (time-add now (days-to-time sem-daily-plan-deadline-horizon-days))))
         (counter 0)
         (overdue '()) (today-items '()) (upcoming '()) (backlog '()))
    (with-temp-buffer
      (insert (or content ""))
      (org-mode)
      (org-element-map (org-element-parse-buffer) 'headline
        (lambda (headline)
          (when (eq (org-element-property :todo-type headline) 'todo)
            (let* ((scheduled (sem-planner--planning headline 'scheduled))
                   (deadline (sem-planner--planning headline 'deadline))
                   (scheduled-date (sem-daily-plan--timestamp-date scheduled))
                   (deadline-date (sem-daily-plan--timestamp-date deadline))
                   (item (list :ref (format "T%d" (setq counter (1+ counter)))
                               :id (org-element-property :ID headline)
                               :title (sem-planner--one-line
                                       (org-element-property :raw-value headline))
                               :tag (sem-planner--task-category headline)
                               :priority (org-element-property :priority headline)
                               :effort (org-element-property :EFFORT headline)
                               :scheduled (sem-daily-plan--timestamp-string scheduled)
                               :deadline (sem-daily-plan--timestamp-string deadline)
                               :scheduled-date scheduled-date
                               :deadline-date deadline-date
                               :excerpt (sem-daily-plan--excerpt headline))))
              (cond
               ((or (and scheduled-date (string< scheduled-date today))
                    (and deadline-date (string< deadline-date today)))
                (push item overdue))
               ((and scheduled-date (string= scheduled-date today))
                (push item today-items))
               ((and deadline-date (not (string< horizon deadline-date)))
                (push item upcoming))
               ((and (null scheduled-date) (null deadline-date))
                (push item backlog))))))))
    (cl-flet ((take (items key)
                (let ((max (plist-get sem-daily-plan-max-items key)))
                  (if (> (length items) max) (cl-subseq items 0 max) items))))
      (list :overdue (take (nreverse overdue) :overdue)
            :today (take (nreverse today-items) :today)
            :upcoming (take (nreverse upcoming) :upcoming)
            ;; Higher priority first; file order (oldest first) within a level.
            :backlog (take (cl-stable-sort (nreverse backlog) #'<
                                           :key (lambda (item)
                                                  (or (plist-get item :priority) ?B)))
                           :backlog)))))

;;; Prompt

(defun sem-daily-plan--item-line (item)
  "Format task ITEM as one context line for the LLM."
  (string-join
   (delq nil
         (list (plist-get item :ref)
               (format "[#%c] %s" (or (plist-get item :priority) ?B) (plist-get item :tag))
               (format "EFFORT %s" (or (plist-get item :effort) "unknown"))
               (when (plist-get item :scheduled)
                 (format "SCHEDULED %s" (plist-get item :scheduled)))
               (when (plist-get item :deadline)
                 (format "DEADLINE %s" (plist-get item :deadline)))
               (plist-get item :title)
               (let ((excerpt (plist-get item :excerpt)))
                 (unless (string-empty-p (or excerpt ""))
                   (format "notes: %s" excerpt)))))
   " | "))

(defun sem-daily-plan--section (title items)
  "Format a prompt section TITLE listing ITEMS."
  (concat "=== " title " ===\n"
          (if items
              (mapconcat #'sem-daily-plan--item-line items "\n")
            "(none)")
          "\n\n"))

(defun sem-daily-plan--build-prompt (tasks rules-text now)
  "Build the user prompt from classified TASKS, RULES-TEXT and NOW."
  (concat
   (format "TODAY: %s, current time %s (%s)\n\n"
           (sem-time-format-string "%Y-%m-%d %A" now)
           (sem-time-format-string "%H:%M" now)
           (sem-time-client-timezone))
   "=== USER RULES ===\n"
   (if (string-empty-p (or rules-text "")) "(No rules specified)" rules-text)
   "\n\n"
   (sem-daily-plan--section "ALREADY SCHEDULED TODAY (fixed commitments)"
                            (plist-get tasks :today))
   (sem-daily-plan--section "OVERDUE" (plist-get tasks :overdue))
   (sem-daily-plan--section
    (format "DEADLINES WITHIN %d DAYS" sem-daily-plan-deadline-horizon-days)
    (plist-get tasks :upcoming))
   (sem-daily-plan--section "BACKLOG (unscheduled, highest priority first)"
                            (plist-get tasks :backlog))
   "Respond ONLY with lines in these formats, nothing else:\n"
   "FOCUS: <one short sentence: the theme or main outcome of the day>\n"
   "PLAN: <ref> | <HH:MM-HH:MM> | <why today, max 15 words> | <first concrete step, max 15 words>\n"
   "DEFER: <ref> | <reason, max 12 words> | <YYYY-MM-DD or drop>\n"))

(defun sem-daily-plan--system-prompt ()
  "Return the system prompt for daily planning."
  (format
   (concat
    "You are a proactive personal planning assistant. Each morning you turn the "
    "user's task list into a concrete, realistic plan for today.\n\n"
    "How to plan:\n"
    "- Tasks under ALREADY SCHEDULED TODAY are fixed: plan around them and do "
    "not emit PLAN lines for them.\n"
    "- Pick tasks in this order: OVERDUE first, then DEADLINES, then BACKLOG by "
    "priority. Be decisive: choose, do not list everything.\n"
    "- Keep the day realistic: about 4-6 hours of planned work in total, blocks "
    "sized from EFFORT (estimate from the title when unknown), short buffers "
    "between blocks, no overlap with fixed commitments, all blocks after the "
    "current time.\n"
    "- Follow the user rules (working hours, days, per-category windows).\n"
    "- Include one quick win (<= 30 minutes) when the backlog has one.\n"
    "- Every OVERDUE task that you do not plan today gets a DEFER line with a "
    "realistic new date, or `drop` when it no longer seems worth doing.\n"
    "- The first step must be a concrete physical action, not a restatement of "
    "the task.\n"
    "- Use only refs that appear in the input.\n\n"
    "Write FOCUS, reasons and first steps in %s.")
   (or (sem-llm--env "OUTPUT_LANGUAGE") "English")))

;;; Response Parsing

(defun sem-daily-plan--parse-response (response refs)
  "Parse LLM RESPONSE into a plist with :focus, :plan and :defer.
REFS is the list of valid task refs; lines with unknown refs or malformed
times are dropped.  :plan entries are plists (:ref :start :end :why :step)
sorted by start time; :defer entries are plists (:ref :reason :date)."
  (let ((focus nil) (plan '()) (defer '()))
    (dolist (line (split-string (or response "") "\n" t "[ \t\r]+"))
      (cond
       ((string-match "\\`FOCUS:[ \t]*\\(.+\\)\\'" line)
        (unless focus (setq focus (match-string 1 line))))
       ((string-match
         (concat "\\`PLAN:[ \t]*\\(T[0-9]+\\)[ \t]*|[ \t]*"
                 "\\([0-2][0-9]:[0-5][0-9]\\)-\\([0-2][0-9]:[0-5][0-9]\\)"
                 "[ \t]*|[ \t]*\\([^|]*?\\)[ \t]*|[ \t]*\\(.*?\\)[ \t]*\\'")
         line)
        (let ((ref (match-string 1 line))
              (start (match-string 2 line))
              (end (match-string 3 line))
              (why (match-string 4 line))
              (step (match-string 5 line)))
          (when (and (member ref refs)
                     (string< start end)
                     (not (cl-find ref plan :key (lambda (p) (plist-get p :ref))
                                   :test #'string=)))
            (push (list :ref ref :start start :end end :why why :step step) plan))))
       ((string-match
         (concat "\\`DEFER:[ \t]*\\(T[0-9]+\\)[ \t]*|[ \t]*\\([^|]*?\\)[ \t]*|[ \t]*"
                 "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\|drop\\)[ \t]*\\'")
         line)
        (let ((ref (match-string 1 line)))
          (when (member ref refs)
            (push (list :ref ref :reason (match-string 2 line) :date (match-string 3 line))
                  defer))))))
    (list :focus focus
          :plan (sort (nreverse plan)
                      (lambda (a b) (string< (plist-get a :start) (plist-get b :start))))
          :defer (nreverse defer))))

;;; Rendering

(defun sem-daily-plan--inactive (timestamp)
  "Return TIMESTAMP with inactive brackets so it does not duplicate in agenda."
  (if (and timestamp (string-match "\\`<\\(.*\\)>\\'" timestamp))
      (format "[%s]" (match-string 1 timestamp))
    (or timestamp "")))

(defun sem-daily-plan--link (item)
  "Return an Org link (or plain title) for task ITEM."
  (let ((title (replace-regexp-in-string "[][]" "" (plist-get item :title))))
    (if (plist-get item :id)
        (format "[[id:%s][%s]]" (plist-get item :id) title)
      title)))

(defun sem-daily-plan--label (item)
  "Return the priority, link and category label of task ITEM."
  (format "[#%c] %s :%s:"
          (or (plist-get item :priority) ?B)
          (sem-daily-plan--link item)
          (plist-get item :tag)))

(defun sem-daily-plan--render (tasks parsed now &optional note)
  "Render the daily plan Org text.
TASKS is the classified task plist, PARSED the parsed LLM plan (or nil),
NOW the plan time and NOTE an optional status line."
  (let* ((all (append (plist-get tasks :overdue) (plist-get tasks :today)
                      (plist-get tasks :upcoming) (plist-get tasks :backlog)))
         (by-ref (lambda (ref) (cl-find ref all :key (lambda (i) (plist-get i :ref))
                                        :test #'string=)))
         (date (sem-time-format-string "%Y-%m-%d" now))
         (day (sem-time-format-string "%a" now))
         (planned-refs (mapcar (lambda (p) (plist-get p :ref)) (plist-get parsed :plan))))
    (concat
     (format "#+TITLE: Daily plan %s %s\n" date day)
     (format "#+DATE: [%s %s %s]\n" date day (sem-time-format-string "%H:%M" now))
     "#+STARTUP: showall\n\n"
     (when note (format "%s\n\n" note))
     (when (plist-get parsed :focus)
       (format "* Focus\n%s\n\n" (plist-get parsed :focus)))
     "* Fixed today\n"
     (if (plist-get tasks :today)
         (mapconcat (lambda (item)
                      (format "- %s %s\n"
                              (sem-daily-plan--inactive (plist-get item :scheduled))
                              (sem-daily-plan--label item)))
                    (plist-get tasks :today) "")
       "- (nothing scheduled)\n")
     "\n* Plan\n"
     (if (plist-get parsed :plan)
         (mapconcat
          (lambda (entry)
            (let ((item (funcall by-ref (plist-get entry :ref))))
              (concat
               (format "- [ ] <%s %s %s-%s> %s\n"
                       date day (plist-get entry :start) (plist-get entry :end)
                       (sem-daily-plan--label item))
               (unless (string-empty-p (plist-get entry :why))
                 (format "  - Why: %s\n" (plist-get entry :why)))
               (unless (string-empty-p (plist-get entry :step))
                 (format "  - First step: %s\n" (plist-get entry :step))))))
          (plist-get parsed :plan) "")
       "- (no suggestions)\n")
     (when (plist-get parsed :defer)
       (concat
        "\n* Overdue: reschedule or drop\n"
        (mapconcat
         (lambda (entry)
           (let ((item (funcall by-ref (plist-get entry :ref))))
             (format "- %s -> %s (%s)\n"
                     (sem-daily-plan--label item)
                     (if (string= (plist-get entry :date) "drop")
                         "drop"
                       (format "[%s]" (plist-get entry :date)))
                     (plist-get entry :reason))))
         (plist-get parsed :defer) "")))
     (let ((remaining (cl-remove-if
                       (lambda (item)
                         (or (member (plist-get item :ref) planned-refs)
                             (cl-find (plist-get item :ref) (plist-get parsed :defer)
                                      :key (lambda (d) (plist-get d :ref))
                                      :test #'string=)))
                       (plist-get tasks :overdue))))
       (when remaining
         (concat "\n* Other overdue\n"
                 (mapconcat (lambda (item)
                              (format "- %s (was %s)\n"
                                      (sem-daily-plan--label item)
                                      (or (plist-get item :scheduled-date)
                                          (plist-get item :deadline-date))))
                            remaining ""))))
     (when (plist-get tasks :upcoming)
       (concat "\n* Deadlines this week\n"
               (mapconcat (lambda (item)
                            (format "- %s %s\n"
                                    (sem-daily-plan--inactive (plist-get item :deadline))
                                    (sem-daily-plan--label item)))
                          (plist-get tasks :upcoming) "")))
     (format "\n* Backlog\n%d unscheduled open tasks considered.\n"
             (length (plist-get tasks :backlog))))))

(defun sem-daily-plan--write (text)
  "Atomically write TEXT to `sem-daily-plan-file'."
  (let ((tmp-file (concat sem-daily-plan-file ".tmp")))
    (make-directory (file-name-directory sem-daily-plan-file) t)
    (with-temp-file tmp-file
      (insert text))
    (rename-file tmp-file sem-daily-plan-file t)))

;;; Entry Point

(defun sem-daily-plan--generate (&optional now callback)
  "Generate the daily plan for NOW (default: current time).
CALLBACK, when non-nil, is called with non-nil on an LLM-backed plan and
nil when the fallback plan was written.  Returns t when the request started."
  (let* ((now (or now (current-time)))
         (content (sem-planner--read-tasks-file-content))
         (tasks (sem-daily-plan--collect content now))
         (refs (mapcar (lambda (item) (plist-get item :ref))
                       (append (plist-get tasks :overdue) (plist-get tasks :today)
                               (plist-get tasks :upcoming) (plist-get tasks :backlog))))
         (finish (lambda (parsed note success)
                   (condition-case err
                       (progn
                         (sem-daily-plan--write
                          (sem-daily-plan--render tasks parsed now note))
                         (sem-core-log "planner" "DAILY-PLAN" (if success "OK" "FAIL")
                                       (format "Daily plan written: planned=%d deferred=%d"
                                               (length (plist-get parsed :plan))
                                               (length (plist-get parsed :defer))))
                         (when callback (funcall callback success)))
                     (error
                      (sem-core-log-error "planner" "DAILY-PLAN"
                                          (format "Daily plan write failed: %s"
                                                  (error-message-string err))
                                          nil nil))))))
    (if (null refs)
        (progn
          (funcall finish nil "No open tasks." t)
          nil)
      (sem-llm-request
       (sem-daily-plan--build-prompt tasks (or (sem-rules-read) "") now)
       (sem-daily-plan--system-prompt)
       (lambda (response info _context)
         (if (and response (not (string-empty-p response)))
             (let ((parsed (sem-daily-plan--parse-response response refs)))
               (if (plist-get parsed :plan)
                   (funcall finish parsed nil t)
                 (sem-core-log-error "planner" "DAILY-PLAN"
                                     "Daily plan response had no valid PLAN lines"
                                     nil response)
                 (funcall finish parsed
                          "/The assistant returned no usable plan; tasks are listed without suggestions./"
                          nil)))
           (funcall finish nil
                    (format "/Planning request failed (%s); tasks are listed without suggestions./"
                            (or (plist-get info :error) "unknown error"))
                    nil)))
       nil
       'medium)
      t)))

;;;###autoload
(defun sem-daily-plan-generate ()
  "Cron entry point: write today's plan to `sem-daily-plan-file'."
  (sem-core-run-cron-guarded
   "daily-plan" "planner" "DAILY-PLAN"
   (lambda ()
     (condition-case err
         (sem-daily-plan--generate)
       (error
        (sem-core-log-error "planner" "DAILY-PLAN"
                            (format "Daily plan error: %s" (error-message-string err))
                            nil nil)
        (message "SEM: Daily plan error: %s" (error-message-string err))
        nil)))))

(provide 'sem-daily-plan)
;;; sem-daily-plan.el ends here
