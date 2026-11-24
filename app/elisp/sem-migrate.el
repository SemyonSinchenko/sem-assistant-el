;;; sem-migrate.el --- One-time /data layout migration -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Moves an existing flat /data into the split layout:
;;
;;   /data/tasks/      WebDAV root (Orgzly, organice): inbox, tasks,
;;                     recurring tasks, daily plan, rules, feeds, prompts,
;;                     errors.
;;   /data/org-roam/   git repository (and future orgnote root):
;;                     org-files/ (graph), notes/ (personal notes),
;;                     journal/YYYY-MM.org, digest/ (+ digest/archive/).
;;   /data/            daemon internals only (logs, cursors, elfeed DB).
;;
;; Runs at daemon startup and is idempotent: an entry is moved only when
;; its source exists and its target does not, so nothing is overwritten.
;; Conflicts are left in place and logged.  The legacy journal.org is split
;; into monthly files and the original is kept under /data/.migrated/.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defconst sem-migrate-data-root "/data/"
  "Root of the runtime data volume.")

(defconst sem-migrate-tasks-dir "/data/tasks/"
  "Target directory for task and settings files (WebDAV root).")

(defconst sem-migrate-repo-dir "/data/org-roam/"
  "Target git repository for knowledge files.")

(defconst sem-migrate-backup-dir "/data/.migrated/"
  "Directory keeping originals of files that were transformed.")

(defconst sem-migrate-tasks-entries
  '("inbox-mobile.org" "tasks.org" "rec-tasks.org" "daily-plan.org"
    "rules.org" "feeds.org" "errors.org" "prompts")
  "Root entries that move into `sem-migrate-tasks-dir'.")

(defconst sem-migrate-internal-files '("sem-log.org")
  "Root Org files that stay daemon-internal in /data.")

(defconst sem-migrate-digest-moves
  '(("morning-read" . "digest") ("archive" . "digest/archive"))
  "Root directories moved into the repository, as (SOURCE . TARGET).")

(defconst sem-migrate-repo-ignored '("sem/")
  "Entries ensured in the repository .gitignore.")

(defun sem-migrate--log (format-string &rest args)
  "Log a migration message built from FORMAT-STRING and ARGS."
  (message "SEM: migrate: %s" (apply #'format format-string args)))

(defun sem-migrate--ensure-dir (dir)
  "Create DIR when missing, owned like `sem-migrate-data-root'.
The WebDAV server runs as an unprivileged user that must be able to create
files in the directories it serves."
  (unless (file-directory-p dir)
    (make-directory dir t)
    (let* ((attrs (file-attributes sem-migrate-data-root 'integer))
           (uid (file-attribute-user-id attrs))
           (gid (file-attribute-group-id attrs)))
      (when (and (integerp uid) (integerp gid))
        (ignore-errors
          (call-process "chown" nil nil nil (format "%d:%d" uid gid)
                        (directory-file-name dir)))))))

(defun sem-migrate--move (src dst)
  "Move SRC to DST without overwriting anything.
Directories are merged entry by entry; SRC is removed when it ends up
empty.  Returns the number of moved entries."
  (cond
   ((not (file-exists-p src)) 0)
   ((not (file-exists-p dst))
    (sem-migrate--ensure-dir (file-name-directory (directory-file-name dst)))
    (rename-file src dst)
    (sem-migrate--log "moved %s -> %s" src dst)
    1)
   ((and (file-directory-p src) (file-directory-p dst))
    (let ((moved 0))
      (dolist (name (directory-files src nil directory-files-no-dot-files-regexp))
        (setq moved (+ moved (sem-migrate--move (expand-file-name name src)
                                                (expand-file-name name dst)))))
      (when (null (directory-files src nil directory-files-no-dot-files-regexp))
        (delete-directory src))
      moved))
   (t
    (sem-migrate--log "conflict, left in place: %s (target exists: %s)" src dst)
    0)))

(defun sem-migrate--split-journal (content)
  "Split legacy single-file journal CONTENT into monthly bodies.
The legacy tree is `* YYYY' / `** YYYY-MM' / `*** YYYY-MM-DD' / `**** N';
monthly files use `* YYYY-MM-DD' / `** N'.  Returns an alist of
\(MONTH . BODY) in first-seen order; text before the first day heading is
returned under the key \"preamble\" when it is not blank."
  (let ((chunks '())
        (current "preamble"))
    (dolist (line (split-string content "\n"))
      (cond
       ((string-match-p "\\`\\* [0-9]\\{4\\}[ \t]*\\'" line) nil)
       ((string-match-p "\\`\\*\\* [0-9]\\{4\\}-[0-9]\\{2\\}[ \t]*\\'" line) nil)
       ((string-match "\\`\\*\\*\\* \\(\\([0-9]\\{4\\}-[0-9]\\{2\\}\\)-[0-9]\\{2\\}\\)[ \t]*\\'" line)
        (setq current (match-string 2 line))
        (push (cons current (concat "* " (match-string 1 line))) chunks))
       ((string-match "\\`\\*\\*\\*\\* \\(.*\\)\\'" line)
        (push (cons current (concat "** " (match-string 1 line))) chunks))
       (t (push (cons current line) chunks))))
    (let ((months '()))
      (dolist (chunk (nreverse chunks))
        (let ((cell (assoc (car chunk) months)))
          (if cell
              (setcdr cell (concat (cdr cell) "\n" (cdr chunk)))
            (setq months (append months (list (cons (car chunk) (cdr chunk))))))))
      (cl-remove-if (lambda (cell)
                      (and (string= (car cell) "preamble")
                           (string-blank-p (cdr cell))))
                    (mapcar (lambda (cell)
                              (cons (car cell) (string-trim (cdr cell) "\n+" "[\n \t]+")))
                            months)))))

(defun sem-migrate--journal (journal-file journal-dir)
  "Split legacy JOURNAL-FILE into monthly files under JOURNAL-DIR.
Existing monthly files are appended to.  The original is moved to
`sem-migrate-backup-dir'.  Returns the number of monthly files written."
  (if (not (file-exists-p journal-file))
      0
    (let ((months (sem-migrate--split-journal
                   (with-temp-buffer
                     (insert-file-contents journal-file)
                     (buffer-string))))
          (written 0))
      (sem-migrate--ensure-dir journal-dir)
      (dolist (cell months)
        (let* ((name (if (string= (car cell) "preamble") "preamble" (car cell)))
               (target (expand-file-name (concat name ".org") journal-dir))
               (body (concat (cdr cell) "\n")))
          (if (file-exists-p target)
              (write-region (concat "\n" body) nil target t 'silent)
            (write-region (concat (format "#+TITLE: Journal %s\n\n" name) body)
                          nil target nil 'silent))
          (setq written (1+ written))))
      (sem-migrate--ensure-dir sem-migrate-backup-dir)
      (rename-file journal-file
                   (expand-file-name (file-name-nondirectory journal-file)
                                     sem-migrate-backup-dir)
                   t)
      (sem-migrate--log "journal split into %d monthly files" written)
      written)))

(defun sem-migrate--ensure-gitignore (repo-dir)
  "Ensure `sem-migrate-repo-ignored' entries are in REPO-DIR's .gitignore."
  (when (file-directory-p repo-dir)
    (let* ((file (expand-file-name ".gitignore" repo-dir))
           (content (if (file-exists-p file)
                        (with-temp-buffer (insert-file-contents file) (buffer-string))
                      ""))
           (missing (cl-remove-if
                     (lambda (entry)
                       (string-match-p (concat "^" (regexp-quote entry) "$") content))
                     sem-migrate-repo-ignored)))
      (when missing
        (write-region (concat (if (or (string-empty-p content)
                                      (string-suffix-p "\n" content))
                                  ""
                                "\n")
                              "# daemon-managed read-only copies\n"
                              (mapconcat #'identity missing "\n") "\n")
                      nil file t 'silent)))))

(defun sem-migrate-data-layout ()
  "Migrate a flat /data into the split tasks / repository layout.
Idempotent and safe to call at every startup.  Returns the number of
moved or transformed entries; never signals."
  (condition-case err
      (let ((root sem-migrate-data-root)
            (count 0))
        (when (file-directory-p root)
          (sem-migrate--ensure-dir sem-migrate-tasks-dir)
          (dolist (name sem-migrate-tasks-entries)
            (setq count (+ count (sem-migrate--move (expand-file-name name root)
                                                    (expand-file-name name sem-migrate-tasks-dir)))))
          (when (file-directory-p sem-migrate-repo-dir)
            (dolist (move sem-migrate-digest-moves)
              (setq count (+ count (sem-migrate--move
                                    (expand-file-name (car move) root)
                                    (expand-file-name (cdr move) sem-migrate-repo-dir)))))
            (setq count (+ count (sem-migrate--journal
                                  (expand-file-name "journal.org" root)
                                  (expand-file-name "journal/" sem-migrate-repo-dir))))
            ;; Every other root-level Org file is a personal note.
            (dolist (file (directory-files root t "\\.org\\'"))
              (let ((name (file-name-nondirectory file)))
                ;; Task file names left at the root are conflicts with the
                ;; tasks directory, not notes: they stay put and are logged.
                (unless (or (member name sem-migrate-internal-files)
                            (member name sem-migrate-tasks-entries)
                            (string-prefix-p "." name)
                            (not (file-regular-p file)))
                  (setq count (+ count (sem-migrate--move
                                        file
                                        (expand-file-name
                                         name (expand-file-name "notes/" sem-migrate-repo-dir))))))))
            (sem-migrate--ensure-gitignore sem-migrate-repo-dir)))
        (sem-migrate--log "layout migration done (%d entries)" count)
        count)
    (error
     (sem-migrate--log "layout migration failed: %s" (error-message-string err))
     0)))

(provide 'sem-migrate)
;;; sem-migrate.el ends here
