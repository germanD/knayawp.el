;;; claude-edit-zoomed-dual-window.el --- Probe for #178 dual-window bug -*- lexical-binding: t; -*-

;;; Commentary:

;; Reproduction probe for issue #178: a Claude edit triggered from an
;; already-ZOOMED Claude pane leaves the emacsclient temp file displayed
;; in TWO windows at once (left + right) instead of a single window.  Run
;; via:
;;   test/run-probe.sh test/probes/claude-edit-zoomed-dual-window.el
;;
;; Flow modelled (matches the real emacsclient round-trip, see
;; `server-switch-timing.el' scenario 2):
;;   1. Set up the layout, select the Claude panel, zoom it
;;      (`knayawp-zoom-panel' — side windows except Claude are deleted).
;;   2. `server-visit-hook' fires: `knayawp--claude-edit-record-origin'
;;      captures the (zoomed) Claude window as the edit origin.
;;   3. `server-switch-buffer' fires: simulated here with a real
;;      `display-buffer' of the temp file, as Emacs would do BEFORE our
;;      `server-switch-hook' re-routes.  This places the temp buffer in
;;      some non-dedicated window (window #1 of the duplicate).
;;   4. `server-switch-hook' fires: `knayawp--claude-editor-server-switch'
;;      re-routes per `knayawp-claude-edit-style' (window #2 of the
;;      duplicate).
;;
;; The core assertion counts how many live windows display the temp-file
;; buffer.  The bug is present when that count is > 1.
;;
;; Scenario 1 — default `claude-panel' style, zoomed Claude pane.
;; Scenario 2 — `zoom' style, zoomed Claude pane.
;;
;; Both scenarios tag the expected (correct) value as 1 window, so a RED
;; status with actual=2 is the signature of the reproduced bug.
;;
;; Note on window counts: `test/sandbox.el' opens a `*knayawp-sandbox*'
;; help window.  Full (unzoomed) layout: 3 panels + editor + sandbox
;; helper = 5 windows.

;;; Code:

(require 'cl-lib)

;; Prefer vterm; fall back to eat when vterm is unavailable (CI/container
;; images may ship only the MELPA `eat' package).
(unless (require 'vterm nil t)
  (when (require 'eat nil t)
    (setq knayawp-terminal-backend 'eat)))

(defvar cezd--claude-slot 1
  "Side-window slot of the Claude panel in the sandbox layout.")

(defun cezd--make-temp-file-buffer (suffix)
  "Create and visit a real temp file under the sandbox, return its buffer.
SUFFIX distinguishes files across scenarios.  Mimics a Claude
`claude-prompt-*.md' temp file."
  (let* ((path (expand-file-name
                (format "claude-prompt-%s.md" suffix)
                sandbox--test-dir))
         (buf (find-file-noselect path)))
    (with-current-buffer buf
      (erase-buffer)
      (insert "prompt draft\n")
      (save-buffer))
    buf))

(defun cezd--windows-showing (buf)
  "Return the list of live windows in the selected frame showing BUF."
  (seq-filter (lambda (w) (eq (window-buffer w) buf))
              (window-list nil 'no-minibuf)))

(defun cezd--log-summary (tag)
  "Log the window summary under TAG."
  (knayawp-probe-log "  %s window-summary:" tag)
  (dolist (entry (knayawp-probe-window-summary))
    (knayawp-probe-log "    %S" entry)))

(defun cezd--abort-stub (buf)
  "Call `knayawp--claude-edit-abort' in BUF with the session stubbed."
  (cl-letf (((symbol-function 'server-edit) #'ignore)
            ((symbol-function 'save-buffer) #'ignore))
    (with-current-buffer buf
      (knayawp--claude-edit-abort))))

(defun cezd--run-scenario (label style suffix)
  "Drive the zoomed-pane edit flow under STYLE, assert single-window.
LABEL names the scenario for the report; SUFFIX names the temp file."
  (knayawp-probe-section label)
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir))
            (knayawp-claude-edit-style style)
            (temp-buf nil))
        (knayawp-probe-setup-layout)
        ;; 1. Select and zoom the Claude panel.
        (knayawp-probe-select-slot cezd--claude-slot)
        (knayawp-zoom-panel)
        (sit-for 0.2)
        (knayawp-probe-assert-zoomed 'claude (format "%s-zoomed" suffix))
        ;; 2. server-visit-hook captures origin (Claude pane still selected).
        (setq temp-buf (cezd--make-temp-file-buffer suffix))
        (with-current-buffer temp-buf
          (knayawp--claude-edit-record-origin))
        ;; 3. Simulate server-switch-buffer's own display + focus move,
        ;;    exactly as Emacs does before our server-switch-hook runs.
        (let ((routed (display-buffer temp-buf)))
          (when (window-live-p routed)
            (set-frame-selected-window (window-frame routed) routed)))
        (cezd--log-summary (format "%s-after-server-switch-buffer" suffix))
        (knayawp-probe-log "  %s windows-showing-temp(after switch-buffer)=%d"
                           suffix (length (cezd--windows-showing temp-buf)))
        ;; 4. server-switch-hook re-routes per edit-style.
        (with-current-buffer temp-buf
          (knayawp--claude-editor-server-switch))
        (sit-for 0.2)
        (cezd--log-summary (format "%s-after-server-switch-hook" suffix))
        ;; Core assertion: the temp buffer must be in exactly ONE window.
        (let ((n (length (cezd--windows-showing temp-buf))))
          (knayawp-probe-log "  %s windows-showing-temp(after hook)=%d"
                             suffix n)
          (knayawp-probe-check
           (format "%s-temp-in-single-window" suffix) 1 n))
        ;; C-g abort, then re-check (the user's actual recovery action).
        (cezd--abort-stub temp-buf)
        (sit-for 0.2)
        (cezd--log-summary (format "%s-after-abort" suffix))
        (let ((n (length (cezd--windows-showing temp-buf))))
          (knayawp-probe-log "  %s windows-showing-temp(after abort)=%d"
                             suffix n)
          (knayawp-probe-check
           (format "%s-temp-single-window-after-abort" suffix) 1 n))
        (when (buffer-live-p temp-buf) (kill-buffer temp-buf)))
    (error (knayawp-probe-abort "%s failed: %S" label e)))
  (knayawp-probe-teardown-layout))

;;;; Drive all scenarios

(knayawp-probe-watchdog 90)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-probe-log "  probe start  default-directory=%S" default-directory)
      (cezd--run-scenario
       "SCENARIO 1 -- claude-panel style, zoomed Claude pane"
       'claude-panel "s1")
      (cezd--run-scenario
       "SCENARIO 2 -- zoom style, zoomed Claude pane"
       'zoom "s2"))
  (error (knayawp-probe-abort "top-level error: %S" e)))

(knayawp-probe-finish)

;;; claude-edit-zoomed-dual-window.el ends here
