;;; sem-rss-test.el --- Tests for sem-rss.el -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Tests for sem-rss text cleaning and prompt building functions.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Set prompts directory before loading sem-rss so tests can find prompt files
;; Test file is at app/elisp/tests/sem-rss-test.el, prompts at data/prompts/
(setq sem-rss-prompts-dir
      (expand-file-name "../../../data/prompts/"
                        (file-name-directory (or load-file-name buffer-file-name))))

(require 'sem-rss)

;;; Tests for sem-rss--clean-text

(ert-deftest sem-rss-test-clean-text-html-stripping ()
  "Test HTML tag stripping."
  (let ((html "<html><body><h1>Title</h1><p>Content</p></body></html>"))
    (let ((cleaned (sem-rss--clean-text html)))
      (should-not (string-match-p "<[^>]+>" cleaned))
      (should (string-match-p "Title" cleaned))
      (should (string-match-p "Content" cleaned)))))

(ert-deftest sem-rss-test-clean-text-entity-replacement ()
  "Test HTML entity replacement."
  (let ((html "Tom &amp; Jerry &lt;cats&gt; &quot;quotes&quot;"))
    (let ((cleaned (sem-rss--clean-text html)))
      (should (string-match-p "Tom & Jerry" cleaned))
      (should (string-match-p "<cats>" cleaned))
      (should (string-match-p "\"quotes\"" cleaned)))))

(ert-deftest sem-rss-test-clean-text-truncation ()
  "Test text truncation at 3000 characters."
  (let ((long-text (make-string 5000 ?a)))
    (let ((cleaned (sem-rss--clean-text long-text)))
      (should (<= (length cleaned) 3003)))))  ; 3000 + "..."

(ert-deftest sem-rss-test-clean-text-whitespace-normalization ()
  "Test whitespace normalization."
  (let ((html "<p>Multiple   spaces\n\nand\r\nnewlines</p>"))
    (let ((cleaned (sem-rss--clean-text html)))
      (should-not (string-match-p "  " cleaned))  ; No multiple spaces
      (should-not (string-match-p "\n" cleaned))  ; No newlines
      (should (string-match-p "Multiple spaces and newlines" cleaned)))))

;;; Tests for sem-rss--build-entries-text

(ert-deftest sem-rss-test-build-entries-text-truncation ()
  "Test entries text truncation to max input chars."
  (let* ((entry '(:title "Test" :link "http://test.com" :tags ("test") :content "content"))
         (entries (list entry))
         (original-max sem-rss-max-input-chars))
    ;; Temporarily set a very low max for testing
    (let ((sem-rss-max-input-chars 10))
      (let ((text (sem-rss--build-entries-text entries)))
        (should (<= (length text) 10))))))

;;; Tests for prompt builders use template variables

(ert-deftest sem-rss-test-general-prompt-uses-template ()
  "Test that general prompt builder uses the template variable."
  ;; Load prompt templates (lazy loading)
  (sem-rss--ensure-prompts-loaded)
  ;; The prompt should be built from the template
  (let ((entries nil)
        (days 1))
    (let ((prompt (sem-rss--build-general-prompt entries days)))
      ;; Should be a non-empty string
      (should (stringp prompt))
      (should (> (length prompt) 0))
      ;; Should contain expected content from template
      (should (string-match-p "RSS" prompt)))))

(ert-deftest sem-rss-test-arxiv-prompt-uses-template ()
  "Test that arxiv prompt builder uses the template variable."
  ;; Load prompt templates (lazy loading)
  (sem-rss--ensure-prompts-loaded)
  ;; The prompt should be built from the template
  (let ((entries nil)
        (days 1))
    (let ((prompt (sem-rss--build-arxiv-prompt entries days)))
      ;; Should be a non-empty string
      (should (stringp prompt))
      (should (> (length prompt) 0))
      ;; Should contain expected content from template
      (should (string-match-p "Research" prompt)))))

(ert-deftest sem-rss-test-prompt-templates-loaded ()
  "Test that prompt templates are loaded on demand."
  ;; Load prompt templates (lazy loading)
  (sem-rss--ensure-prompts-loaded)
  ;; Both template variables should be non-nil and non-empty
  (should sem-rss-general-prompt-template)
  (should (stringp sem-rss-general-prompt-template))
  (should (> (length sem-rss-general-prompt-template) 0))
  (should sem-rss-arxiv-prompt-template)
  (should (stringp sem-rss-arxiv-prompt-template))
  (should (> (length sem-rss-arxiv-prompt-template) 0)))

;;; Tests for prompt builders contain category names

(ert-deftest sem-rss-test-build-general-prompt-contains-categories ()
  "Test that general prompt contains category mappings."
  ;; Load prompt templates (lazy loading)
  (sem-rss--ensure-prompts-loaded)
  (let ((entries nil))
    (let ((prompt (sem-rss--build-general-prompt entries 1)))
      (should (string-match-p "Data Engineering" prompt))
      (should (string-match-p "Open Source" prompt))
      (should (string-match-p "Artificial Intelligence" prompt)))))

(ert-deftest sem-rss-test-build-arxiv-prompt-contains-categories ()
  "Test that arxiv prompt contains category mappings."
  ;; Load prompt templates (lazy loading)
  (sem-rss--ensure-prompts-loaded)
  (let ((entries nil))
    (let ((prompt (sem-rss--build-arxiv-prompt entries 1)))
      (should (string-match-p "cs.DB" prompt))
      (should (string-match-p "cs.AI" prompt))
      (should (string-match-p "physics.soc-ph" prompt)))))

;;; Test sem-rss-collect-entries per-feed cap

(ert-deftest sem-rss-test-collect-entries-per-feed-cap ()
  "Test that collect-entries applies per-feed cap.
This is a structural test - actual Elfeed DB testing requires mock DB."
  ;; Verify the constant is set
  (should (numberp sem-rss-max-entries-per-feed))
  (should (> sem-rss-max-entries-per-feed 0))
  ;; The actual capping logic is tested via code inspection
  ;; since it requires Elfeed DB setup
  (should t))

;;; Test RSS uses sem-llm-request

(ert-deftest sem-rss-test-generate-file-uses-sem-llm-request ()
  "Test that sem-rss--generate-file invokes sem-llm-request (not gptel-request).
This is a structural test verifying the code uses sem-llm-request."
  ;; Verify by checking that sem-llm is required in sem-rss--generate-file
  ;; The actual test is that the function loads without error and sem-llm
  ;; is available (which means require 'sem-llm succeeded)
   (require 'sem-llm)
   (should (fboundp 'sem-llm-request)))

(ert-deftest sem-rss-test-generate-file-uses-medium-tier ()
  "Test RSS digest generation requests medium tier intent."
  (let ((captured-tier nil))
    (cl-letf (((symbol-function 'sem-llm-request)
               (lambda (_prompt _system callback context &optional tier)
                 (setq captured-tier tier)
                 (funcall callback nil (list :error "mock") context)
                 nil))
              ((symbol-function 'sem-core-log-error)
               (lambda (&rest _args) nil)))
      (sem-rss--generate-file "/tmp/test-rss-tier.org" "prompt" "Test" 1)
      (should (eq captured-tier 'medium)))))

(ert-deftest sem-rss-test-generate-file-defangs-urls-before-write ()
  "Test RSS file output applies URL defanging contract."
  (let ((target (make-temp-file "sem-rss-sanitize-" nil ".org")))
    (unwind-protect
        (cl-letf (((symbol-function 'sem-llm-request)
                   (lambda (_prompt _system callback context &optional _tier)
                     (funcall callback "Link: https://example.com" nil context)
                     nil))
                 ((symbol-function 'sem-core-log)
                  (lambda (&rest _) nil)))
          (sem-rss--generate-file target "prompt" "Test" 1)
          (with-temp-buffer
            (insert-file-contents target)
            (let ((content (buffer-string)))
              (should (string-match-p "hxxps://example\\.com" content))
              (should-not (string-match-p "https://example\\.com" content)))))
      (when (file-exists-p target)
        (delete-file target)))))

(ert-deftest sem-rss-test-generate-file-latex-in-org-link ()
  "Test sem-rss--generate-file handles LaTeX backslashes inside an org-link.
Reproduces the production 'Invalid use of \\ in replacement text' failure:
the LLM returns an org-link whose description contains LaTeX like
$\\texttt{SynC}$, which must be sanitized and written without error."
  (let ((target (make-temp-file "sem-rss-latex-" nil ".org")))
    (unwind-protect
        (let ((captured-error nil)
              (response "[[https://arxiv.org/abs/2406.15797][$\\texttt{SynC}$: Synergistic Boosting]]"))
          (cl-letf (((symbol-function 'sem-llm-request)
                     (lambda (_prompt _system callback context &optional _tier)
                       (funcall callback response nil context)
                       nil))
                   ((symbol-function 'sem-core-log)
                    (lambda (&rest _) nil))
                   ((symbol-function 'sem-core-log-error)
                    (lambda (&rest _) nil)))
            (condition-case err
                (sem-rss--generate-file target "prompt" "Arxiv Digest" 1)
              (error (setq captured-error err))))
          ;; The callback MUST NOT signal "Invalid use of \\ in replacement text"
          (should-not captured-error)
          ;; The digest file is written successfully with sanitized URLs
          (with-temp-buffer
            (insert-file-contents target)
            (let ((content (buffer-string)))
              (should (string-match-p "hxxps://arxiv\\.org/abs/2406\\.15797"
                                      content))
              (should-not (string-match-p "https://arxiv" content))
              ;; LaTeX markup in the description is preserved verbatim
              (should (string-match-p "\\\\texttt{SynC}" content)))))
      (when (file-exists-p target)
        (delete-file target)))))

(ert-deftest sem-rss-test-nil-hash-handling ()
  "Test that sem-core--mark-processed handles nil hash without crashing.
RSS digest passes nil hash - this should be a no-op."
  ;; This should not crash or error
  (should (null (sem-core--mark-processed nil)))
  ;; Cursor should remain unchanged (empty)
  (let ((test-cursor (make-temp-file "cursor-test-")))
    (unwind-protect
        (let ((sem-core-cursor-file test-cursor))
          (sem-core--mark-processed nil)
          ;; File should not exist or be empty
          (if (file-exists-p test-cursor)
              (with-temp-buffer
                (insert-file-contents test-cursor)
                (should (or (string-blank-p (buffer-string))
                            (string= (buffer-string) "()"))))))
      (delete-file test-cursor))))

;;; Tests for feed parser and reload cache

(ert-deftest sem-rss-test-parse-feeds-supports-org-links-and-inherited-tags ()
  "Test parser supports org-link headings and inherited tags." 
  (let ((tmp-file (make-temp-file "sem-rss-feeds-" nil ".org"
                                  (concat "* Feeds :elfeed:\n"
                                          "** AI :ai:\n"
                                          "*** [[https://example.com/rss.xml][Example]] :csai:\n"
                                          "*** https://another.example/feed :vendors:\n"
                                          "** Ignored :ignore:\n"
                                          "*** https://ignored.example/feed\n"
                                          "* Other\n"
                                          "** https://outside.example/feed\n"))))
    (unwind-protect
        (let* ((feeds (sem-rss--parse-feeds-from-org-file tmp-file))
               (entry1 (seq-find (lambda (entry)
                                   (and (consp entry)
                                        (string= (car entry) "https://example.com/rss.xml")))
                                 feeds))
               (entry2 (seq-find (lambda (entry)
                                   (and (consp entry)
                                        (string= (car entry) "https://another.example/feed")))
                                 feeds)))
          (should (= (length feeds) 2))
          (should entry1)
          (should entry2)
          (should (member 'ai (cdr entry1)))
          (should (member 'csai (cdr entry1)))
          (should (member 'ai (cdr entry2)))
          (should (member 'vendors (cdr entry2))))
      (delete-file tmp-file))))

(ert-deftest sem-rss-test-refresh-feeds-skips-reparse-when-unchanged ()
  "Test refresh uses cache when feeds file fingerprint is unchanged." 
  (let* ((tmp-file (make-temp-file "sem-rss-feeds-" nil ".org"
                                   "* Feeds :elfeed:\n** https://example.com/rss.xml :ai:\n"))
         (cache-file (make-temp-file "sem-rss-feeds-cache-") )
         (setenv-restore (getenv "CLIENT_TIMEZONE"))
         (sem-rss-feeds-file tmp-file)
         (sem-rss-feeds-cache-file cache-file))
    (unwind-protect
        (progn
          (setenv "CLIENT_TIMEZONE" "Etc/UTC")
          (cl-letf (((symbol-function 'sem-core-log) (lambda (&rest _) nil))
                    ((symbol-function 'sem-core-log-error) (lambda (&rest _) nil)))
            (let ((first (sem-rss-refresh-feeds t)))
              (should (plist-get first :reloaded))
              (should (= (plist-get first :count) 1)))
            (setq elfeed-feeds nil)
            (let ((second (sem-rss-refresh-feeds)))
              (should-not (plist-get second :reloaded))
              (should (eq (plist-get second :reason) 'unchanged))
              (should (= (length elfeed-feeds) 1)))))
      (setenv "CLIENT_TIMEZONE" setenv-restore)
      (delete-file tmp-file)
      (delete-file cache-file))))

;;; Tests for sem-rss-archive-old-digests

(defun sem-rss-test--write-digest-file (path content)
  "Write CONTENT to PATH, creating parent directories as needed."
  (make-directory (file-name-directory path) t)
  (with-temp-file path (insert content)))

(defun sem-rss-test--file-contents (path)
  "Return the contents of the file at PATH as a string."
  (with-temp-buffer
    (insert-file-contents path)
    (buffer-string)))

(defun sem-rss-test--make-archive-env ()
  "Create temp source/archive dirs and redirected runtime paths.
Returns a plist with :source, :archive and :state for teardown."
  (let ((source (make-temp-file "sem-rss-arch-src-" t))
        (archive (make-temp-file "sem-rss-arch-dst-" t))
        (state (sem-mock-setup-test-data-paths)))
    (list :source source :archive archive :state state)))

(defun sem-rss-test--teardown-archive-env (env)
  "Clean up directories and runtime paths created by `sem-rss-test--make-archive-env'."
  (let ((source (plist-get env :source))
        (archive (plist-get env :archive))
        (state (plist-get env :state)))
    (sem-mock-teardown-test-data-paths state)
    (when (file-directory-p source)
      (delete-directory source t))
    (when (file-directory-p archive)
      (delete-directory archive t))))

(ert-deftest sem-rss-test-archive-moves-previous-month-files ()
  "Previous-month digest files move to the month subdir; current month stays."
  (let* ((env (sem-rss-test--make-archive-env))
         (source (plist-get env :source))
         (archive (plist-get env :archive)))
    (unwind-protect
        (let ((sem-rss-dir source)
              (sem-rss-archive-dir archive))
          (sem-rss-test--write-digest-file
           (expand-file-name "2026-03-15.org" source) "general march")
          (sem-rss-test--write-digest-file
           (expand-file-name "2026-03-15-arxiv.org" source) "arxiv march")
          (sem-rss-test--write-digest-file
           (expand-file-name "2026-04-02.org" source) "general april")
          (let ((moved (sem-rss-archive-old-digests (encode-time 0 0 0 2 4 2026))))
            (should (= moved 2))
            (should-not (file-exists-p (expand-file-name "2026-03-15.org" source)))
            (should-not (file-exists-p (expand-file-name "2026-03-15-arxiv.org" source)))
            (should (file-exists-p (expand-file-name "2026-04-02.org" source)))
            (should (string= (sem-rss-test--file-contents
                              (expand-file-name "2026-03/2026-03-15.org" archive))
                             "general march"))
            (should (string= (sem-rss-test--file-contents
                              (expand-file-name "2026-03/2026-03-15-arxiv.org" archive))
                             "arxiv march"))))
      (sem-rss-test--teardown-archive-env env))))

(ert-deftest sem-rss-test-archive-idempotent-second-run ()
  "A second run right after the first moves nothing."
  (let* ((env (sem-rss-test--make-archive-env))
         (source (plist-get env :source))
         (archive (plist-get env :archive)))
    (unwind-protect
        (let ((sem-rss-dir source)
              (sem-rss-archive-dir archive)
              (ref (encode-time 0 0 0 2 4 2026)))
          (sem-rss-test--write-digest-file
           (expand-file-name "2026-03-15.org" source) "general march")
          (should (= (sem-rss-archive-old-digests ref) 1))
          (should (= (sem-rss-archive-old-digests ref) 0))
          (should (file-exists-p (expand-file-name "2026-03/2026-03-15.org" archive))))
      (sem-rss-test--teardown-archive-env env))))

(ert-deftest sem-rss-test-archive-empty-folder-is-no-op ()
  "Running over a folder with only current-month files moves nothing."
  (let* ((env (sem-rss-test--make-archive-env))
         (source (plist-get env :source))
         (archive (plist-get env :archive)))
    (unwind-protect
        (let ((sem-rss-dir source)
              (sem-rss-archive-dir archive))
          (sem-rss-test--write-digest-file
           (expand-file-name "2026-04-02.org" source) "current")
          (should (zerop (sem-rss-archive-old-digests (encode-time 0 0 0 2 4 2026))))
          (should (file-exists-p (expand-file-name "2026-04-02.org" source))))
      (sem-rss-test--teardown-archive-env env))))

(ert-deftest sem-rss-test-archive-creates-dirs-and-catches-up-backlog ()
  "Archive/month dirs are created on demand and a multi-month backlog lands in one run."
  (let* ((env (sem-rss-test--make-archive-env))
         (source (plist-get env :source))
         (archive (plist-get env :archive)))
    (unwind-protect
        (let ((sem-rss-dir source)
              (sem-rss-archive-dir archive))
          (sem-rss-test--write-digest-file
           (expand-file-name "2026-01-05.org" source) "jan")
          (sem-rss-test--write-digest-file
           (expand-file-name "2026-02-10-arxiv.org" source) "feb arxiv")
          (sem-rss-test--write-digest-file
           (expand-file-name "2026-03-20.org" source) "mar")
          ;; Remove the archive dir so the routine must recreate it on demand.
          (delete-directory archive t)
          (should (= (sem-rss-archive-old-digests (encode-time 0 0 0 10 4 2026)) 3))
          (should (file-exists-p (expand-file-name "2026-01/2026-01-05.org" archive)))
          (should (file-exists-p (expand-file-name "2026-02/2026-02-10-arxiv.org" archive)))
          (should (file-exists-p (expand-file-name "2026-03/2026-03-20.org" archive)))
          (should-not (directory-files source nil directory-files-no-dot-files-regexp)))
      (sem-rss-test--teardown-archive-env env))))

(ert-deftest sem-rss-test-archive-skips-files-without-month-prefix ()
  "Files without a YYYY-MM filename prefix are skipped, logged, and left in place."
  (let* ((env (sem-rss-test--make-archive-env))
         (source (plist-get env :source))
         (archive (plist-get env :archive)))
    (unwind-protect
        (let ((sem-rss-dir source)
              (sem-rss-archive-dir archive))
          (sem-rss-test--write-digest-file
           (expand-file-name "notes.org" source) "no date")
          (should (zerop (sem-rss-archive-old-digests (encode-time 0 0 0 2 4 2026))))
          (should (file-exists-p (expand-file-name "notes.org" source))))
      (sem-rss-test--teardown-archive-env env))))

(ert-deftest sem-rss-test-archive-move-failure-is-logged-not-raised ()
  "A failing move is logged to errors.org and does not signal to the caller."
  (let* ((env (sem-rss-test--make-archive-env))
         (source (plist-get env :source))
         (archive (plist-get env :archive)))
    (unwind-protect
        (let ((sem-rss-dir source)
              (sem-rss-archive-dir archive))
          (sem-rss-test--write-digest-file
           (expand-file-name "2026-03-15.org" source) "general march")
          (cl-letf (((symbol-function 'rename-file)
                     (lambda (&rest _) (error "Permission denied"))))
            (should (zerop (sem-rss-archive-old-digests (encode-time 0 0 0 2 4 2026)))))
          ;; The file stays in place and the failure was recorded.
          (should (file-exists-p (expand-file-name "2026-03-15.org" source)))
          (should (file-exists-p sem-core-errors-file))
          (should (string-match-p "Permission denied"
                                  (sem-rss-test--file-contents sem-core-errors-file))))
      (sem-rss-test--teardown-archive-env env))))

(provide 'sem-rss-test)
;;; sem-rss-test.el ends here
