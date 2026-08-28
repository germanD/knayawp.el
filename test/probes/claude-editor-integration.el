;;; claude-editor-integration.el --- Probe for Claude editor integration (#121) -*- lexical-binding: t; -*-

;;; Commentary:

;; Three-scenario probe for the Claude editor integration introduced in
;; issue #121.  Run via:
;;   test/run-probe.sh test/probes/claude-editor-integration.el
;;
;; Scenario 1 — EDITOR env var injection when flag is set:
;;   With `knayawp-claude-editor-flag' t and a simulated running server,
;;   verify that creating a new Claude buffer calls `knayawp--make-terminal'
;;   with an env-vars list containing "EDITOR=...emacsclient".
;;
;; Scenario 2 — No injection when flag is off:
;;   With `knayawp-claude-editor-flag' nil, verify that
;;   `knayawp--get-or-create-claude-buffer' passes nil env-vars.
;;
;; Scenario 3 — Hook wired into layout lifecycle:
;;   After `knayawp-layout-setup', verify that
;;   `knayawp--claude-editor-server-switch' is present on
;;   `server-switch-hook'.  After `knayawp-layout-teardown', verify
;;   it has been removed.
;;
;; Note on end-to-end testing:
;;   The full flow — pressing the BEL key in the Claude panel, emacsclient
;;   calling server-visit, `server-switch-hook' firing, and the buffer
;;   landing in the editor pane — requires a live Claude session in a real
;;   Emacs frame with `server-mode' running.  That end-to-end scenario
;;   cannot be exercised in batch mode.  See issue #130 for the plan to
;;   improve automated coverage.  Manual verification steps:
;;     1. Ensure `server-mode' is running (M-x server-start).
;;     2. Run `knayawp-layout-setup'.
;;     3. Move focus to the Claude panel and press C-g.
;;     4. Confirm the prompt temp file opens in the left (editor) pane.

;;; Code:

(require 'cl-lib)

;;;; Helpers

(defun claude-ei--settle ()
  "Pump the event loop briefly to let timers settle."
  (sit-for 0.2))

(defun claude-ei--setup-layout ()
  "Activate `knayawp-mode' and create a fresh layout."
  (knayawp-mode 1)
  (setq knayawp-magit-commit-style 'off)
  (setq knayawp--zoomed-panel nil)
  (knayawp-layout-setup)
  (claude-ei--settle))

(defun claude-ei--teardown-layout ()
  "Tear down the knayawp layout."
  (knayawp-layout-teardown)
  (knayawp-mode -1)
  (claude-ei--settle))

;;;; Scenario 1: EDITOR env var injected when flag is set

(defun claude-ei--scenario-1 ()
  "Scenario 1 — EDITOR=emacsclient injected when flag is t and server runs."
  (knayawp-probe-section "SCENARIO 1 -- EDITOR env var injected (flag=t, server running)")
  (condition-case e
      (let* ((knayawp-claude-editor-flag t)
             (captured-env-vars 'unset)
             (fake-buf (generate-new-buffer " *knayawp-probe-claude-s1*")))
        (unwind-protect
            (cl-letf (((symbol-function 'get-buffer)
                       (lambda (_n) nil))
                      ((symbol-function 'knayawp--server-live-p)
                       (lambda () t))
                      ((symbol-function 'executable-find)
                       (lambda (_cmd) "/usr/bin/emacsclient"))
                      ((symbol-function 'knayawp--make-terminal)
                       (lambda (_name _dir _cmd env-vars)
                         (setq captured-env-vars env-vars)
                         fake-buf)))
              (knayawp--get-or-create-claude-buffer "/fake/proj/" "proj")
              (knayawp-probe-check "s1-env-vars-is-list"
                                   t (listp captured-env-vars) #'eq)
              (knayawp-probe-check "s1-env-vars-length"
                                   1 (length captured-env-vars) #'=)
              (knayawp-probe-check "s1-editor-prefix"
                                   t
                                   (and (stringp (car captured-env-vars))
                                        (string-prefix-p
                                         "EDITOR=" (car captured-env-vars)))
                                   #'eq)
              (knayawp-probe-check "s1-emacsclient-in-editor"
                                   t
                                   (and (stringp (car captured-env-vars))
                                        (if (string-match-p
                                             "emacsclient"
                                             (car captured-env-vars))
                                            t nil))
                                   #'eq))
          (when (buffer-live-p fake-buf) (kill-buffer fake-buf))))
    (error (knayawp-probe-abort "s1 failed: %S" e))))

;;;; Scenario 2: No injection when flag is off

(defun claude-ei--scenario-2 ()
  "Scenario 2 — no EDITOR injection when `knayawp-claude-editor-flag' is nil."
  (knayawp-probe-section "SCENARIO 2 -- no EDITOR injection when flag=nil")
  (condition-case e
      (let* ((knayawp-claude-editor-flag nil)
             (captured-env-vars 'unset)
             (fake-buf (generate-new-buffer " *knayawp-probe-claude-s2*")))
        (unwind-protect
            (cl-letf (((symbol-function 'get-buffer)
                       (lambda (_n) nil))
                      ((symbol-function 'knayawp--make-terminal)
                       (lambda (_name _dir _cmd env-vars)
                         (setq captured-env-vars env-vars)
                         fake-buf)))
              (knayawp--get-or-create-claude-buffer "/fake/proj/" "proj")
              (knayawp-probe-check "s2-env-vars-nil"
                                   nil captured-env-vars))
          (when (buffer-live-p fake-buf) (kill-buffer fake-buf))))
    (error (knayawp-probe-abort "s2 failed: %S" e))))

;;;; Scenario 3: Hook wired into layout lifecycle

(defun claude-ei--scenario-3 ()
  "Scenario 3 — Claude editor hook installed on layout-setup, removed on teardown."
  (knayawp-probe-section "SCENARIO 3 -- hook wired to layout lifecycle")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (claude-ei--setup-layout)
        ;; After layout-setup the hook must be registered.
        (knayawp-probe-check "s3-hook-installed-after-setup"
                             t
                             knayawp--claude-editor-hook-installed
                             #'eq)
        (knayawp-probe-check "s3-fn-on-server-switch-hook"
                             t
                             (not (null
                                   (memq #'knayawp--claude-editor-server-switch
                                         server-switch-hook)))
                             #'eq)
        (claude-ei--teardown-layout)
        ;; After layout-teardown the hook must be removed.
        (knayawp-probe-check "s3-hook-removed-after-teardown"
                             nil
                             knayawp--claude-editor-hook-installed)
        (knayawp-probe-check "s3-fn-off-server-switch-hook"
                             nil
                             (memq #'knayawp--claude-editor-server-switch
                                   server-switch-hook)))
    (error (knayawp-probe-abort "s3 failed: %S" e)))
  ;; Defensive teardown in case the layout survived an error.
  (when knayawp--active-layouts
    (claude-ei--teardown-layout)))

;;;; Drive all scenarios

(knayawp-probe-watchdog 90)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-probe-log "  probe start  default-directory=%S" default-directory)
      (claude-ei--scenario-1)
      (claude-ei--scenario-2)
      (claude-ei--scenario-3))
  (error (knayawp-probe-abort "top-level error: %S" e)))

(knayawp-probe-finish)

;;; claude-editor-integration.el ends here
