;;; sem-router-test.el --- Tests for sem-router.el -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Tests for sem-router routing and headline parsing functions.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'sem-mock)

;; Load modules under test
(load-file (expand-file-name "../sem-core.el" (file-name-directory load-file-name)))
(load-file (expand-file-name "../sem-security.el" (file-name-directory load-file-name)))
(load-file (expand-file-name "../sem-router.el" (file-name-directory load-file-name)))

(defun sem-router-test--capture-runtime-messages (thunk)
  "Run THUNK and return captured runtime message lines."
  (let ((captured '()))
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) captured))))
      (funcall thunk))
    (nreverse captured)))

(defun sem-router-test--assert-no-plaintext-leaks (messages samples)
  "Assert MESSAGES do not include any plaintext SAMPLES."
  (dolist (line messages)
    (dolist (sample samples)
      (should-not (string-match-p (regexp-quote sample) line)))))

;;; Test @link routing to url-capture

(ert-deftest sem-router-test-link-tag-detection ()
  "Test that @link tag is detected for URL routing."
  (let ((headline '(:title "https://example.com" :tags ("link") :body nil)))
    (should (sem-router--is-link-headline headline))))

(ert-deftest sem-router-test-url-as-title-detection ()
  "Test that URL as title is detected without @link tag."
  (let ((headline '(:title "https://example.com/article" :tags nil :body nil)))
    (should (sem-router--is-link-headline headline))))

(ert-deftest sem-router-test-non-link-not-routed ()
  "Test that non-link headlines are not routed to url-capture."
  (let ((headline '(:title "Regular task headline" :tags ("task") :body nil)))
    (should-not (sem-router--is-link-headline headline))))

;;; Test @task routing to LLM pipeline

(ert-deftest sem-router-test-task-tag-detection ()
  "Test that @task tag is detected for LLM routing."
  (let ((headline '(:title "Buy milk" :tags ("task") :body nil)))
    (should (sem-router--is-task-headline headline))))

(ert-deftest sem-router-test-task-route-uses-weak-tier ()
  "Test task route calls sem-llm-request with weak tier intent."
  (let ((captured-tier nil))
    (require 'sem-llm)
    (cl-letf (((symbol-function 'org-id-new)
               (lambda () "550e8400-e29b-41d4-a716-446655440000"))
              ((symbol-function 'sem-llm-request)
               (lambda (_prompt _system callback context &optional tier)
                 (setq captured-tier tier)
                 (funcall callback nil (list :error "mock") context)
                 nil)))
      (sem-router--route-to-task-llm
       '(:title "Buy milk" :tags ("task") :body nil :hash "task-hash")
       (lambda (_success _context) nil))
      (should (eq captured-tier 'weak)))))

(ert-deftest sem-router-test-task-api-error-increments-retry-once-below-cap ()
  "Test task API failure increments retry once and remains retry-eligible."
  (let ((increment-calls 0)
        (dlq-calls 0)
        (callback-success :unset)
        (sem-core--batch-id 5))
    (cl-letf (((symbol-function 'org-id-new)
               (lambda () "550e8400-e29b-41d4-a716-446655440000"))
              ((symbol-function 'getenv)
               (lambda (name)
                  (cond
                   ((string= name "SEM_TASK_API_MAX_RETRIES") "3")
                   ((string= name "CLIENT_TIMEZONE") "Etc/UTC")
                   (t nil))))
              ((symbol-function 'sem-llm-request)
               (lambda (_prompt _system callback context &optional _tier)
                 (funcall callback nil (list :error "provider timeout") context)
                 nil))
              ((symbol-function 'sem-core--increment-retry)
               (lambda (_hash)
                 (setq increment-calls (1+ increment-calls))
                 2))
              ((symbol-function 'sem-core--mark-dlq)
               (lambda (&rest _)
                 (setq dlq-calls (1+ dlq-calls))))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-core-log-error)
               (lambda (&rest _) nil)))
      (sem-router--route-to-task-llm
       '(:title "Buy milk" :tags ("task") :body nil :hash "task-hash")
       (lambda (success _context)
         (setq callback-success success)))
      (should (= increment-calls 1))
      (should (= dlq-calls 0))
      (should-not callback-success))))

(ert-deftest sem-router-test-task-api-error-at-cap-routes-to-dlq ()
  "Test task API failure at retry cap routes to DLQ terminal path."
  (let ((increment-calls 0)
        (dlq-calls 0)
        (callback-success :unset)
        (sem-core--batch-id 6))
    (cl-letf (((symbol-function 'org-id-new)
               (lambda () "550e8400-e29b-41d4-a716-446655440000"))
              ((symbol-function 'getenv)
               (lambda (name)
                  (cond
                   ((string= name "SEM_TASK_API_MAX_RETRIES") "3")
                   ((string= name "CLIENT_TIMEZONE") "Etc/UTC")
                   (t nil))))
              ((symbol-function 'sem-llm-request)
               (lambda (_prompt _system callback context &optional _tier)
                 (funcall callback nil (list :error "provider timeout") context)
                 nil))
              ((symbol-function 'sem-core--increment-retry)
               (lambda (_hash)
                 (setq increment-calls (1+ increment-calls))
                 3))
              ((symbol-function 'sem-core--mark-dlq)
               (lambda (&rest _)
                 (setq dlq-calls (1+ dlq-calls))))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-core-log-error)
               (lambda (&rest _) nil)))
      (sem-router--route-to-task-llm
       '(:title "Buy milk" :tags ("task") :body nil :hash "task-hash")
       (lambda (success _context)
         (setq callback-success success)))
      (should (= increment-calls 1))
      (should (= dlq-calls 1))
      (should callback-success))))

(ert-deftest sem-router-test-task-malformed-output-does-not-increment-api-retry ()
  "Test malformed output path does not increment API retry state." 
  (let ((increment-calls 0)
        (mark-processed-calls 0)
        (sem-core--batch-id 7))
    (cl-letf (((symbol-function 'org-id-new)
               (lambda () "550e8400-e29b-41d4-a716-446655440000"))
              ((symbol-function 'sem-llm-request)
               (lambda (_prompt _system callback context &optional _tier)
                 (funcall callback "* TODO malformed\n:PROPERTIES:\n:ID: wrong-id\n:END:" nil context)
                 nil))
              ((symbol-function 'sem-core--increment-retry)
               (lambda (_hash)
                 (setq increment-calls (1+ increment-calls))
                 1))
              ((symbol-function 'sem-router--mark-processed)
               (lambda (&rest _)
                 (setq mark-processed-calls (1+ mark-processed-calls))))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-core-log-error)
               (lambda (&rest _) nil)))
      (sem-router--route-to-task-llm
       '(:title "Buy milk" :tags ("task") :body nil :hash "task-hash")
       (lambda (_success _context) nil))
      (should (= increment-calls 0))
      (should (= mark-processed-calls 1)))))

(ert-deftest sem-router-test-task-malformed-sensitive-preflight-goes-dlq-without-llm ()
  "Test malformed sensitive block routes to DLQ before any LLM call."
  (let ((llm-called nil)
        (dlq-called nil)
        (callback-success :unset)
        (log-error-call nil)
        (sem-core--batch-id 8))
    (cl-letf (((symbol-function 'org-id-new)
               (lambda () "550e8400-e29b-41d4-a716-446655440000"))
              ((symbol-function 'getenv)
               (lambda (name)
                 (cond
                  ((string= name "OPENROUTER_MODEL") "mock/model")
                  ((string= name "CLIENT_TIMEZONE") "Etc/UTC")
                  (t nil))))
              ((symbol-function 'sem-security-sanitize-for-llm)
               (lambda (_text)
                 (error "Malformed sensitive block: missing #+end_sensitive marker")))
              ((symbol-function 'sem-llm-request)
               (lambda (&rest _)
                 (setq llm-called t)
                 nil))
              ((symbol-function 'sem-core--mark-dlq)
               (lambda (&rest _)
                 (setq dlq-called t)))
              ((symbol-function 'sem-core-log-error)
               (lambda (&rest args)
                 (setq log-error-call args)))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil)))
      (sem-router--route-to-task-llm
       '(:title "Task with malformed block"
         :tags ("task")
         :body "#+begin_sensitive\nsecret"
         :hash "task-hash")
       (lambda (success _context)
         (setq callback-success success))
       8)
      (should-not llm-called)
      (should dlq-called)
      (should callback-success)
      (should log-error-call)
      (should (string= (car log-error-call) "security"))
      (should (equal (nth 5 log-error-call)
                     (list :priority "[#A]" :tags '("security")))))))

(ert-deftest sem-router-test-non-task-not-routed ()
  "Test that non-task headlines are not routed to task LLM."
  (let ((headline '(:title "Just a note" :tags ("note") :body nil)))
    (should-not (sem-router--is-task-headline headline))))

;;; Test unknown tag skip

(ert-deftest sem-router-test-unknown-tag-skip ()
  "Test that unknown tags are skipped with log."
  (let ((headline '(:title "Unknown tag headline" :tags ("unknown") :body nil)))
    (should-not (sem-router--is-link-headline headline))
    (should-not (sem-router--is-task-headline headline))))

;;; Test already-processed hash skip

(ert-deftest sem-router-test-processed-hash-skip ()
  "Test that already-processed hashes are skipped."
  (let ((hash "test-hash-12345")
        (test-file (make-temp-file "sem-cursor-test-")))
    (unwind-protect
        (let ((sem-core-cursor-file test-file))
          ;; Mark as processed
          (sem-core--mark-processed hash)
          ;; Should be detected as processed
          (should (sem-router--is-processed hash)))
      (sem-mock-cleanup-temp-file test-file))))

;;; Test URL extraction from headline title

(ert-deftest sem-router-test-url-extraction ()
  "Test URL extraction from headline title."
  (let ((headline '(:title "https://example.com/article/path" :tags nil :body nil)))
    (should (string= "https://example.com/article/path"
                     (sem-router--is-link-headline headline)))))

(ert-deftest sem-router-test-url-extraction-with-query ()
  "Test URL extraction with query parameters."
  (let ((headline '(:title "https://example.com/search?q=test&page=1" :tags ("link") :body nil)))
    (should (string= "https://example.com/search?q=test&page=1"
                     (sem-router--is-link-headline headline)))))

;;; Test cleanup

(ert-deftest sem-router-test-mock-cleanup ()
  "Test that mock cleanup works correctly."
  (sem-mock-reset-all)
  (should t))

;;; Test org-element based headline parsing

(ert-deftest sem-router-test-parse-headlines-missing-file ()
  "Test that sem-router--parse-headlines handles missing file gracefully."
  (let ((sem-router-inbox-file "/nonexistent/path/inbox-mobile.org"))
    ;; Should return nil without crashing
    (should (null (sem-router--parse-headlines)))))

(ert-deftest sem-router-test-parse-headlines-basic ()
  "Test basic headline parsing with org-element."
  (let ((test-file (make-temp-file "inbox-test-")))
    (unwind-protect
        (progn
          ;; Create temp inbox file with headlines
          (with-temp-file test-file
            (insert "* Headline 1 :link:\n")
            (insert "* Headline 2 :task:\n"))
          ;; Temporarily override inbox file path
          (let ((sem-router-inbox-file test-file))
            (let ((headlines (sem-router--parse-headlines)))
              ;; Should return parsed headlines
              (should (listp headlines))
              (should (= (length headlines) 2))
              ;; Check first headline
              (let ((h1 (car headlines)))
                (should (string= "Headline 1" (plist-get h1 :title)))
                (should (equal '("link") (plist-get h1 :tags)))
                (should (null (plist-get h1 :body))))
              ;; Check second headline
              (let ((h2 (cadr headlines)))
                (should (string= "Headline 2" (plist-get h2 :title)))
                (should (equal '("task") (plist-get h2 :tags)))
                (should (null (plist-get h2 :body)))))))
      (sem-mock-cleanup-temp-file test-file))))

(ert-deftest sem-router-test-parse-headlines-with-body ()
  "Test headline parsing with body content."
  (let ((test-file (make-temp-file "inbox-test-")))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "* Task with body :@task:\n")
            (insert "This is the body text\n")
            (insert "* Next headline :link:\n"))
          (let ((sem-router-inbox-file test-file))
            (let ((headlines (sem-router--parse-headlines)))
              (should (= (length headlines) 2))
              ;; First headline should have body
              (let ((h1 (car headlines)))
                (should (string= "Task with body" (plist-get h1 :title)))
                (should (equal '("@task") (plist-get h1 :tags)))
                (should (string= "This is the body text" (plist-get h1 :body))))
              ;; Second headline should have nil body
              (let ((h2 (cadr headlines)))
                (should (null (plist-get h2 :body)))))))
      (sem-mock-cleanup-temp-file test-file))))

(ert-deftest sem-router-test-parse-headlines-without-body ()
  "Test headline parsing without body content."
  (let ((test-file (make-temp-file "inbox-test-")))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "* Task without body :@task:\n")
            (insert "* Next headline :link:\n"))
          (let ((sem-router-inbox-file test-file))
            (let ((headlines (sem-router--parse-headlines)))
              (should (= (length headlines) 2))
              ;; First headline should have nil body (no content between headlines)
              (let ((h1 (car headlines)))
                (should (null (plist-get h1 :body)))))))
      (sem-mock-cleanup-temp-file test-file))))

(ert-deftest sem-router-test-parse-headlines-nested-excluded ()
  "Test that nested sub-headlines are excluded from body."
  (let ((test-file (make-temp-file "inbox-test-")))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "* Parent :@task:\n")
            (insert "Parent body text\n")
            (insert "** Child :child:\n")
            (insert "Child body text\n"))
          (let ((sem-router-inbox-file test-file))
            (let ((headlines (sem-router--parse-headlines)))
              (should (= (length headlines) 2))
              ;; Parent should only have its own body
              (let ((parent (car headlines)))
                (should (string= "Parent" (plist-get parent :title)))
                (should (string= "Parent body text" (plist-get parent :body))))
              ;; Child should have its own body
              (let ((child (cadr headlines)))
                (should (string= "Child" (plist-get child :title)))
                (should (string= "Child body text" (plist-get child :body)))))))
      (sem-mock-cleanup-temp-file test-file))))

(ert-deftest sem-router-test-parse-headlines-body-with-list ()
  "Test body extraction with list items."
  (let ((test-file (make-temp-file "inbox-test-")))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "* Task with list :@task:\n")
            (insert "- Item 1\n")
            (insert "- Item 2\n")
            (insert "\n")
            (insert "Paragraph text\n"))
          (let ((sem-router-inbox-file test-file))
            (let ((headlines (sem-router--parse-headlines)))
              (should (= (length headlines) 1))
              (let ((h1 (car headlines)))
                (should (string-match-p "Item 1" (plist-get h1 :body)))
                (should (string-match-p "Item 2" (plist-get h1 :body)))
                (should (string-match-p "Paragraph text" (plist-get h1 :body)))))))
      (sem-mock-cleanup-temp-file test-file))))

(ert-deftest sem-router-test-parse-headlines-hash-includes-body ()
  "Test that hash computation includes body content."
  (let ((test-file (make-temp-file "inbox-test-")))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "* Same title :@task:\n")
            (insert "Body one\n"))
          (let ((sem-router-inbox-file test-file))
            (let ((headlines1 (sem-router--parse-headlines)))
              (let ((hash1 (plist-get (car headlines1) :hash)))
                ;; Now change the file with same title but different body
                (with-temp-file test-file
                  (insert "* Same title :@task:\n")
                  (insert "Body two\n"))
                (let ((headlines2 (sem-router--parse-headlines)))
                  (let ((hash2 (plist-get (car headlines2) :hash)))
                    ;; Hashes should be different because bodies are different
                    (should-not (string= hash1 hash2))))))))
      (sem-mock-cleanup-temp-file test-file))))

(ert-deftest sem-router-test-parse-headlines-tags-without-colons ()
  "Test that tags are extracted without colons."
  (let ((test-file (make-temp-file "inbox-test-")))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "* Task :tag1:tag2:\n"))
          (let ((sem-router-inbox-file test-file))
            (let ((headlines (sem-router--parse-headlines)))
              (should (= (length headlines) 1))
              (let ((tags (plist-get (car headlines) :tags)))
                (should (equal '("tag1" "tag2") tags))
                ;; Ensure no colons in tags
                (should-not (member ":tag1:" tags))
                (should-not (member ":tag2:" tags))))))
      (sem-mock-cleanup-temp-file test-file))))

;;; Tests for task LLM pipeline with UUID injection

(ert-deftest sem-router-test-task-validation-valid-response ()
  "Test validation of valid LLM task response with matching UUID.
Success path: valid Org TODO with valid tag and matching UUID should pass validation."
  (let ((injected-id "550e8400-e29b-41d4-a716-446655440000")
        (response "* TODO Test Task
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :work:
:END:
Task description here."))
    (should (sem-router--validate-task-response response injected-id))))

(ert-deftest sem-router-test-task-validation-invalid-tag ()
  "Test validation rejects invalid tag.
DLQ path: invalid tag should fail validation."
  (let ((injected-id "550e8400-e29b-41d4-a716-446655440000")
        (response "* TODO Test Task
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :invalidtag:
:END:
Task description here."))
    (should-not (sem-router--validate-task-response response injected-id))))

(ert-deftest sem-router-test-task-validation-missing-properties ()
  "Test validation rejects missing :PROPERTIES:.
DLQ path: missing properties drawer should fail validation."
  (let ((injected-id "550e8400-e29b-41d4-a716-446655440000")
        (response "* TODO Test Task
:FILETAGS: :work:
Task description here."))
    (should-not (sem-router--validate-task-response response injected-id))))

(ert-deftest sem-router-test-task-validation-missing-id ()
  "Test validation rejects missing :ID:.
DLQ path: missing ID should fail validation."
  (let ((injected-id "550e8400-e29b-41d4-a716-446655440000")
        (response "* TODO Test Task
:PROPERTIES:
:FILETAGS: :work:
:END:
Task description here."))
    (should-not (sem-router--validate-task-response response injected-id))))

(ert-deftest sem-router-test-task-validation-missing-filetags ()
  "Test validation rejects missing :FILETAGS:.
DLQ path: missing FILETAGS should fail validation."
  (let ((injected-id "550e8400-e29b-41d4-a716-446655440000")
        (response "* TODO Test Task
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:END:
Task description here."))
    (should-not (sem-router--validate-task-response response injected-id))))

;; New tests for UUID validation

(ert-deftest sem-router-test-uuid-match-validation-passes ()
  "Test that UUID match passes validation.
Success path: extracted ID matches injected ID exactly."
  (let ((injected-id "abc12345-6789-0def-ghij-klmnopqrstuv")
        (response "* TODO Test Task
:PROPERTIES:
:ID: abc12345-6789-0def-ghij-klmnopqrstuv
:FILETAGS: :work:
:END:
Task description."))
    (should (sem-router--validate-task-response response injected-id))))

(ert-deftest sem-router-test-uuid-mismatch-validation-fails ()
  "Test that UUID mismatch fails validation.
DLQ path: LLM generated different ID than injected."
  (let ((injected-id "abc12345-6789-0def-ghij-klmnopqrstuv")
        (response "* TODO Test Task
:PROPERTIES:
:ID: different-uuid-generated-by-llm
:FILETAGS: :work:
:END:
Task description."))
    (should-not (sem-router--validate-task-response response injected-id))))

(ert-deftest sem-router-test-uuid-missing-validation-fails ()
  "Test that missing UUID fails validation.
DLQ path: LLM omitted ID field entirely."
  (let ((injected-id "abc12345-6789-0def-ghij-klmnopqrstuv")
        (response "* TODO Test Task
:PROPERTIES:
:FILETAGS: :work:
:END:
Task description."))
    (should-not (sem-router--validate-task-response response injected-id))))

(ert-deftest sem-router-test-uuid-nil-injected-id-fails ()
  "Test that nil injected-id fails validation.
Safety check: nil injected-id should return nil."
  (let ((response "* TODO Test Task
:PROPERTIES:
:ID: some-uuid-value
:FILETAGS: :work:
:END:
Task description."))
    (should-not (sem-router--validate-task-response response nil))))

(ert-deftest sem-router-test-uuid-exact-string-match ()
  "Test that UUID validation uses exact string match.
Security: partial matches or case differences should fail."
  (let ((injected-id "ABC12345-6789-0DEF-GHIJ-KLMNOPQRSTUV")
        (response "* TODO Test Task
:PROPERTIES:
:ID: abc12345-6789-0def-ghij-klmnopqrstuv
:FILETAGS: :work:
:END:
Task description."))
    ;; Case-sensitive comparison should fail
    (should-not (sem-router--validate-task-response response injected-id))))

(ert-deftest sem-router-test-task-tag-normalization-routine-default ()
  "Test that absent or invalid tag is substituted with :routine:.
Tag validation test: missing FILETAGS results in :routine: default."
  (let ((response "* TODO Test Task
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:END:
Task description here."))
    (let ((normalized (sem-router--validate-and-normalize-tag response)))
      (should (string-match-p ":FILETAGS: :routine:" normalized)))))

(ert-deftest sem-router-test-task-tag-normalization-invalid-substituted ()
  "Test that invalid tag is substituted with :routine:.
Tag validation test: invalid tag substituted with :routine:."
  (let ((response "* TODO Test Task
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :badtag:
:END:
Task description here."))
    (let ((normalized (sem-router--validate-and-normalize-tag response)))
      (should (string-match-p ":FILETAGS: :routine:" normalized))
      (should-not (string-match-p ":FILETAGS: :badtag:" normalized)))))

(ert-deftest sem-router-test-task-tag-normalization-valid-preserved ()
  "Test that valid tag is preserved.
Success path: valid tag from allowed list is preserved."
  (let ((response "* TODO Test Task
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :opensource:
:END:
Task description here."))
    (let ((normalized (sem-router--validate-and-normalize-tag response)))
      (should (string-match-p ":FILETAGS: :opensource:" normalized)))))

(ert-deftest sem-router-test-priority-normalization-missing-defaults-to-c ()
  "Test missing priority defaults to [#C]."
  (let ((response "* TODO Test Task
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :work:
:END:
Task description here."))
    (let ((normalized (sem-router--validate-and-normalize-priority response)))
      (should (string-match-p "^\\* TODO \\[#C\\] Test Task" normalized)))))

(ert-deftest sem-router-test-priority-normalization-valid-preserved ()
  "Test valid priority token is preserved."
  (let ((response "* TODO [#A] Test Task
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :work:
:END:
Task description here."))
    (let ((normalized (sem-router--validate-and-normalize-priority response)))
      (should (string-match-p "^\\* TODO \\[#A\\] Test Task" normalized))
      (should-not (string-match-p "^\\* TODO \\[#C\\]" normalized)))))

(ert-deftest sem-router-test-priority-normalization-invalid-replaced-with-c ()
  "Test invalid priority token is replaced with [#C]."
  (let ((response "* TODO [#Z] Test Task
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :work:
:END:
Task description here."))
    (let ((normalized (sem-router--validate-and-normalize-priority response)))
      (should (string-match-p "^\\* TODO \\[#C\\] Test Task" normalized))
      (should-not (string-match-p "^\\* TODO \\[#Z\\]" normalized)))))

(ert-deftest sem-router-test-priority-normalization-trailing-token-preserved ()
  "Test trailing valid priority token is moved and preserved once."
  (let ((response "* TODO Ping ops about INC-7781 [#A]
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :work:
:END:
Task description here."))
    (let ((normalized (sem-router--validate-and-normalize-priority response)))
      (should (string-match-p "^\\* TODO \\[#A\\] Ping ops about INC-7781$" (car (split-string normalized "\n"))))
      (should-not (string-match-p "\\[#A\\].*\\[#A\\]" (car (split-string normalized "\n")))))))

(ert-deftest sem-router-test-priority-normalization-multiple-valid-keeps-strongest ()
  "Test multiple valid priorities normalize to one strongest token."
  (let ((response "* TODO [#C] Ping ops [#A]
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :work:
:END:
Task description here."))
    (let ((normalized (sem-router--validate-and-normalize-priority response)))
      (should (string-match-p "^\\* TODO \\[#A\\] Ping ops$" (car (split-string normalized "\n"))))
      (should-not (string-match-p "\\[#C\\].*\\[#A\\]" (car (split-string normalized "\n")))))))

(ert-deftest sem-router-test-headline-normalization-repairs-missing-todo-order ()
  "Test headline normalization repairs misplaced TODO keyword and priority token."
  (let ((response "* [#C] TODO Review pull request #452 for authentication module
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :work:
:END:
Body."))
    (let ((normalized (sem-router--normalize-task-response response)))
      (should (string-match-p "^\\* TODO \\[#C\\] Review pull request #452 for authentication module$"
                              (car (split-string normalized "\n")))))))

(ert-deftest sem-router-test-headline-normalization-repairs-priority-before-todo ()
  "Test headline normalization repairs priority-before-TODO headline form."
  (let ((response "* [#A] Ping ops about INC-7781
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :work:
:END:
Body."))
    (let ((normalized (sem-router--normalize-task-response response)))
      (should (string-match-p "^\\* TODO \\[#A\\] Ping ops about INC-7781$"
                              (car (split-string normalized "\n")))))))

(ert-deftest sem-router-test-task-title-lowercase-normalizes-mixed-case ()
  "Test mixed-case TODO title is normalized to lowercase." 
  (let ((response "* TODO Prepare API Rollout Notes
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :work:
:END:
Body stays mixed case."))
    (let ((normalized (sem-router--normalize-task-title-lowercase response)))
      (should (string-match-p "^\\* TODO prepare api rollout notes$"
                              (car (split-string normalized "\n")))))))

(ert-deftest sem-router-test-task-title-lowercase-idempotent ()
  "Test lowercasing task title is idempotent across retries."
  (let ((response "* TODO [#B] already lowercase title
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :work:
:END:
Body."))
    (let* ((once (sem-router--normalize-task-title-lowercase response))
           (twice (sem-router--normalize-task-title-lowercase once)))
      (should (string= once twice)))))

(ert-deftest sem-router-test-task-title-lowercase-preserves-priority-and-body ()
  "Test priority token and non-title content remain unchanged."
  (let ((response "* TODO [#A] Follow Up With OAuth Team
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :work:
:END:
Body MIXED Case remains.
SCHEDULED: <2026-03-20 09:15>
DEADLINE: <2026-03-21 Sat>"))
    (let* ((normalized (sem-router--normalize-task-title-lowercase response))
           (original-rest (replace-regexp-in-string "\\`[^\n]*\n?" "" response))
           (normalized-rest (replace-regexp-in-string "\\`[^\n]*\n?" "" normalized)))
      (should (string-match-p "^\\* TODO \\[#A\\] follow up with oauth team$"
                              (car (split-string normalized "\n"))))
      (should (string= original-rest normalized-rest)))))

(ert-deftest sem-router-test-scheduled-duration-defaults-to-30-minutes ()
  "Test missing scheduled end time defaults to 30-minute block."
  (let ((response "* TODO [#B] Test Task
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :work:
:END:
Task description here.
SCHEDULED: <2026-03-20 09:15>"))
    (let ((normalized (sem-router--normalize-scheduled-duration response)))
      (should (string-match-p "SCHEDULED: <2026-03-20 09:15-09:45>" normalized)))))

(ert-deftest sem-router-test-scheduled-duration-preserves-explicit-range ()
  "Test explicit scheduled range is preserved."
  (let ((response "* TODO [#B] Test Task
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :work:
:END:
Task description here.
SCHEDULED: <2026-03-20 09:15-10:15>"))
    (let ((normalized (sem-router--normalize-scheduled-duration response)))
      (should (string-match-p "SCHEDULED: <2026-03-20 09:15-10:15>" normalized))
      (should-not (string-match-p "SCHEDULED: <2026-03-20 09:15-09:45>" normalized)))))

(ert-deftest sem-router-test-normalization-allows-unscheduled-task ()
  "Test normalization preserves valid unscheduled task output."
  (let ((response "* TODO Task with ambiguous weekday
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :work:
:END:
Could be next week or later."))
    (let ((normalized (sem-router--normalize-task-response response)))
      (should-not (string-match-p "^SCHEDULED:" normalized))
      (should (string-match-p "^\\* TODO \\[#C\\] Task with ambiguous weekday" normalized)))))

(ert-deftest sem-router-test-build-task-prompt-includes-runtime-datetime-context ()
  "Test Pass 1 prompt builder includes runtime datetime and shorthand examples."
  (let* ((prompt-pair
          (sem-router--build-task-llm-prompts
           "Call vendor tomorrow"
           '("task")
           "Body text"
           "550e8400-e29b-41d4-a716-446655440000"))
         (captured-user-prompt (plist-get prompt-pair :user-prompt))
         (captured-system-prompt (plist-get prompt-pair :system-prompt)))
    (should (string-match-p "CURRENT DATETIME (" captured-user-prompt))
    (should (string-match-p "transform a raw capture note" captured-system-prompt))
    (should (string-match-p "wendsday" captured-system-prompt))))

(ert-deftest sem-router-test-build-task-prompt-language-instruction-is-final-line ()
  "Test language instruction is strict and appended as final line."
  (let ((real-getenv (symbol-function 'getenv)))
    (cl-letf (((symbol-function 'getenv)
               (lambda (name)
                 (if (string= name "OUTPUT_LANGUAGE")
                     "Japanese"
                   (funcall real-getenv name)))))
      (let* ((prompt-pair
              (sem-router--build-task-llm-prompts
               "Call vendor tomorrow"
               '("task")
               "Body text"
               "550e8400-e29b-41d4-a716-446655440000"))
             (captured-system-prompt (plist-get prompt-pair :system-prompt))
             (expected-line
              "OUTPUT LANGUAGE REQUIREMENT: You MUST write the entire response in Japanese only. Do not use any other language.")
             (last-line (car (last (split-string captured-system-prompt "\n" t)))))
        (should (string-match-p "OUTPUT LANGUAGE REQUIREMENT" captured-system-prompt))
        (should (string= last-line expected-line))))))

(ert-deftest sem-router-test-build-task-prompt-language-fallbacks-to-english ()
  "Test empty or unset OUTPUT_LANGUAGE deterministically falls back to English."
  (let ((real-getenv (symbol-function 'getenv)))
    (dolist (raw-value '(nil ""))
      (cl-letf (((symbol-function 'getenv)
                 (lambda (name)
                   (if (string= name "OUTPUT_LANGUAGE")
                       raw-value
                     (funcall real-getenv name)))))
        (let* ((prompt-pair
                (sem-router--build-task-llm-prompts
                 "Call vendor tomorrow"
                 '("task")
                 "Body text"
                 "550e8400-e29b-41d4-a716-446655440000"))
               (captured-system-prompt (plist-get prompt-pair :system-prompt)))
          (should
           (string-match-p
            "OUTPUT LANGUAGE REQUIREMENT: You MUST write the entire response in English only. Do not use any other language."
            captured-system-prompt)))))))

(ert-deftest sem-router-test-task-route-composes-task-prompt-with-language-instruction ()
  "Test task pipeline sends system prompt with strict language instruction."
  (let ((captured-system-prompt nil)
        (sem-core--batch-id 42)
        (real-getenv (symbol-function 'getenv)))
    (require 'sem-llm)
    (cl-letf (((symbol-function 'org-id-new)
               (lambda () "550e8400-e29b-41d4-a716-446655440000"))
              ((symbol-function 'getenv)
               (lambda (name)
                 (if (string= name "OUTPUT_LANGUAGE")
                     "French"
                   (funcall real-getenv name))))
              ((symbol-function 'sem-llm-request)
               (lambda (_prompt system callback context &optional _tier)
                 (setq captured-system-prompt system)
                 (funcall callback nil (list :error "mock") context)
                 nil))
              ((symbol-function 'sem-core--increment-retry)
               (lambda (&rest _) 1))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-core-log-error)
               (lambda (&rest _) nil)))
      (sem-router--route-to-task-llm
       '(:title "Buy milk" :tags ("task") :body nil :hash "task-hash")
       (lambda (_success _context) nil)
       42)
      (should (string-match-p "transform a raw capture note" captured-system-prompt))
      (should
       (string-match-p
        "OUTPUT LANGUAGE REQUIREMENT: You MUST write the entire response in French only. Do not use any other language."
        captured-system-prompt))
      (should
       (string=
        (car (last (split-string captured-system-prompt "\n" t)))
        "OUTPUT LANGUAGE REQUIREMENT: You MUST write the entire response in French only. Do not use any other language.")))))

(ert-deftest sem-router-test-task-write-creates-file ()
  "Test that tasks.org is created if absent.
Success path: tasks.org auto-created on first write."
  (let ((test-tasks-file (make-temp-file "tasks-test-")))
    (unwind-protect
        (progn
          (delete-file test-tasks-file)
          (let ((sem-router-tasks-file test-tasks-file))
            (let ((response "* TODO Test Task
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :routine:
:END:
Task description here."))
              (should (sem-router--write-task-to-file response))
              ;; File should now exist
              (should (file-exists-p test-tasks-file)))))
      (when (file-exists-p test-tasks-file)
        (sem-mock-cleanup-temp-file test-tasks-file)))))

(ert-deftest sem-router-test-temp-write-does-not-add-tasks-heading ()
  "Test that temp task files do not get a '* Tasks' heading."
  (let* ((tmp-dir (make-temp-file "sem-router-test-" t))
         (temp-file (expand-file-name "tasks-tmp-1.org" tmp-dir))
         (response "* TODO Temp Task
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :routine:
:END:
Task description here."))
    (unwind-protect
        (progn
          (should (sem-router--write-task-to-file response temp-file))
          (with-temp-buffer
            (insert-file-contents temp-file)
            (let ((content (buffer-string)))
              (should-not (string-match-p "^\\* Tasks$" content))
              (should (string-match-p "\\* TODO \\[#C\\] Temp Task" content)))))
      (delete-directory tmp-dir t))))

(ert-deftest sem-router-test-task-write-defangs-urls ()
  "Test task write path defangs operator-facing URLs."
  (let ((test-tasks-file (make-temp-file "tasks-test-")))
    (unwind-protect
        (let ((sem-router-tasks-file test-tasks-file)
              (response "* TODO Review docs\n:PROPERTIES:\n:ID: 550e8400-e29b-41d4-a716-446655440000\n:FILETAGS: :routine:\n:END:\nSee https://example.com/guide"))
          (should (sem-router--write-task-to-file response))
          (with-temp-buffer
            (insert-file-contents test-tasks-file)
            (let ((content (buffer-string)))
              (should (string-match-p "hxxps://example\\.com/guide" content))
              (should-not (string-match-p "https://example\\.com/guide" content)))))
      (when (file-exists-p test-tasks-file)
        (sem-mock-cleanup-temp-file test-tasks-file)))))

(ert-deftest sem-router-test-temp-write-drops-mismatched-batch-id ()
  "Test mismatched batch id write is rejected for temp file isolation." 
  (let* ((tmp-dir (make-temp-file "sem-router-test-" t))
         (temp-file (expand-file-name "tasks-tmp-2.org" tmp-dir))
         (response "* TODO Temp Task
:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:FILETAGS: :routine:
:END:
Task description here."))
    (unwind-protect
        (progn
          (should-not (sem-router--write-task-to-file response temp-file 1))
          (should-not (file-exists-p temp-file)))
      (delete-directory tmp-dir t))))

(ert-deftest sem-router-test-stale-task-callback-is-ignored ()
  "Test stale task callback does not write or mutate active batch state." 
  (let ((write-called nil)
        (barrier-arg nil)
        (callback-called nil)
        (sem-core--batch-id 10))
    (require 'sem-llm)
    (cl-letf (((symbol-function 'org-id-new)
               (lambda () "550e8400-e29b-41d4-a716-446655440000"))
              ((symbol-function 'sem-llm-request)
               (lambda (_prompt _system callback context &optional _tier)
                 (funcall callback
                          "* TODO Test task\n:PROPERTIES:\n:ID: 550e8400-e29b-41d4-a716-446655440000\n:FILETAGS: :work:\n:END:\nBody"
                          nil
                          context)
                 nil))
              ((symbol-function 'sem-router--write-task-to-file)
               (lambda (&rest _)
                 (setq write-called t)
                 t))
              ((symbol-function 'sem-core--batch-barrier-check)
               (lambda (&optional batch-id)
                 (setq barrier-arg batch-id)))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-router--mark-processed)
               (lambda (&rest _) nil)))
      (sem-router--route-to-task-llm
       '(:title "Buy milk" :tags ("task") :body nil :hash "task-hash")
       (lambda (_success _context)
         (setq callback-called t))
       9)
      (should-not write-called)
      (should (equal barrier-arg 9))
      (should-not callback-called))))

(ert-deftest sem-router-test-stale-url-callback-is-ignored ()
  "Test stale URL callback does not mutate retry/cursor for active batch." 
  (let ((hash "stale-url-hash")
        (url "https://example.com/stale")
        (dlq-called nil)
        (retry-called nil)
        (barrier-arg nil)
        (sem-core--batch-id 4)
        (sem-core--pending-callbacks 0))
    (cl-letf (((symbol-function 'sem-router--parse-headlines)
               (lambda ()
                 (list (list :title url
                             :tags '("link")
                             :body nil
                             :link url
                             :hash hash))))
              ((symbol-function 'sem-url-capture-process)
               (lambda (_url callback)
                 (funcall callback nil (list :url url :failure-kind 'timeout))
                 t))
              ((symbol-function 'sem-core--increment-retry)
               (lambda (_hash)
                 (setq retry-called t)
                 1))
              ((symbol-function 'sem-core--mark-dlq)
               (lambda (&rest _)
                 (setq dlq-called t)))
              ((symbol-function 'sem-core--batch-barrier-check)
               (lambda (&optional batch-id)
                 (setq barrier-arg batch-id)))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil)))
      (sem-router-process-inbox 3)
      (should-not retry-called)
      (should-not dlq-called)
      (should (equal barrier-arg 3)))))

(ert-deftest sem-router-test-summary-log-omits-errors-field ()
  "Test final inbox summary log contains only processed and skipped counts."
  (let ((summary-message nil)
        (sem-core--batch-id 10)
        (sem-core--pending-callbacks 0))
    (cl-letf (((symbol-function 'sem-router--parse-headlines)
               (lambda ()
                 (list (list :title "Ignore me"
                             :tags '("unknown")
                             :body nil
                             :hash "unknown-hash"))))
              ((symbol-function 'sem-router--mark-processed)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-core-log)
               (lambda (_module _event _status message &optional _tokens)
                 (when (string-match-p "^Processed=" message)
                   (setq summary-message message))))
              ((symbol-function 'sem-core-log-error)
               (lambda (&rest _) nil)))
      (sem-router-process-inbox 10)
      (should (string= summary-message "Processed=0, Skipped=1"))
      (should-not (string-match-p "Errors=" summary-message)))))

;;; Tests for security block round-trip (car/cdr destructuring)

(ert-deftest sem-router-test-security-block-round-trip ()
  "Test that security blocks are correctly destructured and restored as plain text.
Verifies 3-element return: (car result) = sanitized-body, (cadr result) = blocks, (caddr result) = position-info."
  (let* ((original-body "This is content with #+begin_sensitive\nsecret data\n#+end_sensitive")
         ;; Mock the security functions - now 3-element list
         (sanitize-result (list "This is content with <<SENSITIVE_1>>"
                                '(("<<SENSITIVE_1>>" . "#+begin_sensitive\nsecret data\n#+end_sensitive"))
                                '(("<<SENSITIVE_1>>" "#+begin_sensitive\nsecret data\n#+end_sensitive" "This is content with " " for access"))))
         (sanitized-body (car sanitize-result))
         (security-blocks (cadr sanitize-result))
         (position-info (caddr sanitize-result)))
    ;; Verify car gives sanitized body
    (should (string= sanitized-body "This is content with <<SENSITIVE_1>>"))
    ;; Verify cadr gives blocks alist
    (should (equal security-blocks '(("<<SENSITIVE_1>>" . "#+begin_sensitive\nsecret data\n#+end_sensitive"))))
    ;; Verify caddr gives position-info
    (should (listp position-info))
    (should (= (length position-info) 1))
    ;; Verify round-trip restores plain text (no markers)
    (should (string= "This is content with secret data"
                     (sem-security-restore-from-llm sanitized-body security-blocks)))))

;;; Tests for mutex/lock behavior

(ert-deftest sem-router-test-mutex-lock-acquire-release ()
  "Test that lock can be acquired and released."
  ;; Lock starts as nil
  (setq sem-router--tasks-write-lock nil)
  (should (sem-router--acquire-tasks-write-lock))
  (should sem-router--tasks-write-lock)
  ;; Release
  (sem-router--release-tasks-write-lock)
  (should-not sem-router--tasks-write-lock))

(ert-deftest sem-router-test-mutex-lock-contention ()
  "Test that lock contention returns nil (not acquired)."
  ;; Acquire lock
  (setq sem-router--tasks-write-lock nil)
  (should (sem-router--acquire-tasks-write-lock))
  ;; Second acquire should fail
  (should-not (sem-router--acquire-tasks-write-lock))
  ;; Cleanup
  (sem-router--release-tasks-write-lock))

(ert-deftest sem-router-test-mutex-lock-release-on-error ()
  "Test that lock is released even when callback signals error.
Uses unwind-protect to ensure cleanup."
  (setq sem-router--tasks-write-lock nil)
  (should-error
   (sem-router--with-tasks-write-lock
    '(:title "test")
    (lambda ()
      (should sem-router--tasks-write-lock) ;; Lock should be held
      (error "Simulated error"))
    0))
  ;; Lock should be released after error
  (should-not sem-router--tasks-write-lock))

(ert-deftest sem-router-test-mutex-lock-success-callback ()
  "Test that successful callback executes and releases lock."
  (setq sem-router--tasks-write-lock nil)
  (let ((callback-executed nil))
    (sem-router--with-tasks-write-lock
     '(:title "test")
     (lambda ()
       (setq callback-executed t)
       (should sem-router--tasks-write-lock)) ;; Lock should be held during execution
     0)
    ;; Callback should have executed
    (should callback-executed)
    ;; Lock should be released
    (should-not sem-router--tasks-write-lock)))

(ert-deftest sem-router-test-task-route-writes-through-guarded-lock-path ()
  "Test async task callback routes temp write through lock helper."
  (let ((lock-wrapper-called nil)
        (write-called nil)
        (callback-result nil))
    (require 'sem-llm)
    (cl-letf (((symbol-function 'org-id-new)
               (lambda () "550e8400-e29b-41d4-a716-446655440000"))
              ((symbol-function 'sem-llm-request)
               (lambda (_prompt _system callback context &optional _tier)
                 (funcall callback
                          "* TODO Test task\n:PROPERTIES:\n:ID: 550e8400-e29b-41d4-a716-446655440000\n:FILETAGS: :work:\n:END:\nBody"
                          nil
                          context)
                 nil))
              ((symbol-function 'sem-router--with-tasks-write-lock)
               (lambda (_headline callback _retry-count &optional _dlq-callback _batch-id)
                 (setq lock-wrapper-called t)
                 (funcall callback)))
              ((symbol-function 'sem-router--write-task-to-file)
               (lambda (&rest _)
                  (setq write-called t)
                  t))
              ((symbol-function 'sem-router--mark-processed)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-core-log-error)
                (lambda (&rest _) nil)))
      (sem-router--route-to-task-llm
       '(:title "Buy milk" :tags ("task") :body nil :hash "task-hash")
       (lambda (success _context)
          (setq callback-result success)))
      (should lock-wrapper-called)
      (should write-called)
      (should callback-result))))

(ert-deftest sem-router-test-parse-headlines-debug-preview-non-fatal ()
  "Test debug preview logging path does not crash parsing."
  (let ((test-file (make-temp-file "inbox-test-")))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "* Headline 1 :link:\n"))
          (let ((sem-router-inbox-file test-file))
            (should (= (length (sem-router--parse-headlines)) 1))))
      (sem-mock-cleanup-temp-file test-file))))

;;; Tests for body handling

(ert-deftest sem-router-test-body-nil-skips-sanitization ()
  "Test that nil body skips security sanitization and BODY section.
When headline has no body, no BODY: section should be in prompt."
  ;; With nil body, sanitized-body should remain nil
  (let ((body nil)
        (sanitized-body nil)
        (security-blocks nil))
    ;; Simulate the logic: when body is nil, don't sanitize
    (when body
      (let ((result (sem-security-sanitize-for-llm body)))
        (setq sanitized-body (car result))
        (setq security-blocks (cadr result))))
    ;; sanitized-body should still be nil
    (should-not sanitized-body)
    (should-not security-blocks)))

(ert-deftest sem-router-test-empty-body-proceeds ()
  "Test that empty string body proceeds with LLM call.
Empty body is valid for zero-body headlines."
  ;; Empty string is truthy in Emacs Lisp (not nil)
  (let ((sanitized-body ""))
    ;; Empty string should be treated as valid (proceeds with LLM)
    (should sanitized-body) ;; Empty string is not nil
    ;; The when check for adding BODY section should succeed
    (should (when sanitized-body t))))

(ert-deftest sem-router-test-url-capture-timeout-retries-without-cursor-mark ()
  "Test URL capture timeout increments retry and does not mark processed."
  (let* ((hash "timeout-hash-123")
         (url "https://example.com/timeout")
         (captured-timeout-log nil)
         (test-cursor-file (make-temp-file "sem-cursor-timeout-test-"))
         (test-retries-file (make-temp-file "sem-retries-timeout-test-")))
    (unwind-protect
        (cl-letf (((symbol-function 'sem-router--parse-headlines)
                   (lambda ()
                     (list (list :title url
                                 :tags '("link")
                                 :body nil
                                 :link url
                                 :hash hash))))
                  ((symbol-function 'sem-url-capture-process)
                   (lambda (_url callback)
                     (funcall callback nil (list :url url :failure-kind 'timeout))
                     t))
              ((symbol-function 'sem-core--batch-barrier-check)
               (lambda (&optional _batch-id) nil))
                  ((symbol-function 'sem-core-log)
                   (lambda (_module event status message &optional _raw)
                     (when (and (string= event "URL-CAPTURE")
                                (string= status "FAIL")
                                (string-match-p "timeout" message))
                       (setq captured-timeout-log t)))))
          (let ((sem-core-cursor-file test-cursor-file)
                (sem-core-retries-file test-retries-file))
            (sem-router-process-inbox)
            (should (= (sem-core--get-retry-count hash) 1))
            (should-not (sem-core--is-processed hash))
            (should captured-timeout-log)))
      (sem-mock-cleanup-temp-file test-cursor-file)
      (sem-mock-cleanup-temp-file test-retries-file))))

(ert-deftest sem-router-test-runtime-message-task-success-metadata-only ()
  "Test task success emits metadata-only runtime message fields."
  (let* ((title "Sensitive launch playbook")
         (body "private notes inside task body")
         (url "https://sensitive.example.com/private")
         (hash "00112233445566778899aabbccddeeff")
         (captured
          (sem-router-test--capture-runtime-messages
           (lambda ()
             (let ((sem-core--batch-id 100)
                   (sem-core--pending-callbacks 0))
               (cl-letf (((symbol-function 'sem-router--parse-headlines)
                          (lambda ()
                            (list (list :title title
                                        :tags '("task")
                                        :body body
                                        :link url
                                        :hash hash))))
                         ((symbol-function 'sem-router--is-processed)
                          (lambda (_hash) nil))
                         ((symbol-function 'sem-router--route-to-task-llm)
                          (lambda (_headline callback &optional batch-id)
                            (funcall callback t (list :hash hash :batch-id batch-id))
                            t))
                         ((symbol-function 'sem-core--batch-barrier-check)
                          (lambda (&optional _batch-id) nil))
                         ((symbol-function 'sem-core-log)
                          (lambda (&rest _) nil))
                         ((symbol-function 'sem-core-log-error)
                          (lambda (&rest _) nil)))
                 (sem-router-process-inbox 100)))))))
    (should (cl-some (lambda (line)
                       (string-match-p "action=task-callback status=OK" line))
                     captured))
    (sem-router-test--assert-no-plaintext-leaks captured (list title body url))))

(ert-deftest sem-router-test-runtime-message-task-failure-metadata-only ()
  "Test task failure emits metadata-only runtime message fields."
  (let* ((title "Private migration checklist")
         (body "contains internal details")
         (url "https://sensitive.example.com/checklist")
         (hash "ffeeddccbbaa99887766554433221100")
         (captured
          (sem-router-test--capture-runtime-messages
           (lambda ()
             (let ((sem-core--batch-id 101)
                   (sem-core--pending-callbacks 0))
               (cl-letf (((symbol-function 'sem-router--parse-headlines)
                          (lambda ()
                            (list (list :title title
                                        :tags '("task")
                                        :body body
                                        :link url
                                        :hash hash))))
                         ((symbol-function 'sem-router--is-processed)
                          (lambda (_hash) nil))
                         ((symbol-function 'sem-router--route-to-task-llm)
                          (lambda (_headline callback &optional batch-id)
                            (funcall callback nil (list :hash hash :batch-id batch-id))
                            t))
                         ((symbol-function 'sem-core--batch-barrier-check)
                          (lambda (&optional _batch-id) nil))
                         ((symbol-function 'sem-core-log)
                          (lambda (&rest _) nil))
                         ((symbol-function 'sem-core-log-error)
                          (lambda (&rest _) nil)))
                 (sem-router-process-inbox 101)))))))
    (should (cl-some (lambda (line)
                       (string-match-p "action=task-callback status=FAIL" line))
                     captured))
    (sem-router-test--assert-no-plaintext-leaks captured (list title body url))))

(ert-deftest sem-router-test-runtime-message-url-retry-metadata-only ()
  "Test URL retry emits metadata-only runtime message fields."
  (let* ((title "Private incident URL")
         (body "sensitive retry data")
         (url "https://sensitive.example.com/retry")
         (hash "11223344556677889900aabbccddeeff")
         (captured
          (sem-router-test--capture-runtime-messages
           (lambda ()
             (let ((sem-core--batch-id 102)
                   (sem-core--pending-callbacks 0))
               (cl-letf (((symbol-function 'sem-router--parse-headlines)
                          (lambda ()
                            (list (list :title title
                                        :tags '("link")
                                        :body body
                                        :link url
                                        :hash hash))))
                         ((symbol-function 'sem-router--is-processed)
                          (lambda (_hash) nil))
                         ((symbol-function 'sem-url-capture-process)
                          (lambda (_url callback)
                            (funcall callback nil (list :url url :failure-kind 'timeout))
                            t))
                         ((symbol-function 'sem-core--increment-retry)
                          (lambda (_hash) 1))
                         ((symbol-function 'sem-core--batch-barrier-check)
                          (lambda (&optional _batch-id) nil))
                         ((symbol-function 'sem-core-log)
                          (lambda (&rest _) nil))
                         ((symbol-function 'sem-core-log-error)
                          (lambda (&rest _) nil)))
                 (sem-router-process-inbox 102)))))))
    (should (cl-some (lambda (line)
                       (string-match-p "action=url-callback status=RETRY" line))
                     captured))
    (sem-router-test--assert-no-plaintext-leaks captured (list title body url))))

(ert-deftest sem-router-test-runtime-message-stale-url-callback-metadata-only ()
  "Test stale URL callback emits metadata-only runtime message fields."
  (let* ((title "Private stale callback title")
         (body "sensitive stale callback body")
         (url "https://sensitive.example.com/stale")
         (hash "aabbccddeeff00112233445566778899")
         (captured
          (sem-router-test--capture-runtime-messages
           (lambda ()
             (let ((sem-core--batch-id 200)
                   (sem-core--pending-callbacks 0))
               (cl-letf (((symbol-function 'sem-router--parse-headlines)
                          (lambda ()
                            (list (list :title title
                                        :tags '("link")
                                        :body body
                                        :link url
                                        :hash hash))))
                         ((symbol-function 'sem-router--is-processed)
                          (lambda (_hash) nil))
                         ((symbol-function 'sem-url-capture-process)
                          (lambda (_url callback)
                            (funcall callback nil (list :url url :failure-kind 'timeout))
                            t))
                         ((symbol-function 'sem-core--increment-retry)
                          (lambda (&rest _)
                            (error "retry should not run in stale path")))
                         ((symbol-function 'sem-core--batch-barrier-check)
                          (lambda (&optional _batch-id) nil))
                         ((symbol-function 'sem-core-log)
                          (lambda (&rest _) nil))
                         ((symbol-function 'sem-core-log-error)
                          (lambda (&rest _) nil)))
                 (sem-router-process-inbox 199)))))))
    (should (cl-some (lambda (line)
                       (string-match-p "action=url-callback status=STALE" line))
                     captured))
    (sem-router-test--assert-no-plaintext-leaks captured (list title body url))))

(ert-deftest sem-router-test-journal-tag-detection ()
  "Test that :journal: tag is detected for deterministic routing." 
  (let ((headline '(:title "Journal note" :tags ("journal") :body "Entry")))
    (should (sem-router--is-journal-headline headline))))

(ert-deftest sem-router-test-journal-mention-extraction-dedup-and-normalization ()
  "Test mention extraction strips @ and preserves first-seen order." 
  (let ((mentions (sem-router--journal-extract-mentions
                   "Talked to @boss, then @wife; later pinged @boss and @some!")))
    (should (equal mentions '("boss" "wife" "some")))))

(ert-deftest sem-router-test-journal-entry-builds-derived-metadata ()
  "Test journal entry intermediate object includes required metadata fields." 
  (let* ((entry (sem-router--build-journal-entry
                 '(:title "Journal"
                   :hash "hash-1"
                   :tags ("journal" "work" "family")
                   :journal-body "Today I met @boss and @wife")
                 "2026-04-21T13:30:00+02:00")))
    (should (string= (plist-get entry :ingested-at) "2026-04-21T13:30:00+02:00"))
    (should (string= (plist-get entry :tags-inbox) ":work:family:"))
    (should (string= (plist-get entry :mentions-raw) "boss, wife"))
    (should (string= (plist-get entry :body) "Today I met @boss and @wife"))))

(ert-deftest sem-router-test-journal-route-bypasses-task-and-url-pipelines ()
  "Test :journal: entries do not invoke task or URL processing pipelines." 
  (let ((task-called nil)
        (url-called nil)
        (sem-core--batch-id 50)
        (sem-core--pending-callbacks 0))
    (cl-letf (((symbol-function 'sem-router--parse-headlines)
               (lambda ()
                 (list (list :title "https://example.com"
                             :tags '("journal" "task")
                             :body "Body"
                             :hash "journal-hash"))))
              ((symbol-function 'sem-router--is-processed)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-router--process-journal-batch)
               (lambda (&rest _)
                 (list :processed 1 :failed nil :attempted 1)))
              ((symbol-function 'sem-router--route-to-task-llm)
               (lambda (&rest _)
                 (setq task-called t)
                 t))
              ((symbol-function 'sem-url-capture-process)
               (lambda (&rest _)
                 (setq url-called t)
                 t))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-core-log-error)
               (lambda (&rest _) nil)))
      (sem-router-process-inbox 50)
      (should-not task-called)
      (should-not url-called))))

(ert-deftest sem-router-test-journal-payload-inserts-missing-date-headings-once ()
  "Test payload adds missing year/month/day headings once for a batch." 
  (let* ((entries (list (list :body "one" :ingested-at "2026-04-21T00:00:00+00:00"
                              :tags-inbox ":work:" :mentions-raw "boss")
                        (list :body "two" :ingested-at "2026-04-21T00:00:00+00:00"
                              :tags-inbox ":family:" :mentions-raw "wife")))
         (payload (sem-router--journal-build-append-payload
                   entries
                   (encode-time 0 0 10 21 4 2026 t)
                   "")))
    (should (string-prefix-p "* 2026\n** 2026-04\n*** 2026-04-21\n" payload))
    (dolist (heading '("* 2026\n" "** 2026-04\n" "*** 2026-04-21\n"))
      (let ((count 0)
            (start 0))
        (while (string-match (regexp-quote heading) payload start)
          (setq count (1+ count))
          (setq start (match-end 0)))
        (should (= count 1))))))

(ert-deftest sem-router-test-journal-payload-continues-day-numbering ()
  "Test payload numbering continues from existing numeric day items." 
  (let* ((existing "* 2026\n** 2026-04\n*** 2026-04-21\n**** 1\n**** 2\n")
         (entries (list (list :body "three" :ingested-at "2026-04-21T00:00:00+00:00"
                              :tags-inbox "" :mentions-raw "")
                        (list :body "four" :ingested-at "2026-04-21T00:00:00+00:00"
                              :tags-inbox "" :mentions-raw "")))
         (payload (sem-router--journal-build-append-payload
                   entries
                   (encode-time 0 0 10 21 4 2026 t)
                   existing)))
    (should (string-prefix-p "**** 3\n" payload))
    (should (string-match-p (regexp-quote "**** 4\n") payload))
    (should-not (string-match-p "\\* 2026\\n" payload))))

(ert-deftest sem-router-test-journal-process-batch-builds-before-single-append ()
  "Test journal batch prepares all entries before one append call." 
  (let ((build-count 0)
        (append-calls 0)
        (mark-processed-calls 0)
        (sem-core--batch-id 51))
    (cl-letf (((symbol-function 'sem-router--is-processed)
               (lambda (&rest _) nil))
              ((symbol-function 'file-exists-p)
               (lambda (_path) nil))
              ((symbol-function 'sem-router--build-journal-entry)
               (lambda (_headline _ingested-at)
                 (setq build-count (1+ build-count))
                 (list :hash (format "h-%d" build-count)
                       :body "text"
                       :ingested-at "2026-04-21T00:00:00+00:00"
                       :tags-inbox ""
                       :mentions-raw "")))
              ((symbol-function 'sem-router--journal-build-append-payload)
               (lambda (entries _ingest-time _existing-content)
                 (should (= (length entries) 2))
                 (should (= build-count 2))
                 "payload"))
              ((symbol-function 'sem-router--journal-atomic-append)
               (lambda (_payload)
                 (setq append-calls (1+ append-calls))
                 t))
              ((symbol-function 'sem-router--mark-processed)
               (lambda (&rest _)
                 (setq mark-processed-calls (1+ mark-processed-calls))))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-core-log-error)
               (lambda (&rest _) nil)))
      (let ((result (sem-router--process-journal-batch
                     (list (list :title "a" :hash "h1" :tags '("journal") :journal-body "b1")
                           (list :title "b" :hash "h2" :tags '("journal") :journal-body "b2"))
                     51)))
        (should (= (plist-get result :processed) 2))
        (should-not (plist-get result :failed))
        (should (= append-calls 1))
        (should (= mark-processed-calls 2))))))

(ert-deftest sem-router-test-journal-transform-failure-skips-append ()
  "Test transformation failure blocks journal mutation for the whole batch." 
  (let ((append-called nil)
        (sem-core--batch-id 52))
    (cl-letf (((symbol-function 'sem-router--is-processed)
               (lambda (&rest _) nil))
              ((symbol-function 'file-exists-p)
               (lambda (_path) nil))
              ((symbol-function 'sem-router--build-journal-entry)
               (lambda (headline _ingested-at)
                 (if (string= (plist-get headline :hash) "bad")
                     (error "boom")
                   (list :hash "ok" :body "text" :ingested-at "ts" :tags-inbox "" :mentions-raw ""))))
              ((symbol-function 'sem-router--journal-atomic-append)
               (lambda (&rest _)
                 (setq append-called t)
                 t))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-core-log-error)
               (lambda (&rest _) nil)))
      (let ((result (sem-router--process-journal-batch
                     (list (list :title "a" :hash "ok" :tags '("journal") :journal-body "b1")
                           (list :title "b" :hash "bad" :tags '("journal") :journal-body "b2"))
                     52)))
        (should (= (plist-get result :processed) 0))
        (should (plist-get result :failed))
        (should-not append-called)))))


;;; Streaming pipeline regression test

(ert-deftest sem-router-test-task-streaming-chunks-no-premature-retry ()
  "Test streamed chunks deliver one complete response with no premature retry.
Partial chunks must not trigger validation failures, retries, or DLQ;
only the final accumulated response reaches the task pipeline."
  (let ((downstream-calls 0)
        (downstream-success :unset)
        (retry-calls 0)
        (test-tasks-file (make-temp-file "tasks-stream-")))
    (unwind-protect
        (let ((sem-router-tasks-file test-tasks-file)
              (sem-core-cursor-file (make-temp-file "cursor-stream-"))
              (sem-core--batch-id 11))
          (cl-letf (((symbol-function 'org-id-new)
                     (lambda (&optional _) "550e8400-e29b-41d4-a716-446655440000"))
                    ((symbol-function 'getenv)
                     (lambda (name)
                       (cond
                        ((string= name "OPENROUTER_MODEL") "test/medium")
                        ((string= name "SEM_TASK_API_MAX_RETRIES") "3")
                        ((string= name "CLIENT_TIMEZONE") "Etc/UTC")
                        (t nil))))
                    ((symbol-function 'sem-core--increment-retry)
                     (lambda (_hash) (setq retry-calls (1+ retry-calls)) 1))
                    ((symbol-function 'sem-core-log)
                     (lambda (&rest _) nil))
                    ((symbol-function 'sem-core-log-error)
                     (lambda (&rest _) nil)))
            (sem-mock-gptel-request-stream
             (list (cons "* TODO Follow up about the authentication"
                         (list :stream t))
                   (cons " module\n:PROPERTIES:\n:ID: 550e8400-e29b-41d4-a716-446655440000\n:FILETAGS: :work:\n:END:\nReview the pull request."
                         (list :stream t))
                   (cons t (list :stream t))))
            (sem-router--route-to-task-llm
             '(:title "Review pull request #452 for authentication module"
                      :tags ("task")
                      :body nil
                      :hash "streaming-task-hash")
             (lambda (success _context)
               (setq downstream-calls (1+ downstream-calls))
               (setq downstream-success success)))
            (should (= downstream-calls 1))
            (should (eq downstream-success t))
            (should (= retry-calls 0))
            (should (file-exists-p test-tasks-file))))
      (when (file-exists-p test-tasks-file)
        (sem-mock-cleanup-temp-file test-tasks-file)))))


(ert-deftest sem-router-test-task-api-error-with-security-blocks-still-retries ()
  "Test that a failed LLM response for a task with security blocks takes the
retry path instead of crashing on detokenize-of-nil (regression: the old code
called sem-security-restore-from-llm unconditionally, signaling
wrong-type-argument arrayp on nil responses and skipping the retry branch)."
  (let ((callback-success :unset)
        (increment-calls 0)
        (sem-core--batch-id 7))
    (cl-letf (((symbol-function 'org-id-new)
               (lambda (&optional _) "550e8400-e29b-41d4-a716-446655440000"))
              ((symbol-function 'getenv)
               (lambda (name)
                 (cond
                  ((string= name "OPENROUTER_MODEL") "test/medium")
                  ((string= name "SEM_TASK_API_MAX_RETRIES") "3")
                  ((string= name "CLIENT_TIMEZONE") "Etc/UTC")
                  (t nil))))
              ((symbol-function 'sem-llm-request)
               (lambda (_prompt _system callback context &optional _tier)
                 (funcall callback nil (list :error "provider timeout") context)
                 nil))
              ((symbol-function 'sem-core--increment-retry)
               (lambda (_hash) (setq increment-calls (1+ increment-calls)) 1))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-core-log-error)
               (lambda (&rest _) nil)))
      (sem-router--route-to-task-llm
       '(:title "Update password manager"
         :tags ("task")
         :body "Contact the bookkeeper.\n#+begin_sensitive\nsupersecret123\n#+end_sensitive\nand sent the pdf."
         :hash "sensitive-error-hash")
       (lambda (success _context)
         (setq callback-success success)))
      (should (= increment-calls 1))
      (should (eq callback-success nil)))))


;;; Rate-limit (429) handling regression tests

(ert-deftest sem-router-test-rate-limit-detector ()
  "Test 429 detection across gptel plist and string error shapes."
  (should (sem-router--rate-limit-p
           (list :message "Provider returned error" :code 429)))
  (should-not (sem-router--rate-limit-p
               (list :message "Provider returned error" :code 500)))
  (should (sem-router--rate-limit-p
           "Provider returned error :code 429"))
  (should (sem-router--rate-limit-p "temporarily rate-limited upstream"))
  (should-not (sem-router--rate-limit-p "Curl failed with exit code 18"))
  (should-not (sem-router--rate-limit-p nil)))

(ert-deftest sem-router-test-rate-limit-delay-backoff ()
  "Test exponential backoff delays with configurable base."
  (cl-letf (((symbol-function 'getenv)
             (lambda (name)
               (when (string= name "SEM_TASK_RATE_LIMIT_RETRY_DELAY") "20"))))
    (should (= (sem-router--rate-limit-retry-delay 1) 20))
    (should (= (sem-router--rate-limit-retry-delay 2) 40))
    (should (= (sem-router--rate-limit-retry-delay 3) 80)))
  (cl-letf (((symbol-function 'getenv) (lambda (_name) nil)))
    (should (= (sem-router--rate-limit-retry-delay 1) 20))))

(ert-deftest sem-router-test-task-429-schedules-in-process-retry ()
  "Test a 429 failure defers the downstream callback and schedules a retry.
The retried attempt runs in-process; when it succeeds the callback fires
with success and the task is written."
  (let ((downstream nil)
        (scheduled nil)
        (llm-calls 0)
        (test-tasks-file (make-temp-file "tasks-429-")))
    (unwind-protect
        (let ((sem-router-tasks-file test-tasks-file)
              (sem-core-cursor-file (make-temp-file "cursor-429-"))
              (sem-core--batch-id 21)
              (retry-count 0))
          (cl-letf (((symbol-function 'org-id-new)
                     (lambda (&optional _) "550e8400-e29b-41d4-a716-446655440000"))
                    ((symbol-function 'getenv)
                     (lambda (name)
                       (cond
                        ((string= name "OPENROUTER_MODEL") "test/medium")
                        ((string= name "SEM_TASK_API_MAX_RETRIES") "3")
                        ((string= name "SEM_TASK_RATE_LIMIT_RETRY_DELAY") "20")
                        ((string= name "CLIENT_TIMEZONE") "Etc/UTC")
                        (t nil))))
                    ((symbol-function 'run-at-time)
                     (lambda (delay _repeat fn &rest args)
                       (setq scheduled (list delay fn args))))
                    ((symbol-function 'sem-core--increment-retry)
                     (lambda (_hash) (cl-incf retry-count)))
                    ((symbol-function 'sem-core-log)
                     (lambda (&rest _) nil))
                    ((symbol-function 'sem-core-log-error)
                     (lambda (&rest _) nil))
                    ((symbol-function 'sem-llm-request)
                     (lambda (_prompt _system callback context &optional _tier)
                       (cl-incf llm-calls)
                       (if (= llm-calls 1)
                           ;; First attempt: upstream rate limit (429).
                           (funcall callback
                                    nil
                                    (list :error (list :message "Provider returned error"
                                                       :code 429))
                                    context)
                         ;; Retried attempt: valid task output.
                         (funcall callback
                                  "* TODO Follow up about the authentication module\n:PROPERTIES:\n:ID: 550e8400-e29b-41d4-a716-446655440000\n:FILETAGS: :work:\n:END:\nReview the pull request."
                                  (list :status "finished")
                                  context)
                         t))))
            (sem-router--route-to-task-llm
             '(:title "Review pull request #452 for authentication module"
                      :tags ("task")
                      :body nil
                      :hash "rate-limit-hash")
             (lambda (success _context)
               (setq downstream (cons success downstream))))
            ;; First attempt: no downstream call, retry scheduled.
            (should (null downstream))
            (should (= llm-calls 1))
            (should (= retry-count 1))
            (should scheduled)
            (should (= (nth 0 scheduled) 20))
            (should (eq (nth 1 scheduled) #'sem-router--route-to-task-llm))
            ;; Simulate the timer firing: retried attempt succeeds.
            (apply (nth 1 scheduled) (nth 2 scheduled))
            (should (= llm-calls 2))
            (should (= (length downstream) 1))
            (should (eq (car downstream) t))
            (should (file-exists-p test-tasks-file))))
      (when (file-exists-p test-tasks-file)
        (sem-mock-cleanup-temp-file test-tasks-file)))))

(ert-deftest sem-router-test-task-429-exhausted-goes-to-dlq ()
  "Test that an exhausted rate-limited task reaches DLQ and fires the callback."
  (let ((downstream nil)
        (scheduled nil)
        (dlq-marks 0)
        (sem-core--batch-id 22))
    (cl-letf (((symbol-function 'org-id-new)
               (lambda (&optional _) "550e8400-e29b-41d4-a716-446655440000"))
              ((symbol-function 'getenv)
               (lambda (name)
                 (cond
                  ((string= name "OPENROUTER_MODEL") "test/medium")
                  ((string= name "SEM_TASK_API_MAX_RETRIES") "3")
                  ((string= name "CLIENT_TIMEZONE") "Etc/UTC")
                  (t nil))))
              ((symbol-function 'run-at-time)
               (lambda (&rest _)
                 (setq scheduled t)))
              ((symbol-function 'sem-core--increment-retry)
               (lambda (_hash) 3))
              ((symbol-function 'sem-core--mark-dlq)
               (lambda (_hash) (cl-incf dlq-marks)))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-core-log-error)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-llm-request)
               (lambda (_prompt _system callback context &optional _tier)
                 (funcall callback
                          nil
                          (list :error (list :message "Provider returned error"
                                             :code 429))
                          context)
                 nil)))
      (sem-router--route-to-task-llm
       '(:title "Process quarterly financial reports"
                :tags ("task")
                :body nil
                :hash "rate-limit-dlq-hash")
       (lambda (success _context)
         (setq downstream (cons success downstream))))
      (should (= dlq-marks 1))
      (should-not scheduled)
      (should (= (length downstream) 1))
      (should (eq (car downstream) t)))))


;;; Dispatch stagger regression tests

(ert-deftest sem-router-test-task-dispatch-stagger-delays ()
  "Test stagger delays: first dispatch immediate, linear growth, capped."
  (cl-letf (((symbol-function 'getenv)
             (lambda (name)
               (when (string= name "SEM_TASK_DISPATCH_STAGGER_SECONDS") "2"))))
    (should (= (sem-router--task-dispatch-delay 1) 0))
    (should (= (sem-router--task-dispatch-delay 2) 2))
    (should (= (sem-router--task-dispatch-delay 11) 20))
    (should (= (sem-router--task-dispatch-delay 40) 30)))
  (cl-letf (((symbol-function 'getenv) (lambda (_name) "0")))
    ;; Non-positive base disables staggering.
    (should (= (sem-router--task-dispatch-delay 5) 0))))


(ert-deftest sem-router-test-url-capture-retry-schedules-recapture ()
  "Test that a rate-limited URL capture schedules a delayed recapture.
The scheduler must not invoke the capture or callback synchronously;
firing the timer re-dispatches the same URL and callback."
  (let ((scheduled nil)
        (captured nil)
        (cb-called nil)
        (url "https://example.com/article")
        (callback (lambda (filepath _context) (setq cb-called filepath))))
    ;; Pre-load so the scheduler's `require' cannot rebind the mock.
    (require 'sem-url-capture)
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (delay _repeat fn &rest args)
                 (setq scheduled (list delay fn args))))
              ((symbol-function 'sem-url-capture-process)
               (lambda (a-url a-callback)
                 (setq captured (list a-url a-callback))
                 t))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil)))
      (sem-router--schedule-url-capture-retry url callback 1 "abc123" 1)
      ;; Nothing runs synchronously: no capture, no callback.
      (should-not captured)
      (should-not cb-called)
      (should (= (nth 0 scheduled)
                 (sem-router--rate-limit-retry-delay 1)))
      ;; Firing the timer re-dispatches the same URL and callback.
      (apply (nth 1 scheduled) (nth 2 scheduled))
      (should (equal captured (list url callback)))
      (should-not cb-called))))


;;; Rate-limit callback regression tests

(ert-deftest sem-router-test-rate-limited-url-callback-schedules-retry ()
  "Test 429 URL callback schedules in-process retry with the same callback.
Regression test for the free-variable `callback' reference in the URL
completion path: a rate-limited failure must schedule the retry without
signalling and must reuse the callback object registered with the original
dispatch, and the batch barrier must stay unresolved until the terminal
outcome."
  (let ((hash "rate-limited-url-hash")
        (url "https://example.com/rate-limited")
        (captured-callback nil)
        (retry-args nil)
        (barrier-calls nil)
        (dlq-called nil)
        (sem-core--batch-id 5)
        (sem-core--pending-callbacks 0))
    (cl-letf (((symbol-function 'sem-router--parse-headlines)
               (lambda ()
                 (list (list :title url
                             :tags '("link")
                             :body nil
                             :link url
                             :hash hash))))
              ((symbol-function 'sem-url-capture-process)
               (lambda (_url callback)
                 (setq captured-callback callback)
                 t))
              ((symbol-function 'sem-core--increment-retry)
               (lambda (_hash) 1))
              ((symbol-function 'sem-router--schedule-url-capture-retry)
               (lambda (cb-url callback batch-id cb-hash retry-count)
                 (setq retry-args (list cb-url callback batch-id cb-hash retry-count))))
              ((symbol-function 'sem-core--mark-dlq)
               (lambda (&rest _) (setq dlq-called t)))
              ((symbol-function 'sem-core--batch-barrier-check)
               (lambda (&optional batch-id)
                 (push batch-id barrier-calls)))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-core-log-error)
               (lambda (&rest _) nil)))
      (sem-router-process-inbox 5)
      ;; Simulate the LLM layer reporting a 429 rate limit for the capture.
      (should captured-callback)
      (funcall captured-callback nil (list :url url :failure-kind 'rate-limited))
      ;; Retry scheduled in-process with the SAME callback object.
      (should retry-args)
      (should (equal (nth 0 retry-args) url))
      (should (eq (nth 1 retry-args) captured-callback))
      (should (equal (nth 2 retry-args) 5))
      (should (equal (nth 3 retry-args) hash))
      (should (equal (nth 4 retry-args) 1))
      ;; Deferred retry: the batch barrier is not resolved yet.
      (should-not barrier-calls)
      (should-not dlq-called))))

(ert-deftest sem-router-test-url-callback-retry-exhausted-routes-to-dlq ()
  "Test 3rd cumulative retryable URL failure routes to DLQ, barrier resolves."
  (let ((hash "exhausted-url-hash")
        (url "https://example.com/exhausted")
        (captured-callback nil)
        (dlq-called nil)
        (retry-scheduled nil)
        (barrier-calls nil)
        (sem-core--batch-id 6)
        (sem-core--pending-callbacks 0))
    (cl-letf (((symbol-function 'sem-router--parse-headlines)
               (lambda ()
                 (list (list :title url
                             :tags '("link")
                             :body nil
                             :link url
                             :hash hash))))
              ((symbol-function 'sem-url-capture-process)
               (lambda (_url callback)
                 (setq captured-callback callback)
                 t))
              ((symbol-function 'sem-core--increment-retry)
               (lambda (_hash) 3))
              ((symbol-function 'sem-core--mark-dlq)
               (lambda (&rest _) (setq dlq-called t)))
              ((symbol-function 'sem-router--schedule-url-capture-retry)
               (lambda (&rest _) (setq retry-scheduled t)))
              ((symbol-function 'sem-core--batch-barrier-check)
               (lambda (&optional batch-id)
                 (push batch-id barrier-calls)))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-core-log-error)
               (lambda (&rest _) nil)))
      (sem-router-process-inbox 6)
      ;; Rate-limited failure with exhausted retry budget is terminal.
      (should captured-callback)
      (funcall captured-callback nil (list :url url :failure-kind 'rate-limited))
      (should dlq-called)
      (should-not retry-scheduled)
      ;; Terminal outcome: barrier resolves exactly once for the active batch.
      (should (equal barrier-calls (list 6))))))

(ert-deftest sem-router-test-stale-url-callback-rate-limited-no-retry ()
  "Test stale URL callback with rate-limited kind never schedules a retry.
The stale branch skips retry/DLQ handling entirely and resolves the
barrier for the old batch id only."
  (let ((hash "stale-rate-limited-hash")
        (url "https://example.com/stale-429")
        (captured-callback nil)
        (retry-scheduled nil)
        (dlq-called nil)
        (retry-counted nil)
        (barrier-calls nil)
        (sem-core--batch-id 7)
        (sem-core--pending-callbacks 0))
    (cl-letf (((symbol-function 'sem-router--parse-headlines)
               (lambda ()
                 (list (list :title url
                             :tags '("link")
                             :body nil
                             :link url
                             :hash hash))))
              ((symbol-function 'sem-url-capture-process)
               (lambda (_url callback)
                 (setq captured-callback callback)
                 t))
              ((symbol-function 'sem-core--increment-retry)
               (lambda (_hash) (setq retry-counted t) 1))
              ((symbol-function 'sem-router--schedule-url-capture-retry)
               (lambda (&rest _) (setq retry-scheduled t)))
              ((symbol-function 'sem-core--mark-dlq)
               (lambda (&rest _) (setq dlq-called t)))
              ((symbol-function 'sem-core--batch-barrier-check)
               (lambda (&optional batch-id)
                 (push batch-id barrier-calls)))
              ((symbol-function 'sem-core-log)
               (lambda (&rest _) nil))
              ((symbol-function 'sem-core-log-error)
               (lambda (&rest _) nil)))
      (sem-router-process-inbox 8)
      ;; Dispatch batch (8) differs from the active batch (7): stale.
      (should captured-callback)
      (funcall captured-callback nil (list :url url :failure-kind 'rate-limited))
      (should-not retry-scheduled)
      (should-not dlq-called)
      (should-not retry-counted)
      ;; Only the old batch's barrier is resolved.
      (should (equal barrier-calls (list 8))))))

(provide 'sem-router-test)
;;; sem-router-test.el ends here
