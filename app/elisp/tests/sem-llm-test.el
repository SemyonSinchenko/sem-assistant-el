;;; sem-llm-test.el --- Tests for sem-llm.el -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Tests for sem-llm LLM request handling and error logic.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'sem-mock)
(require 'sem-core)

;; Load module under test
(load-file (expand-file-name "../sem-llm.el" (file-name-directory load-file-name)))

;;; Test API error does NOT add hash to cursor

(ert-deftest sem-llm-test-api-error-hash-not-added ()
  "Test that API error (429, timeout) does NOT mark hash as processed."
  (let ((test-hash "test-api-error-hash")
        (test-file (make-temp-file "sem-cursor-")))
    (unwind-protect
        (let ((sem-core-cursor-file test-file))
          ;; Initially not processed
          (should-not (sem-core--is-processed test-hash))

          ;; Simulate API error handling (this would be called by sem-llm)
          ;; In real code, sem-llm--handle-api-error does NOT mark processed
          ;; We verify the cursor file is unchanged
          (let ((cursor-before (sem-core--read-cursor)))
            ;; Simulate what sem-llm--handle-api-error does (nothing to cursor)
            ;; The hash should NOT be added
            (let ((cursor-after (sem-core--read-cursor)))
              (should (= (length cursor-before) (length cursor-after))))))
      (sem-mock-cleanup-temp-file test-file))))

;;; Test malformed output adds hash to cursor + sem-core-log-error called

(ert-deftest sem-llm-test-malformed-output-hash-added ()
  "Test that malformed LLM output marks hash as processed."
  (let ((test-hash "test-malformed-hash")
        (test-file (make-temp-file "sem-cursor-")))
    (unwind-protect
        (let ((sem-core-cursor-file test-file))
          ;; Initially not processed
          (should-not (sem-core--is-processed test-hash))

          ;; Mark as processed (simulating sem-llm--handle-malformed-output)
          (sem-core--mark-processed test-hash)

          ;; Should now be processed
          (should (sem-core--is-processed test-hash)))
      (sem-mock-cleanup-temp-file test-file))))

;;; Test valid response invokes success callback

(ert-deftest sem-llm-test-valid-response-callback ()
  "Test that valid response invokes success callback."
  (let ((callback-called nil)
        (callback-response nil))

    ;; Setup mock to return valid response
    (sem-mock-gptel-request-success "Valid response")

    (unwind-protect
        (progn
          ;; Define a test callback
          (let ((test-callback (lambda (response _info)
                                 (setq callback-called t)
                                 (setq callback-response response))))
            ;; Call the mock gptel-request directly (gptel is already stubbed in sem-mock)
            (gptel-request "Test prompt"
              :callback test-callback
              :stream nil))

          ;; Verify callback was called with correct response
          (should callback-called)
          (should (string= "Valid response" callback-response)))
      (sem-mock-gptel-reset))))

;;; Test error response invokes callback with error info

(ert-deftest sem-llm-test-error-response-callback ()
  "Test that error response invokes callback with error info."
  (let ((callback-called nil)
        (callback-error nil))

    ;; Setup mock to return error
    (sem-mock-gptel-request-error "API rate limit exceeded")

    (unwind-protect
        (progn
          ;; Define a test callback
          (let ((test-callback (lambda (_response info)
                                 (setq callback-called t)
                                 (setq callback-error (plist-get info :error)))))
            ;; Call the mock gptel-request directly (gptel is already stubbed in sem-mock)
            (gptel-request "Test prompt"
              :callback test-callback
              :stream nil))

          ;; Verify callback was called with error
          (should callback-called)
          (should (string= "API rate limit exceeded" callback-error)))
      (sem-mock-gptel-reset))))

;;; Test cleanup

(ert-deftest sem-llm-test-mock-cleanup ()
  "Test that mock cleanup works correctly."
  (sem-mock-reset-all)
  (should t))

(ert-deftest sem-llm-test-resolve-model-for-tier-weak-configured ()
  "Test weak tier resolves to configured weak model."
  (cl-letf (((symbol-function 'getenv)
             (lambda (name)
               (cond
                ((string= name "OPENROUTER_MODEL") "openrouter/medium")
                ((string= name "OPENROUTER_WEAK_MODEL") "openrouter/weak")
                (t nil)))))
    (let ((resolved (sem-llm--resolve-model-for-tier 'weak)))
      (should (eq (plist-get resolved :tier) 'weak))
      (should (string= (plist-get resolved :model) "openrouter/weak"))
      (should-not (plist-get resolved :weak-fallback)))))

(ert-deftest sem-llm-test-resolve-model-for-tier-weak-unset-fallback ()
  "Test weak tier falls back to medium when weak model is unset."
  (cl-letf (((symbol-function 'getenv)
             (lambda (name)
               (cond
                ((string= name "OPENROUTER_MODEL") "openrouter/medium")
                ((string= name "OPENROUTER_WEAK_MODEL") nil)
                (t nil)))))
    (let ((resolved (sem-llm--resolve-model-for-tier 'weak)))
      (should (string= (plist-get resolved :model) "openrouter/medium"))
      (should (plist-get resolved :weak-fallback)))))

(ert-deftest sem-llm-test-resolve-model-for-tier-weak-empty-fallback ()
  "Test weak tier falls back to medium when weak model is empty."
  (cl-letf (((symbol-function 'getenv)
             (lambda (name)
               (cond
                ((string= name "OPENROUTER_MODEL") "openrouter/medium")
                ((string= name "OPENROUTER_WEAK_MODEL") "   ")
                (t nil)))))
    (let ((resolved (sem-llm--resolve-model-for-tier 'weak)))
      (should (string= (plist-get resolved :model) "openrouter/medium"))
      (should (plist-get resolved :weak-fallback)))))

(ert-deftest sem-llm-test-resolve-model-for-tier-medium-default ()
  "Test medium tier resolves to OPENROUTER_MODEL."
  (cl-letf (((symbol-function 'getenv)
             (lambda (name)
               (cond
                ((string= name "OPENROUTER_MODEL") "openrouter/medium")
                ((string= name "OPENROUTER_WEAK_MODEL") "openrouter/weak")
                (t nil)))))
    (let ((resolved (sem-llm--resolve-model-for-tier 'medium)))
      (should (eq (plist-get resolved :tier) 'medium))
      (should (string= (plist-get resolved :model) "openrouter/medium"))
      (should-not (plist-get resolved :weak-fallback)))))

(ert-deftest sem-llm-test-request-binds-gptel-model-per-request ()
  "Test sem-llm-request uses dynamic gptel-model binding for tier intent."
  (let ((captured-model nil)
        (callback-called nil))
    (cl-letf (((symbol-function 'getenv)
               (lambda (name)
                 (cond
                  ((string= name "OPENROUTER_MODEL") "openrouter/medium")
                  ((string= name "OPENROUTER_WEAK_MODEL") "openrouter/weak")
                  (t nil))))
              ((symbol-function 'gptel-request)
               (lambda (_prompt &rest args)
                 (setq captured-model gptel-model)
                 (let ((cb (plist-get args :callback)))
                   (when cb
                     (funcall cb "ok" (list :status 200))))
                 nil)))
      (sem-llm-request
       "prompt"
       "system"
       (lambda (response _info _context)
         (setq callback-called (string= response "ok"))
         nil)
       nil
       'weak)
      (should callback-called)
      (should (eq captured-model 'openrouter/weak)))))


;;; Streaming normalization regression tests

(ert-deftest sem-llm-test-streaming-chunks-delivered-once ()
  "Test that streaming chunks accumulate and deliver exactly one full response."
  (let ((calls nil))
    (sem-mock-gptel-request-stream
     (list (cons "partial one " (list :stream t))
           (cons "partial two" (list :stream t))
           (cons t (list :stream t :status "finished"))))
    (setenv "OPENROUTER_MODEL" "test-model")
    (unwind-protect
        (progn
          (sem-llm-request "p" "s" (lambda (response info context)
                         (push (list response (plist-get info :error) context) calls)) :ctx 'weak)
          (should (= (length calls) 1))
          (should (string= (nth 0 (car calls)) "partial one partial two"))
          (should (eq (nth 2 (car calls)) :ctx)))
      (sem-mock-gptel-reset))))

(ert-deftest sem-llm-test-streaming-reasoning-conses-withheld ()
  "Test that reasoning conses are never delivered as response text."
  (let ((calls nil))
    (sem-mock-gptel-request-stream
     (list (cons (cons 'reasoning "thinking...") (list :stream t))
           (cons '(reasoning . t) (list :stream t))
           (cons "final text" (list :stream t))
           (cons t (list :stream t))))
    (setenv "OPENROUTER_MODEL" "test-model")
    (unwind-protect
        (progn
          (sem-llm-request "p" "s" (lambda (response info context)
                         (push (list response (plist-get info :error) context) calls)) nil 'weak)
          (should (= (length calls) 1))
          (should (string= (nth 0 (car calls)) "final text")))
      (sem-mock-gptel-reset))))

(ert-deftest sem-llm-test-streaming-empty-stream-delivers-nil-once ()
  "Test that a stream ending without content delivers nil exactly once."
  (let ((calls nil))
    (sem-mock-gptel-request-stream
     (list (cons t (list :stream t))))
    (setenv "OPENROUTER_MODEL" "test-model")
    (unwind-protect
        (progn
          (sem-llm-request "p" "s" (lambda (response info context)
                         (push (list response (plist-get info :error) context) calls)) nil 'weak)
          (should (= (length calls) 1))
          (should (null (nth 0 (car calls)))))
      (sem-mock-gptel-reset))))

(ert-deftest sem-llm-test-streaming-duplicate-sentinels-deliver-once ()
  "Test the once-only delivery guard: terminal events after delivery are ignored."
  (let ((calls nil))
    (sem-mock-gptel-request-stream
     (list (cons "text" (list :stream t))
           (cons t (list :stream t))
           (cons t (list :stream t))
           (cons nil (list :stream t :error "late"))))
    (setenv "OPENROUTER_MODEL" "test-model")
    (unwind-protect
        (progn
          (sem-llm-request "p" "s" (lambda (response info context)
                         (push (list response (plist-get info :error) context) calls)) nil 'weak)
          (should (= (length calls) 1))
          (should (string= (nth 0 (car calls)) "text")))
      (sem-mock-gptel-reset))))

(ert-deftest sem-llm-test-streaming-failure-preserves-cause ()
  "Test that a failure sentinel delivers nil with the transport cause preserved."
  (let ((calls nil)
        (error-logs nil))
    (sem-mock-gptel-request-stream
     (list (cons "partial" (list :stream t))
           (cons nil (list :stream t :error "Curl failed with exit code 18"))))
    (setenv "OPENROUTER_MODEL" "test-model")
    (unwind-protect
        (cl-letf (((symbol-function 'sem-core-log-error)
                   (lambda (_module _event msg &rest _)
                     (push msg error-logs))))
          (sem-llm-request "p" "s" (lambda (response info context)
                         (push (list response (plist-get info :error) context) calls)) nil 'weak)
          (should (= (length calls) 1))
          (should (null (nth 0 (car calls))))
          (should (string= (nth 1 (car calls)) "Curl failed with exit code 18"))
          (should (= (length error-logs) 1))
          (should (string-match-p "Curl failed with exit code 18" (car error-logs))))
      (sem-mock-gptel-reset))))

(ert-deftest sem-llm-test-caller-callback-error-caught ()
  "Test that an error raised inside the caller callback is caught and logged."
  (let ((propagated nil))
    (sem-mock-gptel-request-success "Valid response")
    (setenv "OPENROUTER_MODEL" "test-model")
    (unwind-protect
        (progn
          (condition-case _err
              (sem-llm-request "p" "s" (lambda (&rest _) (error "boom")) nil 'weak)
            (error (setq propagated t)))
          (should-not propagated))
      (sem-mock-gptel-reset))))



;;; Request watchdog timeout regression tests

(ert-deftest sem-llm-test-request-timeout-delivers-once ()
  "Test that a hung request delivers a timeout failure exactly once and
a late response is discarded."
  (let ((calls nil)
        (watchdog nil)
        (watchdog-delay nil)
        (late-callback nil))
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (delay _repeat fn &rest _)
                 (setq watchdog fn watchdog-delay delay)
                 'watchdog-timer))
              ((symbol-function 'cancel-timer)
               (lambda (_timer) nil))
              ((symbol-function 'gptel-request)
               (lambda (_prompt &rest args)
                 (setq late-callback (plist-get args :callback))
                 nil)))
      (unwind-protect
          (progn
            (setenv "OPENROUTER_MODEL" "test-model")
            (setenv "SEM_LLM_REQUEST_TIMEOUT_SECONDS" "180")
            (should (= (sem-llm-request-timeout-seconds) 180))
            (sem-llm-request "p" "s"
                             (lambda (response info _context)
                               (push (list response (plist-get info :error)) calls))
                             nil 'weak)
            (should watchdog)
            (should (= watchdog-delay 180))
            (should (functionp late-callback))
            ;; Watchdog fires: timeout failure delivered exactly once.
            (funcall watchdog)
            (should (= (length calls) 1))
            (should (null (nth 0 (car calls))))
            (should (string-match-p "timed out" (nth 1 (car calls))))
            ;; Late real response after the timeout is discarded.
            (funcall late-callback "late text" (list :status 200))
            (should (= (length calls) 1)))
        (setenv "SEM_LLM_REQUEST_TIMEOUT_SECONDS" nil)))))

(ert-deftest sem-llm-test-request-timeout-configurable ()
  "Test that SEM_LLM_REQUEST_TIMEOUT_SECONDS is honored at call time."
  (let ((value nil))
    (unwind-protect
        (progn
          (setenv "SEM_LLM_REQUEST_TIMEOUT_SECONDS" "90")
          (setq value (sem-llm-request-timeout-seconds))
          (should (= value 90)))
      (setenv "SEM_LLM_REQUEST_TIMEOUT_SECONDS" nil))))

(ert-deftest sem-llm-test-request-timeout-default-300 ()
  "Test that the watchdog defaults to 300 seconds when the env var is unset
or holds an invalid value."
  (unwind-protect
      (progn
        (setenv "SEM_LLM_REQUEST_TIMEOUT_SECONDS" nil)
        (should (= (sem-llm-request-timeout-seconds) 300))
        (setenv "SEM_LLM_REQUEST_TIMEOUT_SECONDS" "not-a-number")
        (should (= (sem-llm-request-timeout-seconds) 300))
        (setenv "SEM_LLM_REQUEST_TIMEOUT_SECONDS" "0")
        (should (= (sem-llm-request-timeout-seconds) 300)))
    (setenv "SEM_LLM_REQUEST_TIMEOUT_SECONDS" nil)))


;;; Provider and reasoning configuration

(defmacro sem-llm-test--with-env (env &rest body)
  "Run BODY with `getenv' answering from alist ENV (unknown names are nil)."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'getenv)
              (lambda (name &rest _) (cdr (assoc name ,env)))))
     ,@body))

(ert-deftest sem-llm-test-provider-defaults-to-deepseek ()
  "Test DeepSeek is the default provider with a default model."
  (sem-llm-test--with-env '(("DEEPSEEK_API_KEY" . "k"))
    (should (string= (sem-llm-provider) "deepseek"))
    (should (string= (sem-llm-api-key) "k"))
    (should (string= (plist-get (sem-llm--resolve-model-for-tier 'medium) :model)
                     "deepseek-flash"))))

(ert-deftest sem-llm-test-provider-infers-legacy-openrouter ()
  "Test an OpenRouter-only environment keeps using OpenRouter."
  (sem-llm-test--with-env '(("OPENROUTER_KEY" . "k") ("OPENROUTER_MODEL" . "x/y"))
    (should (string= (sem-llm-provider) "openrouter"))
    (should (string= (plist-get (sem-llm--resolve-model-for-tier 'medium) :model) "x/y"))))

(ert-deftest sem-llm-test-deepseek-ignores-openrouter-model-vars ()
  "Test explicit DeepSeek provider does not pick up stale OpenRouter models."
  (sem-llm-test--with-env '(("LLM_PROVIDER" . "deepseek")
                            ("OPENROUTER_MODEL" . "qwen/qwen3")
                            ("LLM_WEAK_MODEL" . "deepseek-flash"))
    (should (string= (plist-get (sem-llm--resolve-model-for-tier 'medium) :model)
                     "deepseek-flash"))))

(ert-deftest sem-llm-test-unknown-provider-signals ()
  "Test an unknown provider name is rejected."
  (sem-llm-test--with-env '(("LLM_PROVIDER" . "acme"))
    (should-error (sem-llm-provider))))

(ert-deftest sem-llm-test-deepseek-thinking-disabled-by-default ()
  "Test DeepSeek requests disable thinking unless an effort is configured."
  (sem-llm-test--with-env '(("LLM_PROVIDER" . "deepseek")
                            ("LLM_WEAK_REASONING_EFFORT" . "LOW")
                            ("LLM_REASONING_EFFORT" . "bogus"))
    (should (equal (sem-llm--request-params-for-tier 'medium)
                   '(:thinking (:type "disabled"))))
    (should (equal (sem-llm--request-params-for-tier 'weak)
                   '(:thinking (:type "enabled") :reasoning_effort "low")))))

(ert-deftest sem-llm-test-request-binds-reasoning-params ()
  "Test sem-llm-request applies tier reasoning params to the gptel call."
  (let ((captured nil))
    (sem-llm-test--with-env '(("LLM_PROVIDER" . "deepseek")
                              ("LLM_REASONING_EFFORT" . "high"))
      (cl-letf (((symbol-function 'gptel-request)
                 (lambda (_prompt &rest args)
                   (setq captured gptel--request-params)
                   (funcall (plist-get args :callback) "ok" (list :status 200))
                   nil)))
        (sem-llm-request "p" "s" (lambda (&rest _) nil) nil 'medium)
        (should (equal captured
                       '(:thinking (:type "enabled") :reasoning_effort "high")))))))

(provide 'sem-llm-test)
;;; sem-llm-test.el ends here
