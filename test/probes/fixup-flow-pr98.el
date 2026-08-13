;;; fixup-flow-pr98.el --- Fixup-focus flow probe for PR #98 -*- lexical-binding: t; -*-

;;; Commentary:

;; Probe for issue #98: auto-focus the `magit-log-select' buffer when
;; the user runs `c f' (fixup) in magit.  Run via the suite
;; (test/run-probes.sh) or:
;;   test/run-probe.sh test/probes/fixup-flow-pr98.el
;;
;; Scenarios:
;;   A — layout active, style `zoom': calling the setup handler focuses
;;       the magit slot (side window slot -1).
;;   B — after setup handler, calling finish handler returns focus to
;;       editor (per `knayawp-magit-fixup-focus-after' = `editor').
;;   C — after setup handler, calling cancel handler same as B.
;;   D — style `off': setup handler is a no-op, focus unchanged.
;;   E — no active layout: setup handler is a no-op.

;;; Code:

(require 'cl-lib)

;;;; Helpers

(defun pr98--magit-slot ()
  "Return the configured slot number for the magit panel."
  (let ((spec (assq 'magit knayawp-panels)))
    (and spec (knayawp--panel-slot spec))))

(defun pr98--magit-win ()
  "Return the magit side window, or nil."
  (let ((slot (pr98--magit-slot)))
    (and slot (knayawp--side-window-for-slot slot))))

(defun pr98--editor-win ()
  "Return the editor (non-side) window."
  (seq-find (lambda (w) (not (window-parameter w 'window-side)))
            (window-list)))

;;;; Scenario A — style zoom, layout active: setup handler focuses magit slot

(defun pr98--scenario-a ()
  "SCENARIO A: setup handler focuses the magit side window."
  (knayawp-probe-section "SCENARIO A -- setup handler focuses magit slot")
  (let* ((magit-win (pr98--magit-win))
         (editor-win (pr98--editor-win)))
    (knayawp-probe-log "  before: selected=%S magit-win=%S"
                       (buffer-name (window-buffer (selected-window)))
                       magit-win)
    ;; Start from the editor window.
    (select-window editor-win)
    (knayawp-probe-check "pre-focus-on-editor" nil
                         (window-parameter (selected-window) 'window-side))
    ;; Fire the setup handler directly (simulates magit-log-select-mode-hook).
    (knayawp--magit-log-select-setup-handler)
    (knayawp-probe-log "  after:  selected=%S active=%S"
                       (buffer-name (window-buffer (selected-window)))
                       (knayawp--fixup-flow-active-p))
    (knayawp-probe-check "flow-active" t
                         (knayawp--fixup-flow-active-p))
    (knayawp-probe-check "selected-is-magit-slot" -1
                         (window-parameter (selected-window) 'window-slot))))

;;;; Scenario B — finish handler returns focus to editor

(defun pr98--scenario-b ()
  "SCENARIO B: finish handler restores focus to the editor pane."
  (knayawp-probe-section "SCENARIO B -- finish handler -> editor focus")
  ;; Set up state as if the setup handler had run.
  (setq knayawp-magit-fixup-focus-after 'editor)
  (setq knayawp--fixup-pre-state
        (list :active t :pre-fixup-window (pr98--editor-win)))
  ;; Select the magit window first to simulate mid-fixup state.
  (when-let* ((mw (pr98--magit-win)))
    (select-window mw))
  (knayawp-probe-check "pre-handler-in-magit" 'right
                       (window-parameter (selected-window) 'window-side))
  (knayawp--magit-log-select-finish-handler)
  (knayawp-probe-check "flow-cleared" nil
                       (knayawp--fixup-flow-active-p))
  (knayawp-probe-check "focus-on-editor" nil
                       (window-parameter (selected-window) 'window-side)))

;;;; Scenario C — cancel handler returns focus to editor

(defun pr98--scenario-c ()
  "SCENARIO C: cancel handler restores focus to the editor pane."
  (knayawp-probe-section "SCENARIO C -- cancel handler -> editor focus")
  (setq knayawp-magit-fixup-focus-after 'editor)
  (setq knayawp--fixup-pre-state
        (list :active t :pre-fixup-window (pr98--editor-win)))
  (when-let* ((mw (pr98--magit-win)))
    (select-window mw))
  (knayawp-probe-check "pre-handler-in-magit" 'right
                       (window-parameter (selected-window) 'window-side))
  (knayawp--magit-log-select-cancel-handler)
  (knayawp-probe-check "flow-cleared" nil
                       (knayawp--fixup-flow-active-p))
  (knayawp-probe-check "focus-on-editor" nil
                       (window-parameter (selected-window) 'window-side)))

;;;; Scenario D — style off: setup handler is a no-op

(defun pr98--scenario-d ()
  "SCENARIO D: style `off' — setup handler does not move focus."
  (knayawp-probe-section "SCENARIO D -- style off, handler is no-op")
  (let ((knayawp-magit-fixup-style 'off)
        (knayawp--fixup-pre-state nil))
    (let ((editor (pr98--editor-win)))
      (select-window editor)
      (knayawp--magit-log-select-setup-handler)
      (knayawp-probe-check "focus-unchanged-editor" nil
                           (window-parameter (selected-window) 'window-side))
      (knayawp-probe-check "state-nil" nil
                           (knayawp--fixup-flow-active-p)))))

;;;; Scenario E — no active layout: setup handler is a no-op

(defun pr98--scenario-e ()
  "SCENARIO E: no active layout — setup handler does not move focus."
  (knayawp-probe-section "SCENARIO E -- no layout, handler is no-op")
  (let ((knayawp--active-layouts nil)
        (knayawp--fixup-pre-state nil)
        (knayawp-magit-fixup-style 'zoom))
    (let ((editor (pr98--editor-win)))
      (select-window editor)
      (knayawp--magit-log-select-setup-handler)
      (knayawp-probe-check "focus-unchanged-editor" nil
                           (window-parameter (selected-window) 'window-side))
      (knayawp-probe-check "state-nil" nil
                           (knayawp--fixup-flow-active-p)))))

;;;; Main probe body

(knayawp-probe-watchdog 60)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-mode 1)
      (setq knayawp-magit-fixup-style 'zoom)
      (setq knayawp-magit-fixup-focus-after 'editor)
      (knayawp-layout-setup))
  (error (knayawp-probe-abort "setup failed: %S" e)))

;; Give the layout a moment to settle before running checks.
(run-with-timer
 0.5 nil
 (lambda ()
   (condition-case e
       (progn
         (pr98--scenario-a)
         ;; Clear fixup state before next scenario.
         (setq knayawp--fixup-pre-state nil)
         (pr98--scenario-b)
         (pr98--scenario-c)
         (pr98--scenario-d)
         (pr98--scenario-e)
         (knayawp-probe-finish))
     (error (knayawp-probe-abort "probe error: %S" e)))))

;;; fixup-flow-pr98.el ends here
