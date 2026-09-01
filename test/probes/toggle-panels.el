;;; toggle-panels.el --- Probe for knayawp-toggle-panels (issue #104) -*- lexical-binding: t; -*-

;;; Commentary:

;; Three-scenario probe for `knayawp-toggle-panels'.  Run via the suite
;; (test/run-probes.sh) or individually:
;;   test/run-probe.sh test/probes/toggle-panels.el
;;
;; `knayawp-toggle-panels' wraps `window-toggle-side-windows', which
;; atomically hides all side windows (saving them) and restores them on
;; the next call.  The probe verifies:
;;
;; Scenario 1 — toggle off: setup layout, call toggle once; all side windows
;;   must be hidden (0 side windows remain in the frame).
;;
;; Scenario 2 — toggle off then on: call toggle a second time; all three
;;   side windows must be restored.
;;
;; Scenario 3 — idempotence across 3 cycles: toggle off, on, off in
;;   sequence; after each transition the expected side-window count must
;;   hold (0 then 3 then 0), confirming the toggle is stable over multiple
;;   presses.
;;
;; Note on window counts: `test/sandbox.el' opens a `*knayawp-sandbox*'
;; help window.  All total-window counts include it:
;;   Full layout:    5 total (3 panels + editor + sandbox helper).
;;   Panels hidden:  2 total (editor + sandbox helper).

;;; Code:

(require 'cl-lib)
(require 'seq)

;;;; Helpers

(defun toggle--settle ()
  "Pump the event loop briefly to let timers and redraws settle."
  (sit-for 0.3))

(defun toggle--setup-layout ()
  "Activate `knayawp-mode' and create a fresh layout."
  (knayawp-mode 1)
  (setq knayawp-magit-commit-style 'off)
  (setq knayawp--zoomed-panel nil)
  (set-frame-parameter nil 'knayawp--monocle-config nil)
  (knayawp-layout-setup)
  (toggle--settle))

(defun toggle--teardown-layout ()
  "Tear down the layout; restore side windows first if hidden."
  ;; knayawp-toggle-panels stores the saved window configuration under
  ;; knayawp--panels-hidden-config.  Restore before teardown so
  ;; knayawp-layout-teardown sees the full layout.
  (when (frame-parameter nil 'knayawp--panels-hidden-config)
    (knayawp-toggle-panels)
    (toggle--settle))
  (when (frame-parameter nil 'knayawp--monocle-config)
    (knayawp-monocle-panel)
    (toggle--settle))
  (ignore-errors (knayawp-layout-teardown))
  (toggle--settle))

(defun toggle--count-side-windows ()
  "Return the count of side windows in the selected frame."
  (length (knayawp-probe-side-windows)))

(defun toggle--count-windows ()
  "Return total live windows (minibuffer excluded)."
  (length (window-list nil 'nomini)))

;;;; Scenario 1: toggle off — side windows hidden

(defun toggle--scenario-1 ()
  "Scenario 1 — toggle panels off: side windows become hidden."
  (knayawp-probe-section "SCENARIO 1 -- toggle off (side windows hidden)")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (toggle--setup-layout)
        (knayawp-probe-log "  pre-toggle windows: %S"
                           (knayawp-probe-window-summary))
        (knayawp-probe-check "s1-pre-side-wins" 3
                             (toggle--count-side-windows))
        (knayawp-probe-check "s1-pre-total" 5
                             (toggle--count-windows))
        ;; Toggle panels off.
        (knayawp-toggle-panels)
        (toggle--settle)
        (knayawp-probe-log "  post-toggle-off windows: %S"
                           (knayawp-probe-window-summary))
        ;; All side windows must be hidden.
        (knayawp-probe-check "s1-side-wins-hidden" 0
                             (toggle--count-side-windows))
        ;; Only editor + sandbox helper remain visible.
        (knayawp-probe-check "s1-total-hidden" 2
                             (toggle--count-windows)))
    (error (knayawp-probe-abort "s1 failed: %S" e)))
  (toggle--teardown-layout))

;;;; Scenario 2: toggle off then on — side windows restored

(defun toggle--scenario-2 ()
  "Scenario 2 — toggle off then on restores all three side windows."
  (knayawp-probe-section "SCENARIO 2 -- toggle off then on (side windows restored)")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (toggle--setup-layout)
        ;; First toggle: panels off.
        (knayawp-toggle-panels)
        (toggle--settle)
        (knayawp-probe-check "s2-panels-off" 0
                             (toggle--count-side-windows))
        ;; Second toggle: panels on.
        (knayawp-toggle-panels)
        (toggle--settle)
        (knayawp-probe-log "  post-restore windows: %S"
                           (knayawp-probe-window-summary))
        ;; All three side windows must be back.
        (knayawp-probe-check "s2-panels-restored" 3
                             (toggle--count-side-windows))
        ;; Full layout: 5 windows.
        (knayawp-probe-check "s2-total-restored" 5
                             (toggle--count-windows)))
    (error (knayawp-probe-abort "s2 failed: %S" e)))
  (toggle--teardown-layout))

;;;; Scenario 3: three-cycle idempotence

(defun toggle--scenario-3 ()
  "Scenario 3 — three toggle cycles (off/on/off) are stable."
  (knayawp-probe-section "SCENARIO 3 -- three-cycle idempotence (off/on/off)")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (toggle--setup-layout)
        ;; Cycle 1: toggle off.
        (knayawp-toggle-panels)
        (toggle--settle)
        (knayawp-probe-log "  after cycle-1 (off) windows: %S"
                           (knayawp-probe-window-summary))
        (knayawp-probe-check "s3-cycle1-side-wins" 0
                             (toggle--count-side-windows))
        (knayawp-probe-check "s3-cycle1-total" 2
                             (toggle--count-windows))
        ;; Cycle 2: toggle on.
        (knayawp-toggle-panels)
        (toggle--settle)
        (knayawp-probe-log "  after cycle-2 (on) windows: %S"
                           (knayawp-probe-window-summary))
        (knayawp-probe-check "s3-cycle2-side-wins" 3
                             (toggle--count-side-windows))
        (knayawp-probe-check "s3-cycle2-total" 5
                             (toggle--count-windows))
        ;; Cycle 3: toggle off again.
        (knayawp-toggle-panels)
        (toggle--settle)
        (knayawp-probe-log "  after cycle-3 (off) windows: %S"
                           (knayawp-probe-window-summary))
        (knayawp-probe-check "s3-cycle3-side-wins" 0
                             (toggle--count-side-windows))
        (knayawp-probe-check "s3-cycle3-total" 2
                             (toggle--count-windows)))
    (error (knayawp-probe-abort "s3 failed: %S" e)))
  (toggle--teardown-layout))

;;;; Drive all scenarios

(knayawp-probe-watchdog 90)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-probe-log "  probe start  default-directory=%S" default-directory)
      (toggle--scenario-1)
      (toggle--scenario-2)
      (toggle--scenario-3))
  (error (knayawp-probe-abort "top-level error: %S" e)))

(knayawp-probe-finish)

;;; toggle-panels.el ends here
