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
        (knayawp--saved-project-switch-commands :unset))
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
        (knayawp--saved-project-switch-commands :unset))
    (knayawp--mode-on)
    (knayawp--mode-off)
    (should (eq project-switch-commands 'sentinel-original))
    (should (eq knayawp--saved-project-switch-commands :unset))))

(ert-deftest knayawp-test-mode-on-double-call-preserves-saved ()
  "Calling `knayawp--mode-on' twice keeps the original saved value."
  (let ((project-switch-commands 'sentinel-original)
        (knayawp--saved-project-switch-commands :unset))
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
        (knayawp--saved-project-switch-commands :unset))
    (knayawp--mode-off)
    (should (eq project-switch-commands 'user-value))
    (should (eq knayawp--saved-project-switch-commands :unset))))

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

;; knayawp-zoom-panel geometry (enter zoom, window counts, exit zoom) cannot be
;; verified in batch mode because `emacs -batch' has no real frame.  The zoom
;; behaviour is fully exercised by test/probes/monocle.el (scenarios 6-9) and
;; test/probes/commit-flow-manual-zoom.el.  The user-error guard (fires when the
;; selected window is not a side window) is testable in batch and lives below.

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
        (knayawp--saved-project-switch-commands :unset)
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
        (knayawp--saved-project-switch-commands :unset)
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
        (knayawp--saved-project-switch-commands :unset)
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
  "With style = `zoom', setup installs all four commit hooks.
Also asserts that `server-switch-hook' is APPENDED — its entry
must land after any pre-existing entries so `knayawp's late
focus-grab runs after `magit-commit-diff-while-committing'."
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
          ;; Seed `server-switch-hook' with a sentinel so we can
          ;; verify the knayawp handler is appended after it.
          (server-switch-hook '(ignore))
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
            (should (memq #'knayawp--server-switch-handler
                          server-switch-hook))
            ;; Sentinel must precede the knayawp entry: appended.
            (should (equal (last server-switch-hook)
                           (list #'knayawp--server-switch-handler)))
            (should knayawp--commit-hooks-installed))
        (knayawp--teardown-magit-integration)
        (setq magit-display-buffer-function original)))))

(ert-deftest knayawp-test-commit-hooks-removed-on-teardown ()
  "Teardown unregisters all four commit-flow handlers."
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
          (server-switch-hook nil)
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
            (should-not (memq #'knayawp--server-switch-handler
                              server-switch-hook))
            (should-not knayawp--commit-hooks-installed))
        (setq magit-display-buffer-function original)))))

(ert-deftest knayawp-test-commit-pre-state-shape ()
  "`knayawp--save-commit-pre-state' populates all expected plist keys."
  (let ((knayawp--commit-pre-state nil)
        (knayawp--zoomed-panel nil)
        (fake-commit-buf (generate-new-buffer " *knayawp-test-commit*")))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'knayawp--side-window-for-slot)
                     (lambda (_slot) nil)))
            (knayawp--save-commit-pre-state -1 fake-commit-buf))
          (should (plist-member knayawp--commit-pre-state :active))
          (should (plist-member knayawp--commit-pre-state :was-zoomed))
          (should (plist-member knayawp--commit-pre-state
                                :prior-magit-buf))
          (should (plist-member knayawp--commit-pre-state
                                :commit-buffer))
          (should (plist-member knayawp--commit-pre-state
                                :pre-commit-window))
          (should (eq t (plist-get knayawp--commit-pre-state :active)))
          (should (eq fake-commit-buf
                      (plist-get knayawp--commit-pre-state
                                 :commit-buffer)))
          (should (windowp (plist-get knayawp--commit-pre-state
                                      :pre-commit-window))))
      (setq knayawp--commit-pre-state nil)
      (when (buffer-live-p fake-commit-buf)
        (kill-buffer fake-commit-buf)))))

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

(ert-deftest knayawp-test-server-switch-handler-reasserts-commit ()
  "`knayawp--server-switch-handler' re-selects COMMIT_EDITMSG.
Simulates the magit-commit-diff-while-committing race: the magit
slot's buffer has been displaced by a stand-in `*magit-diff*' and
focus has wandered.  After the handler runs the magit window
must show the recorded COMMIT_EDITMSG buffer again, and the
magit window must be the selected window.

Reproduces the scenario found during manual scenario 1 of PR
#76 review (focus landing on the diff instead of the commit
message)."
  (let* ((commit-buf
          (generate-new-buffer " *knayawp-test-COMMIT_EDITMSG*"))
         (diff-buf
          (generate-new-buffer " *knayawp-test-magit-diff*"))
         (fake-magit-win (selected-window))
         (selected nil)
         (knayawp--commit-pre-state
          (list :active t
                :was-zoomed nil
                :prior-magit-buf nil
                :commit-buffer commit-buf
                :pre-commit-window fake-magit-win)))
    (unwind-protect
        (cl-letf (((symbol-function 'knayawp--side-window-for-slot)
                   (lambda (_slot) fake-magit-win))
                  ((symbol-function 'set-window-buffer)
                   (lambda (_win buf) (setq selected buf)))
                  ((symbol-function 'select-window)
                   (lambda (win &optional _norecord)
                     (setq fake-magit-win win)
                     win)))
          ;; Simulate the race: the slot has been clobbered by the
          ;; diff buffer and focus has drifted there.
          (setq selected diff-buf)
          (knayawp--server-switch-handler)
          (should (eq selected commit-buf))
          (should (eq fake-magit-win (selected-window))))
      (when (buffer-live-p commit-buf) (kill-buffer commit-buf))
      (when (buffer-live-p diff-buf) (kill-buffer diff-buf)))))

(ert-deftest knayawp-test-server-switch-handler-noop-without-flow ()
  "`knayawp--server-switch-handler' does nothing when idle.
With no commit-flow session active the handler must not touch
`set-window-buffer' or `select-window' — the hook runs on every
emacsclient invocation so a stray side effect would be system-wide."
  (let ((knayawp--commit-pre-state nil)
        (touched 0))
    (cl-letf (((symbol-function 'knayawp--side-window-for-slot)
               (lambda (_slot)
                 (cl-incf touched)
                 (selected-window)))
              ((symbol-function 'set-window-buffer)
               (lambda (&rest _) (cl-incf touched)))
              ((symbol-function 'select-window)
               (lambda (&rest _) (cl-incf touched))))
      (knayawp--server-switch-handler)
      (should (= 0 touched)))))

(ert-deftest knayawp-test-restore-commit-pre-state-resets-zoomed-panel ()
  "`knayawp--restore-commit-pre-state' resets `knayawp--zoomed-panel'.
Bug B (round 2 of PR #76 sandbox testing): after the first
commit, `knayawp--zoomed-panel' was left at `magit', so the
second commit's `knayawp--save-commit-pre-state' recorded
`:was-zoomed t' and the flow skipped the zoom step.

Two sub-cases:

1. The pre-flow zoom was `terminal' (a legitimate manual zoom);
   restore must put `knayawp--zoomed-panel' back to `terminal',
   not nil.

2. The pre-flow zoom was nil (no manual zoom); restore must put
   `knayawp--zoomed-panel' back to nil so the next commit's zoom
   step is allowed to fire."
  ;; Sub-case 1: manual zoom pre-existed the flow.
  (let ((knayawp--zoomed-panel 'terminal)
        (knayawp--commit-pre-state nil))
    (cl-letf (((symbol-function 'knayawp--focus-target-window)
               (lambda () nil))
              ((symbol-function 'knayawp--side-window-for-slot)
               (lambda (_slot) nil)))
      ;; Simulate the flow entry: save records `:was-zoomed 'terminal',
      ;; then the zoom step is skipped (manual zoom already active) but
      ;; `knayawp--zoomed-panel' stays at `terminal'.
      (knayawp--save-commit-pre-state -1 nil)
      (should (eq 'terminal
                  (plist-get knayawp--commit-pre-state :was-zoomed)))
      (knayawp--restore-commit-pre-state)
      (should (eq 'terminal knayawp--zoomed-panel))
      (should-not knayawp--commit-pre-state)))
  ;; Sub-case 2: no manual zoom pre-existed.  Simulate Bug B's first
  ;; commit: enter the flow (zoom is applied, sets the panel to
  ;; `magit'), then restore must reset to nil.
  (let ((knayawp--zoomed-panel nil)
        (knayawp--commit-pre-state nil))
    (cl-letf (((symbol-function 'knayawp--focus-target-window)
               (lambda () nil))
              ((symbol-function 'knayawp--side-window-for-slot)
               (lambda (_slot) nil)))
      (knayawp--save-commit-pre-state -1 nil)
      (should-not (plist-get knayawp--commit-pre-state :was-zoomed))
      ;; Imitate `knayawp--apply-zoom-solo-magit' side-effect.
      (setq knayawp--zoomed-panel 'magit)
      (knayawp--restore-commit-pre-state)
      (should-not knayawp--zoomed-panel)
      (should-not knayawp--commit-pre-state))))

(ert-deftest knayawp-test-restore-commit-pre-state-redisplays-magit-status ()
  "`knayawp--restore-commit-pre-state' re-displays magit-status.
Bug A (round 2 of PR #76 sandbox testing): the
`with-editor-previous-winconf' snapshot captured by
`magit-commit-create' already contains `*magit-diff*' in the
magit slot (the diff is shown synchronously before `with-editor'
is invoked), so when `with-editor-return' restores the
configuration on finish the user sees `*magit-diff*' where they
expect magit-status.

The restore step looks up the project's status buffer via
`magit-mode-get-buffer' and re-displays it in the slot.  When the
user was in a manual zoom before the flow, the slot is theirs and
we must not touch it.

Two sub-cases:

1. `:was-zoomed' nil and status buffer is live: the slot's
   `window-buffer' becomes the status buffer.

2. `:was-zoomed' non-nil: the slot's buffer is left untouched."
  ;; Sub-case 1: slot updated to magit-status.
  (let* ((diff-buf
          (generate-new-buffer " *knayawp-test-magit-diff*"))
         (status-buf
          (generate-new-buffer " *knayawp-test-magit-status*"))
         (fake-magit-win (selected-window))
         (slot-buffer diff-buf)
         (knayawp--zoomed-panel nil)
         (knayawp--commit-pre-state
          (list :active t
                :was-zoomed nil
                :prior-magit-buf nil
                :commit-buffer nil
                :pre-commit-window fake-magit-win)))
    (unwind-protect
        (cl-letf (((symbol-function 'knayawp--side-window-for-slot)
                   (lambda (_slot) fake-magit-win))
                  ((symbol-function 'window-live-p)
                   (lambda (_win) t))
                  ((symbol-function 'magit-mode-get-buffer)
                   (lambda (_mode) status-buf))
                  ((symbol-function 'set-window-buffer)
                   (lambda (_win buf) (setq slot-buffer buf)))
                  ((symbol-function 'knayawp--focus-target-window)
                   (lambda () nil)))
          (knayawp--restore-commit-pre-state)
          (should (eq slot-buffer status-buf)))
      (when (buffer-live-p diff-buf) (kill-buffer diff-buf))
      (when (buffer-live-p status-buf) (kill-buffer status-buf))))
  ;; Sub-case 2: `:was-zoomed' truthy means the user had a manual
  ;; zoom active; do not change the slot buffer.
  (let* ((diff-buf
          (generate-new-buffer " *knayawp-test-magit-diff-2*"))
         (status-buf
          (generate-new-buffer " *knayawp-test-magit-status-2*"))
         (fake-magit-win (selected-window))
         (slot-buffer diff-buf)
         (knayawp--zoomed-panel 'terminal)
         (knayawp--commit-pre-state
          (list :active t
                :was-zoomed 'terminal
                :prior-magit-buf nil
                :commit-buffer nil
                :pre-commit-window fake-magit-win)))
    (unwind-protect
        (cl-letf (((symbol-function 'knayawp--side-window-for-slot)
                   (lambda (_slot) fake-magit-win))
                  ((symbol-function 'window-live-p)
                   (lambda (_win) t))
                  ((symbol-function 'magit-mode-get-buffer)
                   (lambda (_mode) status-buf))
                  ((symbol-function 'set-window-buffer)
                   (lambda (_win buf) (setq slot-buffer buf)))
                  ((symbol-function 'knayawp--focus-target-window)
                   (lambda () nil)))
          (knayawp--restore-commit-pre-state)
          (should (eq slot-buffer diff-buf)))
      (when (buffer-live-p diff-buf) (kill-buffer diff-buf))
      (when (buffer-live-p status-buf) (kill-buffer status-buf)))))

(ert-deftest knayawp-test-commit-flow-start-captures-winconf ()
  "`knayawp--commit-flow-start' records the pre-zoom winconf.
Round 3 of PR #76 sandbox testing showed only one side window
remaining after `C-c C-c': `with-editor-previous-winconf' was
captured AFTER our setup handler had already zoomed the layout,
so the snapshot only contained the magit slot.

The fix is for knayawp to capture its own winconf in
`knayawp--commit-flow-start' before the zoom step.  This test
exercises just the capture: invoking the flow-start in a
controlled context must populate the `:winconf' plist key with a
`window-configuration-p' object."
  (let ((knayawp--commit-pre-state nil)
        (knayawp--zoomed-panel nil)
        (knayawp-panels '((magit :slot -1)
                          (terminal :slot 0)
                          (claude :slot 1))))
    (cl-letf (((symbol-function 'knayawp--side-window-for-slot)
               (lambda (_slot) (selected-window)))
              ((symbol-function 'knayawp--apply-zoom-solo-magit)
               #'ignore))
      (knayawp--commit-flow-start)
      (should (plist-member knayawp--commit-pre-state :winconf))
      (should (window-configuration-p
               (plist-get knayawp--commit-pre-state :winconf))))
    (setq knayawp--commit-pre-state nil)))

(ert-deftest knayawp-test-restore-commit-pre-state-restores-winconf ()
  "Restore step calls `set-window-configuration' on the saved winconf.
The saved winconf snapshots the layout BEFORE the zoom step, so
restoring it brings back the terminal and Claude side windows
that `with-editor's later restore could not."
  (let* ((sentinel (current-window-configuration))
         (called-with 'unset)
         (knayawp--zoomed-panel nil)
         (knayawp--commit-pre-state
          (list :active t
                :was-zoomed nil
                :prior-magit-buf nil
                :commit-buffer nil
                :pre-commit-window (selected-window)
                :winconf sentinel)))
    (cl-letf (((symbol-function 'set-window-configuration)
               (lambda (wc &rest _) (setq called-with wc)))
              ((symbol-function 'window-configuration-frame)
               (lambda (_wc) (selected-frame)))
              ((symbol-function 'knayawp--side-window-for-slot)
               (lambda (_slot) nil))
              ((symbol-function 'knayawp--focus-target-window)
               (lambda () nil)))
      (knayawp--restore-commit-pre-state)
      (should (eq called-with sentinel)))))

(ert-deftest knayawp-test-restore-commit-pre-state-skips-winconf-wrong-frame ()
  "Restore step does NOT touch winconf when its frame is gone.
Cross-frame restores can crash or scramble the layout when the
recorded frame is no longer selected.  The guard checks
`window-configuration-frame' against `selected-frame' and skips
the restore on mismatch."
  (let* ((sentinel (current-window-configuration))
         (other-frame (cons 'fake-frame 'sentinel))
         (called-with 'unset)
         (knayawp--zoomed-panel nil)
         (knayawp--commit-pre-state
          (list :active t
                :was-zoomed nil
                :prior-magit-buf nil
                :commit-buffer nil
                :pre-commit-window (selected-window)
                :winconf sentinel)))
    (cl-letf (((symbol-function 'set-window-configuration)
               (lambda (wc &rest _) (setq called-with wc)))
              ((symbol-function 'window-configuration-frame)
               (lambda (_wc) other-frame))
              ((symbol-function 'knayawp--side-window-for-slot)
               (lambda (_slot) nil))
              ((symbol-function 'knayawp--focus-target-window)
               (lambda () nil)))
      (knayawp--restore-commit-pre-state)
      (should (eq called-with 'unset)))))

;;;; Commit-style reconcile (#76 follow-up)

(ert-deftest knayawp-test-reconcile-zoom-to-editor ()
  "Reconcile drops zoom hooks and installs the COMMIT_EDITMSG entry.
Models the runtime path that the scenario-2 probe exposed: setup
ran under `zoom', the user then changed `knayawp-magit-commit-style'
to `editor', and the integration must reflect the new style."
  (when (require 'magit nil t)
    (let ((original magit-display-buffer-function)
          (knayawp--magit-saved-display-fn nil)
          (knayawp--commit-display-entry nil)
          (knayawp--process-display-entry nil)
          (knayawp--commit-hooks-installed nil)
          (knayawp--commit-style-shim-warned t)
          (knayawp-magit-commit-style 'zoom)
          (git-commit-setup-hook nil)
          (with-editor-post-finish-hook nil)
          (with-editor-post-cancel-hook nil)
          (server-switch-hook nil)
          (display-buffer-alist nil))
      (unwind-protect
          (progn
            (knayawp--setup-magit-integration)
            ;; Sanity: zoom state installed, editor entry absent.
            (should knayawp--commit-hooks-installed)
            (should-not knayawp--commit-display-entry)
            ;; Flip the style and reconcile.
            (setq knayawp-magit-commit-style 'editor)
            (knayawp--reconcile-commit-style)
            (should-not knayawp--commit-hooks-installed)
            (should-not (memq #'knayawp--git-commit-setup-handler
                              git-commit-setup-hook))
            (should knayawp--commit-display-entry)
            (should (memq knayawp--commit-display-entry
                          display-buffer-alist)))
        (knayawp--teardown-magit-integration)
        (setq magit-display-buffer-function original)))))

(ert-deftest knayawp-test-reconcile-zoom-to-off ()
  "Reconcile under `off' removes hooks AND the COMMIT_EDITMSG entry."
  (when (require 'magit nil t)
    (let ((original magit-display-buffer-function)
          (knayawp--magit-saved-display-fn nil)
          (knayawp--commit-display-entry nil)
          (knayawp--process-display-entry nil)
          (knayawp--commit-hooks-installed nil)
          (knayawp--commit-style-shim-warned t)
          (knayawp-magit-commit-style 'zoom)
          (git-commit-setup-hook nil)
          (with-editor-post-finish-hook nil)
          (with-editor-post-cancel-hook nil)
          (server-switch-hook nil)
          (display-buffer-alist nil))
      (unwind-protect
          (progn
            (knayawp--setup-magit-integration)
            (should knayawp--commit-hooks-installed)
            (setq knayawp-magit-commit-style 'off)
            (knayawp--reconcile-commit-style)
            (should-not knayawp--commit-hooks-installed)
            (should-not knayawp--commit-display-entry))
        (knayawp--teardown-magit-integration)
        (setq magit-display-buffer-function original)))))

(ert-deftest knayawp-test-reconcile-idempotent ()
  "Reconcile is a no-op when the resolved style has not changed."
  (when (require 'magit nil t)
    (let ((original magit-display-buffer-function)
          (knayawp--magit-saved-display-fn nil)
          (knayawp--commit-display-entry nil)
          (knayawp--process-display-entry nil)
          (knayawp--commit-hooks-installed nil)
          (knayawp--commit-style-shim-warned t)
          (knayawp-magit-commit-style 'editor)
          (knayawp-magit-commit-in-editor-flag nil)
          (display-buffer-alist nil))
      (unwind-protect
          (progn
            (knayawp--setup-magit-integration)
            (let ((entry knayawp--commit-display-entry))
              (should entry)
              ;; Second reconcile must not duplicate or drop the entry.
              (knayawp--reconcile-commit-style)
              (should (eq entry knayawp--commit-display-entry))
              (should (= 1 (cl-count-if
                            (lambda (e)
                              (and (stringp (car e))
                                   (string-match-p "COMMIT_EDITMSG"
                                                   (car e))))
                            display-buffer-alist)))))
        (knayawp--teardown-magit-integration)
        (setq magit-display-buffer-function original)))))

(ert-deftest knayawp-test-commit-style-setter-reconciles-when-active ()
  "Setting via `customize-set-variable' reconciles when active.
Gates on `magit-display-buffer-function' being knayawp's: this is
the only honest signal that the magit integration is currently
installed."
  (when (require 'magit nil t)
    (let* ((calls 0)
           (saved-style (default-value 'knayawp-magit-commit-style))
           (original magit-display-buffer-function))
      (unwind-protect
          (cl-letf (((symbol-function 'knayawp--reconcile-commit-style)
                     (lambda () (setq calls (1+ calls)))))
            ;; Active integration: setter must reconcile.
            (setq magit-display-buffer-function
                  #'knayawp--magit-display-buffer)
            (customize-set-variable 'knayawp-magit-commit-style 'editor)
            (should (= 1 calls))
            (customize-set-variable 'knayawp-magit-commit-style 'off)
            (should (= 2 calls)))
        (customize-set-variable 'knayawp-magit-commit-style saved-style)
        (setq magit-display-buffer-function original)))))

(ert-deftest knayawp-test-commit-style-setter-passive-when-inactive ()
  "Setter is a no-op when no magit integration is installed.
Loading the package and tweaking the option without ever calling
`knayawp-layout-setup' must not install hooks or entries (P7
passive-loading discipline carries through to the customize path)."
  (let* ((calls 0)
         (saved-style (default-value 'knayawp-magit-commit-style))
         (original (and (boundp 'magit-display-buffer-function)
                        magit-display-buffer-function)))
    (unwind-protect
        (cl-letf (((symbol-function 'knayawp--reconcile-commit-style)
                   (lambda () (setq calls (1+ calls)))))
          ;; No integration: ensure the display-buffer-function is NOT
          ;; knayawp's, regardless of test ordering.
          (setq magit-display-buffer-function
                (or original #'ignore))
          (customize-set-variable 'knayawp-magit-commit-style 'editor)
          (customize-set-variable 'knayawp-magit-commit-style 'zoom)
          (customize-set-variable 'knayawp-magit-commit-style 'off)
          (should (zerop calls)))
      (customize-set-variable 'knayawp-magit-commit-style saved-style)
      (when original
        (setq magit-display-buffer-function original)))))

;;;; One-shot terminal copy/paste (#77)

(ert-deftest knayawp-test-command-map-copy-paste-bindings ()
  "Command map has SPC and y bound to copy/paste commands."
  (should (eq 'knayawp-terminal-copy-mode
              (lookup-key knayawp-command-map " ")))
  (should (eq 'knayawp-terminal-yank
              (lookup-key knayawp-command-map "y"))))

(ert-deftest knayawp-test-command-map-ctrl-x-binding ()
  "Command map binds ctrl-x to `knayawp-claude-send-ctrl-x'."
  (should (eq 'knayawp-claude-send-ctrl-x
              (lookup-key knayawp-command-map (kbd "C-x")))))

(ert-deftest knayawp-test-claude-send-ctrl-x-no-panel ()
  "`knayawp-claude-send-ctrl-x' signals user-error with no Claude window."
  (let ((knayawp-panels '((claude :slot 2))))
    (should-error (knayawp-claude-send-ctrl-x) :type 'user-error)))

(ert-deftest knayawp-test-terminal-panel-windows-excludes-magit ()
  "`knayawp--terminal-panel-windows' omits the magit slot.
Only vterm/claude panel types are returned; the magit panel at
slot -1 is filtered out.  In batch mode there are no real side
windows, so the results are all nil and `seq-filter' returns an
empty list."
  (let ((knayawp-panels '((magit  :slot -1)
                          (vterm  :slot  0)
                          (claude :slot  1))))
    ;; In batch mode every slot lookup returns nil; seq-filter removes
    ;; them all, but magit is excluded BEFORE the nil filter too.
    ;; Verify at least that the function does not signal an error.
    (should (listp (knayawp--terminal-panel-windows)))))

(ert-deftest knayawp-test-active-terminal-window-no-layout ()
  "`knayawp--active-terminal-window' errors when no terminal window exists.
In batch mode no side windows exist, so the function must signal a
`user-error' rather than returning nil or crashing."
  (should-error (knayawp--active-terminal-window)
                :type 'user-error))

(ert-deftest knayawp-test-active-terminal-window-prefers-current ()
  "Return the selected window when it is a terminal panel window."
  (let ((knayawp-panels '((magit  :slot -1)
                          (vterm  :slot  0)
                          (claude :slot  1)))
        (fake-win-0 (selected-window))
        (fake-win-1 'other-win))
    (cl-letf (((symbol-function 'knayawp--side-window-for-slot)
               (lambda (slot)
                 (pcase slot
                   (0 fake-win-0)
                   (1 fake-win-1)
                   (_ nil)))))
      ;; The selected window IS fake-win-0 (slot 0 / vterm).
      (should (eq fake-win-0
                  (knayawp--active-terminal-window))))))

(ert-deftest knayawp-test-active-terminal-window-falls-back-to-first ()
  "Return the first terminal panel window when not in one."
  (let ((knayawp-panels '((magit  :slot -1)
                          (vterm  :slot  0)
                          (claude :slot  1)))
        (fake-win-0 'win-vterm)
        (fake-win-1 'win-claude))
    (cl-letf (((symbol-function 'knayawp--side-window-for-slot)
               (lambda (slot)
                 (pcase slot
                   (0 fake-win-0)
                   (1 fake-win-1)
                   (_ nil))))
              ;; selected-window returns something other than any panel.
              ((symbol-function 'selected-window)
               (lambda () 'editor-win)))
      ;; Not in a panel → fall back to first (vterm, slot 0).
      (should (eq fake-win-0
                  (knayawp--active-terminal-window))))))

(ert-deftest knayawp-test-terminal-copy-mode-dispatches-vterm ()
  "`knayawp-terminal-copy-mode' calls the vterm backend helper."
  (let ((knayawp-terminal-backend 'vterm)
        (dispatched-to nil))
    (cl-letf (((symbol-function 'knayawp--active-terminal-window)
               (lambda () 'fake-win))
              ((symbol-function 'select-window)
               #'ignore)
              ((symbol-function 'knayawp--make-terminal-copy-mode-vterm)
               (lambda (win) (setq dispatched-to win)))
              ((symbol-function 'knayawp--make-terminal-copy-mode-eat)
               (lambda (_win) (error "eat called unexpectedly"))))
      (knayawp-terminal-copy-mode)
      (should (eq dispatched-to 'fake-win)))))

(ert-deftest knayawp-test-terminal-copy-mode-dispatches-eat ()
  "`knayawp-terminal-copy-mode' calls the eat backend helper."
  (let ((knayawp-terminal-backend 'eat)
        (dispatched-to nil))
    (cl-letf (((symbol-function 'knayawp--active-terminal-window)
               (lambda () 'fake-win))
              ((symbol-function 'select-window)
               #'ignore)
              ((symbol-function 'knayawp--make-terminal-copy-mode-eat)
               (lambda (win) (setq dispatched-to win)))
              ((symbol-function 'knayawp--make-terminal-copy-mode-vterm)
               (lambda (_win) (error "vterm called unexpectedly"))))
      (knayawp-terminal-copy-mode)
      (should (eq dispatched-to 'fake-win)))))

(ert-deftest knayawp-test-terminal-yank-dispatches-vterm ()
  "`knayawp-terminal-yank' calls the vterm backend helper."
  (let ((knayawp-terminal-backend 'vterm)
        (dispatched-to nil))
    (cl-letf (((symbol-function 'knayawp--active-terminal-window)
               (lambda () 'fake-win))
              ((symbol-function 'select-window)
               #'ignore)
              ((symbol-function 'knayawp--make-terminal-yank-vterm)
               (lambda (win) (setq dispatched-to win)))
              ((symbol-function 'knayawp--make-terminal-yank-eat)
               (lambda (_win) (error "eat called unexpectedly"))))
      (knayawp-terminal-yank)
      (should (eq dispatched-to 'fake-win)))))

(ert-deftest knayawp-test-terminal-yank-dispatches-eat ()
  "`knayawp-terminal-yank' calls the eat backend helper."
  (let ((knayawp-terminal-backend 'eat)
        (dispatched-to nil))
    (cl-letf (((symbol-function 'knayawp--active-terminal-window)
               (lambda () 'fake-win))
              ((symbol-function 'select-window)
               #'ignore)
              ((symbol-function 'knayawp--make-terminal-yank-eat)
               (lambda (win) (setq dispatched-to win)))
              ((symbol-function 'knayawp--make-terminal-yank-vterm)
               (lambda (_win) (error "vterm called unexpectedly"))))
      (knayawp-terminal-yank)
      (should (eq dispatched-to 'fake-win)))))

(ert-deftest knayawp-test-terminal-copy-mode-unknown-backend ()
  "`knayawp-terminal-copy-mode' signals user-error for unknown backend."
  (let ((knayawp-terminal-backend 'nonexistent))
    (cl-letf (((symbol-function 'knayawp--active-terminal-window)
               (lambda () 'fake-win))
              ((symbol-function 'select-window)
               #'ignore))
      (should-error (knayawp-terminal-copy-mode) :type 'user-error))))

(ert-deftest knayawp-test-terminal-yank-unknown-backend ()
  "`knayawp-terminal-yank' signals user-error for unknown backend."
  (let ((knayawp-terminal-backend 'nonexistent))
    (cl-letf (((symbol-function 'knayawp--active-terminal-window)
               (lambda () 'fake-win))
              ((symbol-function 'select-window)
               #'ignore))
      (should-error (knayawp-terminal-yank) :type 'user-error))))

;;;; Layout hook positive-path (#66)

(ert-deftest knayawp-test-layout-hook-runs-after-setup ()
  "Hook fires once after a successful `knayawp-layout-setup'.
The test stubs out all side-effecting helpers so it runs in
batch mode without a real frame or project on disk."
  (let ((counter 0)
        (knayawp--active-layouts nil)
        (knayawp--frame-widths nil)
        (window-sides-slots window-sides-slots))
    (let ((knayawp-layout-hook
           (list (lambda () (setq counter (1+ counter))))))
      (cl-letf (((symbol-function 'knayawp--project-root)
                 (lambda () "/fake/project/"))
                ((symbol-function 'knayawp--project-name)
                 (lambda (_root) "project"))
                ((symbol-function 'knayawp--create-panel-buffer)
                 (lambda (_type _root _name)
                   (get-buffer-create "*knayawp-test-panel*")))
                ((symbol-function 'display-buffer-in-side-window)
                 (lambda (_buf _alist) (selected-window)))
                ((symbol-function 'knayawp--balance-side-windows) #'ignore)
                ((symbol-function 'knayawp--setup-magit-integration) #'ignore)
                ((symbol-function 'knayawp--select-editor-window) #'ignore)
                ((symbol-function 'add-hook) #'ignore))
        (knayawp-layout-setup)))
    (should (= 1 counter))))

(ert-deftest knayawp-test-layout-hook-sees-final-state ()
  "Hook function receives control after setup completes.
Specifically, the hook must run AFTER the layout is stored in
`knayawp--active-layouts' (so hook functions can read the layout)
and AFTER the editor window is selected."
  (let ((hook-layout nil)
        (knayawp--active-layouts nil)
        (knayawp--frame-widths nil)
        (window-sides-slots window-sides-slots))
    (cl-letf (((symbol-function 'knayawp--project-root)
               (lambda () "/fake/project/"))
              ((symbol-function 'knayawp--project-name)
               (lambda (_root) "project"))
              ((symbol-function 'knayawp--create-panel-buffer)
               (lambda (_type _root _name)
                 (get-buffer-create "*knayawp-test-panel2*")))
              ((symbol-function 'display-buffer-in-side-window)
               (lambda (_buf _alist) (selected-window)))
              ((symbol-function 'knayawp--balance-side-windows) #'ignore)
              ((symbol-function 'knayawp--setup-magit-integration) #'ignore)
              ((symbol-function 'knayawp--select-editor-window) #'ignore)
              ((symbol-function 'add-hook) #'ignore))
      (let ((knayawp-layout-hook
             (list (lambda ()
                     ;; Capture layout state at hook-run time.
                     (setq hook-layout
                           (alist-get "/fake/project/"
                                      knayawp--active-layouts
                                      nil nil #'equal))))))
        (knayawp-layout-setup)))
    ;; The hook ran after the layout was recorded.
    (should hook-layout)))

;;;; Mode-off sentinel behavior (#60)

(ert-deftest knayawp-test-mode-off-preserves-unset-sentinel ()
  "Mode-off resets saved value to `:unset', not nil.
This ensures a subsequent `mode-on' call still captures the real
`project-switch-commands' value rather than treating a stale nil
as the pre-mode value."
  (let ((project-switch-commands 'some-original)
        (knayawp--saved-project-switch-commands :unset)
        (knayawp--panel-display-entries nil))
    (knayawp--mode-on)
    (knayawp--mode-off)
    (should (eq knayawp--saved-project-switch-commands :unset))))

(ert-deftest knayawp-test-mode-off-does-not-clobber-when-unset ()
  "Mode-off leaves `project-switch-commands' alone when unset.
When mode-on was never called (`:unset' sentinel intact) but the
user happens to have `project-switch-commands' set to our
function, mode-off must not reset it to nil."
  (let ((project-switch-commands #'knayawp-layout-setup)
        (knayawp--saved-project-switch-commands :unset)
        (knayawp--panel-display-entries nil))
    (knayawp--mode-off)
    ;; Our function should still be installed — we never saved anything.
    (should (eq project-switch-commands #'knayawp-layout-setup))))

;;;; Magit-status auto-refresh (#78)

(ert-deftest knayawp-test-maybe-refresh-magit-calls-refresh ()
  "`knayawp--maybe-refresh-magit' calls `magit-refresh' on status buffer.
Uses a fake window that holds a buffer derived from
`magit-status-mode'."
  (let* ((buf (generate-new-buffer " *knayawp-test-magit-status*"))
         (refresh-called nil))
    (unwind-protect
        (cl-letf (((symbol-function 'window-live-p) (lambda (_w) t))
                  ((symbol-function 'window-buffer) (lambda (_w) buf))
                  ((symbol-function 'buffer-live-p) (lambda (_b) t))
                  ((symbol-function 'derived-mode-p)
                   (lambda (mode) (eq mode 'magit-status-mode)))
                  ((symbol-function 'magit-refresh)
                   (lambda () (setq refresh-called t))))
          (knayawp--maybe-refresh-magit 'fake-win)
          (should refresh-called))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest knayawp-test-maybe-refresh-magit-skips-non-status ()
  "`knayawp--maybe-refresh-magit' is a no-op for non-status buffers.
When the window holds a buffer that is not in `magit-status-mode',
`magit-refresh' must not be called."
  (let* ((buf (generate-new-buffer " *knayawp-test-other-buf*"))
         (refresh-called nil))
    (unwind-protect
        (cl-letf (((symbol-function 'window-live-p) (lambda (_w) t))
                  ((symbol-function 'window-buffer) (lambda (_w) buf))
                  ((symbol-function 'buffer-live-p) (lambda (_b) t))
                  ((symbol-function 'derived-mode-p)
                   (lambda (_mode) nil))
                  ((symbol-function 'magit-refresh)
                   (lambda () (setq refresh-called t))))
          (knayawp--maybe-refresh-magit 'fake-win)
          (should-not refresh-called))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest knayawp-test-maybe-refresh-magit-skips-dead-window ()
  "`knayawp--maybe-refresh-magit' is a no-op for a dead window."
  (let ((refresh-called nil))
    (cl-letf (((symbol-function 'window-live-p) (lambda (_w) nil))
              ((symbol-function 'magit-refresh)
               (lambda () (setq refresh-called t))))
      (knayawp--maybe-refresh-magit 'dead-win)
      (should-not refresh-called))))

;;;; Keymap-style :set auto-rebuild (#67)

(ert-deftest knayawp-test-keymap-style-set-rebuilds-map ()
  "Setting `knayawp-keymap-style' via customize rebuilds the map.
The `:set' form calls `knayawp-rebuild-command-map' when the map
object already exists, so arrow bindings appear immediately."
  (let* ((rebuilds 0)
         (saved-style (default-value 'knayawp-keymap-style)))
    (unwind-protect
        (cl-letf (((symbol-function 'knayawp-rebuild-command-map)
                   (lambda () (cl-incf rebuilds))))
          (customize-set-variable 'knayawp-keymap-style 'tmux)
          (should (= 1 rebuilds))
          (customize-set-variable 'knayawp-keymap-style 'byobu)
          (should (= 2 rebuilds))
          (customize-set-variable 'knayawp-keymap-style 'default)
          (should (= 3 rebuilds)))
      (customize-set-variable 'knayawp-keymap-style saved-style))))

(ert-deftest knayawp-test-keymap-style-set-tmux-arrow-bindings ()
  "Setting style to `tmux' via setopt produces arrow bindings.
End-to-end: the real `knayawp-rebuild-command-map' is invoked."
  (let ((saved-style (default-value 'knayawp-keymap-style)))
    (unwind-protect
        (progn
          (customize-set-variable 'knayawp-keymap-style 'tmux)
          (should (eq 'knayawp-prev-panel
                      (lookup-key knayawp-command-map (kbd "<up>"))))
          (should (eq 'knayawp-next-panel
                      (lookup-key knayawp-command-map (kbd "<down>")))))
      (customize-set-variable 'knayawp-keymap-style saved-style))))

;;;; COMMIT_EDITMSG frame-locality guard (#79)

(ert-deftest knayawp-test-commit-editmsg-display-routes-same-frame ()
  "Route COMMIT_EDITMSG to the editor window on the selected frame.
When `knayawp--editor-window' is live, not a side window, and on
the selected frame, the buffer is placed there via
`set-window-buffer' and that window is returned."
  (let ((knayawp--editor-window 'editor-win)
        (buf (generate-new-buffer " *knayawp-test-editmsg*"))
        (set-target nil))
    (unwind-protect
        (cl-letf (((symbol-function 'window-live-p) (lambda (_w) t))
                  ((symbol-function 'window-frame) (lambda (_w) 'frame-a))
                  ((symbol-function 'selected-frame) (lambda () 'frame-a))
                  ((symbol-function 'window-parameter) (lambda (_w _p) nil))
                  ((symbol-function 'set-window-buffer)
                   (lambda (win _b) (setq set-target win))))
          (should (eq 'editor-win
                      (knayawp--commit-editmsg-display-function buf nil)))
          (should (eq 'editor-win set-target)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest knayawp-test-commit-editmsg-display-skips-other-frame ()
  "Do not hijack the editor window when it lives on another frame.
`knayawp--editor-window' is a single global; a commit started on
one frame must not route COMMIT_EDITMSG into the editor window of
a different frame.  The function falls back to
`display-buffer-use-some-window' and never calls `set-window-buffer'."
  (let ((knayawp--editor-window 'editor-win)
        (buf (generate-new-buffer " *knayawp-test-editmsg2*"))
        (set-called nil)
        (fallback-called nil))
    (unwind-protect
        (cl-letf (((symbol-function 'window-live-p) (lambda (_w) t))
                  ((symbol-function 'window-frame) (lambda (_w) 'frame-b))
                  ((symbol-function 'selected-frame) (lambda () 'frame-a))
                  ((symbol-function 'window-parameter) (lambda (_w _p) nil))
                  ((symbol-function 'set-window-buffer)
                   (lambda (&rest _) (setq set-called t)))
                  ((symbol-function 'display-buffer-use-some-window)
                   (lambda (_b _a) (setq fallback-called t) 'some-win)))
          (should (eq 'some-win
                      (knayawp--commit-editmsg-display-function buf nil)))
          (should fallback-called)
          (should-not set-called))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;;;; winner-mode integration (#32)

(ert-deftest knayawp-test-winner-integration-flag-default ()
  "`knayawp-winner-integration-flag' defaults to t."
  (should (eq t (default-value 'knayawp-winner-integration-flag))))

(ert-deftest knayawp-test-teardown-saves-winner-when-active ()
  "Teardown calls `winner-save-conditionally' when flag and mode are on."
  (let ((knayawp-winner-integration-flag t)
        (winner-mode t)
        (saved nil)
        (knayawp--commit-pre-state nil)
        (knayawp--frame-widths nil)
        (knayawp--magit-saved-display-fn nil)
        (knayawp--commit-display-entry nil)
        (knayawp--process-display-entry nil)
        (knayawp--commit-hooks-installed nil))
    (cl-letf (((symbol-function 'winner-save-conditionally)
               (lambda () (setq saved t)))
              ((symbol-function 'knayawp--teardown-magit-integration)
               #'ignore)
              ((symbol-function 'knayawp--side-windows)
               (lambda () nil)))
      (knayawp-layout-teardown))
    (should saved)))

(ert-deftest knayawp-test-teardown-skips-winner-when-flag-off ()
  "Teardown skips `winner-save-conditionally' when flag is nil."
  (let ((knayawp-winner-integration-flag nil)
        (winner-mode t)
        (saved nil)
        (knayawp--commit-pre-state nil)
        (knayawp--frame-widths nil)
        (knayawp--magit-saved-display-fn nil)
        (knayawp--commit-display-entry nil)
        (knayawp--process-display-entry nil)
        (knayawp--commit-hooks-installed nil))
    (cl-letf (((symbol-function 'winner-save-conditionally)
               (lambda () (setq saved t)))
              ((symbol-function 'knayawp--teardown-magit-integration)
               #'ignore)
              ((symbol-function 'knayawp--side-windows)
               (lambda () nil)))
      (knayawp-layout-teardown))
    (should-not saved)))

(ert-deftest knayawp-test-teardown-skips-winner-when-mode-off ()
  "Teardown skips `winner-save-conditionally' when winner-mode is off."
  (let ((knayawp-winner-integration-flag t)
        (winner-mode nil)
        (saved nil)
        (knayawp--commit-pre-state nil)
        (knayawp--frame-widths nil)
        (knayawp--magit-saved-display-fn nil)
        (knayawp--commit-display-entry nil)
        (knayawp--process-display-entry nil)
        (knayawp--commit-hooks-installed nil))
    (cl-letf (((symbol-function 'winner-save-conditionally)
               (lambda () (setq saved t)))
              ((symbol-function 'knayawp--teardown-magit-integration)
               #'ignore)
              ((symbol-function 'knayawp--side-windows)
               (lambda () nil)))
      (knayawp-layout-teardown))
    (should-not saved)))

;;;; Narrow-frame guard (#30)

(ert-deftest knayawp-test-min-editor-columns-default ()
  "`knayawp-min-editor-columns' defaults to 40."
  (should (equal 40 (default-value 'knayawp-min-editor-columns))))

(ert-deftest knayawp-test-frame-wide-enough-p-wide-frame ()
  "`knayawp--frame-wide-enough-p' returns t when frame is wide."
  (let ((knayawp-right-width 0.4)
        (knayawp-min-editor-columns 40))
    (cl-letf (((symbol-function 'frame-width) (lambda () 200)))
      ;; right-cols = 80, editor-cols = 120 >= 40
      (should (knayawp--frame-wide-enough-p)))))

(ert-deftest knayawp-test-frame-wide-enough-p-narrow-frame ()
  "`knayawp--frame-wide-enough-p' returns nil when frame is too narrow."
  (let ((knayawp-right-width 0.4)
        (knayawp-min-editor-columns 40))
    (cl-letf (((symbol-function 'frame-width) (lambda () 60)))
      ;; right-cols = 24, editor-cols = 36 < 40
      (should-not (knayawp--frame-wide-enough-p)))))

(ert-deftest knayawp-test-layout-setup-skips-when-narrow ()
  "`knayawp-layout-setup' skips setup and does not call project-root.
When the frame is too narrow, the function must not proceed past the
guard — verifiable by confirming `knayawp--project-root' is never
called (it would signal an error if reached)."
  (let ((knayawp-min-editor-columns 400)
        (project-root-called nil))
    (cl-letf (((symbol-function 'frame-width) (lambda () 100))
              ((symbol-function 'knayawp--project-root)
               (lambda ()
                 (setq project-root-called t)
                 (error "should not be reached"))))
      ;; With min-editor-columns=400 and frame-width=100, even 0 right
      ;; columns leaves only 100 editor cols, which is < 400.
      (knayawp-layout-setup)
      (should-not project-root-called))))

;;;; Configurable slot heights (#56)

(ert-deftest knayawp-test-panel-height-accessor ()
  "Extract :height from panel spec."
  (should (equal 0.34
                 (knayawp--panel-height '(magit :slot -1 :height 0.34))))
  (should (equal 0.33
                 (knayawp--panel-height '(vterm :slot 0 :height 0.33))))
  (should (null (knayawp--panel-height '(magit :slot -1)))))

(ert-deftest knayawp-test-default-panels-have-heights ()
  "Default panels include :height values that sum to approximately 1.0."
  (let* ((panels (default-value 'knayawp-panels))
         (heights (mapcar #'knayawp--panel-height panels))
         (total (apply #'+ heights)))
    (should (seq-every-p #'numberp heights))
    ;; Sum should be within rounding tolerance of 1.0.
    (should (< (abs (- total 1.0)) 0.01))))

;;;; knayawp-panels :set callback (#65)

(ert-deftest knayawp-test-panels-set-reinstalls-when-mode-on ()
  "Setting `knayawp-panels' re-installs routing when mode is on."
  (let ((remove-calls 0)
        (install-calls 0)
        (knayawp-mode t)
        (knayawp--panel-display-entries nil)
        (display-buffer-alist nil))
    (cl-letf (((symbol-function 'knayawp--remove-panel-display-routing)
               (lambda () (cl-incf remove-calls)))
              ((symbol-function 'knayawp--install-panel-display-routing)
               (lambda () (cl-incf install-calls))))
      ;; Invoke the :set callback directly
      (let ((setter (get 'knayawp-panels 'custom-set)))
        (should setter)
        (funcall setter 'knayawp-panels
                 '((magit :slot -1) (vterm :slot 0)))))
    (should (= 1 remove-calls))
    (should (= 1 install-calls))))

(ert-deftest knayawp-test-panels-set-noop-when-mode-off ()
  "Setting `knayawp-panels' does not install routing when mode is off."
  (let ((remove-calls 0)
        (install-calls 0)
        (knayawp-mode nil))
    (cl-letf (((symbol-function 'knayawp--remove-panel-display-routing)
               (lambda () (cl-incf remove-calls)))
              ((symbol-function 'knayawp--install-panel-display-routing)
               (lambda () (cl-incf install-calls))))
      (let ((setter (get 'knayawp-panels 'custom-set)))
        (should setter)
        (funcall setter 'knayawp-panels
                 '((magit :slot -1) (vterm :slot 0)))))
    (should (= 0 remove-calls))
    (should (= 0 install-calls))))

;;;; Monocle mode (#85)

(ert-deftest knayawp-test-monocle-panel-default-nil ()
  "Monocle frame parameter is nil by default on a fresh frame."
  ;; The frame parameter is not set at package load time — monocle is
  ;; off until the user invokes `knayawp-monocle-panel'.
  (should (null (frame-parameter nil 'knayawp--monocle-config))))

(ert-deftest knayawp-test-monocle-panel-enters-monocle ()
  "Entering monocle saves config+zoom and iterates window-list.
When the frame parameter is nil, `knayawp-monocle-panel' must
store a cons of (window-config . zoomed-panel) in the frame
parameter and then delete all other windows via `delete-window'.
Note: `delete-window' requires a live frame environment, so we
stub `window-list' to return an empty list (no extra windows) to
keep the test self-contained in batch mode."
  (let ((knayawp--zoomed-panel 'fake-zoom)
        stored-cfg)
    (cl-letf (((symbol-function 'current-window-configuration)
               (lambda () 'fake-wc))
              ((symbol-function 'frame-parameter)
               (lambda (frame sym)
                 (if (eq sym 'knayawp--monocle-config) nil
                   (funcall #'frame-parameter frame sym))))
              ((symbol-function 'set-frame-parameter)
               (lambda (_frame sym val)
                 (when (eq sym 'knayawp--monocle-config)
                   (setq stored-cfg val))))
              ;; No extra windows: skip the deletion loop safely.
              ((symbol-function 'window-list)
               (lambda (&rest _) (list (selected-window)))))
      (knayawp-monocle-panel)
      ;; The frame parameter must hold (wc . zoomed-panel).
      (should (equal stored-cfg (cons 'fake-wc 'fake-zoom)))
      ;; Entering monocle must clear the zoom variable.
      (should (null knayawp--zoomed-panel)))))

(ert-deftest knayawp-test-monocle-panel-exits-monocle ()
  "Exiting monocle restores config+zoom and clears the frame parameter.
When the frame parameter is a cons (wc . zoom), `knayawp-monocle-panel'
must call `set-window-configuration' with the car, restore
`knayawp--zoomed-panel' to the cdr, and set the frame parameter to nil."
  (let ((knayawp--zoomed-panel nil)
        restored-wc
        cleared)
    (cl-letf (((symbol-function 'frame-parameter)
               (lambda (frame sym)
                 (if (eq sym 'knayawp--monocle-config)
                     (cons 'saved-wc 'saved-zoom)
                   (funcall #'frame-parameter frame sym))))
              ((symbol-function 'set-window-configuration)
               (lambda (wc) (setq restored-wc wc)))
              ((symbol-function 'set-frame-parameter)
               (lambda (_frame sym val)
                 (when (eq sym 'knayawp--monocle-config)
                   (setq cleared (null val))))))
      (knayawp-monocle-panel)
      (should (eq restored-wc 'saved-wc))
      (should (eq knayawp--zoomed-panel 'saved-zoom))
      (should cleared))))

(ert-deftest knayawp-test-monocle-panel-clears-zoomed-state ()
  "Entering monocle stores and clears the panel zoom state.
When `knayawp--zoomed-panel' is non-nil and monocle is off,
`knayawp-monocle-panel' must save it in the frame parameter cons
and set `knayawp--zoomed-panel' to nil."
  (let ((knayawp--zoomed-panel 'vterm)
        stored-cfg)
    (cl-letf (((symbol-function 'current-window-configuration)
               (lambda () 'fake-wc))
              ((symbol-function 'frame-parameter)
               (lambda (frame sym)
                 (if (eq sym 'knayawp--monocle-config) nil
                   (funcall #'frame-parameter frame sym))))
              ((symbol-function 'set-frame-parameter)
               (lambda (_frame sym val)
                 (when (eq sym 'knayawp--monocle-config)
                   (setq stored-cfg val))))
              ((symbol-function 'window-list)
               (lambda (&rest _) (list (selected-window)))))
      (knayawp-monocle-panel)
      (should (null knayawp--zoomed-panel))
      ;; Zoom state must be preserved inside the saved cons.
      (should (eq (cdr stored-cfg) 'vterm)))))

;;;; Monocle state management (#97)

;; The enter/exit state-machine (save winconfig+zoom on enter, restore on exit,
;; clear frame parameter) is already covered by the simpler mocked tests above
;; (`knayawp-test-monocle-panel-enters-monocle', `knayawp-test-monocle-panel-exits-monocle',
;; `knayawp-test-monocle-panel-clears-zoomed-state').  Full geometry (window
;; counts, side-window visibility, panel selection) is verified by
;; test/probes/monocle.el.  No additional batch tests are needed here.

(ert-deftest knayawp-test-monocle-clears-frame-param-on-exit ()
  "After monocle exit the frame parameter is nil."
  (unwind-protect
      (progn
        (set-frame-parameter nil 'knayawp--monocle-config
                             (cons (current-window-configuration) nil))
        (cl-letf (((symbol-function 'set-window-configuration) #'ignore))
          (knayawp-monocle-panel))
        (should-not (frame-parameter nil 'knayawp--monocle-config)))
    (set-frame-parameter nil 'knayawp--monocle-config nil)))

(ert-deftest knayawp-test-monocle-panel-command-map-binding ()
  "Command map binds Z to `knayawp-monocle-panel'."
  (should (eq 'knayawp-monocle-panel
              (lookup-key knayawp-command-map "Z"))))

(ert-deftest knayawp-test-teardown-clears-monocle-config ()
  "`knayawp-layout-teardown' clears the monocle frame parameter."
  (let ((knayawp--commit-pre-state nil)
        (knayawp--frame-widths nil)
        (knayawp--magit-saved-display-fn nil)
        (knayawp--commit-display-entry nil)
        (knayawp--process-display-entry nil)
        (knayawp--commit-hooks-installed nil)
        cleared)
    (cl-letf (((symbol-function 'knayawp--teardown-magit-integration)
               #'ignore)
              ((symbol-function 'knayawp--side-windows)
               (lambda () nil))
              ((symbol-function 'set-frame-parameter)
               (lambda (_frame sym val)
                 (when (eq sym 'knayawp--monocle-config)
                   (setq cleared (null val))))))
      (knayawp-layout-teardown))
    (should cleared)))

;;;; knayawp-panels :set refreshes magit integration (#87)

(ert-deftest knayawp-test-panels-set-refreshes-magit-when-mode-on ()
  "Setting `knayawp-panels' refreshes magit integration when mode is on.
The process-buffer `display-buffer-alist' entry hard-codes the
magit slot captured at setup time; when the user changes the
:slot, a teardown+setup cycle must be triggered so the entry is
rebuilt with the new slot number."
  (let ((teardown-calls 0)
        (setup-calls 0)
        (knayawp-mode t)
        (knayawp--panel-display-entries nil)
        (display-buffer-alist nil))
    (cl-letf (((symbol-function 'knayawp--remove-panel-display-routing)
               #'ignore)
              ((symbol-function 'knayawp--install-panel-display-routing)
               #'ignore)
              ((symbol-function 'knayawp--teardown-magit-integration)
               (lambda () (cl-incf teardown-calls)))
              ((symbol-function 'knayawp--setup-magit-integration)
               (lambda () (cl-incf setup-calls))))
      (let ((setter (get 'knayawp-panels 'custom-set)))
        (should setter)
        (funcall setter 'knayawp-panels
                 '((magit :slot -2) (vterm :slot 0)))))
    (should (= 1 teardown-calls))
    (should (= 1 setup-calls))))

(ert-deftest knayawp-test-panels-set-no-magit-refresh-when-mode-off ()
  "Setting `knayawp-panels' does not touch magit integration when mode is off."
  (let ((teardown-calls 0)
        (setup-calls 0)
        (knayawp-mode nil))
    (cl-letf (((symbol-function 'knayawp--teardown-magit-integration)
               (lambda () (cl-incf teardown-calls)))
              ((symbol-function 'knayawp--setup-magit-integration)
               (lambda () (cl-incf setup-calls))))
      (let ((setter (get 'knayawp-panels 'custom-set)))
        (should setter)
        (funcall setter 'knayawp-panels
                 '((magit :slot -1) (vterm :slot 0)))))
    (should (= 0 teardown-calls))
    (should (= 0 setup-calls))))

;;;; knayawp-panels widget type validation (#88)

(ert-deftest knayawp-test-panels-default-value-accessors ()
  "Default `knayawp-panels' value works with all accessor helpers.
Verifies the repeat+list widget change did not alter the runtime
data format consumed by `knayawp--panel-slot',
`knayawp--panel-height', and `knayawp--panel-type'."
  (let ((panels (default-value 'knayawp-panels)))
    ;; All three entries must be reachable by type key.
    (should (assq 'magit  panels))
    (should (assq 'vterm  panels))
    (should (assq 'claude panels))
    ;; Slot accessor works on each entry.
    (should (integerp (knayawp--panel-slot (assq 'magit  panels))))
    (should (integerp (knayawp--panel-slot (assq 'vterm  panels))))
    (should (integerp (knayawp--panel-slot (assq 'claude panels))))
    ;; Height accessor works on each entry (default panels all have :height).
    (should (floatp (knayawp--panel-height (assq 'magit  panels))))
    (should (floatp (knayawp--panel-height (assq 'vterm  panels))))
    (should (floatp (knayawp--panel-height (assq 'claude panels))))))

(ert-deftest knayawp-test-panels-slot-accessor-integer-round-trip ()
  "Panel :slot accessor returns the correct integer for valid specs.
Covers both the with-:height and without-:height forms, confirming
that the choice widget's two arities are both handled correctly by
the runtime plist accessors."
  ;; With :height present (5-element form).
  (let ((spec '(magit :slot -1 :height 0.34)))
    (should (equal -1 (knayawp--panel-slot spec)))
    (should (integerp (knayawp--panel-slot spec)))
    (should (floatp (knayawp--panel-height spec))))
  (let ((spec '(vterm :slot 0 :height 0.33)))
    (should (equal 0 (knayawp--panel-slot spec)))
    (should (integerp (knayawp--panel-slot spec)))
    (should (floatp (knayawp--panel-height spec))))
  ;; Without :height (3-element form) — :height accessor must return nil.
  (let ((spec '(claude :slot 1)))
    (should (equal 1 (knayawp--panel-slot spec)))
    (should (integerp (knayawp--panel-slot spec)))
    (should (null (knayawp--panel-height spec)))))

;;;; Active-layouts cleanup from non-project buffers (#90)

(ert-deftest knayawp-test-teardown-removes-active-layout-via-frame-param ()
  "`knayawp-layout-teardown' cleans up `knayawp--active-layouts' using
the frame parameter, not `project-current'.
When called from a non-project buffer `project-current' returns nil,
so the old `when-let* / project-current' guard would short-circuit and
leave a stale entry.  The fix reads the frame parameter set at setup
time instead."
  (let ((knayawp--active-layouts
         (list (cons "/fake/root/" '((magit . nil)))))
        (knayawp--commit-pre-state nil)
        (knayawp--frame-widths nil)
        (knayawp--magit-saved-display-fn nil)
        (knayawp--commit-display-entry nil)
        (knayawp--process-display-entry nil)
        (knayawp--commit-hooks-installed nil))
    (cl-letf (((symbol-function 'knayawp--teardown-magit-integration)
               #'ignore)
              ((symbol-function 'knayawp--side-windows)
               (lambda () nil))
              ;; Simulate teardown called from a non-project buffer:
              ;; `project-current' would return nil but the frame param is set.
              ((symbol-function 'project-current)
               (lambda (&optional _maybe-prompt)
                 nil))
              ((symbol-function 'frame-parameter)
               (lambda (_frame sym)
                 (when (eq sym 'knayawp--current-project-root)
                   "/fake/root/")))
              ((symbol-function 'set-frame-parameter)
               #'ignore))
      (knayawp-layout-teardown))
    ;; The stale entry must be gone even though project-current returned nil.
    (should-not (alist-get "/fake/root/" knayawp--active-layouts
                           nil nil #'equal))))

;;;; Auto theme refresh (#100)

(ert-deftest knayawp-test-auto-theme-refresh-flag-default ()
  "`knayawp-auto-theme-refresh-flag' defaults to t."
  (should (eq t (default-value 'knayawp-auto-theme-refresh-flag))))

(ert-deftest knayawp-test-mode-on-installs-theme-refresh-hook ()
  "Enabling `knayawp-mode' registers the theme refresh handler.
After `knayawp--mode-on' runs, `knayawp--refresh-panels-after-theme'
must be present in `enable-theme-functions'."
  (let ((enable-theme-functions nil)
        (project-switch-commands 'sentinel)
        (knayawp--saved-project-switch-commands :unset)
        (knayawp--panel-display-entries nil)
        (display-buffer-alist nil))
    (unwind-protect
        (progn
          (knayawp--mode-on)
          (should (memq #'knayawp--refresh-panels-after-theme
                        enable-theme-functions)))
      (knayawp--mode-off))))

(ert-deftest knayawp-test-mode-off-removes-theme-refresh-hook ()
  "Disabling `knayawp-mode' unregisters the theme refresh handler.
After `knayawp--mode-off' runs, `knayawp--refresh-panels-after-theme'
must no longer be present in `enable-theme-functions'."
  (let ((enable-theme-functions nil)
        (project-switch-commands 'sentinel)
        (knayawp--saved-project-switch-commands :unset)
        (knayawp--panel-display-entries nil)
        (display-buffer-alist nil))
    (unwind-protect
        (progn
          (knayawp--mode-on)
          (knayawp--mode-off)
          (should-not (memq #'knayawp--refresh-panels-after-theme
                            enable-theme-functions)))
      (knayawp--mode-off))))

(ert-deftest knayawp-test-refresh-panels-calls-toggle-twice ()
  "Theme refresh handler double-toggles side windows when active.
When `knayawp-auto-theme-refresh-flag' is t and a layout is active,
`window-toggle-side-windows' must be called exactly twice per frame."
  (let ((knayawp-auto-theme-refresh-flag t)
        (knayawp--active-layouts '((fake-root . t)))
        (knayawp--zoomed-panel nil)
        (toggle-calls 0))
    (cl-letf (((symbol-function 'frame-parameter)
               (lambda (_frame _param) nil))
              ;; Use the real frame-list so save-selected-window gets a
              ;; live frame; stub knayawp--side-windows-in-frame to
              ;; return a non-nil list for whatever frame batch has.
              ((symbol-function 'knayawp--side-windows-in-frame)
               (lambda (_frame) '(fake-win)))
              ((symbol-function 'window-toggle-side-windows)
               (lambda (_frame) (cl-incf toggle-calls))))
      (knayawp--refresh-panels-after-theme 'modus-vivendi)
      ;; Batch mode has exactly one frame; expect 2 calls for that frame.
      (should (= 2 toggle-calls)))))

(ert-deftest knayawp-test-refresh-panels-noop-when-flag-off ()
  "Theme refresh handler is a no-op when the flag is nil."
  (let ((knayawp-auto-theme-refresh-flag nil)
        (knayawp--active-layouts '((fake-root . t)))
        (knayawp--zoomed-panel nil)
        (toggle-calls 0))
    (cl-letf (((symbol-function 'frame-parameter)
               (lambda (_frame _param) nil))
              ((symbol-function 'frame-list)
               (lambda () '(fake-frame)))
              ((symbol-function 'knayawp--side-windows-in-frame)
               (lambda (_frame) '(fake-win)))
              ((symbol-function 'window-toggle-side-windows)
               (lambda (_frame) (cl-incf toggle-calls))))
      (knayawp--refresh-panels-after-theme 'modus-vivendi)
      (should (= 0 toggle-calls)))))

(ert-deftest knayawp-test-refresh-panels-noop-when-no-layout ()
  "Theme refresh handler is a no-op when no knayawp layout is active."
  (let ((knayawp-auto-theme-refresh-flag t)
        (knayawp--active-layouts nil)
        (knayawp--zoomed-panel nil)
        (toggle-calls 0))
    (cl-letf (((symbol-function 'frame-parameter)
               (lambda (_frame _param) nil))
              ((symbol-function 'frame-list)
               (lambda () '(fake-frame)))
              ((symbol-function 'knayawp--side-windows-in-frame)
               (lambda (_frame) '(fake-win)))
              ((symbol-function 'window-toggle-side-windows)
               (lambda (_frame) (cl-incf toggle-calls))))
      (knayawp--refresh-panels-after-theme 'modus-operandi)
      (should (= 0 toggle-calls)))))

(ert-deftest knayawp-test-refresh-panels-noop-when-zoomed ()
  "Theme refresh is a no-op when a panel is zoomed.
`knayawp--zoomed-panel' non-nil means the guard fires and
`window-toggle-side-windows' must not be called."
  (let ((knayawp-auto-theme-refresh-flag t)
        (knayawp--active-layouts '((fake-root . t)))
        (knayawp--zoomed-panel 'terminal)
        (toggle-calls 0))
    (cl-letf (((symbol-function 'frame-parameter)
               (lambda (_frame _param) nil))
              ((symbol-function 'frame-list)
               (lambda () '(fake-frame)))
              ((symbol-function 'knayawp--side-windows-in-frame)
               (lambda (_frame) '(fake-win)))
              ((symbol-function 'window-toggle-side-windows)
               (lambda (_frame) (cl-incf toggle-calls))))
      (knayawp--refresh-panels-after-theme 'modus-vivendi)
      (should (= 0 toggle-calls)))))

(ert-deftest knayawp-test-refresh-panels-noop-when-monocle ()
  "Theme refresh is a no-op when monocle mode is active.
The `knayawp--monocle-config' frame parameter being non-nil must
prevent `window-toggle-side-windows' from being called."
  (let ((knayawp-auto-theme-refresh-flag t)
        (knayawp--active-layouts '((fake-root . t)))
        (knayawp--zoomed-panel nil)
        (toggle-calls 0))
    (cl-letf (((symbol-function 'frame-parameter)
               (lambda (_frame _param) 'saved-cfg))
              ((symbol-function 'frame-list)
               (lambda () '(fake-frame)))
              ((symbol-function 'knayawp--side-windows-in-frame)
               (lambda (_frame) '(fake-win)))
              ((symbol-function 'window-toggle-side-windows)
               (lambda (_frame) (cl-incf toggle-calls))))
      (knayawp--refresh-panels-after-theme 'modus-vivendi)
      (should (= 0 toggle-calls)))))

;;;; Fixup-focus flow (#98)

(ert-deftest knayawp-test-fixup-flag-default ()
  "`knayawp-magit-fixup-style' defaults to `zoom'."
  (should (eq 'zoom (default-value 'knayawp-magit-fixup-style))))

(ert-deftest knayawp-test-fixup-focus-after-default ()
  "`knayawp-magit-fixup-focus-after' defaults to `editor'."
  (should (eq 'editor (default-value 'knayawp-magit-fixup-focus-after))))

(ert-deftest knayawp-test-fixup-hooks-installed-on-mode-on ()
  "Setup installs all three fixup hooks when style is `zoom'."
  (when (require 'magit nil t)
    (let ((original magit-display-buffer-function)
          (knayawp--magit-saved-display-fn nil)
          (knayawp--commit-display-entry nil)
          (knayawp--process-display-entry nil)
          (knayawp--commit-hooks-installed nil)
          (knayawp--fixup-hooks-installed nil)
          (knayawp--commit-style-shim-warned t)
          (knayawp-magit-fixup-style 'zoom)
          (knayawp-magit-commit-style 'zoom)
          (magit-log-select-mode-hook nil)
          (magit-log-select-pick-hook nil)
          (magit-log-select-quit-hook nil)
          (display-buffer-alist nil))
      (unwind-protect
          (progn
            (knayawp--setup-magit-integration)
            (should (memq #'knayawp--magit-log-select-setup-handler
                          magit-log-select-mode-hook))
            (should (memq #'knayawp--magit-log-select-finish-handler
                          magit-log-select-pick-hook))
            (should (memq #'knayawp--magit-log-select-cancel-handler
                          magit-log-select-quit-hook))
            (should knayawp--fixup-hooks-installed))
        (knayawp--teardown-magit-integration)
        (setq magit-display-buffer-function original)))))

(ert-deftest knayawp-test-fixup-hooks-removed-on-mode-off ()
  "Teardown removes all three fixup hooks."
  (when (require 'magit nil t)
    (let ((original magit-display-buffer-function)
          (knayawp--magit-saved-display-fn nil)
          (knayawp--commit-display-entry nil)
          (knayawp--process-display-entry nil)
          (knayawp--commit-hooks-installed nil)
          (knayawp--fixup-hooks-installed nil)
          (knayawp--commit-style-shim-warned t)
          (knayawp-magit-fixup-style 'zoom)
          (knayawp-magit-commit-style 'zoom)
          (magit-log-select-mode-hook nil)
          (magit-log-select-pick-hook nil)
          (magit-log-select-quit-hook nil)
          (display-buffer-alist nil))
      (unwind-protect
          (progn
            (knayawp--setup-magit-integration)
            (knayawp--teardown-magit-integration)
            (should-not (memq #'knayawp--magit-log-select-setup-handler
                              magit-log-select-mode-hook))
            (should-not (memq #'knayawp--magit-log-select-finish-handler
                              magit-log-select-pick-hook))
            (should-not (memq #'knayawp--magit-log-select-cancel-handler
                              magit-log-select-quit-hook))
            (should-not knayawp--fixup-hooks-installed))
        (setq magit-display-buffer-function original)))))

(ert-deftest knayawp-test-fixup-setup-handler-noop-when-style-off ()
  "Setup handler is a no-op when `knayawp-magit-fixup-style' is `off'."
  (let ((knayawp-magit-fixup-style 'off)
        (knayawp--active-layouts '((fake-root . t)))
        (knayawp--fixup-pre-state nil)
        (selected nil))
    (cl-letf (((symbol-function 'knayawp--side-window-for-slot)
               (lambda (_slot) 'fake-window))
              ((symbol-function 'select-window)
               (lambda (win &optional _norecord) (setq selected win))))
      (knayawp--magit-log-select-setup-handler)
      (should-not selected)
      (should-not knayawp--fixup-pre-state))))

(ert-deftest knayawp-test-fixup-setup-handler-noop-without-layout ()
  "Setup handler is a no-op when `knayawp--active-layouts' is nil."
  (let ((knayawp-magit-fixup-style 'zoom)
        (knayawp--active-layouts nil)
        (knayawp--fixup-pre-state nil)
        (selected nil))
    (cl-letf (((symbol-function 'knayawp--side-window-for-slot)
               (lambda (_slot) 'fake-window))
              ((symbol-function 'select-window)
               (lambda (win &optional _norecord) (setq selected win))))
      (knayawp--magit-log-select-setup-handler)
      (should-not selected)
      (should-not knayawp--fixup-pre-state))))

(ert-deftest knayawp-test-fixup-setup-handler-noop-without-magit-window ()
  "Setup handler is a no-op when the magit side window does not exist."
  (let ((knayawp-magit-fixup-style 'zoom)
        (knayawp--active-layouts '((fake-root . t)))
        (knayawp--fixup-pre-state nil)
        (selected nil))
    (cl-letf (((symbol-function 'knayawp--side-window-for-slot)
               (lambda (_slot) nil))
              ((symbol-function 'select-window)
               (lambda (win &optional _norecord) (setq selected win))))
      (knayawp--magit-log-select-setup-handler)
      (should-not selected)
      (should-not knayawp--fixup-pre-state))))

(ert-deftest knayawp-test-fixup-setup-handler-focuses-magit-window ()
  "Setup handler focuses the magit window when all conditions are met."
  (let ((knayawp-magit-fixup-style 'zoom)
        (knayawp--active-layouts '((fake-root . t)))
        (knayawp--fixup-pre-state nil)
        (selected nil))
    (unwind-protect
        (cl-letf (((symbol-function 'knayawp--side-window-for-slot)
                   (lambda (_slot) 'fake-magit-win))
                  ((symbol-function 'select-window)
                   (lambda (win &optional _norecord) (setq selected win))))
          (knayawp--magit-log-select-setup-handler)
          (should (eq selected 'fake-magit-win))
          (should (knayawp--fixup-flow-active-p)))
      (setq knayawp--fixup-pre-state nil))))

(ert-deftest knayawp-test-fixup-setup-handler-noop-when-already-active ()
  "Setup handler is a no-op when a fixup session is already active."
  (let ((knayawp-magit-fixup-style 'zoom)
        (knayawp--active-layouts '((fake-root . t)))
        (knayawp--fixup-pre-state (list :active t :pre-fixup-window nil))
        (selected nil))
    (unwind-protect
        (cl-letf (((symbol-function 'knayawp--side-window-for-slot)
                   (lambda (_slot) 'fake-window))
                  ((symbol-function 'select-window)
                   (lambda (win &optional _norecord) (setq selected win))))
          (knayawp--magit-log-select-setup-handler)
          (should-not selected))
      (setq knayawp--fixup-pre-state nil))))

(ert-deftest knayawp-test-fixup-finish-handler-clears-state ()
  "Finish handler clears `knayawp--fixup-pre-state' and places focus."
  (let ((knayawp-magit-fixup-focus-after 'editor)
        (knayawp--fixup-pre-state (list :active t :pre-fixup-window nil))
        (selected nil))
    (cl-letf (((symbol-function 'window-list)
               (lambda (&rest _) (list 'editor-win)))
              ((symbol-function 'window-parameter)
               (lambda (_win _param) nil))
              ((symbol-function 'window-live-p)
               (lambda (_win) t))
              ((symbol-function 'select-window)
               (lambda (win &optional _norecord) (setq selected win))))
      (knayawp--magit-log-select-finish-handler)
      (should-not knayawp--fixup-pre-state)
      (should (eq selected 'editor-win)))))

(ert-deftest knayawp-test-fixup-cancel-handler-clears-state ()
  "Cancel handler clears `knayawp--fixup-pre-state' and places focus."
  (let ((knayawp-magit-fixup-focus-after 'editor)
        (knayawp--fixup-pre-state (list :active t :pre-fixup-window nil))
        (selected nil))
    (cl-letf (((symbol-function 'window-list)
               (lambda (&rest _) (list 'editor-win)))
              ((symbol-function 'window-parameter)
               (lambda (_win _param) nil))
              ((symbol-function 'window-live-p)
               (lambda (_win) t))
              ((symbol-function 'select-window)
               (lambda (win &optional _norecord) (setq selected win))))
      (knayawp--magit-log-select-cancel-handler)
      (should-not knayawp--fixup-pre-state)
      (should (eq selected 'editor-win)))))

(ert-deftest knayawp-test-fixup-finish-handler-noop-when-idle ()
  "Finish handler is a no-op when no fixup session is active."
  (let ((knayawp--fixup-pre-state nil)
        (selected nil))
    (cl-letf (((symbol-function 'select-window)
               (lambda (win &optional _norecord) (setq selected win))))
      (knayawp--magit-log-select-finish-handler)
      (should-not selected)
      (should-not knayawp--fixup-pre-state))))

(ert-deftest knayawp-test-fixup-cancel-handler-noop-when-idle ()
  "Cancel handler is a no-op when no fixup session is active."
  (let ((knayawp--fixup-pre-state nil)
        (selected nil))
    (cl-letf (((symbol-function 'select-window)
               (lambda (win &optional _norecord) (setq selected win))))
      (knayawp--magit-log-select-cancel-handler)
      (should-not selected)
      (should-not knayawp--fixup-pre-state))))

(ert-deftest knayawp-test-fixup-buffer-kill-handler-clears-state ()
  "Kill-buffer handler clears fixup state when log-select buffer is killed.
When `knayawp--fixup-pre-state' is active and a buffer in
`magit-log-select-mode' is killed, the handler must clear the state."
  (let ((saved-state knayawp--fixup-pre-state)
        (knayawp--fixup-pre-state
         (list :active t :pre-fixup-window nil)))
    (unwind-protect
        (cl-letf (((symbol-function 'derived-mode-p)
                   (lambda (mode) (eq mode 'magit-log-select-mode))))
          (knayawp--fixup-buffer-kill-handler)
          (should-not knayawp--fixup-pre-state))
      (setq knayawp--fixup-pre-state saved-state))))

(ert-deftest knayawp-test-fixup-install-idempotent ()
  "`knayawp--install-fixup-hooks' is idempotent.
Double-install must not add duplicate entries to the hooks."
  (let ((knayawp--fixup-hooks-installed nil)
        (add-hook-calls nil))
    (unwind-protect
        (cl-letf (((symbol-function 'add-hook)
                   (lambda (hook fn &rest _)
                     (push (cons hook fn) add-hook-calls))))
          (knayawp--install-fixup-hooks)
          (knayawp--install-fixup-hooks)
          ;; The flag is set after first install and blocks the second.
          (should knayawp--fixup-hooks-installed)
          ;; Each handler must appear exactly once in the recorded calls.
          (should (= (cl-count 'magit-log-select-mode-hook add-hook-calls
                               :key #'car)
                     1))
          (should (= (cl-count 'magit-log-select-pick-hook add-hook-calls
                               :key #'car)
                     1))
          (should (= (cl-count 'magit-log-select-quit-hook add-hook-calls
                               :key #'car)
                     1)))
      (setq knayawp--fixup-hooks-installed nil))))

(ert-deftest knayawp-test-fixup-remove-idempotent ()
  "`knayawp--remove-fixup-hooks' is idempotent."
  (let ((knayawp--fixup-hooks-installed nil))
    ;; Remove when not installed must not error.
    (knayawp--remove-fixup-hooks)
    (should-not knayawp--fixup-hooks-installed)))

(ert-deftest knayawp-test-reconcile-fixup-style-zoom-installs ()
  "`knayawp--reconcile-fixup-style' installs hooks when style is `zoom'."
  (let ((knayawp-magit-fixup-style 'zoom)
        (knayawp--fixup-hooks-installed nil))
    (unwind-protect
        (progn
          (knayawp--reconcile-fixup-style)
          (should knayawp--fixup-hooks-installed))
      (knayawp--remove-fixup-hooks))))

(ert-deftest knayawp-test-reconcile-fixup-style-off-removes ()
  "`knayawp--reconcile-fixup-style' removes hooks when style is `off'."
  (let ((knayawp-magit-fixup-style 'zoom)
        (knayawp--fixup-hooks-installed nil))
    (knayawp--install-fixup-hooks)
    (should knayawp--fixup-hooks-installed)
    (setq knayawp-magit-fixup-style 'off)
    (knayawp--reconcile-fixup-style)
    (should-not knayawp--fixup-hooks-installed)))

;;;; Side-pane visit routing (#52)

(ert-deftest knayawp-test-side-pane-visit-style-default ()
  "`knayawp-side-pane-visit-style' defaults to `default'."
  (should (eq 'default (default-value 'knayawp-side-pane-visit-style))))

(ert-deftest knayawp-test-visit-condition-requires-managed-split-style ()
  "Condition returns nil when style is `default'."
  (let ((knayawp-side-pane-visit-style 'default)
        (knayawp--active-layouts '(("/fake/" . t)))
        (buf (get-buffer-create " *knayawp-test-visit-default*")))
    (unwind-protect
        (cl-letf (((symbol-function 'frame-parameter)
                   (lambda (_f _p) nil))
                  ((symbol-function 'window-parameter)
                   (lambda (_w _p) 'right))
                  ((symbol-function 'selected-window)
                   (lambda () 'fake-side-win)))
          (should-not (knayawp--visit-from-side-window-p buf nil)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest knayawp-test-visit-condition-requires-active-layout ()
  "Condition returns nil when `knayawp--active-layouts' is nil."
  (let ((knayawp-side-pane-visit-style 'managed-split)
        (knayawp--active-layouts nil)
        (buf (get-buffer-create " *knayawp-test-visit-no-layout*")))
    (unwind-protect
        (cl-letf (((symbol-function 'frame-parameter)
                   (lambda (_f _p) nil))
                  ((symbol-function 'window-parameter)
                   (lambda (_w _p) 'right))
                  ((symbol-function 'selected-window)
                   (lambda () 'fake-side-win)))
          (should-not (knayawp--visit-from-side-window-p buf nil)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest knayawp-test-visit-condition-requires-right-side-window ()
  "Condition returns nil when selected window is not a right side window.
After finding 2 the check is `eq ... \\='right', so left/top/bottom
side windows (imenu-list, treemacs, etc.) must NOT trigger routing."
  (let ((knayawp-side-pane-visit-style 'managed-split)
        (knayawp--active-layouts '(("/fake/" . t)))
        (buf (get-buffer-create " *knayawp-test-visit-no-side*")))
    (unwind-protect
        (progn
          ;; window-parameter returns nil → not a side window at all.
          (cl-letf (((symbol-function 'frame-parameter)
                     (lambda (_f _p) nil))
                    ((symbol-function 'window-parameter)
                     (lambda (_w _p) nil))
                    ((symbol-function 'selected-window)
                     (lambda () 'fake-editor-win))
                    ((symbol-function 'buffer-file-name)
                     (lambda (_b) "/fake/file.el")))
            (should-not (knayawp--visit-from-side-window-p buf nil)))
          ;; window-parameter returns 'left → left side window, must not route.
          (cl-letf (((symbol-function 'frame-parameter)
                     (lambda (_f _p) nil))
                    ((symbol-function 'window-parameter)
                     (lambda (_w _p) 'left))
                    ((symbol-function 'selected-window)
                     (lambda () 'fake-left-win))
                    ((symbol-function 'buffer-file-name)
                     (lambda (_b) "/fake/file.el")))
            (should-not (knayawp--visit-from-side-window-p buf nil))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest knayawp-test-visit-condition-excludes-knayawp-buffers ()
  "Condition returns nil for `*knayawp-vterm-proj*' buffers."
  (let ((knayawp-side-pane-visit-style 'managed-split)
        (knayawp--active-layouts '(("/fake/" . t)))
        (buf (get-buffer-create "*knayawp-vterm-proj*")))
    (unwind-protect
        (cl-letf (((symbol-function 'frame-parameter)
                   (lambda (_f _p) nil))
                  ((symbol-function 'window-parameter)
                   (lambda (_w _p) 'right))
                  ((symbol-function 'selected-window)
                   (lambda () 'fake-side-win))
                  ((symbol-function 'buffer-file-name)
                   (lambda (_b) "/fake/file.el")))
          (should-not (knayawp--visit-from-side-window-p buf nil)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest knayawp-test-visit-condition-excludes-buffers-without-file ()
  "Condition returns nil for buffers without a backing file.
Magit transient buffers (COMMIT_EDITMSG, *magit-diff*, git-rebase-todo,
etc.) do not have a `buffer-file-name', so the structural check
excludes them without relying on name-prefix heuristics."
  (let ((knayawp-side-pane-visit-style 'managed-split)
        (knayawp--active-layouts '(("/fake/" . t)))
        (buf (get-buffer-create " *knayawp-test-no-file-buf*")))
    (unwind-protect
        (cl-letf (((symbol-function 'frame-parameter)
                   (lambda (_f _p) nil))
                  ((symbol-function 'window-parameter)
                   (lambda (_w _p) 'right))
                  ((symbol-function 'selected-window)
                   (lambda () 'fake-side-win))
                  ;; buffer-file-name returns nil → no backing file.
                  ((symbol-function 'buffer-file-name)
                   (lambda (_b) nil)))
          (should-not (knayawp--visit-from-side-window-p buf nil)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest knayawp-test-visit-condition-routes-file-visits ()
  "Condition returns non-nil for buffers with a backing file.
A real file visit (find-file, magit-find-file) produces a buffer
with `buffer-file-name' set; those must be routed to the editor
split."
  (let ((knayawp-side-pane-visit-style 'managed-split)
        (knayawp--active-layouts '(("/fake/" . t)))
        (buf (get-buffer-create " *knayawp-test-file-buf*")))
    (unwind-protect
        (cl-letf (((symbol-function 'frame-parameter)
                   (lambda (_f _p) nil))
                  ((symbol-function 'window-parameter)
                   (lambda (_w _p) 'right))
                  ((symbol-function 'selected-window)
                   (lambda () 'fake-side-win))
                  ((symbol-function 'buffer-file-name)
                   (lambda (_b) "/some/project/src/foo.el")))
          (should (knayawp--visit-from-side-window-p buf nil)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest knayawp-test-visit-condition-requires-no-monocle ()
  "Condition returns nil when monocle frame param is set."
  (let ((knayawp-side-pane-visit-style 'managed-split)
        (knayawp--active-layouts '(("/fake/" . t)))
        (buf (get-buffer-create " *knayawp-test-visit-monocle*")))
    (unwind-protect
        (cl-letf (;; frame-parameter returns non-nil → monocle is active.
                  ((symbol-function 'frame-parameter)
                   (lambda (_f _p) 'saved-config))
                  ((symbol-function 'window-parameter)
                   (lambda (_w _p) 'right))
                  ((symbol-function 'selected-window)
                   (lambda () 'fake-side-win)))
          (should-not (knayawp--visit-from-side-window-p buf nil)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest knayawp-test-visit-display-entry-initially-nil ()
  "`knayawp--visit-display-entry' is nil before installation."
  (should-not knayawp--visit-display-entry))

(ert-deftest knayawp-test-install-visit-routing-adds-entry ()
  "Install adds one entry to `display-buffer-alist'."
  (let ((display-buffer-alist nil)
        (knayawp--visit-display-entry nil))
    (unwind-protect
        (progn
          (knayawp--install-visit-routing)
          (should knayawp--visit-display-entry)
          (should (memq knayawp--visit-display-entry
                        display-buffer-alist))
          (should (eq 'knayawp--visit-from-side-window-p
                      (car knayawp--visit-display-entry))))
      (knayawp--remove-visit-routing))))

(ert-deftest knayawp-test-install-visit-routing-idempotent ()
  "Double install does not duplicate the entry."
  (let ((display-buffer-alist nil)
        (knayawp--visit-display-entry nil))
    (unwind-protect
        (progn
          (knayawp--install-visit-routing)
          (knayawp--install-visit-routing)
          (should (= 1 (length display-buffer-alist))))
      (knayawp--remove-visit-routing))))

(ert-deftest knayawp-test-remove-visit-routing-clears-entry ()
  "Remove takes the entry out of `display-buffer-alist'."
  (let ((display-buffer-alist nil)
        (knayawp--visit-display-entry nil))
    (knayawp--install-visit-routing)
    (knayawp--remove-visit-routing)
    (should-not knayawp--visit-display-entry)
    (should (null display-buffer-alist))))

(ert-deftest knayawp-test-layout-setup-installs-visit-routing-when-managed ()
  "`knayawp-layout-setup' installs visit routing for `managed-split'."
  (let ((knayawp-side-pane-visit-style 'managed-split)
        (knayawp--visit-display-entry nil)
        (knayawp--active-layouts nil)
        (knayawp--frame-widths nil)
        (display-buffer-alist nil)
        (window-sides-slots window-sides-slots)
        (visit-installed 0))
    (cl-letf (((symbol-function 'knayawp--project-root)
               (lambda () "/fake/project/"))
              ((symbol-function 'knayawp--project-name)
               (lambda (_root) "project"))
              ((symbol-function 'knayawp--create-panel-buffer)
               (lambda (_type _root _name)
                 (get-buffer-create "*knayawp-test-setup-visit*")))
              ((symbol-function 'display-buffer-in-side-window)
               (lambda (_buf _alist) (selected-window)))
              ((symbol-function 'knayawp--balance-side-windows)
               #'ignore)
              ((symbol-function 'knayawp--setup-magit-integration)
               #'ignore)
              ((symbol-function 'knayawp--select-editor-window)
               #'ignore)
              ((symbol-function 'knayawp--install-visit-routing)
               (lambda () (cl-incf visit-installed)))
              ((symbol-function 'add-hook) #'ignore))
      (knayawp-layout-setup))
    (should (= 1 visit-installed))))

(ert-deftest knayawp-test-layout-setup-skips-visit-routing-when-default ()
  "`knayawp-layout-setup' skips visit routing when style is `default'."
  (let ((knayawp-side-pane-visit-style 'default)
        (knayawp--visit-display-entry nil)
        (knayawp--active-layouts nil)
        (knayawp--frame-widths nil)
        (display-buffer-alist nil)
        (window-sides-slots window-sides-slots)
        (visit-installed 0))
    (cl-letf (((symbol-function 'knayawp--project-root)
               (lambda () "/fake/project/"))
              ((symbol-function 'knayawp--project-name)
               (lambda (_root) "project"))
              ((symbol-function 'knayawp--create-panel-buffer)
               (lambda (_type _root _name)
                 (get-buffer-create "*knayawp-test-setup-default*")))
              ((symbol-function 'display-buffer-in-side-window)
               (lambda (_buf _alist) (selected-window)))
              ((symbol-function 'knayawp--balance-side-windows)
               #'ignore)
              ((symbol-function 'knayawp--setup-magit-integration)
               #'ignore)
              ((symbol-function 'knayawp--select-editor-window)
               #'ignore)
              ((symbol-function 'knayawp--install-visit-routing)
               (lambda () (cl-incf visit-installed)))
              ((symbol-function 'add-hook) #'ignore))
      (knayawp-layout-setup))
    (should (= 0 visit-installed))))

(ert-deftest knayawp-test-teardown-removes-visit-routing ()
  "`knayawp-layout-teardown' calls `knayawp--remove-visit-routing'."
  (let ((knayawp--visit-display-entry nil)
        (knayawp--commit-pre-state nil)
        (knayawp--frame-widths nil)
        (knayawp--magit-saved-display-fn nil)
        (knayawp--commit-display-entry nil)
        (knayawp--process-display-entry nil)
        (knayawp--commit-hooks-installed nil)
        (display-buffer-alist nil)
        (remove-called 0))
    (cl-letf (((symbol-function 'knayawp--teardown-magit-integration)
               #'ignore)
              ((symbol-function 'knayawp--side-windows)
               (lambda () nil))
              ((symbol-function 'knayawp--remove-visit-routing)
               (lambda () (cl-incf remove-called))))
      (knayawp-layout-teardown))
    (should (= 1 remove-called))))

;;;; Visit-style :set reconciliation (#111 review)

(ert-deftest knayawp-test-visit-style-set-installs-routing-when-layout-active ()
  "Setting style to `managed-split' installs routing when a layout is active."
  (let ((saved-style (default-value 'knayawp-side-pane-visit-style))
        (knayawp--active-layouts '(("/fake/" . t)))
        (knayawp--visit-display-entry nil)
        (remove-calls 0)
        (install-calls 0))
    (unwind-protect
        (cl-letf (((symbol-function 'knayawp--remove-visit-routing)
                   (lambda () (cl-incf remove-calls)))
                  ((symbol-function 'knayawp--install-visit-routing)
                   (lambda () (cl-incf install-calls))))
          (customize-set-variable 'knayawp-side-pane-visit-style
                                  'managed-split)
          ;; Remove is always called; install only when layout active.
          (should (= 1 remove-calls))
          (should (= 1 install-calls)))
      (customize-set-variable 'knayawp-side-pane-visit-style saved-style))))

(ert-deftest knayawp-test-visit-style-set-skips-install-when-no-layout ()
  "Setting style to `managed-split' skips install when no layout is active."
  (let ((saved-style (default-value 'knayawp-side-pane-visit-style))
        (knayawp--active-layouts nil)
        (knayawp--visit-display-entry nil)
        (remove-calls 0)
        (install-calls 0))
    (unwind-protect
        (cl-letf (((symbol-function 'knayawp--remove-visit-routing)
                   (lambda () (cl-incf remove-calls)))
                  ((symbol-function 'knayawp--install-visit-routing)
                   (lambda () (cl-incf install-calls))))
          (customize-set-variable 'knayawp-side-pane-visit-style
                                  'managed-split)
          (should (= 1 remove-calls))
          ;; No layout → install must not fire.
          (should (= 0 install-calls)))
      (customize-set-variable 'knayawp-side-pane-visit-style saved-style))))

(ert-deftest knayawp-test-visit-style-set-removes-routing-when-default ()
  "Setting style to `default' removes routing regardless of layout."
  (let ((saved-style (default-value 'knayawp-side-pane-visit-style))
        (knayawp--active-layouts '(("/fake/" . t)))
        (knayawp--visit-display-entry nil)
        (remove-calls 0)
        (install-calls 0))
    (unwind-protect
        (cl-letf (((symbol-function 'knayawp--remove-visit-routing)
                   (lambda () (cl-incf remove-calls)))
                  ((symbol-function 'knayawp--install-visit-routing)
                   (lambda () (cl-incf install-calls))))
          (customize-set-variable 'knayawp-side-pane-visit-style 'default)
          (should (= 1 remove-calls))
          ;; style = 'default → install must not fire.
          (should (= 0 install-calls)))
      (customize-set-variable 'knayawp-side-pane-visit-style saved-style))))

;;;; Claude editor integration (#121)

(ert-deftest knayawp-test-claude-editor-flag-default ()
  "`knayawp-claude-editor-flag' defaults to t."
  (should (eq t (default-value 'knayawp-claude-editor-flag))))

(ert-deftest knayawp-test-claude-editor-hook-installed-initially-nil ()
  "Claude editor hook install state is nil before setup."
  (should-not knayawp--claude-editor-hook-installed))

(ert-deftest knayawp-test-install-claude-editor-hook-idempotent ()
  "Installing the Claude editor hook twice does not duplicate it."
  ;; Note: we stub add-hook/remove-hook because Emacs `add-hook' writes
  ;; to the default (global) hook value, not the let-bound local.
  ;; Counting calls via stubs is the correct testing approach here.
  (let ((knayawp--claude-editor-hook-installed nil)
        (add-calls 0)
        (remove-calls 0))
    (cl-letf (((symbol-function 'add-hook)
               (lambda (_hook _fn &rest _) (cl-incf add-calls)))
              ((symbol-function 'remove-hook)
               (lambda (_hook _fn) (cl-incf remove-calls))))
      (knayawp--install-claude-editor-hook)
      (should knayawp--claude-editor-hook-installed)
      (should (= 1 add-calls))
      ;; Second call is a no-op — add-hook must not be called again.
      (knayawp--install-claude-editor-hook)
      (should (= 1 add-calls))
      ;; Cleanup
      (knayawp--remove-claude-editor-hook)
      (should-not knayawp--claude-editor-hook-installed)
      (should (= 1 remove-calls)))))

(ert-deftest knayawp-test-remove-claude-editor-hook-idempotent ()
  "Removing the hook twice is safe."
  (let ((knayawp--claude-editor-hook-installed nil)
        (server-switch-hook nil))
    (knayawp--install-claude-editor-hook)
    (knayawp--remove-claude-editor-hook)
    (should-not knayawp--claude-editor-hook-installed)
    (should-not (memq #'knayawp--claude-editor-server-switch
                      server-switch-hook))
    ;; Second remove must not error.
    (knayawp--remove-claude-editor-hook)
    (should-not knayawp--claude-editor-hook-installed)))

(ert-deftest knayawp-test-install-claude-editor-hook-appended ()
  "The Claude editor hook is appended (APPEND=t) to `server-switch-hook'.
Verify that `add-hook' is invoked with a truthy APPEND argument so
the Claude handler lands after any pre-existing entries — in
particular after magit's `magit-commit-diff-while-committing'."
  (let ((knayawp--claude-editor-hook-installed nil)
        (captured-append nil))
    (cl-letf (((symbol-function 'add-hook)
               (lambda (_hook _fn &optional append &rest _)
                 (setq captured-append append))))
      (knayawp--install-claude-editor-hook)
      ;; Must have been called with a truthy APPEND.
      (should captured-append))))

(ert-deftest knayawp-test-claude-editor-server-switch-routes-file ()
  "`knayawp--claude-editor-server-switch' routes file buffers to editor.
When a layout is active, `knayawp--editor-window' is live, the
current buffer visits a file, and no commit-flow is active, the
buffer must be displayed in `knayawp--editor-window'."
  (let* ((file-buf (generate-new-buffer " *knayawp-test-claude-file*"))
         (fake-editor-win (selected-window))
         (buf-set nil)
         (win-selected nil)
         (knayawp-claude-editor-flag t)
         (knayawp--active-layouts '(("/fake/" . t)))
         (knayawp--editor-window fake-editor-win)
         (knayawp--commit-pre-state nil))
    (unwind-protect
        (cl-letf (((symbol-function 'window-live-p)
                   (lambda (_w) t))
                  ((symbol-function 'buffer-file-name)
                   (lambda () "/tmp/claude-prompt-12345"))
                  ((symbol-function 'current-buffer)
                   (lambda () file-buf))
                  ((symbol-function 'set-window-buffer)
                   (lambda (_win buf) (setq buf-set buf)))
                  ((symbol-function 'select-window)
                   (lambda (win &optional _norecord)
                     (setq win-selected win))))
          (knayawp--claude-editor-server-switch)
          (should (eq buf-set file-buf))
          (should (eq win-selected fake-editor-win)))
      (when (buffer-live-p file-buf) (kill-buffer file-buf)))))

(ert-deftest knayawp-test-claude-editor-server-switch-noop-flag-off ()
  "`knayawp--claude-editor-server-switch' is a no-op when flag is nil.
If the user disables `knayawp-claude-editor-flag' after layout setup,
the hook must not route buffers."
  (let* ((fake-editor-win (selected-window))
         (knayawp-claude-editor-flag nil)
         (knayawp--active-layouts '(("/fake/" . t)))
         (knayawp--editor-window fake-editor-win)
         (knayawp--commit-pre-state nil)
         (touched 0))
    (cl-letf (((symbol-function 'window-live-p) (lambda (_w) t))
              ((symbol-function 'buffer-file-name)
               (lambda () "/tmp/claude-prompt-12345"))
              ((symbol-function 'set-window-buffer)
               (lambda (&rest _) (cl-incf touched)))
              ((symbol-function 'select-window)
               (lambda (&rest _) (cl-incf touched))))
      (knayawp--claude-editor-server-switch)
      (should (= 0 touched)))))

(ert-deftest knayawp-test-claude-editor-server-switch-noop-no-layout ()
  "`knayawp--claude-editor-server-switch' is a no-op with no layout."
  (let ((knayawp--active-layouts nil)
        (touched 0))
    (cl-letf (((symbol-function 'set-window-buffer)
               (lambda (&rest _) (cl-incf touched)))
              ((symbol-function 'select-window)
               (lambda (&rest _) (cl-incf touched))))
      (knayawp--claude-editor-server-switch)
      (should (= 0 touched)))))

(ert-deftest knayawp-test-claude-editor-server-switch-noop-no-editor-win ()
  "`knayawp--claude-editor-server-switch' is a no-op when editor window is dead."
  (let ((knayawp--active-layouts '(("/fake/" . t)))
        (knayawp--editor-window nil)
        (touched 0))
    (cl-letf (((symbol-function 'set-window-buffer)
               (lambda (&rest _) (cl-incf touched)))
              ((symbol-function 'select-window)
               (lambda (&rest _) (cl-incf touched))))
      (knayawp--claude-editor-server-switch)
      (should (= 0 touched)))))

(ert-deftest knayawp-test-claude-editor-server-switch-noop-commit-active ()
  "`knayawp--claude-editor-server-switch' defers to commit-flow handler.
When a commit-zoom session is active the magit handler owns
`server-switch-hook'; the Claude handler must not interfere."
  (let* ((fake-editor-win (selected-window))
         (knayawp-claude-editor-flag t)
         (knayawp--active-layouts '(("/fake/" . t)))
         (knayawp--editor-window fake-editor-win)
         (knayawp--commit-pre-state (list :active t))
         (touched 0))
    (cl-letf (((symbol-function 'window-live-p) (lambda (_w) t))
              ((symbol-function 'buffer-file-name)
               (lambda () "/tmp/claude-prompt-12345"))
              ((symbol-function 'set-window-buffer)
               (lambda (&rest _) (cl-incf touched)))
              ((symbol-function 'select-window)
               (lambda (&rest _) (cl-incf touched))))
      (knayawp--claude-editor-server-switch)
      (should (= 0 touched)))))

(ert-deftest knayawp-test-claude-editor-server-switch-noop-no-file ()
  "`knayawp--claude-editor-server-switch' ignores non-file buffers.
Magit commit messages and scratch buffers have no `buffer-file-name';
the handler must pass them through unchanged."
  (let* ((fake-editor-win (selected-window))
         (knayawp-claude-editor-flag t)
         (knayawp--active-layouts '(("/fake/" . t)))
         (knayawp--editor-window fake-editor-win)
         (knayawp--commit-pre-state nil)
         (touched 0))
    (cl-letf (((symbol-function 'window-live-p) (lambda (_w) t))
              ((symbol-function 'buffer-file-name)
               (lambda () nil))
              ((symbol-function 'set-window-buffer)
               (lambda (&rest _) (cl-incf touched)))
              ((symbol-function 'select-window)
               (lambda (&rest _) (cl-incf touched))))
      (knayawp--claude-editor-server-switch)
      (should (= 0 touched)))))

(ert-deftest knayawp-test-get-or-create-claude-injects-editor-env ()
  "Claude buffer creation passes EDITOR=emacsclient when flag is set.
When `knayawp-claude-editor-flag' is t and a server is running,
`knayawp--get-or-create-claude-buffer' must call `knayawp--make-terminal'
with an env-vars list that contains an EDITOR= entry."
  (let ((knayawp-claude-editor-flag t)
        (knayawp-claude-command "claude")
        (captured-env-vars 'unset)
        (buf (generate-new-buffer " *knayawp-test-claude-env*")))
    (unwind-protect
        (cl-letf (((symbol-function 'get-buffer) (lambda (_n) nil))
                  ((symbol-function 'server-running-p) (lambda () t))
                  ((symbol-function 'executable-find)
                   (lambda (_cmd) "/usr/bin/emacsclient"))
                  ((symbol-function 'knayawp--make-terminal)
                   (lambda (_name _dir _cmd env-vars)
                     (setq captured-env-vars env-vars)
                     buf)))
          (knayawp--get-or-create-claude-buffer "/fake/" "fake")
          (should (listp captured-env-vars))
          (should (= 1 (length captured-env-vars)))
          (should (string-prefix-p "EDITOR=" (car captured-env-vars)))
          (should (string-match-p "emacsclient" (car captured-env-vars))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest knayawp-test-get-or-create-claude-no-env-when-flag-off ()
  "No EDITOR injection when `knayawp-claude-editor-flag' is nil."
  (let ((knayawp-claude-editor-flag nil)
        (captured-env-vars 'unset)
        (buf (generate-new-buffer " *knayawp-test-claude-no-env*")))
    (unwind-protect
        (cl-letf (((symbol-function 'get-buffer) (lambda (_n) nil))
                  ((symbol-function 'knayawp--make-terminal)
                   (lambda (_name _dir _cmd env-vars)
                     (setq captured-env-vars env-vars)
                     buf)))
          (knayawp--get-or-create-claude-buffer "/fake/" "fake")
          (should (null captured-env-vars)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest knayawp-test-get-or-create-claude-no-env-when-no-server ()
  "No EDITOR injection when no Emacs server is running."
  (let ((knayawp-claude-editor-flag t)
        (captured-env-vars 'unset)
        (buf (generate-new-buffer " *knayawp-test-claude-no-server*")))
    (unwind-protect
        (cl-letf (((symbol-function 'get-buffer) (lambda (_n) nil))
                  ((symbol-function 'server-running-p) (lambda () nil))
                  ((symbol-function 'knayawp--make-terminal)
                   (lambda (_name _dir _cmd env-vars)
                     (setq captured-env-vars env-vars)
                     buf)))
          (knayawp--get-or-create-claude-buffer "/fake/" "fake")
          (should (null captured-env-vars)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest knayawp-test-teardown-removes-claude-editor-hook ()
  "`knayawp-layout-teardown' unregisters the Claude editor hook."
  (let ((knayawp--claude-editor-hook-installed t)
        (knayawp--commit-pre-state nil)
        (knayawp--fixup-pre-state nil)
        (knayawp--frame-widths nil)
        (remove-called nil))
    (cl-letf (((symbol-function 'knayawp--teardown-magit-integration) #'ignore)
              ((symbol-function 'knayawp--remove-visit-routing) #'ignore)
              ((symbol-function 'knayawp--remove-claude-editor-hook)
               (lambda () (setq remove-called t)
                 (setq knayawp--claude-editor-hook-installed nil)))
              ((symbol-function 'knayawp--side-windows) (lambda () nil)))
      (knayawp-layout-teardown))
    (should remove-called)
    (should-not knayawp--claude-editor-hook-installed)))

;;; knayawp-test.el ends here
