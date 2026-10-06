;;; server-switch-timing.el --- Probe for server-visit-hook origin capture -*- lexical-binding: t; -*-

;;; Commentary:

;; Two-scenario probe verifying that `knayawp--claude-edit-record-origin'
;; (on `server-visit-hook') captures the correct origin window even when
;; `server-switch-buffer' subsequently moves focus elsewhere.  Run via:
;;   test/run-probe.sh test/probes/server-switch-timing.el
;;
;; Background
;; ----------
;; `server-switch-hook' fires AFTER `server-switch-buffer' has already
;; called `display-buffer' + `set-frame-selected-window', so any origin
;; captured there reflects the window Emacs chose for the temp file —
;; not the window the user was in before the edit.
;;
;; The fix (issue #164) moves origin capture to `server-visit-hook',
;; which fires BEFORE `server-switch-buffer'.  At visit-hook time
;; `(selected-window)' is still the user's original window.
;;
;; Two scenarios
;; -------------
;; Scenario 1 — DIRECT call (baseline):
;;   Select Claude panel, call record-origin then the switch hook directly
;;   without a simulated server-switch-buffer.  Origin = Claude panel.
;;   Expected: GREEN.
;;
;; Scenario 2 — SIMULATED server-switch-buffer flow (regression test):
;;   Select Claude panel, call record-origin (still Claude panel at that
;;   point), THEN simulate server-switch-buffer via display-buffer +
;;   set-frame-selected-window (moves focus to editor pane in CI),
;;   THEN call the switch hook.  Origin should still be the Claude panel
;;   because it was captured before focus moved.
;;   Expected: GREEN (was RED before the server-visit-hook fix).
;;
;; How to run
;; ----------
;;   bash test/run-probe.sh test/probes/server-switch-timing.el
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
        ;; Simulate visit-hook (fires before server-switch-buffer).
        (with-current-buffer tmp-buf
          (knayawp--claude-edit-record-origin))
        ;; Direct switch-hook call — no server-switch-buffer in between.
        (with-current-buffer tmp-buf
          (knayawp--claude-editor-server-switch))
        (sit-for 0.2)
        ;; Abort: focus should return to Claude panel.
        (sst--abort-stub tmp-buf)
        (sit-for 0.2)
        (knayawp-probe-assert-total-window-count 5 "s1-layout-intact")
        (knayawp-probe-assert-selected-window-slot
         sst--claude-slot "s1-origin-is-claude-panel")
        (when (buffer-live-p tmp-buf) (kill-buffer tmp-buf)))
    (error (knayawp-probe-abort "s1 failed: %S" e)))
  (knayawp-probe-teardown-layout))

;;;; Scenario 2: simulated server-switch-buffer flow — regression test for the fix

(defun sst--scenario-2 ()
  "Scenario 2 — visit-hook before server-switch-buffer: origin survives focus move."
  (knayawp-probe-section "SCENARIO 2 -- visit-hook fires before server-switch-buffer")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir))
            (knayawp-claude-edit-style 'claude-panel)
            tmp-buf routed-win)
        (knayawp-probe-setup-layout)
        ;; Select Claude panel — user is here before C-g.
        (knayawp-probe-select-slot sst--claude-slot)
        (setq tmp-buf (sst--make-temp-buf "s2"))
        ;; Step 1: visit-hook fires while Claude panel is still selected.
        (with-current-buffer tmp-buf
          (knayawp--claude-edit-record-origin))
        ;; Step 2: simulate server-switch-buffer moving focus away
        ;; (display-buffer picks a non-dedicated window — editor pane in CI).
        (setq routed-win (display-buffer tmp-buf))
        (when (window-live-p routed-win)
          (set-frame-selected-window (window-frame routed-win) routed-win))
        (knayawp-probe-log "  After simulated server-switch-buffer:")
        (knayawp-probe-log "    selected-window=%S" (selected-window))
        (knayawp-probe-log "    routed-win=%S" routed-win)
        (knayawp-probe-log "    claude-panel-win=%S"
                           (knayawp--side-window-for-slot sst--claude-slot))
        ;; Step 3: switch-hook fires with wrong selected-window (editor pane).
        (with-current-buffer tmp-buf
          (knayawp--claude-editor-server-switch))
        (sit-for 0.2)
        ;; The recorded origin should still be the Claude panel (set in step 1).
        (let ((recorded-origin
               (buffer-local-value 'knayawp--claude-edit-origin-window tmp-buf))
              (claude-win (knayawp--side-window-for-slot sst--claude-slot)))
          (knayawp-probe-log "  recorded origin=%S" recorded-origin)
          (knayawp-probe-log "  claude-panel-win=%S" claude-win)
          (knayawp-probe-check "s2-origin-is-claude-panel"
                               claude-win
                               recorded-origin
                               #'eq))
        ;; Abort: focus should return to Claude panel.
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
