;;; commit-focus-after.el --- Probe for knayawp-magit-commit-focus-after (issue #106) -*- lexical-binding: t; -*-

;;; Commentary:

;; Two-scenario probe for the `knayawp-magit-commit-focus-after' defcustom.
;; Run via the suite (test/run-probes.sh) or individually:
;;   test/run-probe.sh test/probes/commit-focus-after.el
;;
;; `knayawp-magit-commit-focus-after' controls which window is selected
;; after a `zoom'-style commit finishes via `with-editor-finish'.  The three
;; valid values are:
;;
;;   `editor'   — focus goes to the non-side editor window (default)
;;   `magit'    — focus goes to the magit side window (slot -1)
;;   `previous' — focus returns to the window selected before the commit
;;
;; Scenario 1 — value `magit': after `with-editor-finish', the selected
;;   window must be the magit side window (slot -1, window-side 'right).
;;
;; Scenario 2 — value `previous': focus must return to the window that was
;;   selected before `magit-commit-create' was invoked (captured in
;;   `knayawp--commit-pre-state' as `:pre-commit-window').  In this probe
;;   that window is the editor pane, but the key thing verified is that
;;   the focus-after machinery used the `:pre-commit-window' value (i.e.,
;;   the magit slot is NOT selected, confirming `magit' branch was not taken).
;;
;; Note on window counts: `test/sandbox.el' opens a `*knayawp-sandbox*'
;; help window.  All total-window counts include it:
;;   Full layout: 5 total (3 panels + editor + sandbox helper).

;;; Code:

(require 'cl-lib)
(require 'seq)

;;;; Helpers

(defun cfa--settle ()
  "Pump the event loop to let timers and redraws settle."
  (sit-for 0.5))

(defun cfa--setup-layout (focus-after)
  "Enable zoom commit style with FOCUS-AFTER and set up the layout."
  (knayawp-mode 1)
  (setq knayawp-magit-commit-style 'zoom)
  (setq knayawp-magit-commit-focus-after focus-after)
  (setq knayawp--zoomed-panel nil)
  (set-frame-parameter nil 'knayawp--monocle-config nil)
  (let ((default-directory (file-name-as-directory sandbox--test-dir)))
    (knayawp-layout-setup))
  (cfa--settle))

(defun cfa--count-side-windows ()
  "Return the count of side windows in the selected frame."
  (length (knayawp-probe-side-windows)))

(defun cfa--teardown-layout ()
  "Tear down the layout safely."
  (ignore-errors (knayawp-layout-teardown))
  (cfa--settle))

;;;; Scenario 1: focus-after `magit' — lands in magit side window

(defun cfa--scenario-1-mid ()
  "Probe B — mid-commit, before finish, focus-after=`magit'."
  (knayawp-probe-section "PROBE B -- mid-commit (focus-after=magit)")
  (knayawp-probe-log "  windows: %S" (knayawp-probe-window-summary))
  (knayawp-probe-check "s1b-commit-flow-active" t
                       (knayawp--commit-flow-active-p))
  (knayawp-probe-check "s1b-focus-after" 'magit
                       knayawp-magit-commit-focus-after))

(defun cfa--scenario-1-done ()
  "Probe C — post-finish, selected window should be the magit slot."
  (knayawp-probe-section "PROBE C -- post-finish (focus-after=magit)")
  (knayawp-probe-log "  windows: %S" (knayawp-probe-window-summary))
  ;; Commit state cleared.
  (knayawp-probe-check "s1c-flow-gone" nil
                       (knayawp--commit-flow-active-p))
  ;; Full layout restored.
  (knayawp-probe-check "s1c-side-wins" 3
                       (cfa--count-side-windows))
  ;; Focus must be in the magit slot: a right side window at slot -1.
  (let ((sel (selected-window)))
    (knayawp-probe-check "s1c-selected-side" 'right
                         (window-parameter sel 'window-side))
    (knayawp-probe-check "s1c-selected-slot" -1
                         (window-parameter sel 'window-slot)))
  ;; Teardown before chaining.
  (cfa--teardown-layout)
  ;; Chain scenario 2.
  (cfa--scenario-2))

;;;; Scenario 2: focus-after `previous' — returns to pre-commit window

(defun cfa--scenario-2-mid ()
  "Probe B — mid-commit, before finish, focus-after=`previous'."
  (knayawp-probe-section "PROBE B -- mid-commit (focus-after=previous)")
  (knayawp-probe-log "  windows: %S" (knayawp-probe-window-summary))
  (knayawp-probe-check "s2b-commit-flow-active" t
                       (knayawp--commit-flow-active-p))
  (knayawp-probe-check "s2b-focus-after" 'previous
                       knayawp-magit-commit-focus-after)
  ;; Verify the pre-commit window was captured.
  (let ((pre-win (and knayawp--commit-pre-state
                      (plist-get knayawp--commit-pre-state
                                 :pre-commit-window))))
    (knayawp-probe-check "s2b-pre-win-live" t
                         (and (window-live-p pre-win) t))))

(defun cfa--scenario-2-done ()
  "Probe C — post-finish, selected window should be the pre-commit window."
  (knayawp-probe-section "PROBE C -- post-finish (focus-after=previous)")
  (knayawp-probe-log "  windows: %S" (knayawp-probe-window-summary))
  ;; Commit state cleared.
  (knayawp-probe-check "s2c-flow-gone" nil
                       (knayawp--commit-flow-active-p))
  ;; Full layout restored.
  (knayawp-probe-check "s2c-side-wins" 3
                       (cfa--count-side-windows))
  ;; With `previous' and the pre-commit window being the editor pane, focus
  ;; must land in a non-side window (the editor).
  (knayawp-probe-check "s2c-focus-not-side" nil
                       (window-parameter (selected-window) 'window-side))
  ;; Additionally confirm we are NOT in the magit slot (which would happen
  ;; if the `magit' branch had been taken by mistake).
  (knayawp-probe-check "s2c-not-magit-slot" t
                       (not (eql -1 (window-parameter (selected-window)
                                                      'window-slot))))
  (cfa--teardown-layout)
  (knayawp-probe-finish))

(defun cfa--scenario-2 ()
  "Scenario 2 — focus-after `previous' returns to pre-commit window."
  (knayawp-probe-section "SCENARIO 2 -- focus-after=previous")
  (condition-case e
      (progn
        (cfa--setup-layout 'previous)
        ;; Ensure we are in the editor pane before the commit so it becomes
        ;; the `:pre-commit-window'.
        (knayawp-select-editor)
        (knayawp-probe-section "PROBE A -- post-setup state")
        (knayawp-probe-check "s2a-focus-after" 'previous
                             knayawp-magit-commit-focus-after)
        (knayawp-probe-check "s2a-editor-selected" nil
                             (window-parameter (selected-window)
                                              'window-side))
        (knayawp-probe-drive-commit
         #'cfa--scenario-2-mid
         #'cfa--scenario-2-done))
    (error (knayawp-probe-abort "s2 setup failed: %S" e))))

;;;; Scenario 1 entry point

(defun cfa--scenario-1 ()
  "Scenario 1 — focus-after `magit' selects magit panel after commit."
  (knayawp-probe-section "SCENARIO 1 -- focus-after=magit")
  (condition-case e
      (progn
        (cfa--setup-layout 'magit)
        ;; Start from the editor pane.
        (knayawp-select-editor)
        (knayawp-probe-section "PROBE A -- post-setup state")
        (knayawp-probe-check "s1a-focus-after" 'magit
                             knayawp-magit-commit-focus-after)
        (knayawp-probe-check "s1a-side-wins" 3
                             (cfa--count-side-windows))
        ;; Drive commit → done-fn chains into scenario 2.
        (knayawp-probe-drive-commit
         #'cfa--scenario-1-mid
         #'cfa--scenario-1-done))
    (error (knayawp-probe-abort "s1 setup failed: %S" e))))

;;;; Drive all scenarios

(knayawp-probe-watchdog 90)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-probe-log "  probe start  default-directory=%S" default-directory)
      ;; Scenario 1 is async; its done-fn chains into scenario 2; scenario 2's
      ;; done-fn calls knayawp-probe-finish.
      (cfa--scenario-1))
  (error (knayawp-probe-abort "top-level error: %S" e)))

;;; commit-focus-after.el ends here
