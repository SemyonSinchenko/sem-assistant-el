;;; sem-orgnote-test.el --- Tests for sem-orgnote.el -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Tests for orgnote sync: task copies, git exclusion, conflict reporting and
;; the asynchronous orgnote-cli run (against a fake orgnote-cli script).

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'sem-mock)

(load-file (expand-file-name "../sem-core.el" (file-name-directory load-file-name)))
(load-file (expand-file-name "../sem-orgnote.el" (file-name-directory load-file-name)))

(defmacro sem-orgnote-test--with-env (&rest body)
  "Run BODY with orgnote paths inside a temporary directory bound to `dir'."
  (declare (indent 0))
  `(let* ((dir (file-name-as-directory (make-temp-file "sem-orgnote-" t)))
          (sem-orgnote-root (expand-file-name "org-roam/" dir))
          (sem-orgnote-home (expand-file-name "home/" dir))
          (sem-orgnote-backup-dir (expand-file-name "backups/" dir))
          (sem-orgnote-log-file (expand-file-name "orgnote-cli.log" dir))
          (sem-orgnote-copy-dir (expand-file-name "org-roam/sem/" dir))
          (sem-orgnote-copy-sources (list (expand-file-name "tasks/tasks.org" dir)))
          (sem-orgnote-conflicts-file (expand-file-name "conflicts.el" dir))
          (sem-orgnote--process nil))
     (unwind-protect
         (progn
           (make-directory (expand-file-name "tasks/" dir) t)
           (make-directory (expand-file-name ".git/info/" sem-orgnote-root) t)
           ,@body)
       (delete-directory dir t))))

(defun sem-orgnote-test--read (file)
  "Return FILE contents."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(ert-deftest sem-orgnote-test-refresh-copies-writes-only-on-change ()
  "Test task copies carry a read-only header and are rewritten only on change."
  (sem-orgnote-test--with-env
    (write-region "* TODO a\n" nil (car sem-orgnote-copy-sources) nil 'silent)
    (progn
      (should (= 1 (sem-orgnote-refresh-copies)))
      (should (= 0 (sem-orgnote-refresh-copies)))
      (let ((copy (sem-orgnote-test--read (expand-file-name "tasks.org" sem-orgnote-copy-dir))))
        (should (string-prefix-p "# Read-only copy of tasks.org" copy))
        (should (string-suffix-p "* TODO a\n" copy)))
      ;; An edit of the copy (e.g. from orgnote) is overwritten.
      (write-region "edited\n" nil (expand-file-name "tasks.org" sem-orgnote-copy-dir) nil 'silent)
      (should (= 1 (sem-orgnote-refresh-copies))))))

(ert-deftest sem-orgnote-test-git-exclude-and-gitignore-cleanup ()
  "Test sem/ moves from .gitignore to .git/info/exclude, idempotently."
  (sem-orgnote-test--with-env
    (write-region "org-roam.db\n# daemon-managed read-only copies\nsem/\n" nil
                  (expand-file-name ".gitignore" sem-orgnote-root) nil 'silent)
    (sem-orgnote--ensure-git-exclude sem-orgnote-root)
    (sem-orgnote--ensure-git-exclude sem-orgnote-root)
    (should (string= (sem-orgnote-test--read (expand-file-name ".gitignore" sem-orgnote-root))
                     "org-roam.db\n"))
    (let ((exclude (sem-orgnote-test--read
                    (expand-file-name ".git/info/exclude" sem-orgnote-root))))
      (should (= 1 (with-temp-buffer (insert exclude)
                                     (how-many "^sem/$" (point-min) (point-max)))))
      (should (string-match-p "^\\.orgnote/$" exclude)))))

(ert-deftest sem-orgnote-test-conflicts-reported-once ()
  "Test each conflict file creates one errors.org entry until resolved."
  (sem-orgnote-test--with-env
    (let ((reported '()))
      (cl-letf (((symbol-function 'sem-core-log-error)
                 (lambda (_m _e msg &rest _) (push msg reported))))
        (make-directory (expand-file-name "notes/" sem-orgnote-root) t)
        (write-region "x" nil (expand-file-name "notes/a.sync-conflict-1-phone.org"
                                                sem-orgnote-root) nil 'silent)
        (write-region "x" nil (expand-file-name ".git/b.sync-conflict-1.org"
                                                sem-orgnote-root) nil 'silent)
        (should (equal (sem-orgnote-report-conflicts) '("notes/a.sync-conflict-1-phone.org")))
        (should-not (sem-orgnote-report-conflicts))
        (should (= 1 (length reported)))
        (should (string-match-p "notes/a.sync-conflict" (car reported)))))))

(ert-deftest sem-orgnote-test-config-content ()
  "Test the generated orgnote-cli config targets the repo and quotes values."
  (sem-orgnote-test--with-env
    (cl-letf (((symbol-function 'getenv)
               (lambda (name &rest _) (when (string= name "ORGNOTE_REMOTE_ADDRESS") nil))))
      (let* ((file (sem-orgnote--write-config "tok\"en"))
             (content (sem-orgnote-test--read file)))
        (should (string-match-p "^remoteAddress = \"http://orgnote-backend:3000/v1\"$" content))
        (should (string-match-p "^token = \"tok\\\\\"en\"$" content))
        (should (string-match-p (concat "^rootFolder = \""
                                        (regexp-quote (directory-file-name sem-orgnote-root))
                                        "\"$")
                                content))
        (should (string-match-p "\"digest/archive/\\*\\*\"" content))
        (should (= (file-modes file) #o600))))))

(defun sem-orgnote-test--fake-cli (dir script)
  "Install a fake orgnote-cli running SCRIPT in DIR; return its bin directory."
  (let* ((bin (expand-file-name "bin/" dir))
         (file (expand-file-name "orgnote-cli" bin)))
    (make-directory bin t)
    (write-region (concat "#!/bin/sh\n" script "\n") nil file nil 'silent)
    (set-file-modes file #o755)
    bin))

(defun sem-orgnote-test--run-sync ()
  "Run `sem-orgnote-sync' and wait for its callback; return the result."
  (let ((result :pending))
    (should (sem-orgnote-sync (lambda (ok) (setq result ok))))
    (with-timeout (10 (error "orgnote sync did not finish"))
      (while (eq result :pending)
        (accept-process-output nil 0.05)))
    result))

(ert-deftest sem-orgnote-test-sync-runs-cli-with-persistent-home ()
  "Test the CLI runs asynchronously with HOME on the data volume."
  (sem-orgnote-test--with-env
    (let* ((bin (sem-orgnote-test--fake-cli
                 dir "echo \"home=$HOME args=$*\" > \"$HOME/run.txt\"; echo 'Everything is up to date.'"))
           (exec-path (cons bin exec-path))
           (process-environment (cons (concat "PATH=" bin ":" (getenv "PATH"))
                                      (cons "ORGNOTE_API_TOKEN=secret" process-environment)))
           (logs '()))
      (cl-letf (((symbol-function 'sem-core-log)
                 (lambda (_m _e status msg &rest _) (push (cons status msg) logs)))
                ((symbol-function 'sem-core-log-error)
                 (lambda (&rest args) (push (cons "FAIL" args) logs))))
        (should (eq (sem-orgnote-test--run-sync) t))
        (should (string-match-p
                 (concat "home=" (regexp-quote (directory-file-name sem-orgnote-home))
                         " args=sync --account sem")
                 (sem-orgnote-test--read (expand-file-name "run.txt" sem-orgnote-home))))
        (should (file-exists-p (expand-file-name ".config/orgnote/config.toml" sem-orgnote-home)))
        (should (assoc "OK" logs))
        (should-not (sem-orgnote-running-p))))))

(ert-deftest sem-orgnote-test-sync-detects-error-despite-exit-zero ()
  "Test an orgnote-cli error is a failure even when it exits with 0."
  (sem-orgnote-test--with-env
    (let* ((bin (sem-orgnote-test--fake-cli
                 dir "echo '[index.ts] Unexpected error: 401 Unauthorized'; exit 0"))
           (exec-path (cons bin exec-path))
           (process-environment (cons (concat "PATH=" bin ":" (getenv "PATH"))
                                      (cons "ORGNOTE_API_TOKEN=secret" process-environment)))
           (errors '()))
      (cl-letf (((symbol-function 'sem-core-log) (lambda (&rest _) nil))
                ((symbol-function 'sem-core-log-error)
                 (lambda (_m _e msg &rest _) (push msg errors))))
        (should (null (sem-orgnote-test--run-sync)))
        (should (string-match-p "401 Unauthorized" (car errors)))))))

(ert-deftest sem-orgnote-test-disabled-without-token ()
  "Test sync is a no-op without ORGNOTE_API_TOKEN."
  (sem-orgnote-test--with-env
    (let ((process-environment (cons "ORGNOTE_API_TOKEN" process-environment))
          (called :unset))
      (should-not (sem-orgnote-sync (lambda (ok) (setq called ok))))
      (should (null called)))))

(provide 'sem-orgnote-test)
;;; sem-orgnote-test.el ends here
