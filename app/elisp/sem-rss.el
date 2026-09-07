;;; sem-rss.el --- RSS digest generation via LLM -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; This module generates daily RSS/arXiv digests via LLM.
;; Ported from tools-rss.el with all interactive patterns stripped.
;; Configuration is via environment variables, not defcustom.
;; Digest output is operator-facing, so URLs are defanged before write,
;; except links to trusted feed source hosts (derived from `elfeed-feeds'
;; via `sem-rss--trusted-hosts-from-feeds'), which stay clickable.

;;; Code:

(require 'seq)
(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'elfeed)
(require 'sem-core)
(require 'sem-llm)
(require 'sem-security)
(require 'sem-time)

;;; Configuration (from environment variables)

(defconst sem-rss-max-entries-per-feed
  (or (when-let* ((val (getenv "RSS_MAX_ENTRIES_PER_FEED")))
        (string-to-number val))
      10)
  "Maximum number of entries per feed. Read from RSS_MAX_ENTRIES_PER_FEED.")

(defconst sem-rss-max-input-chars
  (or (when-let* ((val (getenv "RSS_MAX_INPUT_CHARS")))
        (string-to-number val))
      199000)
  "Maximum input characters for LLM. Read from RSS_MAX_INPUT_CHARS.")

(defconst sem-rss-arxiv-stagger-seconds 5
  "Seconds to wait before arXiv digest generation starts.
Counted from the start of the general digest step, so the two
digest LLM requests are not dispatched back-to-back.")

(defconst sem-rss-rate-limit-retry-delay-seconds 300
  "Fixed delay in seconds before each digest rate-limit (429) retry.")

(defconst sem-rss-rate-limit-max-retries 3
  "Maximum retries after the initial digest request fails with 429.
The initial attempt plus this many retries bound the total number
of attempts (4 with the default value).")

(defconst sem-rss-dir "/data/morning-read/"
  "Directory where daily digests are stored.")

(defconst sem-rss-archive-dir "/data/archive/"
  "Directory where archived digest files are stored.
Digest files from previous months are moved into a `YYYY-MM'
subdirectory of this directory.")

(defconst sem-rss-feeds-file "/data/feeds.org"
  "Path to feeds configuration file in Org format.")

(defconst sem-rss-feeds-cache-file "/data/.sem-feeds-cache.el"
  "Path to feed parsing cache metadata.")

;;; Prompt Templates (loaded from external files)

(defvar sem-rss-prompts-dir nil
  "Directory containing prompt template files.
If nil, defaults to /data/prompts/ or SEM_PROMPTS_DIR env var.
Set this before loading sem-rss to override the default location.")

(defun sem-rss--get-prompts-dir ()
  "Get the prompts directory.
Uses sem-rss-prompts-dir if set, otherwise SEM_PROMPTS_DIR env var,
or defaults to /data/prompts/."
  (or sem-rss-prompts-dir
      (getenv "SEM_PROMPTS_DIR")
      "/data/prompts/"))

(defvar sem-rss-general-prompt-template nil
  "Template for general RSS digest prompts.
Loaded lazily on first use from general-prompt.txt.")

(defvar sem-rss-arxiv-prompt-template nil
  "Template for arXiv digest prompts.
Loaded lazily on first use from arxiv-prompt.txt.")

;;; Trusted Source Hosts

(defun sem-rss--trusted-hosts-from-feeds ()
  "Derive the trusted host set for digest URL masking from `elfeed-feeds'.
Feed entries are either URL strings or (URL . TAGS) lists.  Returns the
distinct set of feed URL hosts plus their base domains (last two labels,
see `sem-security--host-base-domain'), all downcased.  Returns nil when
no feed hosts can be derived, which keeps `sem-security-sanitize-urls'
in its mask-all mode (every URL defanged)."
  (let ((hosts nil))
    (dolist (entry elfeed-feeds)
      (let* ((url (cond
                   ((stringp entry) entry)
                   ((consp entry) (car entry))))
             (host (sem-security--url-host url)))
        (when host
          (cl-pushnew host hosts :test #'string=))))
    (when hosts
      (delete-dups
       (append hosts
               (delq nil (mapcar #'sem-security--host-base-domain hosts)))))))

;;; Feed Parsing and Reload Cache

(defun sem-rss--extract-feed-url-from-heading-line (line)
  "Extract feed URL from Org heading LINE.
Supports both plain URL headings and Org links.
Returns URL string or nil when LINE does not define a feed URL." 
  (cond
   ((string-match "^\\(?:\\*+\\s-+\\)?\\(https?://[^[:space:]]+\\)" line)
    (match-string 1 line))
   ((string-match "^\\(?:\\*+\\s-+\\)?\\[\\[\\(https?://[^]]+\\)\\]\\(\\[[^]]*\\]\\)?\\]" line)
    (match-string 1 line))
   (t nil)))

(defun sem-rss--normalized-feed-tags (tags)
  "Normalize TAGS for Elfeed feed entry.
Removes structural tags and returns a list of symbols." 
  (thread-last tags
               (mapcar #'downcase)
               (seq-remove (lambda (tag)
                             (member tag '("elfeed" "ignore"))))
               delete-dups
               (mapcar #'intern)))

(defun sem-rss--parse-feeds-from-org-file (file-path)
  "Parse FILE-PATH and return Elfeed feed definitions.
The return value is a list of Elfeed feed entries.
Each entry is either a URL string or a list where CAR is URL and CDR are tags." 
  (with-temp-buffer
    (insert-file-contents file-path)
    (let ((feeds '())
          (seen (make-hash-table :test 'equal))
          (tag-stack '()))
      (goto-char (point-min))
      (while (re-search-forward "^\\(\\*+\\)\\s-+\\(.*\\)$" nil t)
        (let* ((level (length (match-string 1)))
               (raw-heading (match-string 2))
               (title raw-heading)
               (local-tags '()))
          (when (string-match "\\(.*?\\)\\s-+\\(:[[:alnum:]_@#%:.-]+:\\)\\s-*$" raw-heading)
            (setq title (string-trim (match-string 1 raw-heading)))
            (setq local-tags (split-string (match-string 2 raw-heading) ":" t)))

          (while (> (length tag-stack) (1- level))
            (setq tag-stack (butlast tag-stack 1)))

          (let* ((parent-tags (if tag-stack (car (last tag-stack)) '()))
                 (all-tags (delete-dups (append parent-tags local-tags)))
                 (url (sem-rss--extract-feed-url-from-heading-line title)))
            (setq tag-stack (append tag-stack (list all-tags)))
            (when (and url
                       (member "elfeed" all-tags)
                       (not (member "ignore" all-tags))
                       (not (gethash url seen)))
              (puthash url t seen)
              (let ((tag-symbols (sem-rss--normalized-feed-tags all-tags)))
                (push (if tag-symbols
                          (cons url tag-symbols)
                        url)
                      feeds))))))
      (nreverse feeds))))

(defun sem-rss--feeds-file-fingerprint (file-path)
  "Return fingerprint plist for FILE-PATH.
Includes :size and :sha256 keys." 
  (with-temp-buffer
    (insert-file-contents file-path)
    (list :size (buffer-size)
          :sha256 (secure-hash 'sha256 (current-buffer)))))

(defun sem-rss--read-feeds-cache ()
  "Read and return feed cache plist from `sem-rss-feeds-cache-file'."
  (when (file-exists-p sem-rss-feeds-cache-file)
    (condition-case _err
        (with-temp-buffer
          (insert-file-contents sem-rss-feeds-cache-file)
          (read (current-buffer)))
      (error nil))))

(defun sem-rss--write-feeds-cache (cache)
  "Atomically write CACHE plist to `sem-rss-feeds-cache-file'."
  (let ((tmp-file (concat sem-rss-feeds-cache-file ".tmp")))
    (with-temp-file tmp-file
      (prin1 cache (current-buffer)))
    (rename-file tmp-file sem-rss-feeds-cache-file t)))

(defun sem-rss-refresh-feeds (&optional force)
  "Refresh `elfeed-feeds' from feeds Org file.
When FORCE is non-nil, bypass cache fingerprint checks.
Returns a plist with :reloaded, :count, and :reason keys." 
  (condition-case err
      (if (not (file-exists-p sem-rss-feeds-file))
          (progn
            (sem-core-log "rss" "ELFEED-FEEDS" "SKIP"
                          (format "Feeds file missing: %s" sem-rss-feeds-file))
            (setq elfeed-feeds nil)
            (list :reloaded nil :count 0 :reason 'missing-file))
        (let* ((cache (sem-rss--read-feeds-cache))
               (fingerprint (sem-rss--feeds-file-fingerprint sem-rss-feeds-file))
               (same-size (= (plist-get fingerprint :size)
                             (or (plist-get cache :size) -1)))
               (same-hash (string=
                           (plist-get fingerprint :sha256)
                           (or (plist-get cache :sha256) "")))
               (cached-feeds (plist-get cache :feeds))
               (can-reuse (and (not force) same-size same-hash (listp cached-feeds))))
          (if can-reuse
              (progn
                (setq elfeed-feeds cached-feeds)
                (sem-core-log "rss" "ELFEED-FEEDS" "SKIP"
                              (format "Feeds unchanged, reused cache (%d feeds)"
                                      (length cached-feeds)))
                (list :reloaded nil :count (length cached-feeds) :reason 'unchanged))
            (let* ((parsed-feeds (sem-rss--parse-feeds-from-org-file sem-rss-feeds-file))
                   (feed-count (length parsed-feeds))
                   (cache-data (append fingerprint
                                       (list :feeds parsed-feeds
                                             :updated-at (sem-time-format-string "%Y-%m-%dT%H:%M:%S%z")))))
              (setq elfeed-feeds parsed-feeds)
              (sem-rss--write-feeds-cache cache-data)
              (if (> feed-count 0)
                  (sem-core-log "rss" "ELFEED-FEEDS" "OK"
                                (format "Loaded %d feeds from %s" feed-count sem-rss-feeds-file))
                (sem-core-log "rss" "ELFEED-FEEDS" "FAIL"
                              (format "No feeds parsed from %s" sem-rss-feeds-file)))
              (list :reloaded t :count feed-count
                    :reason (if force 'forced 'changed))))))
    (error
     (sem-core-log-error "rss" "ELFEED-FEEDS"
                         (error-message-string err)
                         sem-rss-feeds-file
                         nil)
     (list :reloaded nil :count (length (or elfeed-feeds '())) :reason 'error))))

(defun sem-rss-elfeed-update-cron ()
  "Cron-safe Elfeed update with feed reload and structured logging." 
  (sem-core-run-cron-guarded
   "rss-elfeed-update" "rss" "ELFEED-UPDATE"
   (lambda ()
     (condition-case err
         (let* ((reload-result (sem-rss-refresh-feeds))
                (count (plist-get reload-result :count)))
           (if (<= count 0)
               (sem-core-log "rss" "ELFEED-UPDATE" "SKIP"
                             "Skipping elfeed-update because feed count is zero")
             (progn
               (sem-core-log "rss" "ELFEED-UPDATE" "OK"
                             (format "Starting update for %d feeds" count))
               (elfeed-update)
               (sem-core-log "rss" "ELFEED-UPDATE" "OK"
                             "elfeed-update dispatched"))))
       (error
        (sem-core-log-error "rss" "ELFEED-UPDATE"
                            (error-message-string err)
                            nil
                            nil))))))

(defun sem-rss--load-prompt-template (file-path)
  "Load prompt template from FILE-PATH.
Signals an error if the file is missing or empty."
  (let ((content nil))
    (with-temp-buffer
      (condition-case err
          (progn
            (insert-file-contents file-path)
            (setq content (string-trim (buffer-string)))
            (when (or (null content) (string-empty-p content))
              (error "Prompt file %s is empty" file-path)))
        (file-missing
         (error "Required prompt file missing: %s" file-path))
        (error
         (error "Failed to load prompt file %s: %s" file-path (error-message-string err)))))
    content))

(defun sem-rss--ensure-prompts-loaded ()
  "Load prompt templates if not already loaded.
This is a lazy-loading function to avoid blocking daemon startup."
  (unless sem-rss-general-prompt-template
    (setq sem-rss-general-prompt-template
          (sem-rss--load-prompt-template
           (expand-file-name "general-prompt.txt" (sem-rss--get-prompts-dir)))))
  (unless sem-rss-arxiv-prompt-template
    (setq sem-rss-arxiv-prompt-template
          (sem-rss--load-prompt-template
           (expand-file-name "arxiv-prompt.txt" (sem-rss--get-prompts-dir))))))

;;; Category Mappings

(defconst sem-rss-categories
  '(("dataengineering" . "Data Engineering")
    ("engineers" . "Engineers")
    ("vendors" . "Vendors")
    ("opensource" . "Open Source")
    ("ai" . "Artificial Intelligence")
    ("nonengineering" . "Non Engineering"))
  "Mapping of Elfeed tags to Digest Sections (General).")

(defconst sem-rss-arxiv-categories
  '(("csdb" . "cs.DB (Databases)")
    ("csai" . "cs.AI (Artificial Intelligence)")
    ("socph" . "physics.soc-ph (Social Physics & Networks)")
    ("csds" . "cs.DS (Data Structures & Algorithms)")
    ("csdc" . "cs.DC (Distributed Computing)"))
  "Mapping of Arxiv tags to Digest Sections.")

;;; Text Cleaning

(defun sem-rss--clean-text (html)
  "Aggressively strip HTML to save tokens."
  (when html
    (with-temp-buffer
      (insert html)
      (goto-char (point-min))
      ;; Remove script and style blocks
      (while (re-search-forward "<\\(script\\|style\\)[^>]*>\\([\\s\\S]*?\\)</\\1>" nil t)
        (replace-match " " nil nil))
      ;; Remove all HTML tags
      (goto-char (point-min))
      (while (re-search-forward "<[^>]+>" nil t)
        (replace-match " " nil nil))
      ;; Replace HTML entities (order matters: &amp; must be last)
      (goto-char (point-min))
      (while (re-search-forward "&nbsp;" nil t) (replace-match " " nil nil))
      (goto-char (point-min))
      (while (re-search-forward "&lt;" nil t) (replace-match "<" nil nil))
      (goto-char (point-min))
      (while (re-search-forward "&gt;" nil t) (replace-match ">" nil nil))
      (goto-char (point-min))
      (while (re-search-forward "&quot;" nil t) (replace-match "\"" nil nil))
      (goto-char (point-min))
      (while (re-search-forward "&amp;" nil t) (replace-match "&" nil nil))
      ;; Normalize whitespace
      (goto-char (point-min))
      (while (re-search-forward "[[:space:]\n\r]+" nil t)
        (replace-match " " nil nil))
      (let ((text (string-trim (buffer-string))))
        ;; Truncate if too long
        (if (> (length text) 3000)
            (concat (substring text 0 3000) "...")
          text)))))

;;; Entry Collection

(defun sem-rss-collect-entries (filter-fn days)
  "Fetch entries from last DAYS days.

FILTER-FN is a function that takes a list of tag strings and
returns non-nil if entry should be kept.

Returns a list of entry plists."
  (let* ((days-int (truncate days))
         (since-time (time-subtract (current-time) (days-to-time days-int)))
         (raw-entries '()))
    (elfeed-db-ensure)

    (with-elfeed-db-visit (entry feed)
      (let ((date (elfeed-entry-date entry)))
        (when (time-less-p since-time (seconds-to-time date))
          (let* ((all-tags (mapcar #'symbol-name (elfeed-entry-tags entry)))
                 ;; Remove system tags
                 (tags (seq-remove (lambda (tag)
                                     (member tag '("unread" "starred")))
                                   all-tags)))

            ;; Apply filter BEFORE heavy text processing
            (when (funcall filter-fn tags)
              (let* ((title (elfeed-entry-title entry))
                     (link (elfeed-entry-link entry))
                     (feed-title (elfeed-feed-title feed))
                     (content-raw (elfeed-deref (elfeed-entry-content entry)))
                     (content (sem-rss--clean-text content-raw)))
                (push (list :title title
                            :link link
                            :feed feed-title
                            :date date
                            :tags tags
                            :content content)
                      raw-entries)))))))

    ;; Group by feed and apply per-feed limits
    (thread-last raw-entries
                 (seq-group-by (lambda (x) (plist-get x :feed)))
                 (mapcan (lambda (group)
                           (let* ((entries (cdr group))
                                  (sorted (seq-sort-by (lambda (x) (plist-get x :date)) #'> entries)))
                             (seq-take sorted sem-rss-max-entries-per-feed)))))))

;;; Entry Formatting

(defun sem-rss--format-entry-for-llm (entry)
  "Format an ENTRY plist for LLM input."
  (format "Title: %s\nLink: %s\nTags: %s\nAbstract/Content: %s\n---\n"
          (plist-get entry :title)
          (plist-get entry :link)
          (string-join (plist-get entry :tags) ", ")
          (or (plist-get entry :content) "No content")))

(defun sem-rss--build-entries-text (entries)
  "Build the entries text for LLM input.
Truncates to `sem-rss-max-input-chars' if needed."
  (let* ((entries-text (mapconcat #'sem-rss--format-entry-for-llm entries "\n")))
    (if (> (length entries-text) sem-rss-max-input-chars)
        (substring entries-text 0 sem-rss-max-input-chars)
      entries-text)))

;;; Prompt Builders

(defun sem-rss--build-general-prompt (entries days)
  "Build prompt for general RSS digest.
ENTRIES is the list of entry plists.
DAYS is the number of days the digest covers."
  (format sem-rss-general-prompt-template
          days
          (mapconcat #'cdr sem-rss-categories ", ")
          days
          (sem-rss--build-entries-text entries)))

(defun sem-rss--build-arxiv-prompt (entries days)
  "Build prompt for arXiv digest.
ENTRIES is the list of entry plists.
DAYS is the number of days the digest covers."
  (format sem-rss-arxiv-prompt-template
          (mapconcat #'cdr sem-rss-arxiv-categories ", ")
          days
          (sem-rss--build-entries-text entries)))

;;; File Generation

(defun sem-rss--generate-file (target-path prompt title-prefix days &optional callback)
  "Call LLM and write digest to TARGET-PATH.

PROMPT is the LLM prompt.
TITLE-PREFIX is the title prefix (e.g., \"Daily Digest\" or \"Arxiv Digest\").
DAYS is the number of days the digest covers.
CALLBACK is an optional function of (success context) called when complete.
  - SUCCESS is t if file was written, nil on failure.
  - CONTEXT contains :target-path and other metadata.

Uses sem-llm-request with nil hash (no per-entry cursor tracking for RSS).
On malformed LLM output: log to errors.org, do not write file.
On API error: log to errors.org with RETRY status, do not write file.

Returns immediately (async). The CALLBACK is invoked when complete."
    (let* ((days-int (truncate days))
           ;; Compute date range
           (from-date (time-subtract (current-time) (days-to-time days-int)))
           (to-date (current-time))
           (from-org (sem-time-format-string "[%Y-%m-%d %a]" from-date))
           (to-org (sem-time-format-string "[%Y-%m-%d %a]" to-date))
           (digest-type (if (string-prefix-p "Arxiv" title-prefix)
                            "ARXIV-DIGEST" "RSS-DIGEST"))
           ;; Trusted source hosts for whitelist-aware URL masking, derived
           ;; from the current elfeed feed configuration.  An empty set keeps
           ;; the mask-all default (every URL defanged).
           (trusted-hosts (sem-rss--trusted-hosts-from-feeds))
           (system-prompt "You are a helpful Technical Editor assistant. You output ONLY raw Org-mode text. Never use markdown code fences or any wrapper syntax. Never include reasoning or commentary outside of the requested Org-mode structure. Start your response directly with the first Org-mode heading."))
      (sem-core-log "rss" digest-type "OK"
                    (format "Digest URL masking whitelist: %d trusted hosts"
                            (length trusted-hosts)))
      ;; Use sem-llm-request instead of direct gptel-request
      (require 'sem-llm)
      (cl-labels
          ((run-attempt (attempt-number)
             (sem-llm-request prompt system-prompt
                       (lambda (response info context)
                         "Callback for sem-llm-request in RSS digest.
Handles rate-limit backoff retries, API errors (RETRY) and malformed
output (DLQ)."
                         (let ((deferred nil)
                               (target (plist-get context :target-path))
                               (title (plist-get context :title-prefix))
                               (from (plist-get context :from-org))
                               (to (plist-get context :to-org))
                               (digest-type (plist-get context :digest-type))
                               (trusted-hosts (plist-get context :trusted-hosts))
                               (success nil))
                           (cond
                            ;; Success - write to file
                             ((and response (not (string-empty-p response)))
                              (let ((sanitized-response
                                     (sem-security-sanitize-urls
                                      response trusted-hosts)))
                               (with-temp-file target
                                 (insert "#+TITLE: " title ": " (sem-time-format-string "%Y-%m-%d") "\n")
                                 (insert "#+FROM: " from "\n")
                                 (insert "#+TO: " to "\n")
                                 (insert "#+DATE: " (sem-time-format-string "[%Y-%m-%d %a]") "\n")
                                 (insert "#+STARTUP: showall\n\n")
                                 (insert sanitized-response)))
                              (sem-core-log "rss" digest-type "OK"
                                            (format "Digest written to %s" target)
                                            nil)
                              (setq success t))
                            ;; Rate limited with budget remaining - retry
                            ;; in-process after a backoff delay; the
                            ;; completion callback fires on the terminal
                            ;; outcome.
                            ((and (plist-get info :error)
                                  (sem-llm-rate-limit-p (plist-get info :error))
                                  (< attempt-number
                                     (1+ sem-rss-rate-limit-max-retries)))
                             (let ((delay sem-rss-rate-limit-retry-delay-seconds))
                               (sem-core-log "rss" digest-type "RETRY"
                                             (format "Rate limited (429), attempt %d/%d failed; retrying in %ds"
                                                     attempt-number
                                                     (1+ sem-rss-rate-limit-max-retries)
                                                     delay)
                                             nil)
                               (run-at-time delay nil (function run-attempt) (1+ attempt-number))
                               (setq deferred t)))
                            ((plist-get info :error)
                             (sem-core-log-error "rss" digest-type
                                                 (format "API error: %s" (plist-get info :error))
                                                 (plist-get context :prompt)
                                                 nil)
                             (setq success nil))
                            ;; Malformed/empty response - log DLQ, do not write file
                            (t
                             (sem-core-log-error "rss" digest-type
                                                 "Malformed or empty LLM response"
                                                 (plist-get context :prompt)
                                                 response)
                             (setq success nil)))
                           ;; Call the completion callback if provided
                           (when callback
                             (funcall callback success context))))
                       (list :target-path target-path :title-prefix title-prefix
                             :from-org from-org :to-org to-org :prompt prompt
                             :digest-type digest-type
                             :trusted-hosts trusted-hosts)
                       'medium)))
        (run-attempt 1)
    t)))

    ;; Return immediately - processing continues asynchronously

(provide 'sem-rss)
;;; sem-rss.el ends here


;;; Cron Entry Point

;;;###autoload
(defun sem-rss-generate-morning-digest ()
  "Generate both general and arXiv morning digests.
This is the cron entry point callable via `emacsclient -e`."
  (sem-core-run-cron-guarded
   "rss-morning-digest" "rss" "RSS-DIGEST"
   (lambda ()
     (condition-case err
         (progn
           (sem-core-log "rss" "RSS-DIGEST" "OK" "Morning digest generation started")

           ;; Ensure prompt templates are loaded (lazy loading)
           (sem-rss--ensure-prompts-loaded)

           ;; Ensure output directory exists
           (make-directory sem-rss-dir t)

           ;; Generate filenames
           (let* ((date-str (sem-time-format-string "%Y-%m-%d"))
                  (general-file (expand-file-name (concat date-str ".org") sem-rss-dir))
                  (arxiv-file (expand-file-name (concat date-str "-arxiv.org") sem-rss-dir))
                  (days 1))  ; Always 24-hour lookback

             ;; Check if files already exist
             (if (file-exists-p general-file)
		 (sem-core-log "rss" "RSS-DIGEST" "SKIP" "General digest already exists")
               ;; Generate general digest
               (let ((entries (sem-rss-collect-entries
                               (lambda (tags) (not (member "arxiv" tags)))
                               days)))
		 (if (null entries)
                     (sem-core-log "rss" "RSS-DIGEST" "SKIP" "No entries found for general filter")
                   (sem-core-log "rss" "RSS-DIGEST" "OK"
				 (format "Found %d entries for general digest" (length entries))
				 nil)
                   (sem-rss--generate-file general-file
                                           (sem-rss--build-general-prompt entries days)
                                           "Daily Digest"
                                           days))))

             ;; ArXiv digest, staggered behind the general digest step so the
             ;; two LLM requests are not dispatched back-to-back.  The timer
             ;; fires after the outer condition-case has already returned, so
             ;; the deferred body carries its own error handler.
             (run-at-time
              sem-rss-arxiv-stagger-seconds nil
              (lambda ()
                (condition-case err
                    (if (file-exists-p arxiv-file)
                        (sem-core-log "rss" "ARXIV-DIGEST" "SKIP" "Arxiv digest already exists")
                      ;; Generate arxiv digest
                      (let ((entries (sem-rss-collect-entries
                                      (lambda (tags) (member "arxiv" tags))
                                      days)))
                        (if (null entries)
                            (sem-core-log "rss" "ARXIV-DIGEST" "SKIP" "No entries found for arxiv filter")
                          (sem-core-log "rss" "ARXIV-DIGEST" "OK"
                                        (format "Found %d entries for arxiv digest" (length entries))
                                        nil)
                          (sem-rss--generate-file arxiv-file
                                                  (sem-rss--build-arxiv-prompt entries days)
                                                  "Arxiv Digest"
                                                  days))))
                  (error
                   (sem-core-log-error "rss" "ARXIV-DIGEST"
                                       (error-message-string err)
                                       nil
                                       nil)
                   (message "SEM: arXiv digest error: %s" (error-message-string err)))))))

           (sem-core-log "rss" "RSS-DIGEST" "OK" "Morning digest generation completed"))
       (error
        (sem-core-log-error "rss" "RSS-DIGEST"
                            (error-message-string err)
                            nil
                            nil)
        (message "SEM: RSS digest error: %s" (error-message-string err)))))))

;;; Digest Archival

(defun sem-rss--archive-month-from-filename (filename)
  "Return the `YYYY-MM' month of digest FILENAME, or nil if absent.
FILENAME is a file name without directory.  Digest files carry a
leading `YYYY-MM-DD' date, e.g. `2026-03-15.org' or
`2026-03-15-arxiv.org'."
  (let ((name (file-name-nondirectory filename)))
    (and (string-match "\\`\\([0-9]\\{4\\}-[0-9]\\{2\\}\\)-" name)
         (match-string 1 name))))

(defun sem-rss-archive-old-digests (&optional now)
  "Move digest files from previous months into `sem-rss-archive-dir'.
Each regular file in `sem-rss-dir' whose filename carries a
`YYYY-MM' month earlier than the calendar month of NOW (default
`current-time') is moved into `YYYY-MM/' under
`sem-rss-archive-dir', creating directories on demand.  Files
without a recognizable month prefix are skipped and logged.
Successful moves are logged with status OK; a failing move is
logged via `sem-core-log-error' and does not abort the remaining
files.  Idempotent: a run with nothing to archive moves nothing.
NOW is used by tests to pin the reference time.

This is the cron entry point callable via `emacsclient -e'."
  (sem-core-run-cron-guarded
   "rss-morning-archive" "rss" "RSS-DIGEST"
   (lambda ()
     (condition-case err
         (let* ((current-month (format-time-string "%Y-%m" now))
                (moved 0))
           (make-directory sem-rss-archive-dir t)
           (when (file-directory-p sem-rss-dir)
             (dolist (file (directory-files
                            sem-rss-dir t directory-files-no-dot-files-regexp))
               (when (file-regular-p file)
                 (let* ((name (file-name-nondirectory file))
                        (month (sem-rss--archive-month-from-filename name)))
                   (cond
                    ((null month)
                     (sem-core-log "rss" "RSS-DIGEST" "SKIP"
                                   (format "No month prefix, not archived: %s"
                                           name)))
                    ((string< month current-month)
                     (condition-case move-err
                         (let ((dest-dir
                                (expand-file-name month sem-rss-archive-dir)))
                           (make-directory dest-dir t)
                           (rename-file file (expand-file-name name dest-dir))
                           (setq moved (1+ moved))
                           (sem-core-log "rss" "RSS-DIGEST" "OK"
                                         (format "Archived %s to %s" name month)))
                       (error
                        (sem-core-log-error "rss" "RSS-DIGEST"
                                            (error-message-string move-err)
                                            file)
                        (message "SEM: archive move failed for %s: %s"
                                 name (error-message-string move-err)))))))))
           moved))
       (error
        (sem-core-log-error "rss" "RSS-DIGEST"
                            (error-message-string err)
                            nil)
        (message "SEM: RSS digest archival error: %s"
                 (error-message-string err))
        nil)))))

(provide 'sem-rss)
;;; sem-rss.el ends here
