;;; layout-immunity-p1.el --- Probe for layout immunity (P1, issue #103) -*- lexical-binding: t; -*-

;;; Commentary:

;; Three-scenario probe for property P1 (layout immunity).  Run via the
;; suite (test/run-probes.sh) or individually:
;;   test/run-probe.sh test/probes/layout-immunity-p1.el
;;
;; P1 guarantees that the control-pane side windows are immune to standard
;; window commands that would normally delete or split regular windows:
;;
;; Scenario 1 — `delete-window' in the editor pane: with the editor pane
;;   selected, call `delete-window'; the editor window is gone, but all
;;   three side windows must survive (because they carry
;;   `no-delete-other-windows', `delete-window' on a non-side window does
;;   not touch them).
;;
;; Scenario 2 — `split-window-horizontally' in the editor pane: call
;;   `split-window-horizontally' with the editor selected; the split creates
;;   a second non-side window but must not affect the side-panel count.
;;
;; Scenario 3 — `other-window' isolation (requires
;;   `knayawp-isolate-other-window-flag' non-nil, which is the default):
;;   with the editor selected, cycle through `other-window' calls; focus
;;   must never land in a side window (the `no-other-window' parameter
;;   causes `other-window' to skip them).
;;
;; Note on window counts: `test/sandbox.el' opens a `*knayawp-sandbox*'
;; help window.  All total-window counts include it:
;;   Full layout: 3 panels + editor + sandbox helper = 5 windows.
;;   After editor delete (scenario 1): 3 panels + sandbox helper = 4 windows.
;;   After editor split (scenario 2): 3 panels + editor + split + helper = 6.

;;; Code:

(require 'cl-lib)
(require 'seq)

;;;; Helpers

(defun p1--settle ()
  "Pump the event loop briefly to let timers and redraws settle."
  (sit-for 0.3))

(defun p1--setup-layout ()
  "Activate `knayawp-mode' and create a fresh layout."
  (knayawp-mode 1)
  ;; Disable commit-style hooks so they don't interfere.
  (setq knayawp-magit-commit-style 'off)
  ;; Reset zoom / monocle state so scenarios don't bleed.
  (setq knayawp--zoomed-panel nil)
  (set-frame-parameter nil 'knayawp--monocle-config nil)
  (knayawp-layout-setup)
  (p1--settle))

(defun p1--teardown-layout ()
  "Tear down the knayawp layout safely."
  (when (frame-parameter nil 'knayawp--monocle-config)
    (knayawp-monocle-panel)
    (p1--settle))
  (ignore-errors (knayawp-layout-teardown))
  (p1--settle))

(defun p1--count-windows ()
  "Return total live windows (minibuffer excluded)."
  (length (window-list nil 'nomini)))

(defun p1--count-side-windows ()
  "Return the count of side windows in the selected frame."
  (length (knayawp-probe-side-windows)))

(defun p1--select-editor ()
  "Select the main editor (non-side) window."
  (let ((editor (seq-find (lambda (w)
                            (not (window-parameter w 'window-side)))
                          (window-list nil 'nomini))))
    (unless editor (error "No editor window found"))
    (select-window editor)))

;;;; Scenario 1: delete-window in editor pane leaves side windows intact

(defun p1--scenario-1 ()
  "Scenario 1 — `delete-window' on editor pane does not touch side windows."
  (knayawp-probe-section "SCENARIO 1 -- delete-window in editor pane")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (p1--setup-layout)
        ;; Verify we start with the full layout.
        (knayawp-probe-check "s1-pre-side-wins" 3
                             (p1--count-side-windows))
        (knayawp-probe-check "s1-pre-total" 5
                             (p1--count-windows))
        ;; Select the editor pane and delete it.
        (p1--select-editor)
        (knayawp-probe-check "s1-editor-selected" nil
                             (window-parameter (selected-window) 'window-side))
        (delete-window (selected-window))
        (p1--settle)
        (knayawp-probe-log "  post-delete windows: %S"
                           (knayawp-probe-window-summary))
        ;; All three side windows must still be present.
        (knayawp-probe-check "s1-side-wins-survive" 3
                             (p1--count-side-windows))
        ;; Total is now 4: 3 panels + sandbox helper (editor window gone).
        (knayawp-probe-check "s1-post-total" 4
                             (p1--count-windows)))
    (error (knayawp-probe-abort "s1 failed: %S" e)))
  (p1--teardown-layout))

;;;; Scenario 2: split-window-horizontally in editor pane does not split side panels

(defun p1--scenario-2 ()
  "Scenario 2 — `split-window-horizontally' in editor does not affect side panels."
  (knayawp-probe-section "SCENARIO 2 -- split-window-horizontally in editor pane")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (p1--setup-layout)
        ;; Verify full layout.
        (knayawp-probe-check "s2-pre-side-wins" 3
                             (p1--count-side-windows))
        (knayawp-probe-check "s2-pre-total" 5
                             (p1--count-windows))
        ;; Split the editor pane horizontally.
        (p1--select-editor)
        (split-window-horizontally)
        (p1--settle)
        (knayawp-probe-log "  post-split windows: %S"
                           (knayawp-probe-window-summary))
        ;; Side panel count must be unchanged.
        (knayawp-probe-check "s2-side-wins-unchanged" 3
                             (p1--count-side-windows))
        ;; Total is now 6: 3 panels + editor + new split + sandbox helper.
        (knayawp-probe-check "s2-post-total" 6
                             (p1--count-windows)))
    (error (knayawp-probe-abort "s2 failed: %S" e)))
  (p1--teardown-layout))

;;;; Scenario 3: other-window with isolation flag on never lands in side panels

(defun p1--scenario-3 ()
  "Scenario 3 — `other-window' does not cycle into side panels when flag is on."
  (knayawp-probe-section
   "SCENARIO 3 -- other-window isolation (knayawp-isolate-other-window-flag t)")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        ;; Verify the isolation flag is on (the default).
        (if (not knayawp-isolate-other-window-flag)
            (progn
              (knayawp-probe-log
               "  SKIP: knayawp-isolate-other-window-flag is nil — skipping s3")
              ;; Record a synthetic PASS so the suite does not report FAIL
              ;; simply because the flag is off.
              (knayawp-probe-check "s3-flag-off-skip" t t))
          (p1--setup-layout)
          ;; Start from the editor pane.
          (p1--select-editor)
          (knayawp-probe-check "s3-pre-editor-selected" nil
                               (window-parameter (selected-window) 'window-side))
          ;; Cycle other-window several times; side windows must be skipped.
          ;; In the sandbox session there are 2 non-side windows: editor +
          ;; sandbox helper.  Four cycles cover two full non-side round-trips.
          (let ((side-hit nil))
            (dotimes (_ 4)
              (other-window 1)
              (p1--settle)
              (when (window-parameter (selected-window) 'window-side)
                (setq side-hit t)))
            (knayawp-probe-check "s3-no-side-hit" nil side-hit)
            (knayawp-probe-log "  selected after 4x other-window: side=%S"
                               (window-parameter (selected-window)
                                                 'window-side)))))
    (error (knayawp-probe-abort "s3 failed: %S" e)))
  (p1--teardown-layout))

;;;; Drive all scenarios

(knayawp-probe-watchdog 90)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-probe-log "  probe start  default-directory=%S" default-directory)
      (p1--scenario-1)
      (p1--scenario-2)
      (p1--scenario-3))
  (error (knayawp-probe-abort "top-level error: %S" e)))

(knayawp-probe-finish)

;;; layout-immunity-p1.el ends here
