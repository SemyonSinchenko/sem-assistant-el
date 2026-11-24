;;; sem-url-capture.el --- URL capture for org-roam with LLM assistance -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; This module provides automated web article capture and integration into
;; org-roam. Ported from org-roam-url-catcher.el with all interactive
;; patterns stripped and replaced with non-interactive daemon-safe equivalents.
;;
;; The pipeline:
;; 1. Fetch URL content using trafilatura CLI
;; 2. Sanitize text for token efficiency
;; 3. Extract metadata (umbrella nodes) from org-roam database
;; 4. Build prompts for LLM
;; 5. Request LLM to generate org-roam node content
;; 6. Validate and save the generated content
;;
;; URL contract: persisted org-roam output keeps canonical `http://`/`https://`
;; URLs and never applies URL defanging.
;;
;; Entry point: sem-url-capture-process (callable from sem-router.el)

;;; Code:

(require 'org)
(require 'org-roam)
(require 'org-id)
(require 'sem-core)
(require 'sem-llm)
(require 'sem-paths)
(require 'sem-prompts)
(require 'sem-security)

;;; Constants

(defconst sem-url-capture-max-chars 40000
  "Maximum number of characters to send to LLM after sanitization.")

(defconst sem-url-capture-umbrella-tag "umbrella"
  "Tag used to identify umbrella (semantic hub) nodes in org-roam.")

(defconst sem-url-capture-timeout-seconds 300
  "Maximum wall-clock timeout in seconds for one URL capture attempt.")

;;; URL Fetching

(defun sem-url-capture--fetch-url (url &optional timeout-seconds)
  "Fetch content from URL using trafilatura CLI.

Uses `trafilatura -u URL --markdown --no-comments --fast` to extract
readable content. Returns a plist with:
- :content string on success
- :kind symbol (`timeout' or `error') on failure
- :message string describing the failure

Signals an error if trafilatura binary is not found."
  (unless (executable-find "trafilatura")
    (error "URL Catcher: trafilatura binary not found in PATH"))

  (let ((temp-buffer (generate-new-buffer " *trafilatura-temp*")))
    (unwind-protect
        (let* ((timeout-enabled (and timeout-seconds (> timeout-seconds 0) (executable-find "timeout")))
               (command (if timeout-enabled "timeout" "trafilatura"))
               (args (if timeout-enabled
                         (list (number-to-string (ceiling timeout-seconds))
                               "trafilatura" "-u" url "--markdown" "--no-comments" "--fast")
                       (list "-u" url "--markdown" "--no-comments" "--fast")))
               (exit-code
                (with-current-buffer temp-buffer
                  (apply #'call-process command nil temp-buffer nil args))))
          (cond
           ((and (numberp exit-code) (= exit-code 0))
            (list :content
                  (with-current-buffer temp-buffer
                    (buffer-substring-no-properties (point-min) (point-max)))))
           ((and timeout-enabled (= exit-code 124))
            (list :kind 'timeout
                  :message (format "trafilatura timed out after %ds"
                                   (ceiling timeout-seconds))))
           (t
            (list :kind 'error
                  :message (format "trafilatura failed exit=%d" exit-code)))))
      (when (buffer-live-p temp-buffer)
        (kill-buffer temp-buffer)))))

(defun sem-url-capture--fetch-url-async (url timeout-seconds callback)
  "Fetch content from URL with trafilatura without blocking Emacs.

Runs `trafilatura -u URL --markdown --no-comments --fast` as an
asynchronous subprocess, so the daemon keeps serving emacsclient requests
(cron jobs and the readiness watchdog) while a slow page is fetched.  The
process is killed after TIMEOUT-SECONDS.

CALLBACK is called exactly once with a plist in the same shape as
`sem-url-capture--fetch-url' returns: :content on success, or :kind
\(`timeout' or `error') and :message on failure.  Returns the value of
CALLBACK when it ran synchronously, t otherwise.

Signals an error if trafilatura binary is not found."
  (unless (executable-find "trafilatura")
    (error "URL Catcher: trafilatura binary not found in PATH"))
  (let* ((stdout (generate-new-buffer " *trafilatura*"))
         (stderr (generate-new-buffer " *trafilatura-stderr*"))
         (done nil)
         (timer nil)
         (proc nil)
         (finish
          (lambda (result)
            (unless done
              (setq done t)
              (when timer (cancel-timer timer))
              (ignore-errors (when (process-live-p proc) (delete-process proc)))
              (dolist (buf (list stdout stderr))
                (when (buffer-live-p buf) (kill-buffer buf)))
              (condition-case cb-err
                  (funcall callback result)
                (error
                 (sem-core-log-error "url-capture" "URL-CAPTURE"
                                     (format "Fetch callback error: %s"
                                             (error-message-string cb-err))
                                     url nil)))))))
    (setq proc
          (make-process
           :name "trafilatura"
           :buffer stdout
           :stderr stderr
           :command (list "trafilatura" "-u" url "--markdown" "--no-comments" "--fast")
           :connection-type 'pipe
           :noquery t
           :sentinel
           (lambda (process _event)
             (unless (process-live-p process)
               (let ((status (process-status process))
                     (code (process-exit-status process)))
                 (funcall finish
                          (if (and (eq status 'exit) (= code 0))
                              (list :content
                                    (with-current-buffer stdout
                                      (buffer-substring-no-properties
                                       (point-min) (point-max))))
                            (list :kind 'error
                                  :message (format "trafilatura failed (%s %s)"
                                                   status code)))))))))
    (when (and timeout-seconds (> timeout-seconds 0))
      (setq timer
            (run-at-time timeout-seconds nil
                         (lambda ()
                           (funcall finish
                                    (list :kind 'timeout
                                          :message (format "trafilatura timed out after %ds"
                                                           (ceiling timeout-seconds))))))))
    t))

(defun sem-url-capture--remaining-seconds (deadline)
  "Return remaining seconds until DEADLINE, or 0 when expired."
  (max 0.0 (float-time (time-subtract deadline (current-time)))))

(defun sem-url-capture--timeout-error-p (error-value)
  "Return non-nil when ERROR-VALUE describes a timeout condition."
  (let ((error-string (if error-value (downcase (format "%s" error-value)) "")))
    (or (string-match-p "timeout" error-string)
        (string-match-p "timed out" error-string))))

(defun sem-url-capture--log-timeout-fail (url stage)
  "Log timeout `FAIL' for URL at STAGE with explicit message."
  (sem-core-log "url-capture" "URL-CAPTURE" "FAIL"
                (format "Timeout after %ds at stage=%s url=%s"
                        sem-url-capture-timeout-seconds stage url)
                nil))

;;; Text Sanitization

(defun sem-url-capture--sanitize-text (raw-text)
  "Aggressively sanitize RAW-TEXT for maximum token efficiency.

Applies the following pipeline in order:
1. Remove lines containing only digits (e.g., code block line numbers).
2. Remove lines containing exactly one non-whitespace character.
3. Replace all newlines with a single space.
4. Replace multiple spaces/tabs with a single space.
5. Trim leading and trailing whitespace.
6. Truncate to `sem-url-capture-max-chars` limit.

Returns the sanitized string."
  (if (not raw-text)
      ""
    (let ((text raw-text))
      ;; Remove lines containing only digits
      (setq text (replace-regexp-in-string "^[ \t]*[0-9]+[ \t]*\n" "" text))
      ;; Remove lines containing exactly one non-whitespace character
      (setq text (replace-regexp-in-string "^[ \t]*[^ \t\n][ \t]*\n" "" text))
      ;; Replace all newlines with a single space
      (setq text (replace-regexp-in-string "\n" " " text))
      ;; Replace multiple spaces/tabs with a single space
      (setq text (replace-regexp-in-string "[ \t]+" " " text))
      ;; Trim leading and trailing whitespace
      (setq text (string-trim text))
      ;; Truncate to max chars limit
      (when (> (length text) sem-url-capture-max-chars)
        (setq text (substring text 0 sem-url-capture-max-chars)))
      text)))

;;; Metadata Extraction

(defun sem-url-capture--get-umbrella-nodes ()
  "Query org-roam database for nodes tagged with `sem-url-capture-umbrella-tag`.

Returns an alist mapping node titles to their UUIDs (IDs).
Returns nil if no umbrella nodes exist or on database error."
  (condition-case err
      (let ((rows (org-roam-db-query
                   [:select [nodes:title nodes:id]
                    :from nodes
                    :inner-join tags :on (= nodes:id tags:node_id)
                    :where (= tags:tag $s1)]
                   sem-url-capture-umbrella-tag)))
        (when rows
          (mapcar (lambda (row) (cons (car row) (cadr row))) rows)))
    (error
     (sem-core-log "url-capture" "URL-CAPTURE" "FAIL"
                   (format "Failed to query umbrella nodes: %s"
                           (error-message-string err))
                   nil)
     nil)))

;;; Prompt Generation

(defun sem-url-capture--build-system-prompt ()
  "Build the system prompt for LLM org-roam node generation.
Includes a comprehensive org-mode syntax cheat sheet to prevent markdown hallucinations.
Reads OUTPUT_LANGUAGE at call time with default \"English\" and appends as final line."
  (let* ((output-language (or (getenv "OUTPUT_LANGUAGE") "English"))
         (language-instruction (format "\n\nOUTPUT LANGUAGE: Write your entire response in %s. Do not use any other language." output-language)))
    (concat "You are a specialized Knowledge Management assistant. Your ONLY task is to output valid, raw `org-roam` node text based on the provided article.\n\n"
            sem-prompts-org-mode-cheat-sheet
            "\n\n=== RULES FOR THIS TASK ===\n"
            "1. NEVER wrap your overall response in markdown code blocks (e.g., do NOT start with ```org). Output raw text only.\n"
            "2. At the very top, include a property drawer with the provided ID.\n"
            "3. Below the property drawer, include:\n"
            "   `#+title: <Article Title>`\n"
            "   `#+ROAM_REFS: <Original URL>`\n"
            "   `#+filetags: :article:`\n"
            "4. Write a brief summary and bullet points extracting the core value of the article.\n"
            "5. When Umbrella Nodes are provided, include at least one explicit link to a provided node ID using: `[[id:GIVEN-ID][Title]]`.\n"
            "6. Structure the note with `* Summary` and `* Key Takeaways` sections.\n"
            "7. The first line of the `* Summary` section MUST be: `Source: [[ARTICLE_URL][ARTICLE_URL]]`"
            language-instruction)))

(defun sem-url-capture--make-slug (title)
  "Generate a URL-safe slug from TITLE for filename generation.

1. Downcase the title
2. Strip non-ASCII and non-alphanumeric characters (replace with `-`)
3. Trim leading/trailing hyphens
4. Truncate to 50 characters maximum

Returns the slug string."
  (let ((slug (downcase title)))
    ;; Strip non-ASCII and non-alphanumeric, replace with hyphen
    (setq slug (replace-regexp-in-string "[^a-z0-9]+" "-" slug))
    ;; Trim leading/trailing hyphens
    (setq slug (string-trim slug "\\`-+" "-+\\'"))
    ;; Truncate to 50 characters
    (when (> (length slug) 50)
      (setq slug (substring slug 0 50))
      ;; Trim again after truncation in case we cut off mid-word
      (setq slug (string-trim slug "-")))
    slug))

(defun sem-url-capture--build-user-prompt (url sanitized-text umbrella-nodes-alist)
  "Build the user prompt for LLM org-roam node generation.

URL is the original article URL.
SANITIZED-TEXT is the cleaned article content.
UMBRELLA-NODES-ALIST is an alist of (title . id) for semantic hubs.

Generates a new org-roam ID and includes it in the expected format section."
  (let ((new-id (org-id-new))
        (umbrella-section ""))

    ;; Build umbrella nodes mapping section if available
    (when (and umbrella-nodes-alist (not (null umbrella-nodes-alist)))
      (setq umbrella-section
            (concat "UMBRELLA NODES MAP:\n"
                    (mapconcat
                     (lambda (node)
                       (format "  - %s: [[id:%s][%s]]" (car node) (cdr node) (car node)))
                     umbrella-nodes-alist
                     "\n")
                    "\n\n")))

    (concat umbrella-section
             (if (and umbrella-nodes-alist (not (null umbrella-nodes-alist)))
                 "MANDATORY LINK REQUIREMENT: Include at least one explicit `[[id:<umbrella-id>][...]]` link to a provided umbrella node in the generated output.\n\n"
               "")
             "TITLE GUIDANCE: Keep `#+title:` concise and high-signal. Use semantic compression to preserve the core topic while removing fluff.\n"
             "- Example rewrite: `A Comprehensive Historical Overview of Retrieval-Augmented Generation Systems in Production` -> `RAG systems: production lessons`\n"
             "- Example rewrite: `How We Reduced CI Runtime by 43 Percent Across a Large Monorepo` -> `CI optimization: 43% faster monorepo builds`\n"
             "Do not hard-truncate by character count; prioritize meaning and scanability.\n\n"
             "ARTICLE URL: " url "\n\n"
             "ARTICLE CONTENT:\n" sanitized-text "\n\n"
             "EXPECTED OUTPUT FORMAT:\n"
            ":PROPERTIES:\n"
            ":ID:          " new-id "\n"
            ":END:\n"
            "#+title: <Article Title>\n"
            "#+ROAM_REFS: " url "\n"
            "#+filetags: :article:\n\n"
            "* Summary\n"
            "Source: [[" url "][" url "]]\n"
            "<Brief summary of the article>\n\n"
            "* Key Takeaways\n"
            "- <Key point 1>\n"
            "- <Key point 2>\n"
            "- <Key point 3>\n\n"
            "* Notes\n"
            "<Detailed notes with links to umbrella nodes if relevant>\n\n"
             "Generate the complete org-roam node following this format.")))

(defun sem-url-capture--next-node-filepath (slug)
  "Return a new, non-existing org-roam node filepath for SLUG.
The returned path is always under the resolved notes root."
  (let* ((notes-root (plist-get (sem-paths-resolve) :notes-root))
         (timestamp (format-time-string "%Y%m%d%H%M%S"))
         (base-name (format "%s-%s" timestamp slug))
         (candidate (expand-file-name (format "%s.org" base-name) notes-root))
         (suffix 1))
    (while (file-exists-p candidate)
      (setq candidate
            (expand-file-name (format "%s-%d.org" base-name suffix) notes-root))
      (setq suffix (1+ suffix)))
    candidate))

;;; Validation and Save

(defun sem-url-capture--validate-and-save (llm-response url &optional masked-response)
  "Validate LLM-RESPONSE and save as org-roam node.

URL is the original article URL for error reporting.
MASKED-RESPONSE is the LLM output before sensitive blocks were restored;
when given, it is what gets logged on failure instead of LLM-RESPONSE.

Validation steps:
1. Write to temporary buffer
2. Strip hallucinated markdown code blocks
3. Validate presence of :PROPERTIES:, :ID:, and #+title:
4. Extract title and generate slug
5. Write to notes root with timestamp-slug.org name
6. Invoke org-roam-db-sync
7. Kill temporary buffer

Returns the filepath on success, nil on validation failure."
  (cl-block sem-url-capture--validate-and-save
    (let ((temp-buf (generate-new-buffer " *url-capture-validate*"))
          (filepath nil)
          (title-value nil))
      (unwind-protect
        (progn
          ;; Write response to temporary buffer
          (with-current-buffer temp-buf
            (insert llm-response)
            (goto-char (point-min))

            ;; Strip hallucinated markdown code blocks
            (while (re-search-forward "```org\n\\|```\n\\|```$" nil t)
              (replace-match ""))
            (goto-char (point-min))

            ;; Validate required elements and canonical URL contract.
            (let ((has-properties (re-search-forward "^:PROPERTIES:" nil t))
                  (has-id (re-search-forward "^:ID:" nil t))
                  (has-title nil)
                  (roam-ref-url nil)
                  (source-url-a nil)
                  (source-url-b nil))
              (goto-char (point-min))
              (while (and (not has-title) (not (eobp)))
                (let ((line (string-trim-right
                             (buffer-substring-no-properties
                              (line-beginning-position)
                              (line-end-position)))))
                  (when (string-prefix-p "#+title:" line)
                    (let ((candidate (string-trim (substring line (length "#+title:")))))
                      (unless (string-empty-p candidate)
                        (setq has-title t)
                        (setq title-value candidate))))
                  (forward-line 1)))
              (unless (and has-properties has-id has-title)
                (sem-core-log-error "url-capture" "URL-CAPTURE"
                                    (format "Missing required elements: props=%s, id=%s, title=%s"
                                            has-properties has-id has-title)
                                    url
                                    (or masked-response llm-response))
                (cl-return-from sem-url-capture--validate-and-save nil))
              (goto-char (point-min))
              (while (and (not roam-ref-url) (not (eobp)))
                (let ((line (string-trim-right
                             (buffer-substring-no-properties
                              (line-beginning-position)
                              (line-end-position)))))
                  (when (string-prefix-p "#+ROAM_REFS:" line)
                    (let* ((refs-tail (string-trim (substring line (length "#+ROAM_REFS:"))))
                           (refs (split-string refs-tail "[ \t]+" t)))
                      (setq roam-ref-url (car refs))))
                  (forward-line 1)))
              (goto-char (point-min))
              (while (and (not source-url-a) (not (eobp)))
                (let ((line (string-trim-right
                             (buffer-substring-no-properties
                              (line-beginning-position)
                              (line-end-position)))))
                  (if (string= line "* Summary")
                      (progn
                        (forward-line 1)
                        (let ((source-line (string-trim-right
                                            (buffer-substring-no-properties
                                             (line-beginning-position)
                                             (line-end-position)))))
                          (when (string-match "^Source: \\[\\[\\([^]]+\\)\\]\\[\\([^]]+\\)\\]\\]" source-line)
                            (setq source-url-a (match-string 1 source-line))
                            (setq source-url-b (match-string 2 source-line)))))
                    (forward-line 1))))
              (unless (and roam-ref-url
                           source-url-a
                           source-url-b
                           (string= source-url-a source-url-b)
                           (string= source-url-a roam-ref-url)
                           (string-match-p "^https?://" roam-ref-url)
                           (not (string-match-p "^hxxps?://" roam-ref-url)))
                (sem-core-log-error "url-capture" "URL-CAPTURE"
                                    "Invalid URL contract: require canonical matching ROAM_REFS and Summary Source link"
                                    url
                                    (or masked-response llm-response))
                (cl-return-from sem-url-capture--validate-and-save nil)))

            ;; Extract title for slug generation
            (if title-value
                (let* ((title title-value)
                       (slug (sem-url-capture--make-slug title))
                       (fpath (sem-url-capture--next-node-filepath slug))
                       (content (buffer-string)))

                  ;; Write only to new files (never overwrite existing notes).
                  (with-temp-buffer
                    (insert content)
                    (write-region (point-min) (point-max) fpath nil 'silent nil 'excl))

                  ;; Sync database
                  (org-roam-db-sync)

                  (sem-core-log "url-capture" "URL-CAPTURE" "OK"
                                (format "Successfully saved node to %s" fpath)
                                nil)
                  (setq filepath fpath))
              (sem-core-log-error "url-capture" "URL-CAPTURE"
                                  "Could not extract title from #+title:"
                                  url
                                  (or masked-response llm-response))
              nil)))
      (when (buffer-live-p temp-buf)
        (kill-buffer temp-buf)))
    filepath)))

;;; Non-Interactive Entry Point

(defun sem-url-capture--process-fetched (url callback deadline fetch-result)
  "Continue URL capture for URL after the fetch finished with FETCH-RESULT.
CALLBACK and DEADLINE are as in `sem-url-capture-process'.  FETCH-RESULT is
the plist produced by `sem-url-capture--fetch-url-async'.
Returns t when the LLM request was started, nil on failure."
  (cl-block sem-url-capture--process-fetched
    (condition-case err
        (let* ((raw-content (plist-get fetch-result :content))
               (fetch-kind (plist-get fetch-result :kind)))
          (if raw-content
              (let* ((sanitized (sem-url-capture--sanitize-text raw-content))
                     (security-result nil)
                     (tokenized-text nil)
                     (security-blocks nil))

                ;; Apply security masking: sanitize sensitive blocks before LLM.
                (condition-case sanitize-err
                    (progn
                      (setq security-result (sem-security-sanitize-for-llm sanitized))
                      (setq tokenized-text (car security-result))
                      (setq security-blocks (cadr security-result)))
                  (error
                   (sem-core-log "url-capture" "URL-CAPTURE" "DLQ"
                                 (format "Security preflight failed, moved to DLQ: %s" url)
                                 nil)
                   (sem-core-log-error "security" "URL-CAPTURE"
                                       (error-message-string sanitize-err)
                                       (format "[content withheld: %d chars] %s"
                                               (length sanitized) url)
                                       nil
                                       (list :priority "[#A]" :tags '("security")))
                   (when callback
                     (funcall callback nil (list :url url :failure-kind 'security-malformed)))
                   (cl-return-from sem-url-capture--process-fetched nil)))

                (let* ((umbrella-nodes (sem-url-capture--get-umbrella-nodes))
                       (system-prompt (sem-url-capture--build-system-prompt))
                       (user-prompt (sem-url-capture--build-user-prompt url tokenized-text umbrella-nodes))
                       (completed nil)
                       (timeout-timer nil)
                       (llm-remaining-seconds (sem-url-capture--remaining-seconds deadline)))

                (when (<= llm-remaining-seconds 0)
                  (sem-url-capture--log-timeout-fail url "orchestration")
                  (when callback
                    (funcall callback nil (list :url url :failure-kind 'timeout)))
                  (cl-return-from sem-url-capture--process-fetched nil))

                (setq timeout-timer
                      (run-at-time llm-remaining-seconds nil
                                   (lambda ()
                                     (unless completed
                                       (setq completed t)
                                       (sem-url-capture--log-timeout-fail url "orchestration")
                                       (when callback
                                         (funcall callback nil (list :url url :failure-kind 'timeout)))))))

                ;; Request LLM via sem-llm-request with callback
                (require 'sem-llm)
                 (sem-llm-request user-prompt system-prompt
                                  (lambda (response info context)
                                    "Callback for sem-llm-request.
Calls sem-url-capture--validate-and-save with restored sensitive content."
                                    (unless completed
                                      (setq completed t)
                                      (when timeout-timer
                                        (cancel-timer timeout-timer)
                                        (setq timeout-timer nil))
                                      (let ((filepath nil)
                                            (url (plist-get context :url))
                                            (error-value (plist-get info :error)))
                                        (if (and response (not (string-empty-p response)))
                                            ;; Restore sensitive blocks before validation
                                            (let ((restored-response (sem-security-restore-from-llm response (plist-get context :security-blocks))))
                                              (setq filepath (sem-url-capture--validate-and-save
                                                              restored-response url response))
                                              (when filepath
                                                (setq context (plist-put context :security-blocks nil))))
                                          (progn
                                            (cond
                                             ((sem-url-capture--timeout-error-p error-value)
                                              (sem-url-capture--log-timeout-fail url "llm")
                                              (setq context (plist-put context :failure-kind 'timeout)))
                                             ((sem-llm-rate-limit-p error-value)
                                              ;; Transient upstream rate limit: the
                                              ;; llm module already logged the cause;
                                              ;; the router schedules an in-process
                                              ;; backoff retry.
                                              (setq context (plist-put context :failure-kind 'rate-limited)))
                                             (t
                                              (sem-core-log-error "url-capture" "URL-CAPTURE"
                                                                  (format "LLM request failed: %s"
                                                                          error-value)
                                                                  url
                                                                  response)))
                                            (setq filepath nil)))
                                        ;; Call the completion callback if provided
                                        (when callback
                                          (funcall callback filepath context)))))
                                  (list :security-blocks security-blocks :url url)
                                  'medium)

                  ;; Return immediately - processing continues asynchronously
                  t))
            (progn
              (if (eq fetch-kind 'timeout)
                  (sem-url-capture--log-timeout-fail url "fetch")
                (sem-core-log-error "url-capture" "URL-CAPTURE"
                                    (or (plist-get fetch-result :message) "Failed to fetch content")
                                    url
                                    nil))
              ;; Call callback with failure if provided
              (when callback
                (funcall callback nil (if (eq fetch-kind 'timeout)
                                          (list :url url :failure-kind 'timeout)
                                        (list :url url))))
              nil)))
      (error
       (sem-core-log-error "url-capture" "URL-CAPTURE"
                           (error-message-string err)
                           url
                           nil)
       ;; Call callback with failure if provided
       (when callback
         (funcall callback nil (list :url url)))
       nil))))


(defun sem-url-capture-process (url &optional callback)
  "Fetch URL content and create an org-roam node via LLM.

URL is the original article URL.
CALLBACK is an optional function of (filepath context) called when complete.
  - FILEPATH is the saved file path on success, nil on failure.
  - CONTEXT contains :url and other metadata.

This is the non-interactive entry point callable from sem-router.el.
It orchestrates the full pipeline:
1. Fetch content using trafilatura
2. Sanitize text for token efficiency
3. Apply security masking (sanitize sensitive blocks for LLM)
4. Extract umbrella nodes from org-roam database
5. Build prompts for LLM
6. Request LLM to generate org-roam node via sem-llm-request
7. Validate and save the result

Returns t when async processing starts successfully.
Returns nil when setup fails before async execution starts.
The fetch runs as an asynchronous subprocess; when a test double completes
it synchronously, the result of the remaining pipeline is returned.

The CALLBACK is invoked when complete.
If no callback is provided, processing still happens asynchronously."
  (cl-block sem-url-capture-process
    (condition-case err
        (let* ((deadline (time-add (current-time)
                                   (seconds-to-time sem-url-capture-timeout-seconds)))
               (remaining-seconds (sem-url-capture--remaining-seconds deadline)))
          (sem-core-log "url-capture" "URL-CAPTURE" "OK"
                        (format "Processing URL: %s" url)
                        nil)

        (when (<= remaining-seconds 0)
          (sem-url-capture--log-timeout-fail url "orchestration")
          (when callback
            (funcall callback nil (list :url url :failure-kind 'timeout)))
          (cl-return-from sem-url-capture-process nil))

        ;; Fetch URL content asynchronously; the pipeline continues in
        ;; `sem-url-capture--process-fetched'.
        (sem-url-capture--fetch-url-async
         url remaining-seconds
         (lambda (fetch-result)
           (sem-url-capture--process-fetched url callback deadline fetch-result))))
      (error
       (sem-core-log-error "url-capture" "URL-CAPTURE"
                           (error-message-string err)
                           url
                           nil)
       ;; Call callback with failure if provided
       (when callback
         (funcall callback nil (list :url url)))
       nil))))


(provide 'sem-url-capture)
;;; sem-url-capture.el ends here
