;;; commit-flow-off-switch.el --- Commit-flow regression: off kill-switch -*- lexical-binding: t; -*-

;;; Commentary:

;; Commit-flow regression probe (`off' kill-switch).  Run via the suite
;; (test/run-probes.sh) or:
;;   test/run-probe.sh test/probes/commit-flow-off-switch.el
;;
;; Scenario 7 — `off' kill-switch.  With `knayawp-magit-commit-style' set
;; to `off', knayawp installs NO commit-flow hooks and NO COMMIT_EDITMSG
;; display entry, but keeps `magit-display-buffer-function' routing magit
;; buffers into the layout.  A commit must complete with knayawp entirely
;; passive on the commit path.

;;; Code:

(require 'cl-lib)

(defun pr76-s7--probe-a ()
  "PROBE A — post-setup; knayawp passive on the commit path."
  (knayawp-probe-section "PROBE A -- post-setup state (style=off)")
  (knayawp-probe-check "style" 'off knayawp-magit-commit-style)
  (knayawp-probe-check "resolved" 'off (knayawp--resolve-commit-style))
  (knayawp-probe-check "entry-installed" nil
                       (and knayawp--commit-display-entry t))
  (knayawp-probe-check "hooks-installed" nil
                       knayawp--commit-hooks-installed)
  (knayawp-probe-check "magit-display-fn" t
                       (eq magit-display-buffer-function
                           #'knayawp--magit-display-buffer)))

(defun pr76-s7--probe-b ()
  "PROBE B — post-commit; knayawp never engaged the flow."
  (knayawp-probe-section "PROBE B -- post-commit (knayawp stayed passive)")
  (knayawp-probe-log "  windows: %S" (knayawp-probe-window-summary))
  (knayawp-probe-check "commit-flow-inactive" nil
                       (knayawp--commit-flow-active-p))
  (knayawp-probe-check "commit-pre-state-nil" nil knayawp--commit-pre-state)
  (knayawp-probe-check "zoomed-nil" nil knayawp--zoomed-panel)
  (knayawp-probe-check "commit-buf-gone" nil
                       (and (get-buffer "COMMIT_EDITMSG") t))
  (knayawp-probe-check "all-windows-live" t
                       (seq-every-p #'window-live-p (window-list)))
  (knayawp-probe-finish))

(knayawp-probe-watchdog 60)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-mode 1)
      (setq knayawp-magit-commit-style 'off)
      (knayawp-layout-setup)
      (pr76-s7--probe-a))
  (error (knayawp-probe-abort "setup failed: %S" e)))

;; A normal commit; no mid probe — knayawp must do nothing special.
(knayawp-probe-drive-commit nil #'pr76-s7--probe-b)

;;; commit-flow-off-switch.el ends here
