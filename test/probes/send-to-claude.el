;;; send-to-claude.el --- Probe for knayawp-send-to-claude -*- lexical-binding: t; -*-

;;; Commentary:

;; Four-scenario probe for `knayawp-send-to-claude' (issues #115, #155).
;; Run via:
;;   test/run-probe.sh test/probes/send-to-claude.el
;;
;; Scenarios 1-3 pin the `kill-ring' delivery style (the original #115
;; MVP, now a non-default fallback of `knayawp-send-to-claude-style').
;; Scenario 4 exercises the new default `compose' style (#155).
;;
;; Scenario 1 — kill-ring style, region active, no prefix: kill ring
;;   contains @file:LN-LM reference; Claude panel (slot 1) is selected.
;;
;; Scenario 2 — kill-ring style, region active, C-u prefix: kill ring
;;   contains a fenced code block with the selected text and the file
;;   extension as the language tag; Claude panel (slot 1) is selected.
;;
;; Scenario 3 — kill-ring style, no region active: kill ring contains
;;   bare @file reference (no line numbers); Claude panel is selected.
;;
;; Scenario 4 — compose style (default), region active, no prefix:
;;   a `*knayawp-claude-prompt-*' buffer opens in the editor pane with
;;   `knayawp-claude-prompt-mode' active and pre-loaded with the
;;   reference; finishing with `knayawp-claude-prompt-send' injects
;;   into the Claude panel, restores the editor window, focuses the
;;   Claude panel (slot 1), and kills the compose buffer.
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
        (let ((knayawp-send-to-claude-style 'kill-ring))
          (cl-letf (((symbol-function 'read-string)
                     (lambda (_prompt initial &rest _) initial)))
            (knayawp-send-to-claude nil)))
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
        (let ((knayawp-send-to-claude-style 'kill-ring))
          (cl-letf (((symbol-function 'read-string)
                     (lambda (_prompt initial &rest _) initial)))
            (knayawp-send-to-claude '(4))))
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
        (let ((knayawp-send-to-claude-style 'kill-ring))
          (cl-letf (((symbol-function 'read-string)
                     (lambda (_prompt initial &rest _) initial)))
            (knayawp-send-to-claude nil)))
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

;;;; Scenario 4: compose style (default) => editor-pane prompt buffer

(defun stc--scenario-4 ()
  "Scenario 4 — compose style: prompt buffer opens, send injects + focuses."
  (knayawp-probe-section
   "SCENARIO 4 -- compose style => editor-pane prompt buffer, send focuses Claude")
  (condition-case e
      (let* ((default-directory (file-name-as-directory sandbox--test-dir))
             (test-file (stc--make-test-file "stc-test4.el"
                                             ";; c1\n;; c2\n;; c3\n")))
        (knayawp-probe-setup-layout)
        (stc--open-test-file test-file)
        ;; Select lines 1-3.
        (goto-char (point-min))
        (set-mark (point-min))
        (goto-char (point-max))
        (activate-mark)
        (knayawp-probe-check "s4-region-active" t (use-region-p) #'eq)
        ;; Default style is `compose'; open the prompt buffer.
        (knayawp-send-to-claude nil)
        (stc--settle)
        ;; The compose buffer must be current, in prompt mode, holding the ref.
        (knayawp-probe-check "s4-compose-buffer-current"
                             t
                             (not (null (string-match-p
                                         "\\*knayawp-claude-prompt-"
                                         (buffer-name))))
                             #'eq)
        (knayawp-probe-check "s4-prompt-mode-active"
                             t (and knayawp-claude-prompt-mode t) #'eq)
        (knayawp-probe-check "s4-reference-preloaded"
                             t
                             (not (null (string-match-p
                                         "@stc-test4\\.el:L"
                                         (buffer-string))))
                             #'eq)
        ;; The compose buffer must live in a non-side (editor) window.
        (knayawp-probe-check "s4-editor-window-not-side"
                             nil
                             (window-parameter (selected-window) 'window-side)
                             #'eq)
        ;; Finish: inject into Claude, restore editor, focus Claude panel.
        (let ((compose-buf (current-buffer)))
          (knayawp-claude-prompt-send)
          (stc--settle)
          (knayawp-probe-check "s4-compose-buffer-killed"
                               nil (buffer-live-p compose-buf) #'eq))
        (knayawp-probe-check "s4-prompt-var-cleared"
                             nil knayawp--claude-prompt-buffer #'eq)
        (knayawp-probe-assert-selected-window-slot 1 "s4-claude-panel-selected")
        (knayawp-probe-assert-selected-window-side 'right "s4-claude-panel-side")
        (knayawp-probe-assert-total-window-count 5 "s4-full-layout-restored"))
    (error (knayawp-probe-abort "s4 failed: %S" e)))
  (knayawp-probe-teardown-layout))

;;;; Drive all scenarios

(knayawp-probe-watchdog 90)

(condition-case e
    (let ((default-directory (file-name-as-directory sandbox--test-dir)))
      (knayawp-probe-log "  probe start  default-directory=%S" default-directory)
      (stc--scenario-1)
      (stc--scenario-2)
      (stc--scenario-3)
      (stc--scenario-4))
  (error (knayawp-probe-abort "top-level error: %S" e)))

(knayawp-probe-finish)

;;; send-to-claude.el ends here
