;;; commit-flow-delete-other-windows.el --- Commit-flow regression: C-x 1 -*- lexical-binding: t; -*-

;;; Commentary:

;; Commit-flow regression probe (`C-x 1' mid-commit).  Run via the suite
;; (test/run-probes.sh) or:
;;   test/run-probe.sh test/probes/commit-flow-delete-other-windows.el
;;
;; Scenario 4 — `C-x 1' mid-commit (`zoom' style).  With the magit slot
;; zoomed and showing COMMIT_EDITMSG, the user presses `C-x 1'.  The
;; protected magit slot must survive; on finish, knayawp's self-captured
;; winconf must restore the full 3-panel layout with the magit slot back
;; to magit-status.
;;
;; Note on `C-x 1': focus mid-commit is inside COMMIT_EDITMSG, which is a
;; side window, so `delete-other-windows' there signals "Cannot make side
;; window the only window" and is a no-op.  This probe records the actual
;; effect (window count + any error) rather than assuming the editor pane
;; is deleted; the load-bearing invariant is that the protected slot
;; survives and the winconf restore later rebuilds the layout (PROBE C).

;;; Code:

(require 'cl-lib)

(defun pr76-s4--probe-a ()
  "PROBE A — mid-commit, before `C-x 1'."
  (knayawp-probe-section "PROBE A -- mid-commit, before C-x 1")
  (let* ((win (get-buffer-window "COMMIT_EDITMSG")))
    (knayawp-probe-log "  windows: %S" (knayawp-probe-window-summary))
    (knayawp-probe-check "commit-flow-active" t
                         (knayawp--commit-flow-active-p))
    (knayawp-probe-check "commit-win-no-delete-other" t
                         (and win (window-parameter
                                   win 'no-delete-other-windows)))
    (knayawp-probe-check "commit-win-selected" t
                         (eq win (selected-window)))))

(defun pr76-s4--simulate-cx1 ()
  "Simulate `C-x 1' from the COMMIT_EDITMSG window; record the effect."
  (knayawp-probe-section "C-x 1 -- delete-other-windows from commit window")
  (let* ((win (get-buffer-window "COMMIT_EDITMSG"))
         (err nil))
    (when (window-live-p win) (select-window win))
    (condition-case e (delete-other-windows)
      (error (setq err e)))
    (knayawp-probe-log "  cx1-error=%S n-windows=%d windows=%S"
                       err (length (window-list))
                       (knayawp-probe-window-summary))
    ;; Load-bearing invariant: the protected magit slot survived.
    (knayawp-probe-check "magit-slot-survived" t
                         (and (window-live-p
                               (get-buffer-window "COMMIT_EDITMSG"))
                              t))))

(defun pr76-s4--mid ()
  "Mid-flow step: PROBE A, then `C-x 1'."
  (pr76-s4--probe-a)
  (pr76-s4--simulate-cx1))

(defun pr76-s4--probe-c ()
  "PROBE C — post-finish; winconf restore must rebuild the layout."
  (knayawp-probe-section "PROBE C -- post-finish (winconf restore)")
  (let* ((spec (assq 'magit knayawp-panels))
         (slot (and spec (knayawp--panel-slot spec)))
         (mwin (and slot (knayawp--side-window-for-slot slot)))
         (mbuf (and mwin (buffer-name (window-buffer mwin)))))
    (knayawp-probe-log "  windows: %S" (knayawp-probe-window-summary))
    (knayawp-probe-log "  magit-slot-buf=%S" mbuf)
    (knayawp-probe-check "commit-flow-inactive" nil
                         (knayawp--commit-flow-active-p))
    (knayawp-probe-check "commit-buf-gone" nil
                         (and (get-buffer "COMMIT_EDITMSG") t))
    (knayawp-probe-check "zoomed-nil" nil knayawp--zoomed-panel)
    (knayawp-probe-check "side-window-count" 3
                         (length (knayawp-probe-side-windows)))
    ;; Bug A guard: the magit slot shows magit-status, not *magit-diff*.
    (knayawp-probe-check "magit-slot-is-status" t
                         (and mbuf (string-prefix-p "magit: " mbuf) t))
    ;; focus-after defaults to editor => selected window is not a side.
    (knayawp-probe-check "focus-on-editor" nil
                         (window-parameter (selected-window)
                                           'window-side)))
  (knayawp-probe-finish))

(knayawp-probe-watchdog 60)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-mode 1)
      (setq knayawp-magit-commit-style 'zoom)
      (knayawp-layout-setup))
  (error (knayawp-probe-abort "setup failed: %S" e)))

;; Drive the commit: knayawp auto-zooms on setup; our mid step probes and
;; presses C-x 1; PROBE C checks the restore after finish.
(knayawp-probe-drive-commit #'pr76-s4--mid #'pr76-s4--probe-c)

;;; commit-flow-delete-other-windows.el ends here
