;;; commit-cancel-flow.el --- Probe for commit-cancel flow (issue #105) -*- lexical-binding: t; -*-

;;; Commentary:

;; Two-scenario probe for the magit commit-cancel flow under the `zoom'
;; commit style.  Run via the suite (test/run-probes.sh) or individually:
;;   test/run-probe.sh test/probes/commit-cancel-flow.el
;;
;; When the user opens a magit commit (COMMIT_EDITMSG appears in the magit
;; slot under zoom style) and then cancels it (`with-editor-cancel'), the
;; `with-editor-post-cancel-hook' fires.  knayawp's handler on that hook
;; calls `knayawp--commit-flow-end', which restores the pre-zoom 3-panel
;; layout and places focus per `knayawp-magit-commit-focus-after'.
;;
;; Scenario 1 — cancel after commit opens: setup layout (zoom style), drive
;;   a commit start, cancel before inserting a message via `with-editor-cancel',
;;   verify that the full 3-panel layout is restored, `knayawp--commit-pre-state'
;;   is nil (flow cleaned up), and focus is back in the editor pane (the default
;;   value of `knayawp-magit-commit-focus-after' is `editor').
;;
;; Scenario 2 — cancel when editor pane had a file open: same as scenario 1
;;   but with a specific file buffer in the editor before the commit starts;
;;   after cancel the editor pane should still show a non-side-window buffer
;;   (the file buffer or whatever the layout restore left there) and the
;;   side window count must be 3.
;;
;; Note on window counts: `test/sandbox.el' opens a `*knayawp-sandbox*'
;; help window.  All total-window counts include it:
;;   Full layout:   5 total (3 panels + editor + sandbox helper).
;;   During zoom:   3 total (magit slot + editor + sandbox helper).

;;; Code:

(require 'cl-lib)
(require 'seq)

;; `with-editor-cancel' is called at runtime after with-editor loads.
;; `magit-run-git' and `magit-commit-create' are declared in probe-lib.el.
(declare-function with-editor-cancel "with-editor")

;;;; Local cancel driver
;;
;; probe-lib provides `knayawp-probe-drive-commit' which finishes the commit.
;; We need a cancel variant: same hook-up but calls `with-editor-cancel'
;; instead of `with-editor-finish'.

(defvar commit-cancel--mid-fn nil
  "Function called once COMMIT_EDITMSG is open (before cancel).")

(defvar commit-cancel--done-fn nil
  "Function called after `with-editor-post-cancel-hook' fires.")

(defun commit-cancel--on-setup ()
  "One-shot `git-commit-setup-hook': run mid probe, then cancel."
  (remove-hook 'git-commit-setup-hook #'commit-cancel--on-setup)
  (let ((buf (current-buffer))
        (mid commit-cancel--mid-fn))
    (run-with-timer
     knayawp-probe--settle nil
     (lambda ()
       (condition-case e
           (progn
             (when mid (funcall mid))
             (when (buffer-live-p buf)
               (with-current-buffer buf
                 (with-editor-cancel nil))))
         (error (knayawp-probe-abort "cancel/mid failed: %S" e)))))))

(defun commit-cancel--on-cancel ()
  "One-shot `with-editor-post-cancel-hook': run done probe."
  (remove-hook 'with-editor-post-cancel-hook #'commit-cancel--on-cancel)
  (let ((done commit-cancel--done-fn))
    (run-with-timer
     knayawp-probe--settle nil
     (lambda ()
       (condition-case e (when done (funcall done))
         (error (knayawp-probe-abort "done failed: %S" e)))))))

(defun commit-cancel--stage-and-open ()
  "Edit hello.el, stage it, and open the commit editor without finishing."
  (let* ((default-directory (file-name-as-directory sandbox--test-dir))
         (file (expand-file-name "hello.el" sandbox--test-dir)))
    (with-temp-buffer
      (insert "\n;; cancel-probe edit\n")
      (append-to-file (point-min) (point-max) file))
    (magit-run-git "add" "hello.el")
    (magit-commit-create)))

(defun commit-cancel--drive (mid-fn done-fn)
  "Drive the commit-cancel flow: open commit, run MID-FN, cancel, run DONE-FN."
  (setq commit-cancel--mid-fn mid-fn
        commit-cancel--done-fn done-fn)
  (add-hook 'git-commit-setup-hook #'commit-cancel--on-setup t)
  (add-hook 'with-editor-post-cancel-hook #'commit-cancel--on-cancel t)
  (condition-case e
      (commit-cancel--stage-and-open)
    (error (knayawp-probe-abort "commit kickoff failed: %S" e))))

;;;; Helpers

(defun commit-cancel--settle ()
  "Pump the event loop to let timers and redraws settle."
  (sit-for 0.5))

(defun commit-cancel--setup-layout ()
  "Enable zoom commit style and set up the layout."
  (knayawp-mode 1)
  (setq knayawp-magit-commit-style 'zoom)
  (setq knayawp-magit-commit-focus-after 'editor)
  (setq knayawp--zoomed-panel nil)
  (set-frame-parameter nil 'knayawp--monocle-config nil)
  (let ((default-directory (file-name-as-directory sandbox--test-dir)))
    (knayawp-layout-setup))
  (commit-cancel--settle))

(defun commit-cancel--count-side-windows ()
  "Return the count of side windows in the selected frame."
  (length (knayawp-probe-side-windows)))

(defun commit-cancel--count-windows ()
  "Return total live windows (minibuffer excluded)."
  (length (window-list nil 'nomini)))

;;;; Scenario 1: cancel restores layout and clears commit state

(defun commit-cancel--scenario-1-mid ()
  "Probe B for scenario 1 — state while COMMIT_EDITMSG is open."
  (knayawp-probe-section "PROBE B -- mid-cancel (COMMIT_EDITMSG open)")
  (let* ((win (get-buffer-window "COMMIT_EDITMSG"))
         (side (and win (window-parameter win 'window-side))))
    (knayawp-probe-log "  commit-win=%S side=%S" win side)
    (knayawp-probe-log "  windows: %S" (knayawp-probe-window-summary))
    (knayawp-probe-check "s1b-commit-flow-active" t
                         (knayawp--commit-flow-active-p))
    ;; Under zoom style COMMIT_EDITMSG lands in the magit slot (a side window).
    (knayawp-probe-check "s1b-commit-win-live" t (and (window-live-p win) t))
    (knayawp-probe-check "s1b-commit-in-side" 'right side)))


;;;; Scenario 2: cancel when editor pane had a specific file open

(defun commit-cancel--scenario-2-mid ()
  "Probe B for scenario 2 — file buffer is open in editor before cancel."
  (knayawp-probe-section "PROBE B -- mid-cancel (file in editor)")
  (knayawp-probe-log "  windows: %S" (knayawp-probe-window-summary))
  (knayawp-probe-check "s2b-commit-flow-active" t
                       (knayawp--commit-flow-active-p)))

(defun commit-cancel--scenario-2-done ()
  "Probe C for scenario 2 — editor pane intact after cancel."
  (knayawp-probe-section "PROBE C -- post-cancel (editor pane intact)")
  (knayawp-probe-log "  windows: %S" (knayawp-probe-window-summary))
  ;; 3 side panels restored.
  (knayawp-probe-check "s2c-side-wins" 3
                       (commit-cancel--count-side-windows))
  ;; Commit state cleared.
  (knayawp-probe-check "s2c-flow-gone" nil
                       (knayawp--commit-flow-active-p))
  ;; A non-side window is selected (editor pane).
  (knayawp-probe-check "s2c-focus-not-side" nil
                       (window-parameter (selected-window) 'window-side))
  (knayawp-probe-finish))

(defun commit-cancel--scenario-2 ()
  "Scenario 2 — editor pane buffer is intact after commit cancel."
  (knayawp-probe-section "SCENARIO 2 -- editor pane intact after cancel")
  (condition-case e
      (progn
        (commit-cancel--setup-layout)
        ;; Open hello.el in the editor pane before starting the commit.
        (let* ((file (expand-file-name "hello.el" sandbox--test-dir))
               (file-buf (find-file-noselect file)))
          (knayawp-select-editor)
          (set-window-buffer (selected-window) file-buf)
          (commit-cancel--settle)
          (knayawp-probe-check "s2a-editor-shows-file" t
                               (string= (buffer-name (window-buffer
                                                       (selected-window)))
                                        (buffer-name file-buf))))
        (commit-cancel--drive
         #'commit-cancel--scenario-2-mid
         #'commit-cancel--scenario-2-done))
    (error (knayawp-probe-abort "s2 setup failed: %S" e))))

;;;; Drive all scenarios
;;
;; Both scenarios are async.  Scenario 1 is started by the top-level
;; `condition-case' form below.  Its done-fn is `commit-cancel--chain-scenario-2'
;; rather than `knayawp-probe-finish'; that function runs the post-cancel
;; assertions for scenario 1, tears down the layout, then calls
;; `commit-cancel--scenario-2' directly.  Scenario 2's done-fn calls
;; `knayawp-probe-finish', which writes the report and exits Emacs.

(knayawp-probe-watchdog 90)

;; Override the done-fn for scenario 1 to chain scenario 2 instead of
;; calling probe-finish directly.

(defun commit-cancel--chain-scenario-2 ()
  "Chain scenario 2 after scenario 1's layout is restored."
  (knayawp-probe-section "PROBE C -- post-cancel state (s1)")
  (knayawp-probe-log "  windows: %S" (knayawp-probe-window-summary))
  (knayawp-probe-check "s1c-commit-flow-gone" nil
                       (knayawp--commit-flow-active-p))
  (knayawp-probe-check "s1c-commit-pre-state-nil" nil
                       knayawp--commit-pre-state)
  (knayawp-probe-check "s1c-side-wins" 3
                       (commit-cancel--count-side-windows))
  (knayawp-probe-check "s1c-focus-not-side" nil
                       (window-parameter (selected-window) 'window-side))
  (knayawp-probe-check "s1c-commit-buf-gone" nil
                       (and (get-buffer "COMMIT_EDITMSG") t))
  ;; Tear down layout from s1 and start s2.
  (ignore-errors (knayawp-layout-teardown))
  (sit-for 0.3)
  ;; Run scenario 2: scenario 2's done-fn calls knayawp-probe-finish.
  (commit-cancel--scenario-2))

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-probe-log "  probe start  default-directory=%S" default-directory)
      ;; Run scenario 1 but with a chained done-fn.
      (knayawp-probe-section "SCENARIO 1 -- commit-cancel restores layout")
      (condition-case setup-e
          (progn
            (commit-cancel--setup-layout)
            (knayawp-probe-section "PROBE A -- post-setup state")
            (knayawp-probe-check "s1a-mode-on" t knayawp-mode)
            (knayawp-probe-check "s1a-style" 'zoom knayawp-magit-commit-style)
            (knayawp-probe-check "s1a-hooks-installed" t
                                 knayawp--commit-hooks-installed)
            (knayawp-probe-check "s1a-side-wins" 3
                                 (commit-cancel--count-side-windows))
            ;; Drive with chained done-fn.
            (commit-cancel--drive
             #'commit-cancel--scenario-1-mid
             #'commit-cancel--chain-scenario-2))
        (error (knayawp-probe-abort "s1 setup failed: %S" setup-e))))
  (error (knayawp-probe-abort "top-level error: %S" e)))

;;; commit-cancel-flow.el ends here
