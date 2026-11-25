;;; sem-daily-plan.el --- Morning rescheduling of tasks.org -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Every morning this module turns the task backlog into today's schedule
;; directly in tasks.org.  It collects overdue tasks, tasks scheduled for
;; today without a time, near deadlines and the unscheduled backlog, and asks
;; the LLM to place them into free time blocks of today or to move them to a
;; later date.  Timed tasks of today and today's occurrences of recurring
;; tasks from rec-tasks.org are busy slots: they are never modified.
;;
;; The LLM only returns short lines that reference tasks by a local ref
;; (T1, T2, ...).  The daemon validates them (refs, times after now, no
;; overlaps, dates in the future) and edits only the planning line, the
;; :SEM_DAILY_PLAN: property and, for dropped tasks, the headline tags.
;; DEADLINE timestamps are never changed.
;;
;; Writes follow the optimistic-concurrency scheme of the planner: the new
;; content is written to a temp file, tasks.org is re-hashed, and the temp
;; file replaces tasks.org only when the hash still matches the content the
;; plan was built from.  Otherwise (an edit from the phone or another job
;; landed meanwhile) the whole run starts over with fresh content and a new
;; LLM call.  A copy of the previous tasks.org is kept in
;; `sem-daily-plan-backup-dir'.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'calendar)
(require 'sem-core)
(require 'sem-time)
(require 'sem-rules)
(require 'sem-llm)
(require 'sem-planner)

(defconst sem-daily-plan-rec-tasks-file "/data/tasks/rec-tasks.org"
  "Recurring tasks file; its occurrences today are treated as busy slots.")

(defconst sem-daily-plan-backup-dir "/data/.tasks-backups/"
  "Directory for tasks.org copies taken before each daily plan write.
Kept outside the WebDAV root so mobile clients do not list the copies.")

(defconst sem-daily-plan-backup-keep-days 14
  "Backups older than this many days are deleted.")

(defconst sem-daily-plan-deadline-horizon-days 7
  "Deadlines within this many days are offered for planning.")

(defconst sem-daily-plan-max-items
  '(:overdue 30 :untimed 30 :upcoming 20 :backlog 40)
  "Maximum number of movable tasks per category sent to the LLM.")

(defconst sem-daily-plan-excerpt-chars 200
  "Maximum characters of task body included as context.")

(defconst sem-daily-plan-drop-tag "drop_suggested"
  "Tag added to tasks the LLM suggests dropping.")

(defconst sem-daily-plan-property "SEM_DAILY_PLAN"
  "Property recording the date and action of the last daily plan change.")

;;; Timestamps

(defun sem-daily-plan--timestamp-date (timestamp)
  "Return the YYYY-MM-DD date of org TIMESTAMP (object or string), or nil."
  (let ((parts (and timestamp (sem-planner--parse-timestamp timestamp))))
    (when parts
      (format "%04d-%02d-%02d" (nth 0 parts) (nth 1 parts) (nth 2 parts)))))

(defun sem-daily-plan--timestamp-string (timestamp)
  "Return TIMESTAMP (object or string) as Org text, or nil."
  (cond
   ((null timestamp) nil)
   ((stringp timestamp) (string-trim timestamp))
   (t (string-trim (org-element-interpret-data timestamp)))))

(defun sem-daily-plan--timestamp-has-time-p (timestamp)
  "Return non-nil when org TIMESTAMP (object or string) carries a time of day."
  (cond
   ((null timestamp) nil)
   ((stringp timestamp)
    (string-match-p "<[0-9]+-[0-9]+-[0-9]+[^>]*?[ \t][0-9]+:[0-9]+" timestamp))
   (t (org-element-property :hour-start timestamp))))

(defun sem-daily-plan--minutes (hhmm)
  "Return minutes since midnight for HH:MM string HHMM."
  (+ (* 60 (string-to-number (substring hhmm 0 2)))
     (string-to-number (substring hhmm 3 5))))

(defun sem-daily-plan--hhmm (hour minute)
  "Format HOUR and MINUTE as HH:MM."
  (format "%02d:%02d" hour minute))

(defun sem-daily-plan--date-timestamp (date &optional start end)
  "Return an active Org timestamp for YYYY-MM-DD DATE.
START and END are optional HH:MM strings of a time range."
  (let* ((parts (mapcar #'string-to-number (split-string date "-")))
         (day (format-time-string
               "%a" (encode-time 0 0 12 (nth 2 parts) (nth 1 parts) (nth 0 parts) t) t)))
    (if start
        (format "<%s %s %s-%s>" date day start end)
      (format "<%s %s>" date day))))

;;; Task Collection

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

(defun sem-daily-plan--busy-slot (title timestamp)
  "Return a busy slot plist for TITLE at TIMESTAMP, or nil without a time."
  (when (sem-daily-plan--timestamp-has-time-p timestamp)
    (let ((parts (sem-planner--parse-timestamp timestamp)))
      (when parts
        (list :start (sem-daily-plan--hhmm (nth 3 parts) (nth 4 parts))
              :end (sem-daily-plan--hhmm (nth 5 parts) (nth 6 parts))
              :title title)))))

(defun sem-daily-plan--collect (content now)
  "Classify open tasks in tasks CONTENT relative to NOW.
Returns a plist with :overdue, :untimed, :upcoming and :backlog lists of
movable tasks and :busy, a list of busy slot plists (:start :end :title)
for today's timed tasks.  Each task is a plist with :ref, :begin, :id,
:title, :tag, :priority, :effort, :fixed, :scheduled, :deadline,
:scheduled-date, :deadline-date and :excerpt; :begin is the headline
position in CONTENT."
  (let* ((today (sem-time-format-string "%Y-%m-%d" now))
         (horizon (sem-time-format-string
                   "%Y-%m-%d"
                   (time-add now (days-to-time sem-daily-plan-deadline-horizon-days))))
         (counter 0)
         (overdue '()) (untimed '()) (upcoming '()) (backlog '()) (busy '()))
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
                   (title (sem-planner--one-line
                           (org-element-property :raw-value headline)))
                   (item (list :ref (format "T%d" (setq counter (1+ counter)))
                               :begin (org-element-property :begin headline)
                               :id (org-element-property :ID headline)
                               :title title
                               :tag (sem-planner--task-category headline)
                               :priority (org-element-property :priority headline)
                               :effort (org-element-property :EFFORT headline)
                               :fixed (sem-planner--fixed-schedule-p headline)
                               :scheduled (sem-daily-plan--timestamp-string scheduled)
                               :deadline (sem-daily-plan--timestamp-string deadline)
                               :scheduled-date scheduled-date
                               :deadline-date deadline-date
                               :excerpt (sem-daily-plan--excerpt headline))))
              (cond
               ;; Repeating timestamps belong in rec-tasks.org; never move them.
               ((and (plist-get item :scheduled)
                     (string-match-p "[.+]\\+?[0-9]+[hdwmy]" (plist-get item :scheduled)))
                nil)
               ((or (and scheduled-date (string< scheduled-date today))
                    (and deadline-date (string< deadline-date today)))
                (push item overdue))
               ((and scheduled-date (string= scheduled-date today))
                (if (sem-daily-plan--timestamp-has-time-p scheduled)
                    (let ((slot (sem-daily-plan--busy-slot title scheduled)))
                      (when slot (push slot busy)))
                  (push item untimed)))
               ((and deadline-date (not (string< horizon deadline-date)))
                (push item upcoming))
               ((and (null scheduled-date) (null deadline-date)
                     (not (member sem-daily-plan-drop-tag
                                  (org-element-property :tags headline))))
                (push item backlog))))))))
    (cl-flet ((take (items key)
                (let ((max (plist-get sem-daily-plan-max-items key)))
                  (if (> (length items) max) (cl-subseq items 0 max) items))))
      (list :overdue (take (nreverse overdue) :overdue)
            :untimed (take (nreverse untimed) :untimed)
            :upcoming (take (nreverse upcoming) :upcoming)
            ;; Higher priority first; file order (oldest first) within a level.
            :backlog (take (cl-stable-sort (nreverse backlog) #'<
                                           :key (lambda (item)
                                                  (or (plist-get item :priority) ?B)))
                           :backlog)
            :busy (nreverse busy)))))

(defun sem-daily-plan--recurring-busy (content now)
  "Return busy slots of recurring tasks in CONTENT occurring on NOW's date.
Only open tasks whose SCHEDULED carries a time of day are considered;
repeaters are expanded with `org-closest-date'."
  (let* ((today (sem-time-format-string "%Y-%m-%d" now))
         (today-ts (format "<%s>" today))
         (today-abs (calendar-absolute-from-gregorian
                     (let ((p (mapcar #'string-to-number (split-string today "-"))))
                       (list (nth 1 p) (nth 2 p) (nth 0 p)))))
         (busy '()))
    (unless (string-empty-p (or content ""))
      (with-temp-buffer
        (insert content)
        (org-mode)
        (org-element-map (org-element-parse-buffer) 'headline
          (lambda (headline)
            (let* ((scheduled (sem-planner--planning headline 'scheduled))
                   (ts (sem-daily-plan--timestamp-string scheduled)))
              (when (and ts
                         (not (eq (org-element-property :todo-type headline) 'done))
                         (sem-daily-plan--timestamp-has-time-p scheduled)
                         (ignore-errors
                           (= (org-closest-date ts today-ts 'past) today-abs)))
                (let ((slot (sem-daily-plan--busy-slot
                             (sem-planner--one-line
                              (org-element-property :raw-value headline))
                             ts)))
                  (when slot (push slot busy)))))))))
    (nreverse busy)))

(defun sem-daily-plan--read-file (file)
  "Return the content of FILE, or an empty string when it does not exist."
  (if (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (buffer-string))
    ""))

(defun sem-daily-plan--movable (tasks)
  "Return all movable task items of classified TASKS."
  (append (plist-get tasks :overdue) (plist-get tasks :untimed)
          (plist-get tasks :upcoming) (plist-get tasks :backlog)))

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

(defun sem-daily-plan--build-prompt (tasks busy rules-text now)
  "Build the user prompt from classified TASKS, BUSY slots, RULES-TEXT and NOW."
  (concat
   (format "TODAY: %s, current time %s (%s)\n\n"
           (sem-time-format-string "%Y-%m-%d %A" now)
           (sem-time-format-string "%H:%M" now)
           (sem-time-client-timezone))
   "=== USER RULES ===\n"
   (if (string-empty-p (or rules-text "")) "(No rules specified)" rules-text)
   "\n\n"
   "=== BUSY TODAY (fixed, do not plan into these slots) ===\n"
   (if busy
       (mapconcat (lambda (slot)
                    (format "%s-%s %s" (plist-get slot :start) (plist-get slot :end)
                            (plist-get slot :title)))
                  busy "\n")
     "(none)")
   "\n\n"
   (sem-daily-plan--section "OVERDUE (every one needs PLAN, DEFER or DROP)"
                            (plist-get tasks :overdue))
   (sem-daily-plan--section "SCHEDULED TODAY WITHOUT TIME (give a slot or DEFER)"
                            (plist-get tasks :untimed))
   (sem-daily-plan--section
    (format "DEADLINES WITHIN %d DAYS" sem-daily-plan-deadline-horizon-days)
    (plist-get tasks :upcoming))
   (sem-daily-plan--section "BACKLOG (unscheduled, highest priority first)"
                            (plist-get tasks :backlog))
   "Respond ONLY with lines in these formats, nothing else:\n"
   "PLAN: <ref> | <HH:MM-HH:MM>\n"
   "DEFER: <ref> | <YYYY-MM-DD>\n"
   "DROP: <ref>\n"))

(defun sem-daily-plan--system-prompt ()
  "Return the system prompt for daily planning."
  (concat
   "You are a decisive personal scheduling assistant. Each morning you turn the "
   "user's task list into a concrete schedule for today and move everything "
   "else to realistic dates. Your decisions are written into the calendar "
   "as-is.\n\n"
   "How to schedule:\n"
   "- Never place a block into a BUSY TODAY slot; blocks must not overlap each "
   "other and must start after the current time.\n"
   "- Every OVERDUE task gets exactly one line: PLAN it today, DEFER it to a "
   "realistic future date, or DROP it when it clearly no longer seems worth "
   "doing. Nothing may stay overdue.\n"
   "- Every task under SCHEDULED TODAY WITHOUT TIME gets a PLAN block, or a "
   "DEFER when today is already full.\n"
   "- Then fill the remaining time from DEADLINES and BACKLOG by urgency and "
   "priority. Tasks you do not mention stay as they are.\n"
   "- Keep the day realistic: about 4-6 hours of planned work in total, blocks "
   "sized from EFFORT (estimate from the title when unknown), short buffers "
   "between blocks.\n"
   "- Follow the user rules (working hours, days, per-category windows) for "
   "both today's blocks and DEFER dates; spread deferred work over the next "
   "days instead of piling it onto one date.\n"
   "- Use only refs that appear in the input.\n"))

;;; Response Parsing

(defun sem-daily-plan--parse-response (response refs)
  "Parse LLM RESPONSE into a list of decision plists.
REFS is the list of valid task refs.  Each decision is (:ref :action
:start :end :date) with :action one of `plan', `defer' or `drop'.  Lines
with unknown refs or malformed values are dropped; the first decision per
ref wins."
  (let ((decisions '()))
    (dolist (line (split-string (or response "") "\n" t "[ \t\r*-]+"))
      (let ((decision
             (cond
              ((string-match
                (concat "\\`PLAN:[ \t]*\\(T[0-9]+\\)[ \t]*|[ \t]*"
                        "\\([0-2][0-9]:[0-5][0-9]\\)[ \t]*-[ \t]*\\([0-2][0-9]:[0-5][0-9]\\)")
                line)
               (list :ref (match-string 1 line) :action 'plan
                     :start (match-string 2 line) :end (match-string 3 line)))
              ((string-match
                "\\`DEFER:[ \t]*\\(T[0-9]+\\)[ \t]*|[ \t]*\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)"
                line)
               (list :ref (match-string 1 line) :action 'defer :date (match-string 2 line)))
              ((string-match "\\`DROP:[ \t]*\\(T[0-9]+\\)\\b" line)
               (list :ref (match-string 1 line) :action 'drop)))))
        (when (and decision
                   (member (plist-get decision :ref) refs)
                   (not (cl-find (plist-get decision :ref) decisions
                                 :key (lambda (d) (plist-get d :ref)) :test #'string=)))
          (push decision decisions))))
    (nreverse decisions)))

(defun sem-daily-plan--validate (decisions tasks busy now)
  "Return DECISIONS that are safe to apply to classified TASKS.
PLAN blocks must lie between NOW and midnight and overlap neither BUSY
slots nor each other (earlier blocks win).  DEFER dates must be after
today and, for tasks that are not overdue, not after their deadline;
tasks with a user-set schedule that are not overdue are not deferred.  DROP is accepted for overdue tasks only."
  (let* ((today (sem-time-format-string "%Y-%m-%d" now))
         (now-min (sem-daily-plan--minutes (sem-time-format-string "%H:%M" now)))
         (overdue-refs (mapcar (lambda (i) (plist-get i :ref)) (plist-get tasks :overdue)))
         (all (sem-daily-plan--movable tasks))
         (taken (mapcar (lambda (slot)
                          (cons (sem-daily-plan--minutes (plist-get slot :start))
                                (sem-daily-plan--minutes (plist-get slot :end))))
                        busy))
         (accepted '()))
    (dolist (decision (cl-sort (copy-sequence decisions) #'string<
                               :key (lambda (d) (or (plist-get d :start) "99:99"))))
      (let* ((ref (plist-get decision :ref))
             (item (cl-find ref all :key (lambda (i) (plist-get i :ref)) :test #'string=))
             (overdue (member ref overdue-refs)))
        (when (pcase (plist-get decision :action)
                ('plan
                 (let ((start (sem-daily-plan--minutes (plist-get decision :start)))
                       (end (sem-daily-plan--minutes (plist-get decision :end))))
                   (when (and (< start end) (<= end (* 24 60)) (>= start now-min)
                              (not (cl-some (lambda (slot)
                                              (and (< start (cdr slot)) (< (car slot) end)))
                                            taken)))
                     (push (cons start end) taken)
                     t)))
                ('defer
                 (let ((date (plist-get decision :date))
                       (deadline (plist-get item :deadline-date)))
                   (and (string< today date)
                        (or overdue (not (plist-get item :fixed)))
                        (or overdue (null deadline) (not (string< deadline date))))))
                ('drop overdue))
          (push decision accepted))))
    (nreverse accepted)))

;;; Applying Decisions

(defun sem-daily-plan--set-scheduled (entry timestamp)
  "Return ENTRY with SCHEDULED set to TIMESTAMP, or removed when nil.
ENTRY starts with its headline and ends before the next headline."
  (let ((normalized (sem-core-normalize-planning-line entry timestamp)))
    (if timestamp
        normalized
      (with-temp-buffer
        (insert normalized)
        (goto-char (point-min))
        (forward-line 1)
        (when (looking-at "^[ \t]*\\(?:SCHEDULED\\|DEADLINE\\):")
          (let ((line-start (point)))
            (when (re-search-forward "SCHEDULED:[ \t]*<[^>\n]+>[ \t]*" (line-end-position) t)
              (replace-match ""))
            (goto-char line-start)
            (when (looking-at "^[ \t]*$")
              (delete-region line-start (min (point-max) (1+ (line-end-position)))))))
        (buffer-string)))))

(defun sem-daily-plan--add-tag (entry tag)
  "Return ENTRY with TAG appended to the tags of its headline."
  (with-temp-buffer
    (insert entry)
    (goto-char (point-min))
    (end-of-line)
    (skip-chars-backward " \t")
    (if (looking-back "[ \t]:[[:alnum:]_@#%:]+:" (line-beginning-position))
        (insert tag ":")
      (insert " :" tag ":"))
    (buffer-string)))

(defun sem-daily-plan--apply (content tasks decisions now)
  "Return CONTENT with validated DECISIONS for classified TASKS applied at NOW.
Entries are edited from the bottom of the file up so that the recorded
headline positions stay valid."
  (let* ((today (sem-time-format-string "%Y-%m-%d" now))
         (all (sem-daily-plan--movable tasks))
         (edits (mapcar (lambda (decision)
                          (cons (cl-find (plist-get decision :ref) all
                                         :key (lambda (i) (plist-get i :ref))
                                         :test #'string=)
                                decision))
                        decisions)))
    (with-temp-buffer
      (insert content)
      (org-mode)
      (let ((org-element-use-cache nil))
        (dolist (edit (cl-sort edits #'> :key (lambda (e) (plist-get (car e) :begin))))
          (let* ((item (car edit))
                 (decision (cdr edit))
                 (action (plist-get decision :action))
                 (start (plist-get item :begin))
                 (end (save-excursion
                        (goto-char start)
                        (forward-line 1)
                        (if (re-search-forward "^\\*+[ \t]" nil t)
                            (match-beginning 0)
                          (point-max))))
                 (entry (buffer-substring-no-properties start end))
                 (timestamp (pcase action
                              ('plan (sem-daily-plan--date-timestamp
                                      today (plist-get decision :start) (plist-get decision :end)))
                              ('defer (sem-daily-plan--date-timestamp (plist-get decision :date)))
                              (_ nil)))
                 (new-entry (sem-daily-plan--set-scheduled entry timestamp)))
            (when (eq action 'drop)
              (setq new-entry (sem-daily-plan--add-tag new-entry sem-daily-plan-drop-tag)))
            (delete-region start end)
            (goto-char start)
            (insert new-entry)
            (org-entry-put start sem-daily-plan-property
                           (format "%s %s" today (symbol-name action))))))
      (buffer-string))))

;;; Writing

(defun sem-daily-plan--backup (content now)
  "Save CONTENT as a tasks.org backup stamped with NOW and prune old copies."
  (make-directory sem-daily-plan-backup-dir t)
  (write-region content nil
                (expand-file-name
                 (format "tasks-%s.org" (sem-time-format-string "%Y%m%d-%H%M%S" now))
                 sem-daily-plan-backup-dir)
                nil 'silent)
  (let ((cutoff (time-subtract (current-time)
                               (days-to-time sem-daily-plan-backup-keep-days))))
    (dolist (file (directory-files sem-daily-plan-backup-dir t "\\`tasks-.*\\.org\\'"))
      (when (time-less-p (file-attribute-modification-time (file-attributes file)) cutoff)
        (ignore-errors (delete-file file))))))

(defun sem-daily-plan--commit (new-content base-hash base-content now)
  "Replace tasks.org with NEW-CONTENT unless it changed since BASE-HASH.
BASE-CONTENT is backed up with timestamp NOW first.  Returns `written' or
`conflict'."
  (let* ((tasks-file sem-planner-tasks-file)
         (tmp-file (concat tasks-file ".daily-plan.tmp")))
    (write-region new-content nil tmp-file nil 'silent)
    (if (not (string= (sem-planner--tasks-file-hash) base-hash))
        (progn
          (ignore-errors (delete-file tmp-file))
          'conflict)
      (sem-daily-plan--backup base-content now)
      (rename-file tmp-file tasks-file t)
      'written)))

;;; Entry Point

(defun sem-daily-plan--generate (&optional fixed-now callback attempt)
  "Plan today and write the schedule into tasks.org.
FIXED-NOW overrides the current time (used by tests); otherwise each
attempt uses the time it starts at.
ATTEMPT is the conflict attempt number (default 1); on a conflict the run
restarts with fresh content up to `sem-planner--conflict-max-attempts'
times.  CALLBACK, when non-nil, is called once with `written', `unchanged',
`conflict' or `failed'.  Returns t when an LLM request was started."
  (let* ((now (or fixed-now (current-time)))
         (attempt (or attempt 1))
         (base-content (sem-planner--read-tasks-file-content))
         (base-hash (sem-planner--content-hash base-content))
         (tasks (sem-daily-plan--collect base-content now))
         (busy (sort (append (plist-get tasks :busy)
                             (sem-daily-plan--recurring-busy
                              (sem-daily-plan--read-file sem-daily-plan-rec-tasks-file) now))
                     (lambda (a b) (string< (plist-get a :start) (plist-get b :start)))))
         (refs (mapcar (lambda (item) (plist-get item :ref))
                       (sem-daily-plan--movable tasks)))
         (done (lambda (status text)
                 (sem-core-log "planner" "DAILY-PLAN"
                               (if (memq status '(written unchanged)) "OK" "FAIL")
                               text)
                 (when callback (funcall callback status)))))
    (if (null refs)
        (progn (funcall done 'unchanged "No movable tasks") nil)
      (sem-llm-request
       (sem-daily-plan--build-prompt tasks busy (or (sem-rules-read) "") now)
       (sem-daily-plan--system-prompt)
       (lambda (response info _context)
         (condition-case err
             (if (or (null response) (string-empty-p response))
                 (progn
                   (sem-core-log-error "planner" "DAILY-PLAN"
                                       (format "Daily plan request failed: %s"
                                               (or (plist-get info :error) "unknown error"))
                                       nil nil)
                   (funcall done 'failed "LLM request failed; tasks.org unchanged"))
               (let* ((decisions (sem-daily-plan--validate
                                  (sem-daily-plan--parse-response response refs)
                                  tasks busy now))
                      (new-content (and decisions
                                        (sem-daily-plan--apply base-content tasks
                                                               decisions now))))
                 (if (or (null new-content) (string= new-content base-content))
                     (progn
                       (sem-core-log-error "planner" "DAILY-PLAN"
                                           "Daily plan response had no valid decisions"
                                           nil response)
                       (funcall done 'unchanged "No valid decisions; tasks.org unchanged"))
                   (pcase (sem-daily-plan--commit new-content base-hash base-content now)
                     ('written
                      (funcall done 'written
                               (format "tasks.org updated: plan=%d defer=%d drop=%d"
                                       (cl-count 'plan decisions
                                                 :key (lambda (d) (plist-get d :action)))
                                       (cl-count 'defer decisions
                                                 :key (lambda (d) (plist-get d :action)))
                                       (cl-count 'drop decisions
                                                 :key (lambda (d) (plist-get d :action))))))
                     ('conflict
                      (if (< attempt sem-planner--conflict-max-attempts)
                          (progn
                            (sem-core-log "planner" "DAILY-PLAN" "RETRY"
                                          (format "tasks.org changed during planning, restarting (attempt %d/%d)"
                                                  (1+ attempt)
                                                  sem-planner--conflict-max-attempts))
                            (sem-daily-plan--generate fixed-now callback (1+ attempt)))
                        (sem-core-log-error "planner" "DAILY-PLAN"
                                            (format "tasks.org kept changing; gave up after %d attempts"
                                                    attempt)
                                            nil nil)
                        (funcall done 'conflict "Conflict retry budget exhausted")))))))
           (error
            (sem-core-log-error "planner" "DAILY-PLAN"
                                (format "Daily plan apply failed: %s" (error-message-string err))
                                nil response)
            (funcall done 'failed "Apply error; tasks.org unchanged"))))
       nil
       'medium)
      t)))

;;;###autoload
(defun sem-daily-plan-generate ()
  "Cron entry point: schedule today's work directly in tasks.org."
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
