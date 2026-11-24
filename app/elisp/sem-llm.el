;;; sem-llm.el --- LLM integration wrapper -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; This module wraps gptel-request with a standard callback interface.
;; All LLM calls must go through this module - no direct gptel-request calls.
;;
;; The wrapper normalizes gptel's callback contract for callers: under a
;; streaming backend gptel invokes the callback repeatedly with partial
;; chunks, reasoning conses, and terminal sentinels; this module accumulates
;; the content and delivers exactly one final response (or nil) per request.

;;; Code:

(require 'gptel)
(require 'sem-core)

;;; LLM Request Wrapper

(defun sem-llm--empty-string-p (value)
  "Return non-nil when VALUE is nil or empty after trim."
  (or (null value)
      (and (stringp value)
           (string-empty-p (string-trim value)))))

;;; Provider Configuration

(defconst sem-llm-providers
  '(("deepseek" :key-env "DEEPSEEK_API_KEY" :default-model "deepseek-flash"
     :model-env nil :weak-model-env nil)
    ("openrouter" :key-env "OPENROUTER_KEY" :default-model nil
     :model-env "OPENROUTER_MODEL" :weak-model-env "OPENROUTER_WEAK_MODEL"))
  "Supported LLM providers and their environment conventions.
:key-env names the provider-specific API key variable (`LLM_API_KEY' takes
precedence).  :model-env and :weak-model-env are legacy model variables
consulted after `LLM_MODEL' / `LLM_WEAK_MODEL'.  :default-model is used
when no model variable is set.")

(defconst sem-llm-reasoning-efforts '("none" "low" "high" "max")
  "Accepted reasoning effort levels; `none' disables thinking.")

(defun sem-llm--env (name)
  "Return the trimmed value of environment variable NAME, or nil when blank."
  (let ((value (getenv name)))
    (unless (sem-llm--empty-string-p value)
      (string-trim value))))

(defun sem-llm-provider ()
  "Return the configured LLM provider name.
Reads `LLM_PROVIDER' at call time.  When unset, an existing OpenRouter-only
configuration (`OPENROUTER_KEY' or `OPENROUTER_MODEL' without
`DEEPSEEK_API_KEY') keeps using OpenRouter; otherwise DeepSeek is used.
Signals an error for an unknown provider."
  (let ((provider (downcase
                   (or (sem-llm--env "LLM_PROVIDER")
                       (if (and (not (sem-llm--env "DEEPSEEK_API_KEY"))
                                (or (sem-llm--env "OPENROUTER_KEY")
                                    (sem-llm--env "OPENROUTER_MODEL")))
                           "openrouter"
                         "deepseek")))))
    (unless (assoc provider sem-llm-providers)
      (error "Unsupported LLM_PROVIDER: %s" provider))
    provider))

(defun sem-llm--provider-config (&optional provider)
  "Return the config plist for PROVIDER (default: `sem-llm-provider')."
  (cdr (assoc (or provider (sem-llm-provider)) sem-llm-providers)))

(defun sem-llm-api-key ()
  "Return the API key for the configured provider, or nil when unset.
`LLM_API_KEY' takes precedence over the provider-specific variable."
  (or (sem-llm--env "LLM_API_KEY")
      (sem-llm--env (plist-get (sem-llm--provider-config) :key-env))))

(defun sem-llm--configured-model (generic-env config-key)
  "Return the model from GENERIC-ENV or the provider's CONFIG-KEY variable."
  (or (sem-llm--env generic-env)
      (let ((legacy-env (plist-get (sem-llm--provider-config) config-key)))
        (and legacy-env (sem-llm--env legacy-env)))))

(defun sem-llm--reasoning-effort-for-tier (tier)
  "Return the reasoning effort string for TIER.
Weak tier reads `LLM_WEAK_REASONING_EFFORT', medium reads
`LLM_REASONING_EFFORT'.  Both default to \"none\" (thinking disabled):
these pipelines are bounded transformations where minutes of reasoning add
latency without improving the result.  Unknown values fall back to none."
  (let* ((raw (sem-llm--env (if (eq tier 'weak)
                                "LLM_WEAK_REASONING_EFFORT"
                              "LLM_REASONING_EFFORT")))
         (effort (and raw (downcase raw))))
    (if (member effort sem-llm-reasoning-efforts) effort "none")))

(defun sem-llm--request-params-for-tier (tier)
  "Return provider request parameters controlling reasoning for TIER.
The plist is merged into the request body by gptel."
  (let ((effort (sem-llm--reasoning-effort-for-tier tier)))
    (pcase (sem-llm-provider)
      ("deepseek"
       (if (string= effort "none")
           '(:thinking (:type "disabled"))
         (list :thinking '(:type "enabled") :reasoning_effort effort)))
      ("openrouter"
       (if (string= effort "none")
           '(:reasoning (:exclude t))
         (list :reasoning (list :effort effort :exclude t)))))))

(defun sem-llm--resolve-model-for-tier (&optional tier)
  "Resolve concrete model identifier for TIER.
TIER accepts symbols `weak' or `medium'. Any other value defaults to `medium'.
The medium model comes from `LLM_MODEL', then the provider's legacy model
variable (`OPENROUTER_MODEL'), then the provider default.  Weak tier uses
`LLM_WEAK_MODEL' (or `OPENROUTER_WEAK_MODEL') and falls back to the medium
model when unset or empty.

Returns a plist with keys :tier, :model, and :weak-fallback."
  (let* ((requested-tier (if (eq tier 'weak) 'weak 'medium))
         (medium-model (or (sem-llm--configured-model "LLM_MODEL" :model-env)
                           (plist-get (sem-llm--provider-config) :default-model)))
         (weak-model (sem-llm--configured-model "LLM_WEAK_MODEL" :weak-model-env))
         (weak-fallback nil)
         resolved-model)
    (when (sem-llm--empty-string-p medium-model)
      (error "LLM_MODEL environment variable is not set or empty"))
    (setq resolved-model
          (if (eq requested-tier 'weak)
              (if (sem-llm--empty-string-p weak-model)
                  (progn
                    (setq weak-fallback t)
                    medium-model)
                weak-model)
            medium-model))
    (list :tier requested-tier :model resolved-model :weak-fallback weak-fallback)))

(defun sem-llm--make-response-handler (prompt callback context)
  "Return a gptel response handler that normalizes streaming delivery.

The returned handler implements gptel's streaming callback contract:
gptel invokes it repeatedly with partial string chunks, `(reasoning . TEXT)'
conses, and terminal sentinels (`t' on stream success, `nil' on failure).
The handler accumulates content chunks and invokes CALLBACK exactly once
per request with the final response text (a string) or `nil'.  Under a
non-streaming backend the single complete string is delivered directly.

CALLBACK is a function of (RESPONSE INFO CONTEXT) where RESPONSE is the
final text or nil, INFO is the gptel plist passed through, and CONTEXT is
the caller context passed through.  PROMPT is retained for error logging."
  (let ((acc nil)
        (streaming nil)
        (delivered nil))
    (lambda (response info)
      (condition-case cb-err
          (progn
            (when (plist-get info :stream)
              (setq streaming t))
            (cond
             ;; Once-only delivery guard: later events are anomalies.
             (delivered
              (sem-core-log "llm" "RESPONSE" "SKIP"
                            (format "Ignoring callback event after final delivery: %s"
                                    (type-of response))
                            nil))
             ;; Failure sentinel: deliver nil with the transport cause preserved.
             ((null response)
              (let ((cause (or (plist-get info :error) "Empty response")))
                (setq delivered t)
                (sem-core-log-error "llm" "ERROR"
                                    (format "LLM request failed: %s" cause)
                                    prompt
                                    nil)
                (funcall callback nil (list :error cause) context)))
             ;; Success sentinel: deliver accumulated text, nil when empty.
             ((eq response t)
              (setq streaming t)
              (setq delivered t)
              (if (and acc (not (string-empty-p acc)))
                  (progn
                    (sem-core-log "llm" "RESPONSE" "OK"
                                  (format "Response length: %d chars" (length acc))
                                  nil)
                    (funcall callback acc info context))
                (let ((cause (or (plist-get info :error) "Empty response")))
                  (sem-core-log-error "llm" "ERROR"
                                      (format "LLM request failed: %s" cause)
                                      prompt
                                      nil)
                  (funcall callback nil (list :error cause) context))))
             ;; Reasoning conses are gptel-internal and never delivered.
             ((and (consp response) (eq (car response) 'reasoning))
              (sem-core-log "llm" "REASONING" "OK"
                            (if (stringp (cdr response))
                                (format "Received reasoning chunk (%d chars); withheld from caller"
                                        (length (cdr response)))
                              "Received reasoning block end marker; withheld from caller")
                            nil))
             ;; String chunks accumulate under streaming; deliver directly otherwise.
             ((stringp response)
              (if streaming
                  (setq acc (concat acc response))
                (setq delivered t)
                (sem-core-log "llm" "RESPONSE" "OK"
                              (format "Response length: %d chars" (length response))
                              nil)
                (funcall callback response info context)))
             ;; Any other value shape is a protocol anomaly; skip it.
             (t
              (sem-core-log "llm" "RESPONSE" "SKIP"
                            (format "Ignoring unexpected callback value of type %s"
                                    (type-of response))
                            nil))))
        (error
         (sem-core-log-error "llm" "ERROR"
                             (format "Callback error: %s"
                                     (error-message-string cb-err))
                             prompt
                             (when (stringp response) response)))))))

(defun sem-llm-rate-limit-p (api-error)
  "Return non-nil when API-ERROR reports an HTTP 429 rate limit.
API-ERROR is the failure cause from the LLM layer: either a gptel error
plist carrying an :code field, or a plain string.  Rate limits are
treated as transient and retried in-process with a backoff delay."
  (cond
   ((and (listp api-error) (plist-member api-error :code))
    (eq (plist-get api-error :code) 429))
   ((stringp api-error)
    (and (string-match-p "429\\|rate.limit" api-error) t))
   (t nil)))

(defun sem-llm-rate-limit-retry-delay (attempt)
  "Return the backoff delay in seconds before rate-limit retry ATTEMPT.
ATTEMPT is the 1-based retry attempt number.  The base delay is read from
SEM_TASK_RATE_LIMIT_RETRY_DELAY at call time (default 20 seconds) and
doubles with each attempt, capped at 300 seconds."
  (let* ((raw (getenv "SEM_TASK_RATE_LIMIT_RETRY_DELAY"))
         (base (if (and raw (not (string-empty-p raw)))
                   (string-to-number raw)
                 20)))
    (max 1 (min (* base (expt 2 (max 0 (1- attempt)))) 300))))

(defun sem-llm-request-timeout-seconds ()
  "Return the per-request watchdog timeout in seconds.
Reads `SEM_LLM_REQUEST_TIMEOUT_SECONDS' at call time; defaults to 300.
A request whose stream produces no callback event within this window is
failed with a timeout cause so callers and batch accounting can proceed.
The watchdog is cancelled by the first streamed callback event, so this
bounds time-to-first-token, not total generation time."
  (let* ((raw (getenv "SEM_LLM_REQUEST_TIMEOUT_SECONDS"))
         (parsed (and raw (string-match-p "^[0-9]+$" raw)
                      (string-to-number raw))))
    (if (and (integerp parsed) (> parsed 0))
        parsed
      300)))

(defun sem-llm-request (prompt system-prompt callback &optional context tier)
  "Request LLM with PROMPT and SYSTEM-PROMPT.

 CALLBACK is a function of (response info context) where:
   - RESPONSE is the LLM response text (or nil on error)
   - INFO is a plist with :status, :error, :tokens, etc.
   - CONTEXT is the optional context passed through

 CALLBACK is invoked exactly once per request with the final response,
 regardless of whether the gptel backend streams.  Retry-vs-DLQ policy
 remains with caller modules: on failure RESPONSE is nil and INFO carries
 the underlying failure cause under :error.

This wrapper handles:
- condition-case wrapping for all callbacks
- Normalization of gptel streaming callback events
- Logging via sem-core-log on success/failure"
  (let* ((prompt-length (length prompt))
         (token-estimate (floor (length prompt) 4))
         (resolution (sem-llm--resolve-model-for-tier tier))
         (resolved-tier (plist-get resolution :tier))
         (resolved-model (plist-get resolution :model))
         (weak-fallback (plist-get resolution :weak-fallback)))
    (sem-core-log "llm" "REQUEST" "OK"
                  (format "Prompt length: %d chars, token estimate: %d, tier=%s, model=%s, reasoning=%s%s"
                          prompt-length token-estimate resolved-tier resolved-model
                          (sem-llm--reasoning-effort-for-tier resolved-tier)
                          (if weak-fallback " (weak->medium fallback)" ""))
                  nil)
    (let* ((timeout-seconds (sem-llm-request-timeout-seconds))
           (timeout-timer nil)
           (handler (sem-llm--make-response-handler prompt callback context))
           (guarded-handler
            (lambda (response info)
              "Cancel the watchdog on the first callback event, then delegate.
The response handler's once-only delivery guard ignores later events,
so a late response after a timeout is discarded."
              (when timeout-timer
                (cancel-timer timeout-timer)
                (setq timeout-timer nil))
              (funcall handler response info))))
      (setq timeout-timer
            (run-at-time
             timeout-seconds nil
             (lambda ()
               (message "SEM: LLM request timed out after %ds" timeout-seconds)
               (funcall guarded-handler
                        nil
                        (list :error (format "Request timed out after %ds"
                                             timeout-seconds))))))
      (condition-case err
          ;; gptel copies `gptel--request-params' into the request when
          ;; `gptel-request' is called, so a dynamic binding applies the
          ;; tier's reasoning settings to this request only.
          (let ((gptel-model (intern resolved-model))
                (gptel--request-params (sem-llm--request-params-for-tier resolved-tier)))
            (gptel-request
                prompt
              :system system-prompt
              :callback guarded-handler))
        (error
         (when timeout-timer
           (cancel-timer timeout-timer)
           (setq timeout-timer nil))
         (sem-core-log-error "llm" "ERROR"
                             (error-message-string err)
                             prompt
                             nil)
         (funcall callback nil (list :error (error-message-string err)) context))))))

(provide 'sem-llm)
;;; sem-llm.el ends here
