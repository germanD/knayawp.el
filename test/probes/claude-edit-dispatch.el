;;; claude-edit-dispatch.el --- Probe for finish-and-dispatch vs finish (#144) -*- lexical-binding: t; -*-

;;; Commentary:

;; Two-scenario probe for `knayawp--claude-edit-finish-and-dispatch' and
;; `knayawp--claude-edit-finish' (#144).  Run via:
;;   test/run-probe.sh test/probes/claude-edit-dispatch.el
;;
;; Both scenarios use the default `claude-panel' edit style.  The key
;; difference between the two paths is behavioural inside the Claude TUI
;; (whether Enter is pressed automatically), not a window-management
;; difference that can be asserted against real frame geometry.  Each
;; scenario therefore verifies that after the respective finish call the
;; Claude panel window is focused (slot 1 selected) and the full layout is
;; intact.
;;
;; `server-edit' and `save-buffer' are stubbed (no live emacsclient session).
;; `knayawp--claude-panel-send-string' is stubbed to record the string sent
;; without requiring a live terminal backend.
;;
;; Scenario 1 — finish-and-dispatch (C-c C-c): after calling
;;   `knayawp--claude-edit-finish-and-dispatch', the Claude panel (slot 1)
;;   is focused, the layout is intact, and the stub recorded that \\r was
;;   sent to the Claude panel terminal.
;;
;; Scenario 2 — finish only (C-x #): after calling
;;   `knayawp--claude-edit-finish', the Claude panel (slot 1) is focused
;;   and the layout is intact.  No send-string call is recorded.
;;
;; Note on window counts: `test/sandbox.el' opens a `*knayawp-sandbox*'
;; help window.  Full layout: 3 panels + editor + sandbox helper = 5 windows.

;;; Code:

(require 'cl-lib)

;; Prefer vterm; fall back to eat when vterm is unavailable.
(unless (require 'vterm nil t)
  (when (require 'eat nil t)
    (setq knayawp-terminal-backend 'eat)))

(defvar ced--claude-slot 1
  "Side-window slot of the Claude panel in the sandbox layout.")

(defun ced--make-temp-file-buffer (suffix)
  "Create and visit a real temp file under the sandbox, return its buffer.
SUFFIX distinguishes files across scenarios."
  (let* ((path (expand-file-name
                (format "knayawp-claude-dispatch-%s.txt" suffix)
                sandbox--test-dir))
         (buf (find-file-noselect path)))
    (with-current-buffer buf
      (erase-buffer)
      (insert "prompt draft\n")
      (save-buffer))
    buf))

;;;; Scenario 1: finish-and-dispatch (C-c C-c path)

(defun ced--scenario-1 ()
  "Scenario 1 — finish-and-dispatch: Claude panel focused, \\r sent."
  (knayawp-probe-section "SCENARIO 1 -- finish-and-dispatch (C-c C-c path)")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir))
            (knayawp-claude-edit-style 'claude-panel)
            (sent-strings nil)
            (temp-buf nil))
        (knayawp-probe-setup-layout)
        (setq temp-buf (ced--make-temp-file-buffer "dispatch"))
        (with-current-buffer temp-buf
          (knayawp--claude-editor-server-switch))
        (sit-for 0.2)
        ;; Temp file is now in the Claude slot.
        (knayawp-probe-check "s1-setup-ok"
                             (buffer-name temp-buf)
                             (buffer-name
                              (window-buffer
                               (seq-find
                                (lambda (w)
                                  (and (window-parameter w 'window-slot)
                                       (= ced--claude-slot
                                          (window-parameter w 'window-slot))))
                                (knayawp--side-windows)))))
        ;; Call finish-and-dispatch with finish and send-string stubbed.
        (cl-letf (((symbol-function 'server-edit) #'ignore)
                  ((symbol-function 'save-buffer) #'ignore)
                  ((symbol-function 'knayawp--claude-panel-send-string)
                   (lambda (s) (push s sent-strings))))
          (with-current-buffer temp-buf
            (knayawp--claude-edit-finish-and-dispatch)))
        (sit-for 0.2)
        ;; Layout intact, Claude panel selected (slot 1 focused).
        (knayawp-probe-assert-total-window-count 5 "s1-layout-intact")
        (knayawp-probe-assert-selected-window-slot
         ced--claude-slot "s1-claude-panel-focused")
        ;; send-string was called with "\r".
        (knayawp-probe-check "s1-return-sent"
                             1 (length sent-strings) #'=)
        (knayawp-probe-check "s1-return-value"
                             "\r" (car sent-strings))
        (when (buffer-live-p temp-buf) (kill-buffer temp-buf)))
    (error (knayawp-probe-abort "s1 failed: %S" e)))
  (knayawp-probe-teardown-layout))

;;;; Scenario 2: finish only (C-x # path)

(defun ced--scenario-2 ()
  "Scenario 2 — finish only (C-x #): Claude panel focused, no \\r sent."
  (knayawp-probe-section "SCENARIO 2 -- finish only (C-x # path)")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir))
            (knayawp-claude-edit-style 'claude-panel)
            (send-string-called nil)
            (temp-buf nil))
        (knayawp-probe-setup-layout)
        (setq temp-buf (ced--make-temp-file-buffer "review"))
        (with-current-buffer temp-buf
          (knayawp--claude-editor-server-switch))
        (sit-for 0.2)
        ;; Call finish only — send-string must NOT be invoked.
        (cl-letf (((symbol-function 'server-edit) #'ignore)
                  ((symbol-function 'save-buffer) #'ignore)
                  ((symbol-function 'knayawp--claude-panel-send-string)
                   (lambda (_s) (setq send-string-called t))))
          (with-current-buffer temp-buf
            (knayawp--claude-edit-finish)))
        (sit-for 0.2)
        ;; Layout intact, Claude panel selected.
        (knayawp-probe-assert-total-window-count 5 "s2-layout-intact")
        (knayawp-probe-assert-selected-window-slot
         ced--claude-slot "s2-claude-panel-focused")
        ;; send-string was NOT called.
        (knayawp-probe-check "s2-no-send-string"
                             nil send-string-called)
        (when (buffer-live-p temp-buf) (kill-buffer temp-buf)))
    (error (knayawp-probe-abort "s2 failed: %S" e)))
  (knayawp-probe-teardown-layout))

;;;; Drive all scenarios

(knayawp-probe-watchdog 90)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-probe-log "  probe start  default-directory=%S" default-directory)
      (ced--scenario-1)
      (ced--scenario-2))
  (error (knayawp-probe-abort "top-level error: %S" e)))

(knayawp-probe-finish)

;;; claude-edit-dispatch.el ends here
