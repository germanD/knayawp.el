;;; claude-edit-abort-origin.el --- Probe for abort origin-window focus (#164) -*- lexical-binding: t; -*-

;;; Commentary:

;; Three-scenario probe for `knayawp--claude-edit-abort' origin-window
;; focus (#164).  Each scenario drives the real
;; `knayawp--claude-editor-server-switch' routing from a different trigger
;; origin, then aborts and asserts focus returns to that origin.  Run via:
;;   test/run-probe.sh test/probes/claude-edit-abort-origin.el
;;
;; Each scenario selects an origin window, visits a real temp file (so the
;; server-switch file predicate holds), calls
;; `knayawp--claude-editor-server-switch' as `server-switch-hook' would,
;; then calls `knayawp--claude-edit-abort' with `server-edit'/`save-buffer'
;; stubbed (no live emacsclient session).
;;
;; Scenario 1 — origin = Claude panel (default claude-panel style, C-g
;;   flow): abort returns focus to the Claude panel (slot 1).  This path
;;   was already correct before #164; the probe confirms the origin-based
;;   logic preserves it.
;;
;; Scenario 2 — origin = editor pane (editor-pane style): abort returns
;;   focus to the editor window, not the Claude panel.
;;
;; Scenario 3 — origin = another managed panel, the vterm slot (slot 0),
;;   with claude-panel style: abort restores the displaced Claude buffer
;;   and returns focus to the vterm slot, not the Claude panel.
;;
;; Note on window counts: `test/sandbox.el' opens a `*knayawp-sandbox*'
;; help window.  Full layout: 3 panels + editor + sandbox helper = 5 windows.

;;; Code:

(require 'cl-lib)

;; Prefer vterm; fall back to eat when vterm is unavailable (CI/container
;; images may ship only the MELPA `eat' package).  Keeps the probe runnable
;; across both environments without changing the behaviour under test.
(unless (require 'vterm nil t)
  (when (require 'eat nil t)
    (setq knayawp-terminal-backend 'eat)))

(defvar ceao--claude-slot 1
  "Side-window slot of the Claude panel in the sandbox layout.")

(defvar ceao--vterm-slot 0
  "Side-window slot of the vterm panel in the sandbox layout.")

(defun ceao--make-temp-file-buffer (suffix)
  "Create and visit a real temp file under the sandbox, return its buffer.
SUFFIX distinguishes files across scenarios."
  (let* ((path (expand-file-name
                (format "knayawp-claude-abort-%s.txt" suffix)
                sandbox--test-dir))
         (buf (find-file-noselect path)))
    (with-current-buffer buf
      (erase-buffer)
      (insert "prompt draft\n")
      (save-buffer))
    buf))

(defun ceao--abort-in (temp-buf)
  "Run `knayawp--claude-edit-abort' in TEMP-BUF with the session stubbed."
  (cl-letf (((symbol-function 'server-edit) #'ignore)
            ((symbol-function 'save-buffer) #'ignore))
    (with-current-buffer temp-buf
      (knayawp--claude-edit-abort))))

;;;; Scenario 1: origin = Claude panel

(defun ceao--scenario-1 ()
  "Scenario 1 — C-g flow from the Claude panel: abort refocuses slot 1."
  (knayawp-probe-section "SCENARIO 1 -- origin = Claude panel")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir))
            (knayawp-claude-edit-style 'claude-panel)
            (temp-buf nil))
        (knayawp-probe-setup-layout)
        (knayawp-probe-select-slot ceao--claude-slot)
        (setq temp-buf (ceao--make-temp-file-buffer "claude"))
        (with-current-buffer temp-buf
          (knayawp--claude-editor-server-switch))
        (sit-for 0.2)
        (ceao--abort-in temp-buf)
        (sit-for 0.2)
        (knayawp-probe-assert-total-window-count 5 "s1-layout-intact")
        (knayawp-probe-assert-selected-window-slot
         ceao--claude-slot "s1-focus-on-claude-origin")
        (when (buffer-live-p temp-buf) (kill-buffer temp-buf)))
    (error (knayawp-probe-abort "s1 failed: %S" e)))
  (knayawp-probe-teardown-layout))

;;;; Scenario 2: origin = editor pane

(defun ceao--scenario-2 ()
  "Scenario 2 — edit triggered from the editor pane: abort refocuses it."
  (knayawp-probe-section "SCENARIO 2 -- origin = editor pane")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir))
            (knayawp-claude-edit-style 'editor-pane)
            (temp-buf nil))
        (knayawp-probe-setup-layout)
        (select-window knayawp--editor-window)
        (setq temp-buf (ceao--make-temp-file-buffer "editor"))
        (with-current-buffer temp-buf
          (knayawp--claude-editor-server-switch))
        (sit-for 0.2)
        (ceao--abort-in temp-buf)
        (sit-for 0.2)
        (knayawp-probe-assert-total-window-count 5 "s2-layout-intact")
        (knayawp-probe-check "s2-focus-on-editor-origin"
                             knayawp--editor-window
                             (selected-window)
                             #'eq)
        (when (buffer-live-p temp-buf) (kill-buffer temp-buf)))
    (error (knayawp-probe-abort "s2 failed: %S" e)))
  (knayawp-probe-teardown-layout))

;;;; Scenario 3: origin = another managed panel (vterm slot)

(defun ceao--scenario-3 ()
  "Scenario 3 — edit triggered from the vterm panel: abort refocuses it."
  (knayawp-probe-section "SCENARIO 3 -- origin = vterm panel")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir))
            (knayawp-claude-edit-style 'claude-panel)
            (temp-buf nil))
        (knayawp-probe-setup-layout)
        (knayawp-probe-select-slot ceao--vterm-slot)
        (setq temp-buf (ceao--make-temp-file-buffer "vterm"))
        (with-current-buffer temp-buf
          (knayawp--claude-editor-server-switch))
        (sit-for 0.2)
        (ceao--abort-in temp-buf)
        (sit-for 0.2)
        (knayawp-probe-assert-total-window-count 5 "s3-layout-intact")
        (knayawp-probe-assert-selected-window-slot
         ceao--vterm-slot "s3-focus-on-vterm-origin")
        (when (buffer-live-p temp-buf) (kill-buffer temp-buf)))
    (error (knayawp-probe-abort "s3 failed: %S" e)))
  (knayawp-probe-teardown-layout))

;;;; Drive all scenarios

(knayawp-probe-watchdog 90)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-probe-log "  probe start  default-directory=%S" default-directory)
      (ceao--scenario-1)
      (ceao--scenario-2)
      (ceao--scenario-3))
  (error (knayawp-probe-abort "top-level error: %S" e)))

(knayawp-probe-finish)

;;; claude-edit-abort-origin.el ends here
