;;; claude-edit-style.el --- Probe for knayawp-claude-edit-style -*- lexical-binding: t; -*-

;;; Commentary:

;; Three-scenario probe for `knayawp-claude-edit-style' (#133).  It drives
;; the real `knayawp--claude-editor-server-switch' routing and the
;; finish-time restore for each of the three styles.  Run via:
;;   test/run-probe.sh test/probes/claude-edit-style.el
;;
;; Each scenario visits a real temp file (so the server-switch file
;; predicate holds), sets `knayawp-claude-edit-style', and calls
;; `knayawp--claude-editor-server-switch' as `server-switch-hook' would.
;; `server-edit'/`save-buffer' are stubbed (no live emacsclient session).
;;
;; Scenario 1 — editor-pane: the temp file lands in the editor pane; the
;;   Claude panel (slot 1) is untouched; finishing restores the editor
;;   pane to a non-Claude buffer; full 5-window layout intact throughout.
;;
;; Scenario 2 — claude-panel (default): the temp file replaces the Claude
;;   panel window (slot 1); the displaced Claude buffer is recorded; on
;;   finish the Claude buffer is restored into slot 1; layout intact.
;;
;; Scenario 3 — zoom: the temp file lands in the editor pane which is then
;;   zoomed to fill the frame (side windows deleted, 1 window); on finish
;;   the full layout is restored (5 windows, not zoomed).
;;
;; Note on window counts: `test/sandbox.el' opens a `*knayawp-sandbox*'
;; help window.  Full layout: 3 panels + editor + sandbox helper = 5 windows.

;;; Code:

(require 'cl-lib)

;; Prefer vterm (the default and the apt `elpa-vterm' package on the dev
;; machine); fall back to eat when vterm is unavailable (e.g. a CI or
;; container image with only the MELPA `eat' package installed).  This
;; keeps the probe runnable across both environments without changing the
;; behaviour under test.
(unless (require 'vterm nil t)
  (when (require 'eat nil t)
    (setq knayawp-terminal-backend 'eat)))

(defvar ces--claude-slot 1
  "Side-window slot of the Claude panel in the sandbox layout.")

(defun ces--make-temp-file-buffer (suffix)
  "Create and visit a real temp file under the sandbox, return its buffer.
SUFFIX distinguishes files across scenarios."
  (let* ((path (expand-file-name
                (format "knayawp-claude-edit-%s.txt" suffix)
                sandbox--test-dir))
         (buf (find-file-noselect path)))
    (with-current-buffer buf
      (erase-buffer)
      (insert "prompt draft\n")
      (save-buffer))
    buf))

(defun ces--claude-buffer-at-slot ()
  "Return the buffer name displayed in the Claude side window, or nil."
  (let ((win (seq-find (lambda (w)
                         (and (window-parameter w 'window-slot)
                              (= ces--claude-slot
                                 (window-parameter w 'window-slot))))
                       (knayawp--side-windows))))
    (and win (buffer-name (window-buffer win)))))

;;;; Scenario 1: editor-pane style

(defun ces--scenario-1 ()
  "Scenario 1 — route to editor pane, leave the Claude panel alone."
  (knayawp-probe-section "SCENARIO 1 -- editor-pane style")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir))
            (knayawp-claude-edit-style 'editor-pane)
            (temp-buf nil))
        (knayawp-probe-setup-layout)
        (let ((claude-before (ces--claude-buffer-at-slot)))
          (setq temp-buf (ces--make-temp-file-buffer "editor"))
          (with-current-buffer temp-buf
            (knayawp--claude-editor-server-switch))
          (sit-for 0.2)
          ;; Editor window shows the temp file.
          (knayawp-probe-check "s1-editor-shows-temp"
                               (buffer-name temp-buf)
                               (buffer-name
                                (window-buffer knayawp--editor-window)))
          ;; Claude slot untouched.
          (knayawp-probe-check "s1-claude-slot-untouched"
                               claude-before (ces--claude-buffer-at-slot))
          (knayawp-probe-assert-total-window-count 5 "s1-layout-intact")
          ;; No restore state recorded for editor-pane.
          (knayawp-probe-check "s1-no-displaced-buf"
                               nil knayawp--claude-edit-displaced-buf)
          ;; Finish (stubbed session).
          (cl-letf (((symbol-function 'server-edit) #'ignore)
                    ((symbol-function 'save-buffer) #'ignore))
            (with-current-buffer temp-buf
              (knayawp--claude-edit-finish)))
          (sit-for 0.2)
          (knayawp-probe-assert-total-window-count 5 "s1-layout-intact-after")
          (knayawp-probe-check "s1-claude-slot-still-there"
                               claude-before (ces--claude-buffer-at-slot)))
        (when (buffer-live-p temp-buf) (kill-buffer temp-buf)))
    (error (knayawp-probe-abort "s1 failed: %S" e)))
  (knayawp-probe-teardown-layout))

;;;; Scenario 2: claude-panel style (default)

(defun ces--scenario-2 ()
  "Scenario 2 — replace slot 1, then restore the Claude buffer on finish."
  (knayawp-probe-section "SCENARIO 2 -- claude-panel style (default)")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir))
            (knayawp-claude-edit-style 'claude-panel)
            (temp-buf nil))
        (knayawp-probe-setup-layout)
        (let ((claude-before (ces--claude-buffer-at-slot)))
          (knayawp-probe-check "s2-claude-buffer-present"
                               t (and (stringp claude-before)
                                      (not (null (string-match-p
                                                  "knayawp-claude"
                                                  claude-before))))
                               #'eq)
          (setq temp-buf (ces--make-temp-file-buffer "claude"))
          (with-current-buffer temp-buf
            (knayawp--claude-editor-server-switch))
          (sit-for 0.2)
          ;; Temp file now occupies the Claude slot.
          (knayawp-probe-check "s2-slot-shows-temp"
                               (buffer-name temp-buf)
                               (ces--claude-buffer-at-slot))
          ;; Displaced Claude buffer recorded.
          (knayawp-probe-check "s2-displaced-recorded"
                               claude-before
                               (buffer-name
                                knayawp--claude-edit-displaced-buf))
          (knayawp-probe-assert-total-window-count 5 "s2-layout-intact")
          ;; Finish restores the Claude buffer into slot 1.
          (cl-letf (((symbol-function 'server-edit) #'ignore)
                    ((symbol-function 'save-buffer) #'ignore))
            (with-current-buffer temp-buf
              (knayawp--claude-edit-finish)))
          (sit-for 0.2)
          (knayawp-probe-check "s2-slot-restored"
                               claude-before (ces--claude-buffer-at-slot))
          (knayawp-probe-check "s2-state-cleared"
                               nil knayawp--claude-edit-displaced-buf)
          (knayawp-probe-assert-total-window-count 5 "s2-layout-intact-after")
          (knayawp-probe-assert-selected-window-slot
           ces--claude-slot "s2-focus-on-claude"))
        (when (buffer-live-p temp-buf) (kill-buffer temp-buf)))
    (error (knayawp-probe-abort "s2 failed: %S" e)))
  (knayawp-probe-teardown-layout))

;;;; Scenario 3: zoom style

(defun ces--scenario-3 ()
  "Scenario 3 — fill the frame while editing, restore layout on finish."
  (knayawp-probe-section "SCENARIO 3 -- zoom style")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir))
            (knayawp-claude-edit-style 'zoom)
            (temp-buf nil))
        (knayawp-probe-setup-layout)
        (let ((claude-before (ces--claude-buffer-at-slot)))
          (setq temp-buf (ces--make-temp-file-buffer "zoom"))
          (with-current-buffer temp-buf
            (knayawp--claude-editor-server-switch))
          (sit-for 0.2)
          ;; Editor window is zoomed to the whole frame: 1 window, no sides.
          (knayawp-probe-assert-total-window-count 1 "s3-zoomed-one-window")
          (knayawp-probe-assert-no-side-windows "s3-no-side-windows")
          (knayawp-probe-check "s3-window-shows-temp"
                               (buffer-name temp-buf)
                               (buffer-name (window-buffer (selected-window))))
          (knayawp-probe-check "s3-winconf-recorded"
                               t
                               (window-configuration-p
                                knayawp--claude-edit-zoom-winconf)
                               #'eq)
          ;; Finish restores the full layout.
          (cl-letf (((symbol-function 'server-edit) #'ignore)
                    ((symbol-function 'save-buffer) #'ignore))
            (with-current-buffer temp-buf
              (knayawp--claude-edit-finish)))
          (sit-for 0.2)
          (knayawp-probe-assert-total-window-count 5 "s3-layout-restored")
          (knayawp-probe-assert-not-zoomed "s3-not-zoomed")
          (knayawp-probe-check "s3-state-cleared"
                               nil knayawp--claude-edit-zoom-winconf)
          (knayawp-probe-check "s3-claude-slot-restored"
                               claude-before (ces--claude-buffer-at-slot)))
        (when (buffer-live-p temp-buf) (kill-buffer temp-buf)))
    (error (knayawp-probe-abort "s3 failed: %S" e)))
  (knayawp-probe-teardown-layout))

;;;; Drive all scenarios

(knayawp-probe-watchdog 90)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-probe-log "  probe start  default-directory=%S" default-directory)
      (ces--scenario-1)
      (ces--scenario-2)
      (ces--scenario-3))
  (error (knayawp-probe-abort "top-level error: %S" e)))

(knayawp-probe-finish)

;;; claude-edit-style.el ends here
