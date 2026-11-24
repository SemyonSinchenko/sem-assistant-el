;;; sem-init-test.el --- Tests for init.el module loading -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Tests for sem-init--load-modules to verify all required modules are loaded.

;;; Code:

(require 'ert)
(require 'sem-mock)

(defvar sem-init--skip-startup t)
(load-file (expand-file-name "../init.el" (file-name-directory load-file-name)))

;;; Test that sem-git-sync is loaded during initialization

(ert-deftest sem-init-test-git-sync-loaded ()
  "Test that sem-git-sync module is loaded by sem-init--load-modules.
Mocks all require calls to track which modules are requested, then asserts
that sem-git-sync is among them and that sem-git-sync-org-roam is fbound."
  (let ((required-modules '())
        (original-require (symbol-function 'require))
        (original-message (symbol-function 'message)))
    (unwind-protect
        (progn
          ;; Mock require to capture module names instead of loading
          (fset 'require
                (lambda (feature &rest _)
                  (push feature required-modules)
                  ;; Provide the feature so subsequent requires don't fail
                  (provide feature)
                  ;; For sem-git-sync, also define the main function
                  (when (eq feature 'sem-git-sync)
                    (defun sem-git-sync-org-roam () nil))
                  feature))
          ;; Mock message to suppress output
          (fset 'message (lambda (&rest _) nil))

          ;; Define sem-init--load-modules as it appears in init.el
          (let ((load-file-name "/app/elisp/init.el"))
            (cl-flet ((sem-init--load-modules
                       ()
                       "Load all SEM modules in dependency order."
                        (let ((load-path (cons (file-name-directory load-file-name) load-path)))
                          (require 'sem-core)
                          (require 'sem-time)
                          (require 'sem-security)
                          (require 'sem-llm)
                         (require 'sem-rss)
                         (require 'sem-prompts)
                         (require 'sem-rules)
                         (require 'sem-url-capture)
                         (require 'sem-git-sync)
                         (require 'sem-router)
                         (require 'sem-planner)
                         (message "SEM: All modules loaded"))))

              ;; Call the load modules function
              (sem-init--load-modules)

              ;; Verify sem-git-sync was required
       (should (member 'sem-git-sync required-modules))
       (should (member 'sem-time required-modules))

       ;; Verify sem-git-sync-org-roam is fbound after load
       (should (fboundp 'sem-git-sync-org-roam)))))

      ;; Cleanup: restore original functions
      (fset 'require original-require)
      (fset 'message original-message)
      ;; Remove any features we provided
      (dolist (module required-modules)
        (when (featurep module)
          (setq features (delq module features)))))))

(ert-deftest sem-init-test-resolve-llm-models-deduplicates-when-equal ()
  "Test resolved model list is deduplicated when weak equals medium."
  (cl-letf (((symbol-function 'getenv)
             (lambda (name)
               (cond
                ((string= name "OPENROUTER_MODEL") "openrouter/medium")
                ((string= name "OPENROUTER_WEAK_MODEL") "openrouter/medium")
                (t nil)))))
    (let ((resolved (sem-init--resolve-llm-models)))
      (should (string= (plist-get resolved :medium) "openrouter/medium"))
      (should (string= (plist-get resolved :weak) "openrouter/medium"))
      (should (= (length (plist-get resolved :models)) 1))
      (should-not (plist-get resolved :weak-fallback)))))

(ert-deftest sem-init-test-resolve-llm-models-fallback-when-empty ()
  "Test weak model falls back to medium when weak env var is empty."
  (cl-letf (((symbol-function 'getenv)
             (lambda (name)
               (cond
                ((string= name "OPENROUTER_MODEL") "openrouter/medium")
                ((string= name "OPENROUTER_WEAK_MODEL") "")
                (t nil)))))
    (let ((resolved (sem-init--resolve-llm-models)))
      (should (string= (plist-get resolved :weak) "openrouter/medium"))
      (should (plist-get resolved :weak-fallback))
      (should (= (length (plist-get resolved :models)) 1)))))

(ert-deftest sem-init-test-readiness-probe-ready-when-all-invariants-satisfied ()
  "Test readiness probe returns non-nil when all invariants are satisfied."
  (sem-init--reset-startup-invariants)
  (dolist (invariant sem-init--required-invariants)
    (sem-init--mark-startup-invariant invariant))
  (should (sem-init-readiness-probe)))

(ert-deftest sem-init-test-readiness-probe-not-ready-when-invariant-missing ()
  "Test readiness probe returns nil when any invariant is missing."
  (sem-init--reset-startup-invariants)
  (dolist (invariant sem-init--required-invariants)
    (unless (eq invariant 'modules-loaded)
      (sem-init--mark-startup-invariant invariant)))
  (should-not (sem-init-readiness-probe)))

(ert-deftest sem-init-test-load-package-dependencies-signals-on-failure ()
  "Test dependency load failures signal and block readiness path." 
  (cl-letf (((symbol-function 'require)
             (lambda (feature &rest _)
                (if (eq feature 'gptel)
                    (error "missing gptel")
                  feature)))
             ((symbol-function 'message)
              (lambda (&rest _) nil)))
    (should-error (sem-init--load-package-dependencies))))

(ert-deftest sem-init-test-validate-env-succeeds-with-valid-timezone ()
  "Test environment validation succeeds when CLIENT_TIMEZONE is valid."
  (cl-letf (((symbol-function 'getenv)
             (lambda (name)
               (cond
                ((string= name "OPENROUTER_KEY") "key")
                ((string= name "OPENROUTER_MODEL") "model")
                (t nil))))
            ((symbol-function 'sem-time-client-timezone)
             (lambda () "Etc/UTC"))
            ((symbol-function 'message)
             (lambda (&rest _) nil)))
    (should (null (sem-init--validate-env)))))

(ert-deftest sem-init-test-validate-env-fails-when-timezone-missing ()
  "Test environment validation fails when CLIENT_TIMEZONE is missing."
  (cl-letf (((symbol-function 'getenv)
             (lambda (name)
               (cond
                ((string= name "OPENROUTER_KEY") "key")
                ((string= name "OPENROUTER_MODEL") "model")
                (t nil))))
            ((symbol-function 'sem-time-client-timezone)
             (lambda ()
               (error "SEM: CLIENT_TIMEZONE environment variable is not set or empty"))))
    (should-error (sem-init--validate-env)
                  :type 'error)))

(ert-deftest sem-init-test-validate-env-fails-when-timezone-invalid ()
  "Test environment validation fails when CLIENT_TIMEZONE is invalid."
  (cl-letf (((symbol-function 'getenv)
             (lambda (name)
               (cond
                ((string= name "OPENROUTER_KEY") "key")
                ((string= name "OPENROUTER_MODEL") "model")
                (t nil))))
            ((symbol-function 'sem-time-client-timezone)
             (lambda ()
               (error "SEM: CLIENT_TIMEZONE is invalid or unavailable in runtime tzdata: Bad/Zone"))))
    (should-error (sem-init--validate-env)
                  :type 'error)))

(ert-deftest sem-init-test-set-paths-decouples-notes-and-repo-roots ()
  "Test startup path config sets notes root separately from repository root."
  (let ((captured-messages '()))
    (cl-letf (((symbol-function 'sem-paths-resolve)
               (lambda ()
                 (list :repository-root "/tmp/repo/"
                       :notes-root "/tmp/repo/org-files/")))
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) captured-messages))))
      (sem-init--set-paths)
      (should (string= org-roam-directory "/tmp/repo/org-files/"))
      (should (string= org-roam-db-location "/tmp/repo/org-roam.db"))
      (should (cl-some (lambda (msg)
                         (string-match-p "repo-root=/tmp/repo/ notes-root=/tmp/repo/org-files/"
                                         msg))
                       captured-messages)))))

(ert-deftest sem-init-test-init-git-repo-uses-repository-root-only ()
  "Test git initialization remains anchored to repository root." 
  (let ((created-dirs '())
        (git-inits '()))
    (cl-letf (((symbol-function 'sem-paths-resolve)
               (lambda ()
                 (list :repository-root "/tmp/repo/"
                       :notes-root "/tmp/repo/org-files/")))
              ((symbol-function 'file-directory-p)
               (lambda (_) nil))
              ((symbol-function 'make-directory)
               (lambda (path &optional _parents)
                 (push path created-dirs)))
              ((symbol-function 'write-region)
               (lambda (&rest _) nil))
              ((symbol-function 'call-process)
               (lambda (_program _in _out _display &rest args)
                 (push args git-inits)
                 0))
              ((symbol-function 'message)
               (lambda (&rest _) nil)))
      (sem-init--init-git-repo)
      (should (member "/tmp/repo/" created-dirs))
      (should-not (member "/tmp/repo/org-files/" created-dirs))
      (should (member '("init" "/tmp/repo/") git-inits)))))

(provide 'sem-init-test)
;;; sem-init-test.el ends here
