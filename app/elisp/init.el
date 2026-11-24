;;; init.el --- SEM Assistant Elisp Daemon Initialization -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; This is the main initialization file for the SEM Assistant Elisp daemon.
;; It runs in a Docker container and processes mobile-captured Org notes
;; and RSS feeds autonomously via LLM.
;;
;; Startup sequence (must execute in strict order):
;; 1. Validate required env vars
;; 2. Load package dependencies installed at build time
;; 3. Configure gptel with the LLM provider backend (DeepSeek or OpenRouter)
;; 4. Set hardcoded paths as globals
;; 5. Set security globals
;; 6. Initialize git repo for org-roam
;; 7. Run db-initialization (elfeed + org-roam)
;; 8. Load all modules
;; 9. Install *Messages* redirection hook
;; 10. Daemon ready

;;; Code:

(require 'cl-lib)

(let ((sem-init--this-dir (file-name-directory (or load-file-name buffer-file-name))))
  (when sem-init--this-dir
    (add-to-list 'load-path sem-init--this-dir)))

(require 'sem-paths)
(require 'sem-time)

(defconst sem-init--required-invariants
  '(env-validated
    package-deps-loaded
    gptel-configured
    paths-configured
    security-globals-set
    git-repo-ready
    databases-initialized
    modules-loaded
    messages-hook-installed)
  "Mandatory startup invariants for daemon readiness.")

(defvar sem-init--startup-invariants nil
  "Alist tracking startup invariant completion state.
Each entry is (INVARIANT . DONE-P) where INVARIANT is a symbol from
`sem-init--required-invariants'.")

(defun sem-init--reset-startup-invariants ()
  "Reset startup invariant state to not-ready defaults."
  (setq sem-init--startup-invariants
        (mapcar (lambda (invariant)
                  (cons invariant nil))
                sem-init--required-invariants)))

(defun sem-init--mark-startup-invariant (invariant)
  "Mark INVARIANT as completed in `sem-init--startup-invariants'."
  (let ((cell (assoc invariant sem-init--startup-invariants)))
    (when cell
      (setcdr cell t))))

(defun sem-init-readiness-probe ()
  "Return non-nil when all mandatory startup invariants are satisfied.
This probe is side-effect free and safe for frequent watchdog/startup checks."
  (condition-case _err
      (and (listp sem-init--startup-invariants)
           (cl-every (lambda (invariant)
                       (eq t (cdr (assoc invariant sem-init--startup-invariants))))
                     sem-init--required-invariants))
    (error nil)))

;;; 1. Validate Required Environment Variables

(defun sem-init--validate-env ()
  "Validate required environment variables.
Signal an error when required env vars are unset or invalid."
  (require 'sem-llm)
  (let ((provider (sem-llm-provider)))
    (unless (sem-llm-api-key)
      (error "SEM: API key for LLM provider %s is not set (LLM_API_KEY or %s)"
             provider
             (plist-get (sem-llm--provider-config provider) :key-env)))
    ;; Signals when no model is configured and the provider has no default.
    (sem-llm--resolve-model-for-tier 'medium)
    (sem-time-client-timezone)
    (message "SEM: Environment variables validated successfully (provider=%s)" provider)))

(defun sem-init--resolve-llm-models ()
  "Resolve effective LLM model configuration.
Returns a plist with keys :medium, :weak, :weak-fallback, and :models.
Weak tier uses `LLM_WEAK_MODEL' (or the provider's legacy weak model
variable) when non-empty; otherwise it falls back to the medium model.
The returned :models list is deduplicated."
  (require 'sem-llm)
  (let* ((medium (plist-get (sem-llm--resolve-model-for-tier 'medium) :model))
         (weak-resolution (sem-llm--resolve-model-for-tier 'weak))
         (weak (plist-get weak-resolution :model)))
    (list :medium medium
          :weak weak
          :weak-fallback (plist-get weak-resolution :weak-fallback)
          :models (delete-dups (list medium weak)))))

;;; 2. Load Package Dependencies (installed at build time)

(defun sem-init--load-package-dependencies ()
  "Load build-time-installed package dependencies with `require'.
Signals an error when any required dependency fails to load."
  (let ((failed '()))
    (dolist (pkg '(gptel elfeed org-roam))
      (condition-case err
          (require pkg)
        (error
         (let ((msg (error-message-string err)))
           (push (cons pkg msg) failed)
           (message "SEM: Failed to load package %s: %s" pkg msg)))))
    (when failed
      (error "Dependency load failed: %s"
             (mapconcat
              (lambda (entry)
                (format "%s (%s)" (car entry) (cdr entry)))
              (nreverse failed)
              ", ")))))

;;; 3. Configure gptel with the LLM Provider Backend

(defun sem-init--configure-gptel ()
  "Configure gptel with the backend of the configured LLM provider.
The API key is read via `sem-llm-api-key' at request time.  Reasoning
settings are applied per request by `sem-llm-request', not on the backend."
  (require 'gptel)
  (require 'sem-llm)
  (let* ((provider (sem-llm-provider))
         (resolved (sem-init--resolve-llm-models))
         (medium-model (plist-get resolved :medium))
         (weak-model (plist-get resolved :weak))
         (weak-fallback (plist-get resolved :weak-fallback))
         (registered-models (mapcar #'intern (plist-get resolved :models)))
         (backend-name nil))
    (pcase provider
      ("deepseek"
       (setq backend-name "DeepSeek")
       (if (fboundp 'gptel-make-deepseek)
           (gptel-make-deepseek backend-name
             :stream t
             :key #'sem-llm-api-key
             :models registered-models)
         (gptel-make-openai backend-name
           :host "api.deepseek.com"
           :endpoint "/chat/completions"
           :stream t
           :key #'sem-llm-api-key
           :models registered-models)))
      ("openrouter"
       (setq backend-name "OpenRouter")
       (gptel-make-openai backend-name
         :host "openrouter.ai"
         :endpoint "/api/v1/chat/completions"
         :stream t
         :key #'sem-llm-api-key
         :models registered-models)))
    (setq gptel-backend (gptel-get-backend backend-name))
    (setq gptel-model (intern medium-model))
    (message "SEM: gptel configured with %s backend" backend-name)
    (message "SEM: LLM model config: medium=%s (reasoning=%s) weak=%s (reasoning=%s)%s"
             medium-model
             (sem-llm--reasoning-effort-for-tier 'medium)
             weak-model
             (sem-llm--reasoning-effort-for-tier 'weak)
             (if weak-fallback " (fallback to medium)" ""))))

;;; 4. Set Hardcoded Paths as Globals

(defun sem-init--set-paths ()
  "Set all hardcoded paths as global variables."
  (let* ((resolved-paths (sem-paths-resolve))
         (repository-root (plist-get resolved-paths :repository-root))
         (notes-root (plist-get resolved-paths :notes-root)))
    (setq org-roam-directory notes-root)
    (setq org-roam-db-location (sem-paths-join repository-root "org-roam.db"))
    (message "SEM: Path contract resolved repo-root=%s notes-root=%s"
             repository-root
             notes-root))
  (setq elfeed-db-directory (expand-file-name "/data/elfeed/"))
  (message "SEM: Paths configured"))

;;; 5. Set Security Globals

(defun sem-init--set-security-globals ()
  "Set security-related global variables.
Disables lock files, local variables, and configures org-babel safety."
  (setq create-lockfiles nil)
  (setq enable-local-variables nil)
  (setq org-confirm-babel-evaluate t)
  (setq org-export-babel-evaluate nil)
  (setq org-display-remote-inline-images nil)
  (message "SEM: Security globals set"))

;;; 6. Initialize Git Repo for org-roam (GitHub Sync Readiness)

(defun sem-init--init-git-repo ()
  "Initialize git repo for org-roam if not already present.
Creates /data/org-roam/.git/ if absent and writes .gitignore.
This is pre-wiring for future github-integration."
  (let* ((resolved-paths (sem-paths-resolve))
         (repository-root (plist-get resolved-paths :repository-root))
         (git-dir (expand-file-name ".git" repository-root)))
    (unless (file-directory-p git-dir)
      (message "SEM: Initializing git repo in %s" repository-root)
      (make-directory repository-root t)
      (call-process "git" nil nil nil "init" repository-root)
      ;; Write .gitignore
      (let ((gitignore-path (expand-file-name ".gitignore" repository-root)))
        (with-temp-file gitignore-path
          (insert "# org-roam database files\n")
          (insert "org-roam.db\n")
          (insert "*.db-shm\n")
          (insert "*.db-wal\n"))))
    (message "SEM: Git repo ready")))

;;; 7. Database Initialization

(defun sem-init--init-elfeed-db ()
  "Load Elfeed database with corruption recovery.
Attempts to load existing DB. On error, wipes and recreates."
  (require 'elfeed)
  (let ((db-dir elfeed-db-directory))
    (make-directory db-dir t)
    (condition-case err
        (progn
          (elfeed-db-load)
          (message "SEM: Elfeed DB loaded successfully"))
      (error
       (message "SEM: Elfeed DB corrupt, wiping and recreating: %s"
                (error-message-string err))
       (delete-directory db-dir t)
       (make-directory db-dir t)
       (elfeed-db-load)
       (message "SEM: Elfeed DB recreated")))))

(defun sem-init--init-org-roam-db ()
  "Rebuild org-roam database from scratch.
Always deletes existing DB and calls org-roam-db-sync.
Handles missing /data/org-roam/ gracefully."
  (require 'org-roam)
  (let* ((resolved-paths (sem-paths-resolve))
         (repository-root (plist-get resolved-paths :repository-root))
         (notes-root (plist-get resolved-paths :notes-root))
         (db-path (expand-file-name (or org-roam-db-location
                                        (sem-paths-join repository-root "org-roam.db"))))
         (shm-path (concat db-path "-shm"))
         (wal-path (concat db-path "-wal")))
    ;; Delete old DB files if they exist
    (dolist (path (list db-path shm-path wal-path))
      (when (file-exists-p path)
        (delete-file path)))
    ;; Create directory if needed
    (make-directory notes-root t)
    ;; Sync database
    (condition-case err
        (progn
          (org-roam-db-sync)
          (message "SEM: org-roam DB synced"))
      (error
       (message "SEM: org-roam DB sync error (continuing): %s"
                (error-message-string err))))))

(defun sem-init--init-databases ()
  "Initialize both Elfeed and org-roam databases."
  (sem-init--init-elfeed-db)
  (sem-init--init-org-roam-db))

;;; 8. Load All Modules

(defun sem-init--load-modules ()
  "Load all SEM modules in dependency order.
sem-core must load first as it defines sem-core-log.
sem-prompts must load before sem-router and sem-url-capture."
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
    (require 'sem-daily-plan)
    (require 'sem-migrate)
    (require 'sem-orgnote)
    (message "SEM: All modules loaded")))

;;; 9. Install *Messages* Redirection Hook

(defun sem-init--install-messages-hook ()
  "Install the *Messages* persistence hook with daily rotation."
  (add-hook 'post-command-hook #'sem-core--flush-messages-daily)
  (message "SEM: *Messages* daily rotation installed"))

;;; 10. Daemon Startup Sequence

(defun sem-init--startup ()
  "Execute the complete daemon startup sequence.
All steps run in strict order. Errors are logged to stderr and
written to errors.org to aid debugging."
  (condition-case err
      (progn
        (sem-init--reset-startup-invariants)
        ;; Step 1: Validate env vars
        (message "SEM: Starting init step 1/10 - validate env vars")
        (sem-init--validate-env)
        (sem-init--mark-startup-invariant 'env-validated)
        (message "SEM: Step 1/10 complete - env vars validated")
        ;; Step 2: Load package dependencies
        (message "SEM: Starting init step 2/10 - load package dependencies")
        (sem-init--load-package-dependencies)
        (sem-init--mark-startup-invariant 'package-deps-loaded)
        (message "SEM: Step 2/10 complete - package dependencies loaded")
        ;; Step 3: Configure gptel
        (message "SEM: Starting init step 3/10 - configure gptel")
        (sem-init--configure-gptel)
        (sem-init--mark-startup-invariant 'gptel-configured)
        (message "SEM: Step 3/10 complete - gptel configured")
        ;; Step 4: Set paths
        (message "SEM: Starting init step 4/10 - set paths")
        (sem-init--set-paths)
        ;; Move a legacy flat /data into the tasks / repository split before
        ;; any module touches files.  Idempotent, never signals.
        (require 'sem-migrate)
        (sem-migrate-data-layout)
        (sem-init--mark-startup-invariant 'paths-configured)
        (message "SEM: Step 4/10 complete - paths configured")
        ;; Step 5: Set security globals
        (message "SEM: Starting init step 5/10 - set security globals")
        (sem-init--set-security-globals)
        (sem-init--mark-startup-invariant 'security-globals-set)
        (message "SEM: Step 5/10 complete - security globals set")
        ;; Step 6: Init git repo
        (message "SEM: Starting init step 6/10 - init git repo")
        (sem-init--init-git-repo)
        (sem-init--mark-startup-invariant 'git-repo-ready)
        (message "SEM: Step 6/10 complete - git repo ready")
        ;; Step 7: Init databases
        (message "SEM: Starting init step 7/10 - init databases")
        (sem-init--init-databases)
        (sem-init--mark-startup-invariant 'databases-initialized)
        (message "SEM: Step 7/10 complete - databases initialized")
        ;; Step 8: Load modules
        (message "SEM: Starting init step 8/10 - load modules")
        (sem-init--load-modules)
        (when (fboundp 'sem-rss-refresh-feeds)
          (sem-rss-refresh-feeds))
        (sem-init--mark-startup-invariant 'modules-loaded)
        (message "SEM: Step 8/10 complete - modules loaded")
        ;; Step 9: Install messages hook
        (message "SEM: Starting init step 9/10 - install messages hook")
        (sem-init--install-messages-hook)
        (sem-init--mark-startup-invariant 'messages-hook-installed)
        (message "SEM: Step 9/10 complete - messages hook installed")
        ;; Step 10: Daemon ready
        (message "SEM: Step 10/10 complete - daemon ready")
        (message "SEM: Daemon ready")
        (princ "SEM: Daemon started successfully\n" t))
    (error
     (let ((error-msg (error-message-string err)))
       ;; Log to stderr for immediate visibility in container logs
       (princ (format "SEM: STARTUP ERROR: %s\n" error-msg) t)
       ;; Also log via message (goes to *Messages*)
       (message "SEM: Startup error: %s" error-msg)
       ;; Log to errors.org if sem-core-log-error is available
       (condition-case _err2
           (when (fboundp 'sem-core-log-error)
             (sem-core-log-error "init" "STARTUP" error-msg nil))
         (error nil))))))

;; Run startup when this file is loaded
(unless (bound-and-true-p sem-init--skip-startup)
  (sem-init--startup))

(provide 'init)
;;; init.el ends here
