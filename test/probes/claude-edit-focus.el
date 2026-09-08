;;; claude-edit-focus.el --- Probe for Claude edit buffer focus travel -*- lexical-binding: t; -*-

;;; Commentary:

;; Three-scenario probe for `knayawp--claude-edit-finish' and
;; `knayawp--claude-edit-abort' focus-travel behaviour (#135, #143).
;; Run via:
;;   test/run-probe.sh test/probes/claude-edit-focus.el
;;
;; Scenario 1 — knayawp--claude-edit-select-window focuses Claude slot:
;;   With a live layout, assert that calling the helper directly moves
;;   selected-window to the Claude side window (slot 1).
;;
;; Scenario 2 — knayawp--claude-edit-finish returns focus to Claude:
;;   Start from editor pane; call finish (with server-edit stubbed);
;;   assert selected-window is the Claude panel.
;;
;; Scenario 3 — knayawp--claude-edit-abort returns focus to Claude:
;;   Start from editor pane; call abort (with server-edit stubbed);
;;   assert selected-window is the Claude panel and "Prompt discarded"
;;   message was emitted.
;;
;; Note on window counts: `test/sandbox.el' opens a `*knayawp-sandbox*'
;; help window.  Full layout: 3 panels + editor + sandbox helper = 5 windows.

;;; Code:

(require 'cl-lib)

;;;; Scenario 1: select-window helper focuses Claude slot

(defun cef--scenario-1 ()
  "Scenario 1 — knayawp--claude-edit-select-window selects Claude panel."
  (knayawp-probe-section "SCENARIO 1 -- select-window focuses Claude slot (slot 1)")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        (knayawp-probe-setup-layout)
        ;; Move focus away from Claude panel to editor.
        (knayawp--select-editor-window)
        (knayawp-probe-check "s1-starting-in-editor"
                             nil
                             (window-parameter (selected-window) 'window-side))
        ;; Call the helper.
        (knayawp--claude-edit-select-window)
        ;; Assert Claude panel (slot 1) is now selected.
        (knayawp-probe-assert-selected-window-slot 1 "s1-claude-panel-selected")
        (knayawp-probe-assert-selected-window-side 'right "s1-claude-panel-side"))
    (error (knayawp-probe-abort "s1 failed: %S" e)))
  (knayawp-probe-teardown-layout))

;;;; Scenario 2: finish returns focus to Claude panel

(defun cef--scenario-2 ()
  "Scenario 2 — knayawp--claude-edit-finish leaves focus on Claude panel."
  (knayawp-probe-section "SCENARIO 2 -- finish returns focus to Claude panel")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir))
            (server-edit-called nil)
            (save-buffer-called nil))
        (knayawp-probe-setup-layout)
        ;; Start from editor pane.
        (knayawp--select-editor-window)
        (knayawp-probe-check "s2-starting-in-editor"
                             nil
                             (window-parameter (selected-window) 'window-side))
        ;; Call finish with server-edit and save-buffer stubbed (no live session).
        (cl-letf (((symbol-function 'server-edit)
                   (lambda () (setq server-edit-called t)))
                  ((symbol-function 'save-buffer)
                   (lambda () (setq save-buffer-called t))))
          (knayawp--claude-edit-finish))
        (knayawp-probe-check "s2-save-buffer-called" t save-buffer-called #'eq)
        (knayawp-probe-check "s2-server-edit-called" t server-edit-called #'eq)
        (knayawp-probe-assert-selected-window-slot 1 "s2-claude-panel-selected")
        (knayawp-probe-assert-selected-window-side 'right "s2-claude-panel-side"))
    (error (knayawp-probe-abort "s2 failed: %S" e)))
  (knayawp-probe-teardown-layout))

;;;; Scenario 3: abort returns focus to Claude panel with message

(defun cef--scenario-3 ()
  "Scenario 3 — knayawp--claude-edit-abort leaves focus on Claude and shows message."
  (knayawp-probe-section "SCENARIO 3 -- abort returns focus to Claude and emits message")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir))
            (server-edit-called nil)
            (last-message nil))
        (knayawp-probe-setup-layout)
        ;; Start from editor pane.
        (knayawp--select-editor-window)
        (knayawp-probe-check "s3-starting-in-editor"
                             nil
                             (window-parameter (selected-window) 'window-side))
        ;; Create a scratch buffer so set-buffer-modified-p has a real buffer.
        (with-current-buffer (get-buffer-create " *knayawp-cef-abort-test*")
          (cl-letf (((symbol-function 'server-edit)
                     (lambda () (setq server-edit-called t)))
                    ((symbol-function 'message)
                     (lambda (fmt &rest args)
                       (setq last-message (apply #'format fmt args)))))
            (knayawp--claude-edit-abort)))
        (knayawp-probe-check "s3-server-edit-called" t server-edit-called #'eq)
        (knayawp-probe-check "s3-discarded-message"
                             t
                             (and (stringp last-message)
                                  (not (null (string-match-p "discarded"
                                                             last-message))))
                             #'eq)
        (knayawp-probe-assert-selected-window-slot 1 "s3-claude-panel-selected")
        (knayawp-probe-assert-selected-window-side 'right "s3-claude-panel-side"))
    (error (knayawp-probe-abort "s3 failed: %S" e)))
  (kill-buffer " *knayawp-cef-abort-test*")
  (knayawp-probe-teardown-layout))

;;;; Drive all scenarios

(knayawp-probe-watchdog 90)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-probe-log "  probe start  default-directory=%S" default-directory)
      (cef--scenario-1)
      (cef--scenario-2)
      (cef--scenario-3))
  (error (knayawp-probe-abort "top-level error: %S" e)))

(knayawp-probe-finish)

;;; claude-edit-focus.el ends here
