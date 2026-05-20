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

(ert-deftest knayawp-test-mode-disabled-by-default ()
  "`knayawp-mode' is disabled when the package is merely loaded."
  (should (not (default-value 'knayawp-mode))))

;;;; Global minor mode

(ert-deftest knayawp-test-mode-defined ()
  "`knayawp-mode' is a global minor mode."
  (should (fboundp 'knayawp-mode))
  (should (get 'knayawp-mode 'standard-value)))

(ert-deftest knayawp-test-mode-toggle-invokes-helpers ()
  "Enabling and disabling the mode calls the on/off helpers."
  (let ((on-calls 0)
        (off-calls 0))
    (cl-letf (((symbol-function 'knayawp--mode-on)
               (lambda () (cl-incf on-calls)))
              ((symbol-function 'knayawp--mode-off)
               (lambda () (cl-incf off-calls))))
      (unwind-protect
          (progn
            (knayawp-mode 1)
            (should (= 1 on-calls))
            (should (= 0 off-calls))
            (knayawp-mode -1)
            (should (= 1 on-calls))
            (should (= 1 off-calls)))
        ;; Always leave the mode disabled.
        (knayawp-mode -1)))))

(ert-deftest knayawp-test-mode-roundtrip-leaves-disabled ()
  "Toggling the mode on and off returns to the disabled state."
  (cl-letf (((symbol-function 'knayawp--mode-on) #'ignore)
            ((symbol-function 'knayawp--mode-off) #'ignore))
    (unwind-protect
        (progn
          (knayawp-mode 1)
          (should knayawp-mode)
          (knayawp-mode -1)
          (should (not knayawp-mode)))
      (knayawp-mode -1))))

;;;; project-switch-project auto-layout (#29)

(ert-deftest knayawp-test-mode-on-installs-project-switch-action ()
  "Enabling the mode replaces `project-switch-commands'."
  (let ((project-switch-commands 'sentinel-original)
        (knayawp--saved-project-switch-commands nil))
    (unwind-protect
        (progn
          (knayawp--mode-on)
          (should (eq project-switch-commands
                      #'knayawp-layout-setup))
          (should (eq knayawp--saved-project-switch-commands
                      'sentinel-original)))
      (knayawp--mode-off))))

(ert-deftest knayawp-test-mode-off-restores-project-switch-action ()
  "Disabling the mode restores the saved `project-switch-commands'."
  (let ((project-switch-commands 'sentinel-original)
        (knayawp--saved-project-switch-commands nil))
    (knayawp--mode-on)
    (knayawp--mode-off)
    (should (eq project-switch-commands 'sentinel-original))
    (should-not knayawp--saved-project-switch-commands)))

(ert-deftest knayawp-test-mode-on-double-call-preserves-saved ()
  "Calling `knayawp--mode-on' twice keeps the original saved value."
  (let ((project-switch-commands 'sentinel-original)
        (knayawp--saved-project-switch-commands nil))
    (unwind-protect
        (progn
          (knayawp--mode-on)
          (knayawp--mode-on)
          (should (eq knayawp--saved-project-switch-commands
                      'sentinel-original))
          (should (eq project-switch-commands
                      #'knayawp-layout-setup)))
      (knayawp--mode-off))))

(ert-deftest knayawp-test-mode-off-no-op-when-not-installed ()
  "Disabling the mode is safe when our action is not installed.
This guards against clobbering a user value if mode-off is called
without a matching mode-on."
  (let ((project-switch-commands 'user-value)
        (knayawp--saved-project-switch-commands nil))
    (knayawp--mode-off)
    (should (eq project-switch-commands 'user-value))
    (should-not knayawp--saved-project-switch-commands)))

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
  ;; 1/2/3 dispatch directly through named helpers
  (should (eq 'knayawp--select-panel-1
              (lookup-key knayawp-command-map "1")))
  (should (eq 'knayawp--select-panel-2
              (lookup-key knayawp-command-map "2")))
  (should (eq 'knayawp--select-panel-3
              (lookup-key knayawp-command-map "3"))))

;;;; Keymap style

(ert-deftest knayawp-test-keymap-style-default-value ()
  "`knayawp-keymap-style' defaults to `default'."
  (should (eq 'default (default-value 'knayawp-keymap-style))))

(ert-deftest knayawp-test-build-default-style-no-arrows ()
  "Default style does not bind <up>, <down>, S-<up>, or S-<down>."
  (let* ((knayawp-keymap-style 'default)
         (map (knayawp--build-command-map)))
    (should (eq 'knayawp-next-panel (lookup-key map "n")))
    (should (eq 'knayawp-prev-panel (lookup-key map "p")))
    (should-not (lookup-key map (kbd "<up>")))
    (should-not (lookup-key map (kbd "<down>")))
    (should-not (lookup-key map (kbd "S-<up>")))
    (should-not (lookup-key map (kbd "S-<down>")))))

(ert-deftest knayawp-test-build-tmux-style-arrow-bindings ()
  "Tmux style binds <up>/<down> to panel navigation."
  (let* ((knayawp-keymap-style 'tmux)
         (map (knayawp--build-command-map)))
    (should (eq 'knayawp-prev-panel (lookup-key map (kbd "<up>"))))
    (should (eq 'knayawp-next-panel (lookup-key map (kbd "<down>"))))
    ;; Letter fallback still works.
    (should (eq 'knayawp-layout-setup (lookup-key map "l")))
    (should (eq 'knayawp-next-panel (lookup-key map "n")))
    ;; <left>/<right> are reserved for v0.2 project tabs and unbound now.
    (should-not (lookup-key map (kbd "<left>")))
    (should-not (lookup-key map (kbd "<right>")))))

(ert-deftest knayawp-test-build-byobu-style-shift-arrow-bindings ()
  "Byobu style binds S-<up>/S-<down> to panel navigation."
  (let* ((knayawp-keymap-style 'byobu)
         (map (knayawp--build-command-map)))
    (should (eq 'knayawp-prev-panel (lookup-key map (kbd "S-<up>"))))
    (should (eq 'knayawp-next-panel (lookup-key map (kbd "S-<down>"))))
    ;; Letter fallback still works.
    (should (eq 'knayawp-zoom-panel (lookup-key map "z")))
    (should (eq 'knayawp-toggle-panels (lookup-key map "s")))
    ;; S-<left>/S-<right> are reserved for v0.2 and unbound now.
    (should-not (lookup-key map (kbd "S-<left>")))
    (should-not (lookup-key map (kbd "S-<right>")))))

(ert-deftest knayawp-test-build-unknown-style-errors ()
  "Building the keymap with an unknown style signals user-error."
  (let ((knayawp-keymap-style 'banana))
    (should-error (knayawp--build-command-map) :type 'user-error)))

(ert-deftest knayawp-test-rebuild-command-map-mutates-in-place ()
  "`knayawp-rebuild-command-map' mutates the existing keymap object.
This preserves any prefix binding the user installed against
`knayawp-command-map'."
  (let ((original-object knayawp-command-map)
        (knayawp-keymap-style 'tmux))
    (unwind-protect
        (progn
          (knayawp-rebuild-command-map)
          ;; Same keymap object — prefix bindings still work.
          (should (eq original-object knayawp-command-map))
          ;; New style took effect.
          (should (eq 'knayawp-prev-panel
                      (lookup-key knayawp-command-map (kbd "<up>"))))
          (should (eq 'knayawp-next-panel
                      (lookup-key knayawp-command-map (kbd "<down>")))))
      ;; Restore default style for subsequent tests.
      (setq knayawp-keymap-style 'default)
      (knayawp-rebuild-command-map))))

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

;;;; Panel display routing (#33)

(ert-deftest knayawp-test-panel-display-entries-initially-nil ()
  "Panel display entries are nil before installation."
  (should-not knayawp--panel-display-entries))

(ert-deftest knayawp-test-panel-buffer-name-regexp ()
  "Predicate regexp matches `*knayawp-TYPE-*' buffers only."
  (let ((re (knayawp--panel-buffer-name-regexp 'vterm)))
    (should (string-match-p re "*knayawp-vterm-foo*"))
    (should (string-match-p re "*knayawp-vterm-my-app*"))
    (should-not (string-match-p re "*knayawp-claude-foo*"))
    (should-not (string-match-p re "*scratch*"))
    (should-not (string-match-p re "vterm-foo"))))

(ert-deftest knayawp-test-panel-buffer-predicate-no-window ()
  "Predicate returns nil when no knayawp side window exists.
In batch mode there are never side windows, so the predicate must
return nil regardless of the buffer name match."
  (let* ((spec '(vterm :slot 0))
         (pred (knayawp--make-panel-buffer-predicate spec))
         (buf (get-buffer-create "*knayawp-vterm-testproj*")))
    (unwind-protect
        (progn
          (should-not (funcall pred buf nil))
          (should-not (funcall pred "*knayawp-vterm-testproj*" nil)))
      (kill-buffer buf))))

(ert-deftest knayawp-test-panel-buffer-predicate-rejects-non-match ()
  "Predicate rejects buffers that do not match the type pattern."
  (cl-letf (((symbol-function 'knayawp--side-window-for-slot)
             (lambda (_slot) 'fake-window)))
    (let* ((spec '(vterm :slot 0))
           (pred (knayawp--make-panel-buffer-predicate spec)))
      ;; Even with a "side window" present, name mismatch returns nil.
      (should-not (funcall pred "*scratch*" nil))
      (should-not (funcall pred "*knayawp-claude-foo*" nil))
      ;; Matching name with side window present returns truthy.
      (should (funcall pred "*knayawp-vterm-foo*" nil)))))

(ert-deftest knayawp-test-install-panel-display-routing-adds-entries ()
  "Install adds one entry per panel to `display-buffer-alist'."
  (let ((display-buffer-alist nil)
        (knayawp--panel-display-entries nil)
        (knayawp-panels '((magit  :slot -1)
                          (vterm  :slot  0)
                          (claude :slot  1))))
    (unwind-protect
        (progn
          (knayawp--install-panel-display-routing)
          (should (= 3 (length knayawp--panel-display-entries)))
          (dolist (entry knayawp--panel-display-entries)
            (should (memq entry display-buffer-alist))
            (should (functionp (car entry)))))
      (knayawp--remove-panel-display-routing))))

(ert-deftest knayawp-test-remove-panel-display-routing-clears-entries ()
  "Remove takes installed entries out of `display-buffer-alist'."
  (let ((display-buffer-alist nil)
        (knayawp--panel-display-entries nil)
        (knayawp-panels '((magit  :slot -1)
                          (vterm  :slot  0)
                          (claude :slot  1))))
    (knayawp--install-panel-display-routing)
    (knayawp--remove-panel-display-routing)
    (should (null knayawp--panel-display-entries))
    (should (null display-buffer-alist))))

(ert-deftest knayawp-test-panel-display-routing-roundtrip ()
  "Round-trip leaves `display-buffer-alist' unchanged."
  (let* ((sentinel '("sentinel" display-buffer-pop-up-window))
         (display-buffer-alist (list sentinel))
         (before (copy-sequence display-buffer-alist))
         (knayawp--panel-display-entries nil)
         (knayawp-panels '((magit  :slot -1)
                           (vterm  :slot  0)
                           (claude :slot  1))))
    (knayawp--install-panel-display-routing)
    (knayawp--remove-panel-display-routing)
    (should (equal before display-buffer-alist))))

(ert-deftest knayawp-test-install-panel-display-routing-idempotent ()
  "Double install does not duplicate entries."
  (let ((display-buffer-alist nil)
        (knayawp--panel-display-entries nil)
        (knayawp-panels '((magit  :slot -1)
                          (vterm  :slot  0)
                          (claude :slot  1))))
    (unwind-protect
        (progn
          (knayawp--install-panel-display-routing)
          (knayawp--install-panel-display-routing)
          (should (= 3 (length knayawp--panel-display-entries)))
          (should (= 3 (length display-buffer-alist))))
      (knayawp--remove-panel-display-routing))))

(ert-deftest knayawp-test-mode-on-installs-panel-routing ()
  "Enabling `knayawp-mode' installs panel display entries."
  (let ((display-buffer-alist nil)
        (project-switch-commands 'sentinel-original)
        (knayawp--saved-project-switch-commands nil)
        (knayawp--panel-display-entries nil)
        (knayawp-panels '((magit  :slot -1)
                          (vterm  :slot  0)
                          (claude :slot  1))))
    (unwind-protect
        (progn
          (knayawp--mode-on)
          (should (= 3 (length knayawp--panel-display-entries)))
          (should (= 3 (length display-buffer-alist))))
      (knayawp--mode-off))))

(ert-deftest knayawp-test-mode-off-removes-panel-routing ()
  "Disabling `knayawp-mode' removes panel display entries."
  (let ((display-buffer-alist nil)
        (project-switch-commands 'sentinel-original)
        (knayawp--saved-project-switch-commands nil)
        (knayawp--panel-display-entries nil)
        (knayawp-panels '((magit  :slot -1)
                          (vterm  :slot  0)
                          (claude :slot  1))))
    (knayawp--mode-on)
    (knayawp--mode-off)
    (should (null knayawp--panel-display-entries))
    (should (null display-buffer-alist))))

(ert-deftest knayawp-test-mode-double-on-does-not-duplicate-routing ()
  "Calling `knayawp--mode-on' twice does not duplicate entries."
  (let ((display-buffer-alist nil)
        (project-switch-commands 'sentinel-original)
        (knayawp--saved-project-switch-commands nil)
        (knayawp--panel-display-entries nil)
        (knayawp-panels '((magit  :slot -1)
                          (vterm  :slot  0)
                          (claude :slot  1))))
    (unwind-protect
        (progn
          (knayawp--mode-on)
          (knayawp--mode-on)
          (should (= 3 (length knayawp--panel-display-entries)))
          (should (= 3 (length display-buffer-alist))))
      (knayawp--mode-off))))

;;;; No project signals error

(ert-deftest knayawp-test-no-project-error ()
  "Setup signals user-error when no project is found."
  (let ((default-directory "/"))
    (should-error (knayawp--project-root)
                  :type 'user-error)))

;;;; Layout hook (#31)

(ert-deftest knayawp-test-layout-hook-defined ()
  "`knayawp-layout-hook' is defined and defaults to nil."
  (should (boundp 'knayawp-layout-hook))
  (should (null (default-value 'knayawp-layout-hook))))

(ert-deftest knayawp-test-layout-hook-not-run-on-error ()
  "Hook does not run when `knayawp-layout-setup' errors early.
When no project is found at `default-directory',
`knayawp-layout-setup' must signal a user-error before reaching
the end of its body, leaving `knayawp-layout-hook' unfired."
  (let* ((counter 0)
         (knayawp-layout-hook
          (list (lambda () (cl-incf counter))))
         (default-directory "/"))
    (should-error (knayawp-layout-setup) :type 'user-error)
    (should (= 0 counter))))

;;;; other-window isolation flag (#49)

(ert-deftest knayawp-test-isolate-other-window-flag-default ()
  "`knayawp-isolate-other-window-flag' defaults to t."
  (should (eq t (default-value 'knayawp-isolate-other-window-flag))))

(ert-deftest knayawp-test-side-window-parameters-with-flag ()
  "Helper includes `no-other-window' when flag is non-nil."
  (let ((knayawp-isolate-other-window-flag t))
    (let ((params (knayawp--side-window-parameters)))
      (should (eq t (alist-get 'no-delete-other-windows params)))
      (should (eq t (alist-get 'no-other-window params))))))

(ert-deftest knayawp-test-side-window-parameters-without-flag ()
  "Helper omits `no-other-window' when flag is nil."
  (let ((knayawp-isolate-other-window-flag nil))
    (let ((params (knayawp--side-window-parameters)))
      (should (eq t (alist-get 'no-delete-other-windows params)))
      (should (null (assq 'no-other-window params))))))

;;;; Frame-resize width restoration (#50)

(ert-deftest knayawp-test-frame-widths-initially-nil ()
  "`knayawp--frame-widths' defaults to nil."
  (should (null (default-value 'knayawp--frame-widths))))

(ert-deftest knayawp-test-side-windows-in-frame-empty ()
  "`knayawp--side-windows-in-frame' returns nil when no side windows."
  ;; In batch the selected frame has no side windows.
  (should (null (knayawp--side-windows-in-frame (selected-frame)))))

(ert-deftest knayawp-test-restore-right-width-records-first-call ()
  "First call records the frame width without invoking apply.
On the very first invocation for a frame, there is no recorded
last-width, so the hook must seed the alist and skip the resize
helper."
  (let ((knayawp--frame-widths nil)
        (calls 0))
    (cl-letf (((symbol-function 'knayawp--apply-right-width)
               (lambda (_frame) (cl-incf calls))))
      (knayawp--restore-right-width-on-resize (selected-frame))
      (should (= 0 calls))
      (should (alist-get (selected-frame) knayawp--frame-widths)))))

(ert-deftest knayawp-test-restore-right-width-skips-when-unchanged ()
  "Subsequent calls with the same frame width are a no-op."
  (let ((knayawp--frame-widths nil)
        (calls 0))
    (cl-letf (((symbol-function 'knayawp--apply-right-width)
               (lambda (_frame) (cl-incf calls))))
      ;; First call seeds the width but does not apply.
      (knayawp--restore-right-width-on-resize (selected-frame))
      ;; Second call with unchanged width is a no-op.
      (knayawp--restore-right-width-on-resize (selected-frame))
      (should (= 0 calls)))))

(ert-deftest knayawp-test-restore-right-width-fires-on-width-change ()
  "Apply is invoked when frame width changes between calls."
  (let ((knayawp--frame-widths nil)
        (calls 0))
    (cl-letf (((symbol-function 'knayawp--apply-right-width)
               (lambda (_frame) (cl-incf calls))))
      ;; Seed with the current width.
      (knayawp--restore-right-width-on-resize (selected-frame))
      (should (= 0 calls))
      ;; Simulate an external width change by mutating the recorded
      ;; entry so the next invocation sees a delta.
      (setf (alist-get (selected-frame) knayawp--frame-widths)
            (1- (frame-width (selected-frame))))
      (knayawp--restore-right-width-on-resize (selected-frame))
      (should (= 1 calls)))))

;;;; Commit flow (#48, #53)

(ert-deftest knayawp-test-commit-style-default ()
  "`knayawp-magit-commit-style' defaults to `zoom'."
  (should (eq 'zoom (default-value 'knayawp-magit-commit-style))))

(ert-deftest knayawp-test-commit-style-obsolete-shim-editor ()
  "Old flag = t maps to `editor' when new option is default.
Setup installs a COMMIT_EDITMSG `display-buffer-alist' entry and
no commit hooks."
  (when (require 'magit nil t)
    (let ((original magit-display-buffer-function)
          (knayawp--magit-saved-display-fn nil)
          (knayawp--commit-display-entry nil)
          (knayawp--process-display-entry nil)
          (knayawp--commit-hooks-installed nil)
          (knayawp--commit-style-shim-warned t)
          (knayawp-magit-commit-style 'zoom)
          (knayawp-magit-commit-in-editor-flag t)
          (display-buffer-alist nil))
      (unwind-protect
          (progn
            ;; Simulate "user explicitly set the old flag" by changing
            ;; the default-value via cl-letf'd default-value lookup;
            ;; here we rely on the let-binding above already differing
            ;; from the standard value (t == default), so we force the
            ;; old-customized branch by stubbing default-value lookup.
            (cl-letf (((symbol-function 'default-value)
                       (lambda (sym)
                         (pcase sym
                           ('knayawp-magit-commit-style 'zoom)
                           ('knayawp-magit-commit-in-editor-flag nil)
                           (_ (symbol-value sym))))))
              (knayawp--setup-magit-integration))
            (should (seq-find
                     (lambda (e)
                       (and (stringp (car e))
                            (string-match-p "COMMIT_EDITMSG"
                                            (car e))))
                     display-buffer-alist))
            (should-not (memq #'knayawp--git-commit-setup-handler
                              git-commit-setup-hook))
            (knayawp--teardown-magit-integration))
        (setq magit-display-buffer-function original)))))

(ert-deftest knayawp-test-commit-style-obsolete-shim-off ()
  "Old flag = nil maps to `off' when new option is default.
Setup installs no COMMIT_EDITMSG entry and no commit hooks."
  (when (require 'magit nil t)
    (let ((original magit-display-buffer-function)
          (knayawp--magit-saved-display-fn nil)
          (knayawp--commit-display-entry nil)
          (knayawp--process-display-entry nil)
          (knayawp--commit-hooks-installed nil)
          (knayawp--commit-style-shim-warned t)
          (knayawp-magit-commit-style 'zoom)
          (knayawp-magit-commit-in-editor-flag nil)
          (display-buffer-alist nil))
      (unwind-protect
          (progn
            (cl-letf (((symbol-function 'default-value)
                       (lambda (sym)
                         (pcase sym
                           ('knayawp-magit-commit-style 'zoom)
                           ('knayawp-magit-commit-in-editor-flag t)
                           (_ (symbol-value sym))))))
              (knayawp--setup-magit-integration))
            (should-not (seq-find
                         (lambda (e)
                           (and (stringp (car e))
                                (string-match-p "COMMIT_EDITMSG"
                                                (car e))))
                         display-buffer-alist))
            (should-not (memq #'knayawp--git-commit-setup-handler
                              git-commit-setup-hook))
            (knayawp--teardown-magit-integration))
        (setq magit-display-buffer-function original)))))

(ert-deftest knayawp-test-commit-hooks-installed-when-zoom ()
  "With style = `zoom', setup installs all three commit hooks."
  (when (require 'magit nil t)
    (let ((original magit-display-buffer-function)
          (knayawp--magit-saved-display-fn nil)
          (knayawp--commit-display-entry nil)
          (knayawp--process-display-entry nil)
          (knayawp--commit-hooks-installed nil)
          (knayawp--commit-style-shim-warned t)
          (knayawp-magit-commit-style 'zoom)
          (knayawp-magit-commit-in-editor-flag t)
          (git-commit-setup-hook nil)
          (with-editor-post-finish-hook nil)
          (with-editor-post-cancel-hook nil)
          (display-buffer-alist nil))
      (unwind-protect
          (progn
            (knayawp--setup-magit-integration)
            (should (memq #'knayawp--git-commit-setup-handler
                          git-commit-setup-hook))
            (should (memq #'knayawp--with-editor-finish-handler
                          with-editor-post-finish-hook))
            (should (memq #'knayawp--with-editor-cancel-handler
                          with-editor-post-cancel-hook))
            (should knayawp--commit-hooks-installed))
        (knayawp--teardown-magit-integration)
        (setq magit-display-buffer-function original)))))

(ert-deftest knayawp-test-commit-hooks-removed-on-teardown ()
  "Teardown unregisters all three commit-flow handlers."
  (when (require 'magit nil t)
    (let ((original magit-display-buffer-function)
          (knayawp--magit-saved-display-fn nil)
          (knayawp--commit-display-entry nil)
          (knayawp--process-display-entry nil)
          (knayawp--commit-hooks-installed nil)
          (knayawp--commit-style-shim-warned t)
          (knayawp-magit-commit-style 'zoom)
          (knayawp-magit-commit-in-editor-flag t)
          (git-commit-setup-hook nil)
          (with-editor-post-finish-hook nil)
          (with-editor-post-cancel-hook nil)
          (display-buffer-alist nil))
      (unwind-protect
          (progn
            (knayawp--setup-magit-integration)
            (knayawp--teardown-magit-integration)
            (should-not (memq #'knayawp--git-commit-setup-handler
                              git-commit-setup-hook))
            (should-not (memq #'knayawp--with-editor-finish-handler
                              with-editor-post-finish-hook))
            (should-not (memq #'knayawp--with-editor-cancel-handler
                              with-editor-post-cancel-hook))
            (should-not knayawp--commit-hooks-installed))
        (setq magit-display-buffer-function original)))))

(ert-deftest knayawp-test-commit-pre-state-shape ()
  "`knayawp--save-commit-pre-state' populates all expected plist keys."
  (let ((knayawp--commit-pre-state nil)
        (knayawp--zoomed-panel nil))
    (cl-letf (((symbol-function 'knayawp--side-window-for-slot)
               (lambda (_slot) nil)))
      (knayawp--save-commit-pre-state -1))
    (should (plist-member knayawp--commit-pre-state :active))
    (should (plist-member knayawp--commit-pre-state :was-zoomed))
    (should (plist-member knayawp--commit-pre-state :prior-magit-buf))
    (should (plist-member knayawp--commit-pre-state :pre-commit-window))
    (should (eq t (plist-get knayawp--commit-pre-state :active)))
    (should (windowp (plist-get knayawp--commit-pre-state
                                :pre-commit-window)))
    (setq knayawp--commit-pre-state nil)))

(ert-deftest knayawp-test-commit-flow-handler-gating ()
  "Setup-handler is a no-op when conditions are not met.
Specifically: (a) no layout active, (b) style is not `zoom', and
(c) a commit flow is already active."
  (let ((knayawp--commit-pre-state nil)
        (knayawp-magit-commit-style 'zoom)
        (started 0))
    (cl-letf (((symbol-function 'knayawp--commit-flow-start)
               (lambda () (cl-incf started))))
      ;; (a) No layout active: side-window-for-slot returns nil.
      (cl-letf (((symbol-function 'knayawp--side-window-for-slot)
                 (lambda (_slot) nil)))
        (knayawp--git-commit-setup-handler)
        (should (= 0 started)))
      ;; (b) Style is not `zoom'.
      (cl-letf (((symbol-function 'knayawp--side-window-for-slot)
                 (lambda (_slot) 'fake-window))
                ((symbol-function 'knayawp--resolve-commit-style)
                 (lambda () 'editor)))
        (knayawp--git-commit-setup-handler)
        (should (= 0 started)))
      ;; (c) Commit flow already active.
      (cl-letf (((symbol-function 'knayawp--side-window-for-slot)
                 (lambda (_slot) 'fake-window))
                ((symbol-function 'knayawp--resolve-commit-style)
                 (lambda () 'zoom)))
        (setq knayawp--commit-pre-state (list :active t))
        (knayawp--git-commit-setup-handler)
        (should (= 0 started))
        (setq knayawp--commit-pre-state nil))
      ;; Sanity: when all three conditions hold, the handler fires.
      (cl-letf (((symbol-function 'knayawp--side-window-for-slot)
                 (lambda (_slot) 'fake-window))
                ((symbol-function 'knayawp--resolve-commit-style)
                 (lambda () 'zoom)))
        (knayawp--git-commit-setup-handler)
        (should (= 1 started))))))

(ert-deftest knayawp-test-commit-flow-end-idempotent ()
  "Calling `knayawp--commit-flow-end' twice does not error.
The first call clears state and selects the focus target; the
second call is a no-op because no flow is active."
  (let ((knayawp--commit-pre-state
         (list :active t :was-zoomed nil
               :prior-magit-buf nil
               :pre-commit-window (selected-window)))
        (restored 0))
    (cl-letf (((symbol-function 'knayawp--restore-commit-pre-state)
               (lambda ()
                 (cl-incf restored)
                 (setq knayawp--commit-pre-state nil))))
      (knayawp--commit-flow-end)
      (should (= 1 restored))
      ;; Second call: state is nil, so restore must not be called.
      (knayawp--commit-flow-end)
      (should (= 1 restored)))))

(ert-deftest knayawp-test-commit-pre-state-cleared-by-teardown ()
  "`knayawp-layout-teardown' clears `knayawp--commit-pre-state'."
  (let ((knayawp--commit-pre-state
         (list :active t :was-zoomed nil
               :prior-magit-buf nil
               :pre-commit-window (selected-window)))
        (knayawp--frame-widths nil)
        (knayawp--magit-saved-display-fn nil)
        (knayawp--commit-display-entry nil)
        (knayawp--process-display-entry nil)
        (knayawp--commit-hooks-installed nil))
    (cl-letf (((symbol-function 'knayawp--teardown-magit-integration)
               #'ignore)
              ((symbol-function 'knayawp--side-windows)
               (lambda () nil)))
      (knayawp-layout-teardown))
    (should-not knayawp--commit-pre-state)))

;;; knayawp-test.el ends here
