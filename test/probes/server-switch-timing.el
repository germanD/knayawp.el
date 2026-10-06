;;; server-switch-timing.el --- Probe for server-switch-hook origin timing -*- lexical-binding: t; -*-

;;; Commentary:

;; Diagnostic probe for finding 3 from the PR #166 review: does
;; `knayawp--claude-editor-server-switch' capture the correct origin
;; window when called from the real `server-switch-hook'?
;;
;; Background
;; ----------
;; `server-switch-hook' fires AFTER `server-switch-buffer' has already
;; called `display-buffer' + `set-frame-selected-window', so by hook
;; time `(selected-window)' reflects the window Emacs chose for the
;; temp file — not the window the user was in before the edit.
;;
;; The knayawp hook captures `(selected-window)' as `origin' before
;; re-routing the buffer via `knayawp--claude-edit-display-buffer'.
;; Whether this captures the right window depends on what
;; `server-switch-buffer' left as the selected window.
;;
;; Two scenarios
;; -------------
;; Scenario 1 — DIRECT call (existing probe baseline):
;;   Select Claude panel, call the hook directly without going through
;;   `server-switch-buffer'.  `(selected-window)' = Claude panel.
;;   Origin should be Claude panel.  Expected: GREEN.
;;
;; Scenario 2 — SIMULATED server-switch-buffer flow:
;;   Select Claude panel, then simulate `server-switch-buffer' by
;;   calling `(display-buffer tmp-buf)' (no action constraints, so
;;   Emacs chooses where) and selecting the resulting window — exactly
;;   as `server-switch-buffer' does with `set-frame-selected-window'.
;;   THEN call the hook.  `(selected-window)' is now wherever Emacs
;;   routed the file (typically the editor pane in a knayawp layout).
;;   Origin captured = ?
;;
;;   If origin = Claude panel → PASS  (finding 3 REFUTED)
;;   If origin = editor pane  → FAIL  (finding 3 CONFIRMED)
;;
;; How to run
;; ----------
;;   bash test/run-probe.sh test/probes/server-switch-timing.el
;;
;; Interpreting the result
;; -----------------------
;; STATUS: GREEN  — scenario 2 PASS: the hook captures Claude panel as
;;                  origin even after server-switch-buffer moves focus.
;;                  Finding 3 is REFUTED; no fix needed.
;;
;; STATUS: RED    — scenario 2 FAIL: origin = editor pane, not Claude
;;                  panel.  Finding 3 is CONFIRMED.  The fix: capture
;;                  origin earlier (e.g. save it when the Claude CLI
;;                  opens the session, not at hook time) or use
;;                  `window-point-insertion-type' / frame history to
;;                  identify the user's prior window.
;;
;; Note on window counts: `test/sandbox.el' opens a `*knayawp-sandbox*'
;; help window.  Full layout: 3 panels + editor + sandbox helper = 5 windows.

;;; Code:

(require 'cl-lib)

(unless (require 'vterm nil t)
  (when (require 'eat nil t)
    (setq knayawp-terminal-backend 'eat)))

(defvar sst--claude-slot 1
  "Side-window slot of the Claude panel in the sandbox layout.")

(defun sst--make-temp-buf (suffix)
  "Create and visit a real temp file; return its buffer."
  (let* ((path (expand-file-name
                (format "sst-probe-%s.txt" suffix)
                sandbox--test-dir))
         (buf (find-file-noselect path)))
    (with-current-buffer buf
      (erase-buffer)
      (insert "probe draft\n")
      (save-buffer))
    buf))

(defun sst--abort-stub (buf)
  "Call `knayawp--claude-edit-abort' in BUF with session stubs."
  (cl-letf (((symbol-function 'server-edit) #'ignore)
            ((symbol-function 'save-buffer) #'ignore))
    (with-current-buffer buf
      (knayawp--claude-edit-abort))))

;;;; Scenario 1: direct call — baseline

(defun sst--scenario-1 ()
  "Scenario 1 — direct hook call from Claude panel: origin = Claude panel."
  (knayawp-probe-section "SCENARIO 1 -- direct call (baseline)")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir))
            (knayawp-claude-edit-style 'claude-panel)
            tmp-buf)
        (knayawp-probe-setup-layout)
        ;; Select Claude panel — this is where the user is before C-g.
        (knayawp-probe-select-slot sst--claude-slot)
        (setq tmp-buf (sst--make-temp-buf "s1"))
        ;; Direct call, no server-switch-buffer: selected-window = Claude panel.
        (with-current-buffer tmp-buf
          (knayawp--claude-editor-server-switch))
        (sit-for 0.2)
        ;; Abort.
        (sst--abort-stub tmp-buf)
        (sit-for 0.2)
        ;; After abort: focus should be Claude panel.
        (knayawp-probe-assert-total-window-count 5 "s1-layout-intact")
        (knayawp-probe-assert-selected-window-slot
         sst--claude-slot "s1-origin-is-claude-panel")
        (when (buffer-live-p tmp-buf) (kill-buffer tmp-buf)))
    (error (knayawp-probe-abort "s1 failed: %S" e)))
  (knayawp-probe-teardown-layout))

;;;; Scenario 2: simulated server-switch-buffer flow — the real test

(defun sst--scenario-2 ()
  "Scenario 2 — simulated server-switch-buffer: tests hook timing."
  (knayawp-probe-section "SCENARIO 2 -- simulated server-switch-buffer flow")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir))
            (knayawp-claude-edit-style 'claude-panel)
            tmp-buf routed-win)
        (knayawp-probe-setup-layout)
        ;; Select Claude panel — user is here before C-g.
        (knayawp-probe-select-slot sst--claude-slot)
        (setq tmp-buf (sst--make-temp-buf "s2"))
        ;; Simulate server-switch-buffer: display-buffer with no action
        ;; constraints (Emacs picks a non-dedicated window — editor pane)
        ;; then select the resulting window, as server-switch-buffer does
        ;; via set-frame-selected-window.
        (setq routed-win (display-buffer tmp-buf))
        (when (window-live-p routed-win)
          (set-frame-selected-window (window-frame routed-win) routed-win))
        (knayawp-probe-log "  After simulated server-switch-buffer:")
        (knayawp-probe-log "    selected-window=%S" (selected-window))
        (knayawp-probe-log "    routed-win=%S" routed-win)
        (knayawp-probe-log "    claude-panel-win=%S"
                           (knayawp--side-window-for-slot sst--claude-slot))
        ;; NOW call the hook — just like server-switch-hook would.
        (with-current-buffer tmp-buf
          (knayawp--claude-editor-server-switch))
        (sit-for 0.2)
        ;; Check what origin was recorded.
        (let ((recorded-origin
               (buffer-local-value 'knayawp--claude-edit-origin-window
                                   tmp-buf))
              (claude-win (knayawp--side-window-for-slot sst--claude-slot)))
          (knayawp-probe-log "  recorded origin=%S" recorded-origin)
          (knayawp-probe-log "  claude-panel-win=%S" claude-win)
          ;; The key assertion: did we capture the Claude panel as origin?
          (knayawp-probe-check "s2-origin-is-claude-panel"
                               claude-win
                               recorded-origin
                               #'eq))
        ;; Abort and verify focus.
        (sst--abort-stub tmp-buf)
        (sit-for 0.2)
        (knayawp-probe-assert-total-window-count 5 "s2-layout-intact")
        (knayawp-probe-assert-selected-window-slot
         sst--claude-slot "s2-abort-focus-on-claude-panel")
        (when (buffer-live-p tmp-buf) (kill-buffer tmp-buf)))
    (error (knayawp-probe-abort "s2 failed: %S" e)))
  (knayawp-probe-teardown-layout))

;;;; Drive all scenarios

(knayawp-probe-watchdog 90)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-probe-log "  probe start  default-directory=%S" default-directory)
      (sst--scenario-1)
      (sst--scenario-2))
  (error (knayawp-probe-abort "top-level error: %S" e)))

(knayawp-probe-finish)

;;; server-switch-timing.el ends here
