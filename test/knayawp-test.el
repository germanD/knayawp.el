;;; knayawp-test.el --- Tests for knayawp.el -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for knayawp.el.  Run with:
;;   emacs -batch -l ert -l knayawp.el -l test/knayawp-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'knayawp)

;;;; Project name derivation

(ert-deftest knayawp-test-project-name-simple ()
  "Derive project name from a simple directory path."
  (should (equal "myproject"
                 (knayawp--project-name "/home/user/myproject/"))))

(ert-deftest knayawp-test-project-name-trailing-slash ()
  "Derive project name handles trailing slash correctly."
  (should (equal "foo"
                 (knayawp--project-name "/tmp/foo/"))))

(ert-deftest knayawp-test-project-name-no-trailing-slash ()
  "Derive project name handles path without trailing slash."
  (should (equal "bar"
                 (knayawp--project-name "/tmp/bar"))))

(ert-deftest knayawp-test-project-name-nested ()
  "Derive project name from a deeply nested path."
  (should (equal "deep"
                 (knayawp--project-name "/a/b/c/deep/"))))

;;;; Buffer naming convention

(ert-deftest knayawp-test-buffer-name-magit ()
  "Buffer name for magit panel follows convention."
  (should (equal "*knayawp-magit-myapp*"
                 (knayawp--buffer-name 'magit "myapp"))))

(ert-deftest knayawp-test-buffer-name-vterm ()
  "Buffer name for vterm panel follows convention."
  (should (equal "*knayawp-vterm-myapp*"
                 (knayawp--buffer-name 'vterm "myapp"))))

(ert-deftest knayawp-test-buffer-name-claude ()
  "Buffer name for claude panel follows convention."
  (should (equal "*knayawp-claude-myapp*"
                 (knayawp--buffer-name 'claude "myapp"))))

(ert-deftest knayawp-test-buffer-name-format ()
  "Buffer name uses *knayawp-TYPE-PROJECT* format."
  (let ((name (knayawp--buffer-name 'test "proj")))
    (should (string-prefix-p "*knayawp-" name))
    (should (string-suffix-p "*" name))
    (should (string-match-p "\\*knayawp-test-proj\\*" name))))

;;;; Panel spec parsing

(ert-deftest knayawp-test-panel-type ()
  "Extract panel type from spec."
  (should (eq 'magit
              (knayawp--panel-type '(magit :slot -1)))))

(ert-deftest knayawp-test-panel-slot ()
  "Extract slot from panel spec."
  (should (equal -1
                 (knayawp--panel-slot '(magit :slot -1))))
  (should (equal 0
                 (knayawp--panel-slot '(vterm :slot 0))))
  (should (equal 1
                 (knayawp--panel-slot '(claude :slot 1)))))

;;;; Terminal dispatch routing

(ert-deftest knayawp-test-dispatch-unknown-backend ()
  "Unknown terminal backend signals user-error."
  (let ((knayawp-terminal-backend 'nonexistent))
    (should-error (knayawp--make-terminal "test" "/tmp")
                  :type 'user-error)))

(ert-deftest knayawp-test-dispatch-vterm-missing ()
  "Vterm backend signals user-error when not installed."
  ;; In batch mode, vterm is typically not available
  (unless (featurep 'vterm)
    (let ((knayawp-terminal-backend 'vterm))
      (should-error (knayawp--make-terminal "test" "/tmp")
                    :type 'user-error))))

(ert-deftest knayawp-test-dispatch-eat-missing ()
  "Eat backend signals user-error when not installed."
  ;; In batch mode, eat is typically not available
  (unless (featurep 'eat)
    (let ((knayawp-terminal-backend 'eat))
      (should-error (knayawp--make-terminal "test" "/tmp")
                    :type 'user-error))))

;;;; Default customization values

(ert-deftest knayawp-test-default-right-width ()
  "Default right pane width is 0.4."
  (should (equal 0.4 (default-value 'knayawp-right-width))))

(ert-deftest knayawp-test-default-claude-command ()
  "Default Claude command is \"claude\"."
  (should (equal "claude" (default-value 'knayawp-claude-command))))

(ert-deftest knayawp-test-default-terminal-backend ()
  "Default terminal backend is vterm."
  (should (eq 'vterm (default-value 'knayawp-terminal-backend))))

(ert-deftest knayawp-test-default-panels ()
  "Default panels has three entries with correct types."
  (let ((panels (default-value 'knayawp-panels)))
    (should (equal 3 (length panels)))
    (should (eq 'magit (caar panels)))
    (should (eq 'vterm (caadr panels)))
    (should (eq 'claude (caaddr panels)))))

;;;; Panel spec defaults

(ert-deftest knayawp-test-panel-slots-ordered ()
  "Panel slots are ordered: magit < vterm < claude."
  (let ((panels (default-value 'knayawp-panels)))
    (should (< (knayawp--panel-slot (nth 0 panels))
               (knayawp--panel-slot (nth 1 panels))))
    (should (< (knayawp--panel-slot (nth 1 panels))
               (knayawp--panel-slot (nth 2 panels))))))

;;;; Passive loading (P7)

(ert-deftest knayawp-test-passive-loading ()
  "Requiring the package must not modify window-sides-slots."
  ;; window-sides-slots should not be set by merely loading
  (should (not (equal '(nil nil nil 3)
                      (default-value 'window-sides-slots)))))

;;;; Command map

(ert-deftest knayawp-test-command-map-exists ()
  "Command map is defined and is a keymap."
  (should (keymapp knayawp-command-map)))

(ert-deftest knayawp-test-command-map-bindings ()
  "Command map has expected bindings."
  (should (eq 'knayawp-layout-setup
              (lookup-key knayawp-command-map "l")))
  (should (eq 'knayawp-layout-teardown
              (lookup-key knayawp-command-map "q")))
  (should (eq 'knayawp-next-panel
              (lookup-key knayawp-command-map "n")))
  (should (eq 'knayawp-prev-panel
              (lookup-key knayawp-command-map "p")))
  (should (eq 'knayawp-zoom-panel
              (lookup-key knayawp-command-map "z")))
  (should (eq 'knayawp-select-editor
              (lookup-key knayawp-command-map "0")))
  (should (eq 'knayawp-toggle-panels
              (lookup-key knayawp-command-map "s")))
  ;; 1/2/3 are lambdas, just verify they're bound
  (should (lookup-key knayawp-command-map "1"))
  (should (lookup-key knayawp-command-map "2"))
  (should (lookup-key knayawp-command-map "3")))

;;;; Buffer reuse

(ert-deftest knayawp-test-get-or-create-vterm-reuses ()
  "Reuse existing terminal buffer if it exists."
  (let ((buf-name (knayawp--buffer-name 'vterm "testproj"))
        (buf nil))
    (unwind-protect
        (progn
          (setq buf (get-buffer-create buf-name))
          ;; The function should return the existing buffer
          (should (eq buf (knayawp--get-or-create-vterm-buffer
                           "/tmp/testproj" "testproj"))))
      (when buf (kill-buffer buf)))))

(ert-deftest knayawp-test-get-or-create-claude-reuses ()
  "Reuse existing Claude buffer if it exists."
  (let ((buf-name (knayawp--buffer-name 'claude "testproj"))
        (buf nil))
    (unwind-protect
        (progn
          (setq buf (get-buffer-create buf-name))
          ;; The function should return the existing buffer
          (should (eq buf (knayawp--get-or-create-claude-buffer
                           "/tmp/testproj" "testproj"))))
      (when buf (kill-buffer buf)))))

;;;; Panel navigation helpers

(ert-deftest knayawp-test-panel-spec-at-index ()
  "Return correct panel spec by index."
  (let ((knayawp-panels '((magit :slot -1)
                           (vterm :slot 0)
                           (claude :slot 1))))
    (should (eq 'magit (car (knayawp--panel-spec-at-index 0))))
    (should (eq 'vterm (car (knayawp--panel-spec-at-index 1))))
    (should (eq 'claude (car (knayawp--panel-spec-at-index 2))))
    (should-not (knayawp--panel-spec-at-index 3))))

(ert-deftest knayawp-test-select-panel-bad-index ()
  "Selecting a non-existent panel signals user-error."
  (should-error (knayawp-select-panel 99)
                :type 'user-error))

(ert-deftest knayawp-test-zoom-not-in-panel ()
  "Zooming when not in a side window signals user-error."
  (let ((knayawp--zoomed-panel nil))
    (should-error (knayawp-zoom-panel)
                  :type 'user-error)))

(ert-deftest knayawp-test-current-panel-index-not-side ()
  "Return nil when selected window is not a side window."
  ;; In batch mode, the selected window is never a side window
  (should-not (knayawp--current-panel-index)))

;;;; Magit integration

(ert-deftest knayawp-test-magit-commit-in-editor-flag-default ()
  "Default commit-in-editor flag is t."
  (should (eq t (default-value 'knayawp-magit-commit-in-editor-flag))))

(ert-deftest knayawp-test-magit-saved-display-fn-initially-nil ()
  "Saved magit display function is nil before setup."
  (should-not knayawp--magit-saved-display-fn))

(ert-deftest knayawp-test-magit-commit-entry-initially-nil ()
  "Commit display-buffer-alist entry is nil before setup."
  (should-not knayawp--commit-display-entry))

(ert-deftest knayawp-test-magit-display-buffer-no-layout ()
  "Display function falls back when no side window exists."
  ;; In batch mode there are no side windows, so it should fall back.
  ;; We just verify it doesn't error and returns a window.
  (when (require 'magit nil t)
    (let ((buf (get-buffer-create "*magit-test-fallback*")))
      (unwind-protect
          (should (windowp (knayawp--magit-display-buffer buf)))
        (kill-buffer buf)))))

(ert-deftest knayawp-test-magit-teardown-idempotent ()
  "Tearing down magit integration when not set up is safe."
  (let ((knayawp--magit-saved-display-fn nil)
        (knayawp--commit-display-entry nil)
        (knayawp--process-display-entry nil))
    (knayawp--teardown-magit-integration)
    (should-not knayawp--magit-saved-display-fn)
    (should-not knayawp--commit-display-entry)
    (should-not knayawp--process-display-entry)))

(ert-deftest knayawp-test-magit-setup-teardown-roundtrip ()
  "Setup then teardown restores original display function."
  (when (require 'magit nil t)
    (let ((original magit-display-buffer-function)
          (knayawp--magit-saved-display-fn nil)
          (knayawp--commit-display-entry nil)
          (knayawp--process-display-entry nil)
          (display-buffer-alist display-buffer-alist))
      (unwind-protect
          (progn
            (knayawp--setup-magit-integration)
            (should (eq magit-display-buffer-function
                        #'knayawp--magit-display-buffer))
            (should knayawp--magit-saved-display-fn)
            (knayawp--teardown-magit-integration)
            (should (eq magit-display-buffer-function original))
            (should-not knayawp--magit-saved-display-fn)
            (should-not knayawp--process-display-entry))
        ;; Safety restore
        (setq magit-display-buffer-function original)))))

(ert-deftest knayawp-test-magit-double-setup-safe ()
  "Calling setup twice preserves the real original display function."
  (when (require 'magit nil t)
    (let ((original magit-display-buffer-function)
          (knayawp--magit-saved-display-fn nil)
          (knayawp--commit-display-entry nil)
          (knayawp--process-display-entry nil)
          (knayawp-magit-commit-in-editor-flag t)
          (display-buffer-alist nil))
      (unwind-protect
          (progn
            (knayawp--setup-magit-integration)
            (should (eq knayawp--magit-saved-display-fn original))
            ;; Second setup must not overwrite the saved function
            (knayawp--setup-magit-integration)
            (should (eq knayawp--magit-saved-display-fn original))
            ;; display-buffer-alist must not have duplicates: one
            ;; COMMIT_EDITMSG entry and one magit-process entry.
            (should (= 2 (length display-buffer-alist)))
            ;; Teardown must restore the real original
            (knayawp--teardown-magit-integration)
            (should (eq magit-display-buffer-function original)))
        (setq magit-display-buffer-function original)))))

(ert-deftest knayawp-test-commit-display-alist-entry ()
  "Setup adds COMMIT_EDITMSG to display-buffer-alist."
  (when (require 'magit nil t)
    (let ((original magit-display-buffer-function)
          (knayawp--magit-saved-display-fn nil)
          (knayawp--commit-display-entry nil)
          (knayawp--process-display-entry nil)
          (knayawp-magit-commit-in-editor-flag t)
          (display-buffer-alist nil))
      (unwind-protect
          (progn
            (knayawp--setup-magit-integration)
            ;; Setup adds both the COMMIT_EDITMSG entry and the
            ;; magit-process entry.
            (should (= 2 (length display-buffer-alist)))
            (should (seq-find
                     (lambda (e)
                       (and (stringp (car e))
                            (string-match-p "COMMIT_EDITMSG"
                                            (car e))))
                     display-buffer-alist))
            (knayawp--teardown-magit-integration)
            (should (null display-buffer-alist)))
        (setq magit-display-buffer-function original)))))

(ert-deftest knayawp-test-commit-display-alist-flag-off ()
  "No COMMIT_EDITMSG entry when flag is nil."
  (when (require 'magit nil t)
    (let ((original magit-display-buffer-function)
          (knayawp--magit-saved-display-fn nil)
          (knayawp--commit-display-entry nil)
          (knayawp--process-display-entry nil)
          (knayawp-magit-commit-in-editor-flag nil)
          (display-buffer-alist nil))
      (unwind-protect
          (progn
            (knayawp--setup-magit-integration)
            ;; Process entry is always added; commit entry only with flag.
            (should (= 1 (length display-buffer-alist)))
            (should-not (seq-find
                         (lambda (e)
                           (and (stringp (car e))
                                (string-match-p "COMMIT_EDITMSG"
                                                (car e))))
                         display-buffer-alist))
            (knayawp--teardown-magit-integration)
            (should (null display-buffer-alist)))
        (setq magit-display-buffer-function original)))))

(ert-deftest knayawp-test-magit-process-entry-initially-nil ()
  "Process display-buffer-alist entry is nil before setup."
  (should-not knayawp--process-display-entry))

(ert-deftest knayawp-test-magit-process-buffer-p-no-window ()
  "Process matcher returns nil when no magit side window exists.
This guards against routing process buffers to a side window
when no layout is active."
  ;; In batch mode there are never side windows, so the matcher must
  ;; return nil regardless of the candidate buffer's mode.
  (let ((buf (get-buffer-create "*knayawp-test-process-buffer*")))
    (unwind-protect
        (should-not (knayawp--magit-process-buffer-p buf nil))
      (kill-buffer buf))))

(ert-deftest knayawp-test-magit-process-display-alist-entry ()
  "Setup adds a `magit-process-mode' entry to `display-buffer-alist'.
Teardown removes it."
  (when (require 'magit nil t)
    (let ((original magit-display-buffer-function)
          (knayawp--magit-saved-display-fn nil)
          (knayawp--commit-display-entry nil)
          (knayawp--process-display-entry nil)
          (knayawp-magit-commit-in-editor-flag nil)
          (display-buffer-alist nil))
      (unwind-protect
          (progn
            (knayawp--setup-magit-integration)
            (should knayawp--process-display-entry)
            (should (memq knayawp--process-display-entry
                          display-buffer-alist))
            ;; The matcher is our predicate function.
            (should (eq 'knayawp--magit-process-buffer-p
                        (car knayawp--process-display-entry)))
            ;; The action routes to a right side window in the magit
            ;; slot.
            (let ((alist (cdr knayawp--process-display-entry)))
              (should (memq 'display-buffer-in-side-window
                            (car alist)))
              (should (eq 'right (alist-get 'side alist)))
              (should (equal -1 (alist-get 'slot alist))))
            (knayawp--teardown-magit-integration)
            (should-not knayawp--process-display-entry)
            (should (null display-buffer-alist)))
        (setq magit-display-buffer-function original)))))

;;;; No project signals error

(ert-deftest knayawp-test-no-project-error ()
  "Setup signals user-error when no project is found."
  (let ((default-directory "/"))
    (should-error (knayawp--project-root)
                  :type 'user-error)))

;;; knayawp-test.el ends here
