;;; send-to-terminal.el --- Probe for knayawp-send-to-terminal -*- lexical-binding: t; -*-

;;; Commentary:

;; Two-scenario probe for `knayawp-send-to-terminal' (issue #162).  Run via:
;;   test/run-probe.sh test/probes/send-to-terminal.el
;;
;; Scenario 1 — single-line region: terminal panel (slot 0) is selected
;;   and the kill ring contains the region text after the call.
;;
;; Scenario 2 — multi-line region: same assertions hold for a multi-line
;;   selection, confirming the kill-ring-save path is not line-count-sensitive.
;;
;; Note on window counts: `test/sandbox.el' opens a `*knayawp-sandbox*'
;; help window.  Full layout: 3 panels + editor + sandbox helper = 5 windows.

;;; Code:

(require 'cl-lib)

;;;; Helpers

(defun stt--make-test-file (name content)
  "Create NAME in `sandbox--test-dir' with CONTENT; return absolute path."
  (let ((path (expand-file-name name sandbox--test-dir)))
    (with-temp-file path (insert content))
    path))

(defun stt--open-test-file (path)
  "Open PATH and return its buffer."
  (find-file path)
  (current-buffer))

(defun stt--settle ()
  "Pump the event loop briefly."
  (sit-for 0.3))

;;;; Scenario 1: single-line region

(defun stt--scenario-1 ()
  "Scenario 1 — single-line region: terminal panel selected, kill ring has text."
  (knayawp-probe-section
   "SCENARIO 1 -- single-line region => slot-0 terminal selected, kill ring has text")
  (condition-case e
      (let* ((default-directory (file-name-as-directory sandbox--test-dir))
             (test-file (stt--make-test-file "stt-test1.sh"
                                             "echo hello\necho world\n")))
        (knayawp-probe-setup-layout)
        (stt--open-test-file test-file)
        ;; Select just the first line.
        (goto-char (point-min))
        (set-mark (point-min))
        (end-of-line)
        (activate-mark)
        (knayawp-probe-check "s1-region-active" t (use-region-p) #'eq)
        (let ((region-text (buffer-substring-no-properties
                            (region-beginning) (region-end))))
          (knayawp-send-to-terminal)
          (stt--settle)
          ;; Terminal panel (slot 0) must be selected.
          (knayawp-probe-assert-selected-window-slot 0 "s1-terminal-selected")
          (knayawp-probe-assert-selected-window-side 'right "s1-terminal-side")
          ;; Kill ring must contain the region text.
          (knayawp-probe-log "  region-text: %S  kill-ring-head: %S"
                             region-text (car kill-ring))
          (knayawp-probe-check "s1-kill-ring-has-region" region-text (car kill-ring))))
    (error (knayawp-probe-abort "s1 failed: %S" e)))
  (knayawp-probe-teardown-layout))

;;;; Scenario 2: multi-line region

(defun stt--scenario-2 ()
  "Scenario 2 — multi-line region: terminal selected, kill ring has full text."
  (knayawp-probe-section
   "SCENARIO 2 -- multi-line region => slot-0 terminal selected, kill ring has text")
  (condition-case e
      (let* ((default-directory (file-name-as-directory sandbox--test-dir))
             (test-file (stt--make-test-file "stt-test2.sh"
                                             "echo line1\necho line2\necho line3\n")))
        (knayawp-probe-setup-layout)
        (stt--open-test-file test-file)
        ;; Select the whole buffer.
        (goto-char (point-min))
        (set-mark (point-min))
        (goto-char (point-max))
        (activate-mark)
        (knayawp-probe-check "s2-region-active" t (use-region-p) #'eq)
        (let ((region-text (buffer-substring-no-properties
                            (region-beginning) (region-end))))
          (knayawp-send-to-terminal)
          (stt--settle)
          ;; Terminal panel must be selected.
          (knayawp-probe-assert-selected-window-slot 0 "s2-terminal-selected")
          (knayawp-probe-assert-selected-window-side 'right "s2-terminal-side")
          ;; Kill ring must contain the full multi-line selection.
          (knayawp-probe-log "  region-text: %S  kill-ring-head: %S"
                             region-text (car kill-ring))
          (knayawp-probe-check "s2-kill-ring-has-region" region-text (car kill-ring))
          ;; Full layout must still be intact.
          (knayawp-probe-assert-total-window-count 5 "s2-full-layout-intact")))
    (error (knayawp-probe-abort "s2 failed: %S" e)))
  (knayawp-probe-teardown-layout))

;;;; Drive all scenarios

(knayawp-probe-watchdog 90)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-probe-log "  probe start  default-directory=%S" default-directory)
      (stt--scenario-1)
      (stt--scenario-2))
  (error (knayawp-probe-abort "top-level error: %S" e)))

(knayawp-probe-finish)

;;; send-to-terminal.el ends here
