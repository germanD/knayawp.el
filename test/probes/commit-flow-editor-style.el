;;; commit-flow-editor-style.el --- Commit-flow regression: editor style -*- lexical-binding: t; -*-

;;; Commentary:

;; Commit-flow regression probe (`editor' style).  Run via the suite
;; (test/run-probes.sh) or individually with:
;;
;;   test/run-probe.sh test/probes/commit-flow-editor-style.el
;;
;; Scenario 2 — `editor' commit style.  With the resolved style
;; `editor', the reconcile fix (585ffec) must INSTALL the COMMIT_EDITMSG
;; `display-buffer-alist' entry and REMOVE the zoom commit-flow hooks.
;; The commit message buffer should then land in the editor pane, not a
;; side slot, and tearing the commit down must leave a coherent layout.
;;
;; The check expectations below are copied from the documented
;; "EXPECTED (post-fix)" blocks in the interactive probe.  Where the
;; recorded manual run disagreed with that oracle (PROBE B placement),
;; this probe still asserts the documented expectation so the harness
;; reports the discrepancy honestly rather than rubber-stamping it.

;;; Code:

(require 'cl-lib)

(defvar pr76-s2--message "probe: stub commit message\n"
  "Commit message inserted into COMMIT_EDITMSG during the probe.")

;;;; Probe points

(defun pr76-s2--probe-a ()
  "PROBE A — state right after `knayawp-layout-setup' (style editor)."
  (knayawp-probe-section "PROBE A -- post-setup state (style=editor)")
  (knayawp-probe-check "mode" t knayawp-mode)
  (knayawp-probe-check "style" 'editor knayawp-magit-commit-style)
  (knayawp-probe-check "resolved" 'editor (knayawp--resolve-commit-style))
  (knayawp-probe-check "entry-installed" t
                       (and knayawp--commit-display-entry t))
  (knayawp-probe-check "hooks-installed" nil
                       knayawp--commit-hooks-installed)
  (knayawp-probe-check "magit-display-fn" t
                       (eq magit-display-buffer-function
                           #'knayawp--magit-display-buffer)))

(defun pr76-s2--probe-b ()
  "PROBE B — state while COMMIT_EDITMSG is displayed, before finish."
  (knayawp-probe-section "PROBE B -- mid-commit (COMMIT_EDITMSG shown)")
  (let* ((win (get-buffer-window "COMMIT_EDITMSG"))
         (side (and win (window-parameter win 'window-side)))
         (slot (and win (window-parameter win 'window-slot))))
    (knayawp-probe-log "  commit-window=%S side=%S slot=%S" win side slot)
    (knayawp-probe-log "  windows: %S" (knayawp-probe-window-summary))
    (knayawp-probe-check "commit-buf-live" t
                         (and (get-buffer "COMMIT_EDITMSG") t))
    (knayawp-probe-check "commit-win-live" t (and (window-live-p win) t))
    ;; Documented oracle: COMMIT_EDITMSG lands in the EDITOR pane
    ;; (window-side nil), and that window is selected.
    (knayawp-probe-check "commit-win-side(editor)" nil side)
    (knayawp-probe-check "commit-win-selected" t (eq win (selected-window)))
    (knayawp-probe-check "side-window-count" 3
                         (length (knayawp-probe-side-windows)))))

(defun pr76-s2--probe-c ()
  "PROBE C — state after the commit is finished."
  (knayawp-probe-section "PROBE C -- post-finish state")
  (knayawp-probe-log "  windows: %S" (knayawp-probe-window-summary))
  (knayawp-probe-check "commit-buf-gone" nil
                       (and (get-buffer "COMMIT_EDITMSG") t))
  (knayawp-probe-check "commit-flow-inactive" nil
                       (knayawp--commit-flow-active-p))
  (knayawp-probe-check "zoomed-nil" nil knayawp--zoomed-panel)
  (knayawp-probe-check "side-window-count" 3
                       (length (knayawp-probe-side-windows)))
  (knayawp-probe-finish))

;;;; Driver

(knayawp-probe-watchdog 60)

;; Setup: enable mode, select editor commit style, build the layout.
(condition-case e
    (progn
      (knayawp-mode 1)
      (setq knayawp-magit-commit-style 'editor)
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (knayawp-layout-setup))
      (pr76-s2--probe-a))
  (error (knayawp-probe-abort "setup failed: %S" e)))

;; Drive the editor-style commit: PROBE B mid-flow, PROBE C on finish.
(setq knayawp-probe-commit-message pr76-s2--message)
(knayawp-probe-drive-commit #'pr76-s2--probe-b #'pr76-s2--probe-c)

;;; commit-flow-editor-style.el ends here
