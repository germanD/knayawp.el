;;; commit-flow-manual-zoom.el --- Commit-flow regression: manual zoom -*- lexical-binding: t; -*-

;;; Commentary:

;; Commit-flow regression probe (manual zoom mid-commit).  Run via the
;; suite (test/run-probes.sh) or:
;;   test/run-probe.sh test/probes/commit-flow-manual-zoom.el
;;
;; Scenario 3 — manual zoom mid-commit (`zoom' style).  The user zooms
;; the magit slot BEFORE committing.  The flow must NOT double-zoom and,
;; on finish, must NOT re-expand to 3 panels (the manual zoom is the
;; user's).  Expectations are copied from the interactive probe's
;; documented EXPECTED / VERDICT blocks.

;;; Code:

(require 'cl-lib)

(defun pr76-s3--probe-a ()
  "PROBE A — after the user manually zooms the magit slot."
  (knayawp-probe-section "PROBE A -- pre-commit, user manually zoomed")
  (knayawp-probe-log "  windows: %S" (knayawp-probe-window-summary))
  (knayawp-probe-check "zoomed" 'magit knayawp--zoomed-panel)
  (knayawp-probe-check "side-window-count" 1
                       (length (knayawp-probe-side-windows))))

(defun pr76-s3--probe-b ()
  "PROBE B — mid-commit; the guard must prevent a double-zoom."
  (knayawp-probe-section "PROBE B -- mid-commit (no double-zoom)")
  (let* ((win (get-buffer-window "COMMIT_EDITMSG"))
         (side (and win (window-parameter win 'window-side))))
    (knayawp-probe-log "  commit-window=%S side=%S selected-buf=%S"
                       win side
                       (buffer-name (window-buffer (selected-window))))
    (knayawp-probe-check "was-zoomed" 'magit
                         (plist-get knayawp--commit-pre-state :was-zoomed))
    (knayawp-probe-check "commit-flow-active" t
                         (knayawp--commit-flow-active-p))
    (knayawp-probe-check "zoomed" 'magit knayawp--zoomed-panel)
    (knayawp-probe-check "commit-win-side" 'right side)
    (knayawp-probe-check "side-window-count" 1
                         (length (knayawp-probe-side-windows)))))

(defun pr76-s3--probe-c ()
  "PROBE C — post-finish; manual zoom preserved, no re-expand."
  (knayawp-probe-section "PROBE C -- post-finish (manual zoom preserved)")
  (knayawp-probe-log "  windows: %S" (knayawp-probe-window-summary))
  (knayawp-probe-check "commit-flow-inactive" nil
                       (knayawp--commit-flow-active-p))
  (knayawp-probe-check "zoomed" 'magit knayawp--zoomed-panel)
  (knayawp-probe-check "side-window-count" 1
                       (length (knayawp-probe-side-windows)))
  (knayawp-probe-finish))

(knayawp-probe-watchdog 60)

;; Setup: zoom style, layout, then MANUALLY zoom the magit panel.
(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-mode 1)
      (setq knayawp-magit-commit-style 'zoom)
      (knayawp-layout-setup)
      (knayawp-select-panel 1)          ; focus magit
      (knayawp-zoom-panel)              ; manual zoom
      (pr76-s3--probe-a))
  (error (knayawp-probe-abort "setup failed: %S" e)))

;; Drive the commit.  knayawp's own zoom handlers fire first; our probes
;; (appended) observe the result.
(knayawp-probe-drive-commit #'pr76-s3--probe-b #'pr76-s3--probe-c)

;;; commit-flow-manual-zoom.el ends here
