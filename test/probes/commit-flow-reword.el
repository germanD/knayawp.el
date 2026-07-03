;;; commit-flow-reword.el --- Commit-flow regression: reword via with-editor -*- lexical-binding: t; -*-

;;; Commentary:

;; Commit-flow regression probe (reword via with-editor).  Run via the
;; suite (test/run-probes.sh) or:
;;   test/run-probe.sh test/probes/commit-flow-reword.el
;;
;; Scenario 6 — reword commit message (`zoom' style).  A message buffer
;; opened by `magit-commit-reword' (the with-editor path through an
;; amend/rebase, NOT `magit-commit-create') must drive the SAME zoom
;; flow: zoom fires, the edit buffer is focused in the magit slot, and on
;; finish the 3-panel layout is restored with the magit slot back to
;; magit-status.

;;; Code:

(require 'cl-lib)

(defun pr76-s6--probe-a ()
  "PROBE A — reword buffer open; the zoom flow must have engaged."
  (knayawp-probe-section "PROBE A -- mid-edit (reword buffer open)")
  (let* ((win (selected-window))
         (buf (buffer-name (window-buffer win))))
    (knayawp-probe-log "  edit-buf=%S edit-side=%S windows: %S"
                       buf (window-parameter win 'window-side)
                       (knayawp-probe-window-summary))
    (knayawp-probe-check "commit-flow-active" t
                         (knayawp--commit-flow-active-p))
    (knayawp-probe-check "edit-side" 'right
                         (window-parameter win 'window-side))
    (knayawp-probe-check "was-zoomed" nil
                         (plist-get knayawp--commit-pre-state :was-zoomed))
    (knayawp-probe-check "zoomed" 'magit knayawp--zoomed-panel)
    (knayawp-probe-check "side-window-count" 1
                         (length (knayawp-probe-side-windows)))))

(defun pr76-s6--probe-b ()
  "PROBE B — post-finish; full layout restored, magit-status back."
  (knayawp-probe-section "PROBE B -- post-finish (layout restored)")
  (let* ((spec (assq 'magit knayawp-panels))
         (slot (and spec (knayawp--panel-slot spec)))
         (mwin (and slot (knayawp--side-window-for-slot slot)))
         (mbuf (and mwin (buffer-name (window-buffer mwin)))))
    (knayawp-probe-log "  magit-slot-buf=%S windows: %S"
                       mbuf (knayawp-probe-window-summary))
    (knayawp-probe-check "commit-flow-inactive" nil
                         (knayawp--commit-flow-active-p))
    (knayawp-probe-check "zoomed-nil" nil knayawp--zoomed-panel)
    (knayawp-probe-check "side-window-count" 3
                         (length (knayawp-probe-side-windows)))
    (knayawp-probe-check "magit-slot-is-status" t
                         (and mbuf (string-prefix-p "magit: " mbuf) t))
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

;; Reword HEAD (the sandbox initial commit) rather than creating a commit.
(knayawp-probe-drive-commit #'pr76-s6--probe-a #'pr76-s6--probe-b
                            (lambda ()
                              (let ((default-directory
                                     (file-name-as-directory
                                      sandbox--test-dir)))
                                (magit-commit-reword))))

;;; commit-flow-reword.el ends here
