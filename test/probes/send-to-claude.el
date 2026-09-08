;;; send-to-claude.el --- Probe for knayawp-send-to-claude -*- lexical-binding: t; -*-

;;; Commentary:

;; Three-scenario probe for `knayawp-send-to-claude' (issue #115).
;; Run via:
;;   test/run-probe.sh test/probes/send-to-claude.el
;;
;; Scenario 1 — Region active, no prefix: kill ring contains
;;   @file:LN-LM reference; Claude panel (slot 1) is selected.
;;
;; Scenario 2 — Region active, C-u prefix: kill ring contains a
;;   fenced code block with the selected text and the file extension
;;   as the language tag; Claude panel (slot 1) is selected.
;;
;; Scenario 3 — No region active: kill ring contains bare @file
;;   reference (no line numbers); Claude panel (slot 1) is selected.
;;
;; Note on window counts: `test/sandbox.el' opens a `*knayawp-sandbox*'
;; help window.  Full layout: 3 panels + editor + sandbox helper = 5 windows.

;;; Code:

(require 'cl-lib)

;;;; Helpers

(defun stc--settle ()
  "Pump the event loop briefly to let timers and redraws settle."
  (sit-for 0.3))

(defun stc--make-test-file (name content)
  "Create a file NAME in `sandbox--test-dir' with CONTENT.
Return the absolute path."
  (let ((path (expand-file-name name sandbox--test-dir)))
    (with-temp-file path (insert content))
    path))

(defun stc--open-test-file (path)
  "Open PATH and return its buffer."
  (find-file path)
  (current-buffer))

;;;; Scenario 1: region active, no prefix

(defun stc--scenario-1 ()
  "Scenario 1 — region active, no prefix: @file:LN-LM on kill ring."
  (knayawp-probe-section
   "SCENARIO 1 -- region active, no prefix => @file:L1-L3 on kill ring")
  (condition-case e
      (let* ((default-directory (file-name-as-directory sandbox--test-dir))
             (test-file (stc--make-test-file "stc-test.el"
                                             ";; line 1\n;; line 2\n;; line 3\n")))
        (knayawp-probe-setup-layout)
        ;; Open the test file so buffer-file-name is set.
        (stc--open-test-file test-file)
        ;; Select lines 1-3 (whole buffer).
        (goto-char (point-min))
        (set-mark (point-min))
        (goto-char (point-max))
        (activate-mark)
        (knayawp-probe-check "s1-region-active" t (use-region-p) #'eq)
        ;; Stub read-string to return the pre-filled default unchanged.
        (cl-letf (((symbol-function 'read-string)
                   (lambda (_prompt initial &rest _) initial)))
          (knayawp-send-to-claude nil))
        (stc--settle)
        ;; Kill ring must contain an @file:L1-L3 style reference.
        (let* ((entry (car kill-ring))
               (rel   (file-relative-name test-file sandbox--test-dir)))
          (knayawp-probe-log "  kill-ring head: %S" entry)
          (knayawp-probe-check "s1-kill-ring-at-ref"
                               t
                               (not (null
                                     (and (stringp entry)
                                          (string-match-p
                                           (regexp-quote (format "@%s:L" rel))
                                           entry))))
                               #'eq))
        ;; Claude panel (slot 1) must be selected.
        (knayawp-probe-assert-selected-window-slot 1 "s1-claude-panel-selected")
        (knayawp-probe-assert-selected-window-side 'right "s1-claude-panel-side"))
    (error (knayawp-probe-abort "s1 failed: %S" e)))
  (knayawp-probe-teardown-layout))

;;;; Scenario 2: region active, C-u prefix => fenced code block

(defun stc--scenario-2 ()
  "Scenario 2 — C-u prefix with region: fenced block on kill ring."
  (knayawp-probe-section
   "SCENARIO 2 -- region active, C-u prefix => fenced code block on kill ring")
  (condition-case e
      (let* ((default-directory (file-name-as-directory sandbox--test-dir))
             (test-file (stc--make-test-file "stc-test2.el"
                                             "(defun hello () t)\n")))
        (knayawp-probe-setup-layout)
        (stc--open-test-file test-file)
        ;; Select the whole buffer.
        (goto-char (point-min))
        (set-mark (point-min))
        (goto-char (point-max))
        (activate-mark)
        (knayawp-probe-check "s2-region-active" t (use-region-p) #'eq)
        ;; C-u prefix is simulated by passing a non-nil ARG.
        (cl-letf (((symbol-function 'read-string)
                   (lambda (_prompt initial &rest _) initial)))
          (knayawp-send-to-claude '(4)))
        (stc--settle)
        ;; Kill ring must contain a fenced ```el ... ``` block.
        (let ((entry (car kill-ring)))
          (knayawp-probe-log "  kill-ring head: %S" entry)
          (knayawp-probe-check "s2-fenced-block-start"
                               t
                               (not (null
                                     (and (stringp entry)
                                          (string-match-p "^```el\n" entry))))
                               #'eq)
          (knayawp-probe-check "s2-fenced-block-end"
                               t
                               (not (null
                                     (and (stringp entry)
                                          (string-match-p "```$" entry))))
                               #'eq)
          (knayawp-probe-check "s2-contains-code"
                               t
                               (not (null
                                     (and (stringp entry)
                                          (string-match-p "defun hello" entry))))
                               #'eq))
        ;; Claude panel must be selected.
        (knayawp-probe-assert-selected-window-slot 1 "s2-claude-panel-selected")
        (knayawp-probe-assert-selected-window-side 'right "s2-claude-panel-side"))
    (error (knayawp-probe-abort "s2 failed: %S" e)))
  (knayawp-probe-teardown-layout))

;;;; Scenario 3: no region active => bare @file reference

(defun stc--scenario-3 ()
  "Scenario 3 — no region: bare @file reference on kill ring."
  (knayawp-probe-section
   "SCENARIO 3 -- no region => bare @file reference on kill ring")
  (condition-case e
      (let* ((default-directory (file-name-as-directory sandbox--test-dir))
             (test-file (stc--make-test-file "stc-test3.el"
                                             ";; no selection here\n")))
        (knayawp-probe-setup-layout)
        (stc--open-test-file test-file)
        ;; Ensure no region is active.
        (deactivate-mark)
        (knayawp-probe-check "s3-no-region" nil (use-region-p) #'eq)
        (cl-letf (((symbol-function 'read-string)
                   (lambda (_prompt initial &rest _) initial)))
          (knayawp-send-to-claude nil))
        (stc--settle)
        ;; Kill ring must contain @file with no line numbers.
        (let* ((entry (car kill-ring))
               (rel   (file-relative-name test-file sandbox--test-dir)))
          (knayawp-probe-log "  kill-ring head: %S" entry)
          (knayawp-probe-check "s3-kill-ring-bare-ref"
                               (format "@%s" rel)
                               entry)
          ;; Must NOT contain a line-number suffix.
          (knayawp-probe-check "s3-no-line-numbers"
                               nil
                               (and (stringp entry)
                                    (string-match-p ":L[0-9]" entry))
                               #'eq))
        ;; Claude panel must be selected.
        (knayawp-probe-assert-selected-window-slot 1 "s3-claude-panel-selected")
        (knayawp-probe-assert-selected-window-side 'right "s3-claude-panel-side"))
    (error (knayawp-probe-abort "s3 failed: %S" e)))
  (knayawp-probe-teardown-layout))

;;;; Drive all scenarios

(knayawp-probe-watchdog 90)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-probe-log "  probe start  default-directory=%S" default-directory)
      (stc--scenario-1)
      (stc--scenario-2)
      (stc--scenario-3))
  (error (knayawp-probe-abort "top-level error: %S" e)))

(knayawp-probe-finish)

;;; send-to-claude.el ends here
