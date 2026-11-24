;;; sem-async-test.el --- Tests for async LLM behavior -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Tests for verifying async behavior of LLM request handlers.
;; These tests ensure that:
;; 1. Functions return immediately without blocking
;; 2. Callbacks are invoked when LLM responses arrive
;; 3. Error handling works correctly in async context

;;; Code:

(require 'ert)
(require 'sem-llm)
(require 'sem-router)
(require 'sem-url-capture)
(require 'sem-rss)

;;; Test Helpers

(defvar sem-async-test--callback-called nil
  "Flag to track if callback was invoked.")

(defvar sem-async-test--callback-result nil
  "Store callback result for verification.")

(defun sem-async-test--reset ()
  "Reset test state."
  (setq sem-async-test--callback-called nil)
  (setq sem-async-test--callback-result nil))

(defun sem-async-test--callback (response info context)
  "Test callback that records invocation.
Called with RESPONSE, INFO (gptel response info), and CONTEXT."
  (setq sem-async-test--callback-called t)
  (setq sem-async-test--callback-result response))

(defun sem-async-test--callback-2arg (result context)
  "Test callback for 2-argument callbacks (success/context or filepath/context).
Called with RESULT and CONTEXT."
  (setq sem-async-test--callback-called t)
  (setq sem-async-test--callback-result result))

;;; sem-llm-request Tests

(ert-deftest sem-async-test-llm-request-returns-immediately ()
  "Test that sem-llm-request returns immediately (async)."
  (sem-async-test--reset)
  (let ((start-time (float-time))
        (result nil))
    ;; Mock gptel-request to not actually call the API
    (cl-letf (((symbol-function 'getenv)
               (lambda (name)
                 (if (string= name "OPENROUTER_MODEL") "openrouter/medium"
                   nil)))
              ((symbol-function 'gptel-request)
               (lambda (prompt &rest args)
                 ;; Don't call callback - just return nil immediately
                 nil)))
      (setq result (sem-llm-request "test prompt" "system" #'sem-async-test--callback))
      ;; Should return immediately (within milliseconds)
      (should (< (- (float-time) start-time) 0.1))
      ;; Should return nil (gptel-request returns nil immediately)
      (should (null result)))))

(ert-deftest sem-async-test-llm-request-callback-invoked ()
  "Test that sem-llm-request callback is invoked with response."
  (sem-async-test--reset)
  (let ((mock-response "Test LLM response")
        (mock-info '(:status 200)))
    ;; Mock gptel-request to immediately call the callback
    (cl-letf (((symbol-function 'getenv)
               (lambda (name)
                 (if (string= name "OPENROUTER_MODEL") "openrouter/medium"
                   nil)))
              ((symbol-function 'gptel-request)
               (lambda (prompt &rest args)
                 (let ((callback (plist-get args :callback)))
                   (when callback
                     (funcall callback mock-response mock-info)))
                 nil)))
      (sem-llm-request "test prompt" "system" #'sem-async-test--callback)
      ;; Callback should have been called
      (should sem-async-test--callback-called)
      ;; Callback should receive the response
      (should (equal sem-async-test--callback-result mock-response)))))

(ert-deftest sem-async-test-llm-request-error-handling ()
  "Test that sem-llm-request handles errors gracefully."
  (sem-async-test--reset)
  ;; Mock gptel-request to signal an error
  (cl-letf (((symbol-function 'getenv)
             (lambda (name)
               (if (string= name "OPENROUTER_MODEL") "openrouter/medium"
                 nil)))
            ((symbol-function 'gptel-request)
             (lambda (prompt &rest args)
               (error "Mock API error"))))
    ;; Should not signal error - should return nil and call callback with error
    (let ((result (sem-llm-request "test" "system" #'sem-async-test--callback)))
      (should (null result))
      ;; Callback should be called with nil (error case)
      (should sem-async-test--callback-called)
      (should (null sem-async-test--callback-result)))))

;;; sem-router--route-to-task-llm Tests

(ert-deftest sem-async-test-router-returns-immediately ()
  "Test that sem-router--route-to-task-llm returns immediately."
  (sem-async-test--reset)
  (let ((start-time (float-time))
        (headline '(:title "Test task" :tags ("task") :hash "abc123")))
    ;; Mock sem-llm-request to return immediately
    (cl-letf (((symbol-function 'sem-llm-request)
               (lambda (prompt system callback context &optional _tier)
                  ;; Don't call callback - just return
                  nil)))
      (let ((result (sem-router--route-to-task-llm headline #'sem-async-test--callback)))
        ;; Should return immediately
        (should (< (- (float-time) start-time) 0.1))
        ;; Should return t (async started)
        (should (eq result t))))))

(ert-deftest sem-async-test-router-callback-on-success ()
  "Test that router callback is invoked on successful LLM response."
  (sem-async-test--reset)
  (let ((headline '(:title "Test task" :tags ("task") :hash "abc123"))
        (mock-response "* TODO Test task\n:PROPERTIES:\n:ID: test-id\n:FILETAGS: :work:\n:END:\nTest description"))
    ;; Mock sem-llm-request to simulate success
    (cl-letf (((symbol-function 'sem-llm-request)
               (lambda (prompt system callback context &optional _tier)
                  (funcall callback mock-response '(:status 200) context)
                  nil))
              ((symbol-function 'sem-router--validate-task-response)
               (lambda (response _injected-id) t))
              ((symbol-function 'sem-router--write-task-to-file)
                (lambda (response &optional temp-file expected-batch-id) t))
              ((symbol-function 'sem-router--mark-processed)
               (lambda (hash) nil)))
      (sem-router--route-to-task-llm headline #'sem-async-test--callback-2arg)
      ;; Callback should be called with success
      (should sem-async-test--callback-called)
      (should (eq sem-async-test--callback-result t)))))

(ert-deftest sem-async-test-router-callback-on-error ()
  "Test that router callback is invoked on LLM error."
  (sem-async-test--reset)
  (let ((headline '(:title "Test task" :tags ("task") :hash "abc123")))
    ;; Mock sem-llm-request to simulate API error
    (cl-letf (((symbol-function 'sem-llm-request)
               (lambda (prompt system callback context &optional _tier)
                  (funcall callback nil '(:error "API timeout") context)
                  nil)))
      (sem-router--route-to-task-llm headline #'sem-async-test--callback-2arg)
      ;; Callback should be called with nil (failure)
      (should sem-async-test--callback-called)
      (should (null sem-async-test--callback-result)))))

;;; sem-url-capture-process Tests

(ert-deftest sem-async-test-url-capture-returns-immediately ()
  "Test that sem-url-capture-process returns immediately."
  (sem-async-test--reset)
  (let ((start-time (float-time)))
    ;; Mock dependencies
    (cl-letf (((symbol-function 'sem-url-capture--fetch-url-async)
               (sem-mock-url-fetch-async (lambda (_url &optional _timeout) (list :content "Mock content"))))
              ((symbol-function 'sem-url-capture--sanitize-text)
               (lambda (text) "Sanitized"))
              ((symbol-function 'sem-security-sanitize-for-llm)
               (lambda (text) (cons "Tokenized" nil)))
              ((symbol-function 'sem-url-capture--get-umbrella-nodes)
               (lambda () nil))
              ((symbol-function 'sem-llm-request)
               (lambda (prompt system callback context &optional _tier) nil)))
      (let ((result (sem-url-capture-process "http://example.com" #'sem-async-test--callback-2arg)))
        ;; Should return immediately
        (should (< (- (float-time) start-time) 0.1))
        ;; Should return t (async started)
        (should (eq result t))))))

(ert-deftest sem-async-test-url-capture-callback ()
  "Test that URL capture callback receives filepath on success."
  (sem-async-test--reset)
  (let ((mock-filepath "/data/org-roam/org-files/20240101120000-test.org"))
    ;; Mock dependencies
    (cl-letf (((symbol-function 'sem-url-capture--fetch-url-async)
               (sem-mock-url-fetch-async (lambda (_url &optional _timeout) (list :content "Mock content"))))
              ((symbol-function 'sem-url-capture--sanitize-text)
               (lambda (text) "Sanitized"))
              ((symbol-function 'sem-security-sanitize-for-llm)
               (lambda (text) (cons "Tokenized" nil)))
              ((symbol-function 'sem-url-capture--get-umbrella-nodes)
               (lambda () nil))
              ((symbol-function 'sem-llm-request)
               (lambda (prompt system callback context &optional _tier)
                  (funcall callback "Mock LLM output" '(:status 200) context)
                  nil))
              ((symbol-function 'sem-security-sanitize-urls)
               (lambda (text) text))
              ((symbol-function 'sem-url-capture--validate-and-save)
               (lambda (_response _url &optional _masked) mock-filepath)))
      (sem-url-capture-process "http://example.com" #'sem-async-test--callback-2arg)
      ;; Callback should receive the filepath
      (should sem-async-test--callback-called)
      (should (equal sem-async-test--callback-result mock-filepath)))))

;;; sem-rss--generate-file Tests

(ert-deftest sem-async-test-rss-generate-returns-immediately ()
  "Test that sem-rss--generate-file returns immediately."
  (sem-async-test--reset)
  (let ((start-time (float-time)))
    ;; Mock sem-llm-request
    (cl-letf (((symbol-function 'sem-llm-request)
               (lambda (prompt system callback context &optional _tier) nil)))
      (let ((result (sem-rss--generate-file "/tmp/test.org" "prompt" "Test" 1 #'sem-async-test--callback-2arg)))
        ;; Should return immediately
        (should (< (- (float-time) start-time) 0.1))
        ;; Should return t (async started)
        (should (eq result t))))))

(ert-deftest sem-async-test-rss-generate-callback ()
  "Test that RSS generate callback is invoked with success status."
  (sem-async-test--reset)
  ;; Mock sem-llm-request to simulate success
  (cl-letf (((symbol-function 'sem-llm-request)
             (lambda (prompt system callback context &optional _tier)
                (funcall callback "* RSS Digest\nTest content" '(:status 200) context)
                nil))
            ((symbol-function 'sem-core-log)
             (lambda (&rest args) nil)))
    (sem-rss--generate-file "/tmp/test.org" "prompt" "Test" 1 #'sem-async-test--callback-2arg)
    ;; Callback should be called with success
    (should sem-async-test--callback-called)
    (should (eq sem-async-test--callback-result t))))

(ert-deftest sem-async-test-rss-generate-callback-on-error ()
  "Test that RSS generate callback is invoked with nil on error."
  (sem-async-test--reset)
  ;; Mock sem-llm-request to simulate API error
  (cl-letf (((symbol-function 'sem-llm-request)
             (lambda (prompt system callback context &optional _tier)
                (funcall callback nil '(:error "Internal server error") context)
                nil))
            ((symbol-function 'sem-core-log-error)
             (lambda (&rest args) nil)))
    (sem-rss--generate-file "/tmp/test.org" "prompt" "Test" 1 #'sem-async-test--callback-2arg)
    ;; Callback should be called with nil (failure)
    (should sem-async-test--callback-called)
    (should (null sem-async-test--callback-result))))

;;; Run Tests

(defun sem-async-test-run-all ()
  "Run all async tests."
  (interactive)
  (ert-run-tests-batch "^sem-async-test"))

(provide 'sem-async-test)
;;; sem-async-test.el ends here
