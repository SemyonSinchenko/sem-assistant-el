;;; sem-migrate-test.el --- Tests for sem-migrate.el -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Tests for the one-time /data layout migration, run against a temporary
;; copy of the legacy flat layout.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'sem-mock)

(load-file (expand-file-name "../sem-migrate.el" (file-name-directory load-file-name)))

(defconst sem-migrate-test--legacy-journal
  "* 2026
** 2026-10
*** 2026-10-31
**** 1
:PROPERTIES:
:INGESTED_AT: 2026-10-31T10:00:00+0100
:END:

October entry
** 2026-11
*** 2026-11-01
**** 1
:PROPERTIES:
:INGESTED_AT: 2026-11-01T09:00:00+0100
:END:

November one
**** 2
November two
"
  "Legacy single-file journal spanning two months.")

(defmacro sem-migrate-test--with-data (&rest body)
  "Run BODY with migration roots pointing at a fresh legacy layout in `root'."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "sem-migrate-" t)))
          (sem-migrate-data-root root)
          (sem-migrate-tasks-dir (expand-file-name "tasks/" root))
          (sem-migrate-repo-dir (expand-file-name "org-roam/" root))
          (sem-migrate-backup-dir (expand-file-name ".migrated/" root)))
     (unwind-protect
         (cl-flet ((put (name content)
                     (let ((file (expand-file-name name root)))
                       (make-directory (file-name-directory file) t)
                       (write-region content nil file nil 'silent)))
                   (content (name)
                     (with-temp-buffer
                       (insert-file-contents (expand-file-name name root))
                       (buffer-string))))
           (dolist (name '("inbox-mobile.org" "tasks.org" "rec-tasks.org" "rules.org"
                           "feeds.org" "errors.org" "sem-log.org" "links.org"
                           "quotes.org" "tips.org" "prompts/general-prompt.txt"
                           "morning-read/2026-11-24.org" "archive/2026-10/2026-10-01.org"
                           "org-roam/org-files/node.org" "org-roam/.gitignore"
                           ".sem-cursor.el"))
             (put name (format "content of %s\n" name)))
           (put "journal.org" sem-migrate-test--legacy-journal)
           ,@body)
       (delete-directory root t))))

(ert-deftest sem-migrate-test-splits-legacy-layout ()
  "Test the flat layout is split into tasks, repository and internals."
  (sem-migrate-test--with-data
    (cl-letf (((symbol-function 'message) (lambda (&rest _) nil)))
      (should (> (sem-migrate-data-layout) 0)))
    (dolist (name '("tasks/inbox-mobile.org" "tasks/tasks.org" "tasks/rec-tasks.org"
                    "tasks/rules.org" "tasks/feeds.org" "tasks/errors.org"
                    "tasks/prompts/general-prompt.txt"
                    "org-roam/notes/links.org" "org-roam/notes/quotes.org"
                    "org-roam/notes/tips.org"
                    "org-roam/digest/2026-11-24.org"
                    "org-roam/digest/archive/2026-10/2026-10-01.org"
                    "org-roam/org-files/node.org"
                    "sem-log.org" ".sem-cursor.el" ".migrated/journal.org"))
      (should (file-exists-p (expand-file-name name root))))
    (dolist (name '("tasks.org" "links.org" "journal.org" "morning-read" "archive" "prompts"))
      (should-not (file-exists-p (expand-file-name name root))))
    (should (string= (content "tasks/tasks.org") "content of tasks.org\n"))))

(ert-deftest sem-migrate-test-journal-split-by-month ()
  "Test the legacy journal becomes monthly files with flattened levels."
  (sem-migrate-test--with-data
    (cl-letf (((symbol-function 'message) (lambda (&rest _) nil)))
      (sem-migrate-data-layout))
    (let ((october (content "org-roam/journal/2026-10.org"))
          (november (content "org-roam/journal/2026-11.org")))
      (should (string-prefix-p "#+TITLE: Journal 2026-10\n\n* 2026-10-31\n** 1\n" october))
      (should (string-match-p "October entry" october))
      (should-not (string-match-p "November" october))
      (should (string-match-p "^\\* 2026-11-01$" november))
      (should (string-match-p "^\\*\\* 2$" november))
      (should (string-match-p "November two" november))
      (should-not (string-match-p "^\\*\\*\\*" november)))))

(ert-deftest sem-migrate-test-is-idempotent-and-never-overwrites ()
  "Test a second run changes nothing and conflicting targets are kept."
  (sem-migrate-test--with-data
    (cl-letf (((symbol-function 'message) (lambda (&rest _) nil)))
      (sem-migrate-data-layout)
      ;; A client recreates a file at the old location after the migration.
      (put "tasks.org" "stale copy\n")
      (should (= (sem-migrate-data-layout) 0)))
    (should (string= (content "tasks/tasks.org") "content of tasks.org\n"))
    (should (string= (content "tasks.org") "stale copy\n"))))

(provide 'sem-migrate-test)
;;; sem-migrate-test.el ends here
