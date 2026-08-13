;;; probe-lib.el --- Assertion/reporting harness for knayawp probes -*- lexical-binding: t; -*-

;;; Commentary:

;; Loaded by self-running ("auto") sandbox probes so they can run
;; unattended under test/run-probe.sh: assert facts, accumulate a
;; PASS/FAIL report, write it to a results file, and exit Emacs.
;;
;; A probe typically:
;;   1. performs setup actions (knayawp-mode, layout-setup, ...),
;;   2. records checks via `knayawp-probe-check',
;;   3. for async flows, drives them with hooks/timers and calls
;;      `knayawp-probe-finish' from the terminating step.
;;
;; A watchdog (`knayawp-probe-watchdog') guarantees the file is written
;; and Emacs exits even if the flow never completes, so the harness
;; never hangs.
;;
;; The results file is named by the KNAYAWP_PROBE_RESULTS environment
;; variable (set by run-probe.sh) or `knayawp-probe-results-file'.

;;; Code:

(require 'cl-lib)
(require 'seq)

;; Byte-compiler declarations.  `sandbox--test-dir' is defined by the
;; sandbox session (test/sandbox.el); the magit / with-editor functions
;; are driven at runtime but not required at compile time.
(defvar sandbox--test-dir)
(declare-function magit-run-git "magit-process")
(declare-function magit-commit-create "magit-commit")
(declare-function magit-commit-reword "magit-commit")
(declare-function with-editor-finish "with-editor")

(defvar knayawp-probe-results-file
  (or (getenv "KNAYAWP_PROBE_RESULTS")
      (expand-file-name "knayawp-probe.out" temporary-file-directory))
  "File where `knayawp-probe-finish' writes the report.")

(defvar knayawp-probe--lines nil
  "Report lines accumulated in reverse order.")

(defvar knayawp-probe--pass 0
  "Number of checks that have passed so far.")

(defvar knayawp-probe--fail 0
  "Number of checks that have failed so far.")

(defvar knayawp-probe--finished nil
  "Non-nil once the report has been written.")

(defvar knayawp-probe--aborted nil
  "Non-nil when the run ended via `knayawp-probe-abort' (e.g. timeout).")

(defvar knayawp-probe--saved-commit-style nil
  "Value of `knayawp-magit-commit-style' saved by `knayawp-probe-setup-layout'.")

(defun knayawp-probe-log (fmt &rest args)
  "Append a free-form report line formatted from FMT and ARGS."
  (push (apply #'format fmt args) knayawp-probe--lines))

(defun knayawp-probe-section (name)
  "Start a new report section titled NAME."
  (push (concat "" name) knayawp-probe--lines))

(defun knayawp-probe-check (label expected actual &optional test)
  "Record a check of ACTUAL against EXPECTED under LABEL.
TEST defaults to `equal'.  Return non-nil when the check passes."
  (let* ((test (or test #'equal))
         (ok (funcall test expected actual)))
    (if ok (cl-incf knayawp-probe--pass) (cl-incf knayawp-probe--fail))
    (push (format "  [%s] %-26s expected=%S actual=%S"
                  (if ok "PASS" "FAIL") label expected actual)
          knayawp-probe--lines)
    ok))

(defun knayawp-probe-finish (&optional note)
  "Write the accumulated report and kill Emacs.  Idempotent.
NOTE, when given, is appended as a trailing remark."
  (unless knayawp-probe--finished
    (setq knayawp-probe--finished t)
    (when note (push (concat "NOTE: " note) knayawp-probe--lines))
    (push (format "RESULT: %d passed, %d failed%s"
                  knayawp-probe--pass knayawp-probe--fail
                  (if knayawp-probe--aborted " (ABORTED)" ""))
          knayawp-probe--lines)
    (push (cond (knayawp-probe--aborted "STATUS: INCOMPLETE")
                ((zerop knayawp-probe--fail) "STATUS: GREEN")
                (t "STATUS: RED"))
          knayawp-probe--lines)
    (let ((report (mapconcat #'identity
                             (reverse knayawp-probe--lines) "\n")))
      (with-temp-file knayawp-probe-results-file
        (insert report "\n")))
    (run-with-timer 0.1 nil #'kill-emacs)))

(defun knayawp-probe-abort (fmt &rest args)
  "Record a fatal abort line from FMT and ARGS, then finish.
Marks the run INCOMPLETE so a timeout never reads as GREEN."
  (setq knayawp-probe--aborted t)
  (push (concat "ABORT: " (apply #'format fmt args)) knayawp-probe--lines)
  (knayawp-probe-finish))

(defun knayawp-probe-watchdog (seconds)
  "Force `knayawp-probe-abort' after SECONDS if not yet finished."
  (run-with-timer
   seconds nil
   (lambda ()
     (unless knayawp-probe--finished
       (knayawp-probe-abort "watchdog timeout after %ss" seconds)))))

;;;; Layout / window count assertions

(defun knayawp-probe-assert-side-window-count (expected label)
  "Fail with LABEL unless side-window count equals EXPECTED."
  (let ((actual (length (knayawp--side-windows))))
    (knayawp-probe-check label expected actual)))

(defun knayawp-probe-assert-total-window-count (expected label)
  "Fail with LABEL unless total non-minibuffer window count equals EXPECTED."
  (let ((actual (length (window-list nil 'no-minibuf))))
    (knayawp-probe-check label expected actual)))

(defun knayawp-probe-assert-no-side-windows (label)
  "Fail with LABEL if any side windows exist."
  (knayawp-probe-assert-side-window-count 0 label))

(defun knayawp-probe-assert-selected-window-slot (expected-slot label)
  "Fail with LABEL unless selected window has EXPECTED-SLOT."
  (let ((actual (window-parameter (selected-window) 'window-slot)))
    (knayawp-probe-check label expected-slot actual)))

(defun knayawp-probe-assert-selected-window-side (expected-side label)
  "Fail with LABEL unless selected window has EXPECTED-SIDE."
  (let ((actual (window-parameter (selected-window) 'window-side)))
    (knayawp-probe-check label expected-side actual)))

(defun knayawp-probe-assert-window-buf-at-slot (slot pattern label)
  "Fail with LABEL unless side window at SLOT has buffer matching PATTERN."
  (let* ((win (seq-find (lambda (w)
                          (= slot (window-parameter w 'window-slot)))
                        (knayawp--side-windows)))
         (buf-name (and win (buffer-name (window-buffer win)))))
    (knayawp-probe-check label t
                         (and (stringp buf-name)
                              (string-match-p pattern buf-name))
                         #'eq)))

;;;; Zoom / monocle state assertions

(defun knayawp-probe-assert-zoomed (expected-panel label)
  "Fail with LABEL unless `knayawp--zoomed-panel' eq EXPECTED-PANEL."
  (knayawp-probe-check label expected-panel knayawp--zoomed-panel #'eq))

(defun knayawp-probe-assert-not-zoomed (label)
  "Fail with LABEL if `knayawp--zoomed-panel' is non-nil."
  (knayawp-probe-check label nil knayawp--zoomed-panel))

(defun knayawp-probe-assert-monocle-active (label)
  "Fail with LABEL unless monocle frame parameter is non-nil."
  (let ((cfg (frame-parameter nil 'knayawp--monocle-config)))
    (knayawp-probe-check label t (not (null cfg)) #'eq)))

(defun knayawp-probe-assert-monocle-inactive (label)
  "Fail with LABEL if monocle frame parameter is non-nil."
  (let ((cfg (frame-parameter nil 'knayawp--monocle-config)))
    (knayawp-probe-check label nil cfg)))

;;;; Frame / window parameter assertions

(defun knayawp-probe-assert-frame-param (param expected label)
  "Fail with LABEL unless frame parameter PARAM equals EXPECTED."
  (let ((actual (frame-parameter nil param)))
    (knayawp-probe-check label expected actual)))

(defun knayawp-probe-assert-window-param (window param expected label)
  "Fail with LABEL unless WINDOW parameter PARAM equals EXPECTED."
  (let ((actual (window-parameter window param)))
    (knayawp-probe-check label expected actual)))

;;;; Shared setup / teardown (consolidates per-probe boilerplate)

(defun knayawp-probe-select-slot (slot)
  "Select the side window at SLOT; signal error if not found."
  (let ((win (seq-find (lambda (w) (= slot (window-parameter w 'window-slot)))
                       (knayawp--side-windows))))
    (unless win (error "No side window at slot %d" slot))
    (select-window win)))

(defun knayawp-probe-setup-layout (&optional commit-style)
  "Enable mode, optionally set COMMIT-STYLE, run layout setup, then settle."
  (setq knayawp--zoomed-panel nil)
  (set-frame-parameter nil 'knayawp--monocle-config nil)
  (knayawp-mode 1)
  (when commit-style
    (setq knayawp-probe--saved-commit-style knayawp-magit-commit-style)
    (setq knayawp-magit-commit-style commit-style))
  (knayawp-layout-setup)
  (sit-for knayawp-probe--settle))

(defun knayawp-probe-teardown-layout ()
  "Tear down the layout, handling zoom and monocle state first."
  (when knayawp--zoomed-panel
    (knayawp-zoom-panel))
  (when (frame-parameter nil 'knayawp--monocle-config)
    (knayawp-monocle-panel))
  (knayawp-layout-teardown)
  (knayawp-mode -1)
  (when knayawp-probe--saved-commit-style
    (setq knayawp-magit-commit-style knayawp-probe--saved-commit-style)
    (setq knayawp-probe--saved-commit-style nil)))

;;;; Probe utility functions

(defun knayawp-probe-side-windows ()
  "Return the side windows of the selected frame."
  (seq-filter (lambda (w) (window-parameter w 'window-side))
              (window-list)))

(defun knayawp-probe-window-summary ()
  "Return a compact list describing every window in the selected frame.
Each element is (BUFFER-NAME SIDE SLOT)."
  (mapcar (lambda (w)
            (list (buffer-name (window-buffer w))
                  (window-parameter w 'window-side)
                  (window-parameter w 'window-slot)))
          (window-list)))

;;;; Async commit driver

;; A magit commit runs git asynchronously and calls back into Emacs via
;; `with-editor' to open COMMIT_EDITMSG.  These helpers let a probe drive
;; that round-trip unattended: run a "mid" probe when the editor opens,
;; insert a stub message, finish the commit, then run a "done" probe.
;;
;; The hook functions are global and named (not closures) so `remove-hook'
;; can reliably unregister them, and they are added with APPEND so they
;; run AFTER knayawp's own commit-flow handlers in `zoom' style.

(defvar knayawp-probe--mid-fn nil
  "Function called once COMMIT_EDITMSG is set up, before finishing.")

(defvar knayawp-probe--done-fn nil
  "Function called after the commit finishes.")

(defvar knayawp-probe--settle 0.5
  "Seconds to let the display settle before each commit phase.")

(defvar knayawp-probe-commit-message "probe: stub commit message\n"
  "Message inserted into COMMIT_EDITMSG by the driver.")

(defun knayawp-probe--set-commit-message ()
  "Replace the message body of the current commit buffer with the stub.
Deletes any pre-populated body (e.g. the existing message during a
reword) up to the first comment line, so the stub becomes a clean
single-line summary and git-commit's style check does not prompt."
  (goto-char (point-min))
  (let ((end (save-excursion
               (goto-char (point-min))
               (if (re-search-forward "^#" nil t)
                   (line-beginning-position)
                 (point-max)))))
    (delete-region (point-min) end))
  (goto-char (point-min))
  (insert knayawp-probe-commit-message))

(defun knayawp-probe--on-commit-setup ()
  "One-shot `git-commit-setup-hook': run the mid probe, then finish."
  (remove-hook 'git-commit-setup-hook #'knayawp-probe--on-commit-setup)
  (let ((buf (current-buffer))
        (mid knayawp-probe--mid-fn))
    (run-with-timer
     knayawp-probe--settle nil
     (lambda ()
       (condition-case e
           (progn
             (when mid (funcall mid))
             (when (buffer-live-p buf)
               (with-current-buffer buf
                 (knayawp-probe--set-commit-message)
                 (with-editor-finish nil))))
         (error (knayawp-probe-abort "mid/finish failed: %S" e)))))))

(defun knayawp-probe--on-commit-finish ()
  "One-shot `with-editor-post-finish-hook': run the done probe."
  (remove-hook 'with-editor-post-finish-hook
               #'knayawp-probe--on-commit-finish)
  (let ((done knayawp-probe--done-fn))
    (run-with-timer
     knayawp-probe--settle nil
     (lambda ()
       (condition-case e (when done (funcall done))
         (error (knayawp-probe-abort "done failed: %S" e)))))))

(defun knayawp-probe-stage-and-commit ()
  "Default kickoff: edit and stage hello.el, then `magit-commit-create'."
  (let* ((default-directory (file-name-as-directory sandbox--test-dir))
         (file (expand-file-name "hello.el" sandbox--test-dir)))
    (with-temp-buffer
      (insert "\n;; probe edit\n")
      (append-to-file (point-min) (point-max) file))
    (magit-run-git "add" "hello.el")
    (magit-commit-create)))

(defun knayawp-probe-drive-commit (mid-fn done-fn &optional kickoff-fn)
  "Drive a commit flow unattended.
MID-FN runs (commit buffer current and displayed) when the editor
opens; the driver then inserts a stub message and finishes.
DONE-FN runs after the commit finishes and is expected to call
`knayawp-probe-finish'.  KICKOFF-FN starts the flow, defaulting to
`knayawp-probe-stage-and-commit'."
  (setq knayawp-probe--mid-fn mid-fn
        knayawp-probe--done-fn done-fn)
  (add-hook 'git-commit-setup-hook #'knayawp-probe--on-commit-setup t)
  (add-hook 'with-editor-post-finish-hook
            #'knayawp-probe--on-commit-finish t)
  (condition-case e
      (funcall (or kickoff-fn #'knayawp-probe-stage-and-commit))
    (error (knayawp-probe-abort "commit kickoff failed: %S" e))))

(provide 'probe-lib)
;;; probe-lib.el ends here
