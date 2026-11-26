;;; sem-webdav-config-test.el --- Tests for WebDAV runtime config -*- lexical-binding: t; -*-
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Tests for production and test WebDAV compose/config invariants.

;;; Code:

(require 'ert)

(defconst sem-webdav-config-test--repo-root
  (expand-file-name "../../.." (file-name-directory load-file-name))
  "Repository root for config-file assertions.")

(defun sem-webdav-config-test--read (relative-path)
  "Return file content for RELATIVE-PATH from repository root."
  (with-temp-buffer
    (insert-file-contents (expand-file-name relative-path sem-webdav-config-test--repo-root))
    (buffer-string)))

(ert-deftest sem-webdav-config-test-production-compose-uses-apache-runtime ()
  "Test that production compose uses Apache WebDAV with preserved cert mount."
  (let ((compose (sem-webdav-config-test--read "docker-compose.yml")))
    (should (string-match-p "image: .*httpd:2\\.4" compose))
    (should (string-match-p "/etc/letsencrypt:/certs:ro,z" compose))
    (should (string-match-p "WEBDAV_DOMAIN" compose))
    (should (string-match-p "WEBDAV_RUNTIME_MODE=.*production" compose))
    (should (string-match-p "WEBDAV_PASSWORD=.*ChangeMeStrongPassword2026" compose))
    (should (string-match-p "start-webdav\\.sh" compose))))

(ert-deftest sem-webdav-config-test-apache-template-has-no-rewrite-gate ()
  "Test that Apache template leaves conditional writes to mod_dav.
Unconditional PUTs (organice) must pass; If-Match is checked by mod_dav."
  (let ((template (sem-webdav-config-test--read
                   "webdav/apache/httpd-webdav.conf.template")))
    (should-not (string-match-p "RewriteRule" template))
    (should-not (string-match-p "RewriteCond" template))
    (should-not (string-match-p "R=428" template))))

(ert-deftest sem-webdav-config-test-apache-template-serves-org-ui ()
  "Test that Apache template serves org-ui under /ui without DAV or auth."
  (let ((template (sem-webdav-config-test--read
                   "webdav/apache/httpd-webdav.conf.template"))
        (compose (sem-webdav-config-test--read "docker-compose.yml")))
    (should (string-match-p (regexp-quote "Alias /ui /usr/local/apache2/ui") template))
    ;; DAV must be bound to the data directory, not to <Location "/">,
    ;; otherwise /ui would accept PUT (mod_dav cannot disable a subtree).
    (should (string-match-p "<Directory \"/data/tasks\">[^<]*Dav On" template))
    (should-not (string-match-p "<Location \"/\">[^<]*Dav On" template))
    (should (string-match-p "<Location \"/ui\">[^<]*Require all granted" template))
    (should (string-match-p (regexp-quote "./org-ui/dist:/usr/local/apache2/ui:ro,z") compose))))

(ert-deftest sem-webdav-config-test-integration-runtime-remains-non-tls ()
  "Test that integration override remains independent from production TLS/runtime."
  (let ((compose-test (sem-webdav-config-test--read "dev/integration/docker-compose.test.yml"))
        (webdav-test (sem-webdav-config-test--read "dev/integration/webdav-config.test.yml")))
    (should (string-match-p "image: hacdias/webdav:latest" compose-test))
    (should (string-match-p "webdav-config\\.test\\.yml" compose-test))
    (should (string-match-p "WEBDAV_RUNTIME_MODE=.*integration-test" compose-test))
    (should (string-match-p "tls: false" webdav-test))))

(ert-deftest sem-webdav-config-test-start-script-enforces-production-password-policy ()
  "Test WebDAV startup script enforces production password complexity policy."
  (let ((script (sem-webdav-config-test--read "webdav/apache/start-webdav.sh")))
    (should (string-match-p "WEBDAV_RUNTIME_MODE" script))
    (should (string-match-p "= \"production\"" script))
    (should (string-match-p "password_len" script))
    (should (string-match-p "[a-z]" script))
    (should (string-match-p "[A-Z]" script))
    (should (string-match-p "[0-9]" script))))

(ert-deftest sem-webdav-config-test-start-script-logs-remediation-for-policy-failures ()
  "Test WebDAV startup script emits explicit remediation guidance on failures."
  (let ((script (sem-webdav-config-test--read "webdav/apache/start-webdav.sh")))
    (should (string-match-p "Production password policy validation failed" script))
    (should (string-match-p "Remediation:" script))))

(provide 'sem-webdav-config-test)
;;; sem-webdav-config-test.el ends here
