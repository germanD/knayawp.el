;;; commit-flow-narrow-frame.el --- Commit-flow regression: narrow frame -*- lexical-binding: t; -*-

;;; Commentary:

;; Commit-flow regression probe (narrow frame).  Run via the suite
;; (test/run-probes.sh) or NARROW, explicitly:
;;   test/run-probe.sh test/probes/commit-flow-narrow-frame.el 40x50
;;
;; Probe-Geometry: 40x50
;;
;; Scenario 5 — narrow frame.  At a width where a 3-way side-window split
;; is implausible, building the layout and attempting a commit must not
;; silently corrupt the window tree.  Acceptance: every window live, no
;; degenerate (zero/absurd-width) window, flow state not stuck.  A clean
;; `user-error' is acceptable and is recorded, not failed.
;;
;; Unlike the commit-completing probes, this one does NOT finish the
;; commit (a narrow frame may make that impossible); it captures
;; coherence shortly after the attempt and exits.

;;; Code:

(require 'cl-lib)

(defvar pr76-s5--setup-error nil "Error signalled by layout-setup, if any.")
(defvar pr76-s5--commit-error nil "Error signalled by the commit attempt.")

(defun pr76-s5--probe (reason)
  "Capture coherence of the window tree; REASON labels what triggered it."
  (unless knayawp-probe--finished
    (knayawp-probe-section (format "PROBE -- coherence after commit attempt (%s)" reason))
    (let* ((wins (window-list))
           (widths (mapcar #'window-width wins))
           (min-width (apply #'min widths)))
      (knayawp-probe-log "  frame-width=%d n-windows=%d widths=%S"
                         (frame-width) (length wins) widths)
      (knayawp-probe-log "  windows: %S" (knayawp-probe-window-summary))
      (knayawp-probe-log "  setup-error=%S commit-error=%S"
                         pr76-s5--setup-error pr76-s5--commit-error)
      ;; A user-error on either step is acceptable; a Lisp error whose
      ;; symbol is not `user-error' is treated as a crash.
      (knayawp-probe-check "setup-clean(no-crash)" t
                           (or (null pr76-s5--setup-error)
                               (eq (car pr76-s5--setup-error) 'user-error)))
      (knayawp-probe-check "commit-clean(no-crash)" t
                           (or (null pr76-s5--commit-error)
                               (eq (car pr76-s5--commit-error) 'user-error)))
      (knayawp-probe-check "all-windows-live" t
                           (seq-every-p #'window-live-p wins))
      (knayawp-probe-check "no-degenerate-window" t (> min-width 0))
      (knayawp-probe-check "flow-not-stuck" t
                           (or (not (knayawp--commit-flow-active-p))
                               ;; active is OK only if a real commit buffer
                               ;; backs it; a stuck flow has none.
                               (and (get-buffer "COMMIT_EDITMSG") t))))
    (knayawp-probe-finish)))

(knayawp-probe-watchdog 40)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-mode 1)
      (setq knayawp-magit-commit-style 'zoom)
      (condition-case se (knayawp-layout-setup)
        (error (setq pr76-s5--setup-error se))))
  (error (knayawp-probe-abort "mode/style setup failed: %S" e)))

;; Attempt the commit; at a narrow width this may error cleanly.
(condition-case ce (knayawp-probe-stage-and-commit)
  (error (setq pr76-s5--commit-error ce)))

;; Capture coherence after the attempt has had a moment to unfold.
(run-with-timer 6 nil (lambda () (pr76-s5--probe "settled")))

;;; commit-flow-narrow-frame.el ends here
