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
              (knayawp--panel-type '(magit :slot -1 :height 0.33)))))

(ert-deftest knayawp-test-panel-slot ()
  "Extract slot from panel spec."
  (should (equal -1
                 (knayawp--panel-slot '(magit :slot -1 :height 0.33))))
  (should (equal 0
                 (knayawp--panel-slot '(vterm :slot 0 :height 0.33))))
  (should (equal 1
                 (knayawp--panel-slot '(claude :slot 1 :height 0.34)))))

(ert-deftest knayawp-test-panel-height ()
  "Extract height from panel spec."
  (should (equal 0.33
                 (knayawp--panel-height '(magit :slot -1 :height 0.33))))
  (should (equal 0.34
                 (knayawp--panel-height
                  '(claude :slot 1 :height 0.34)))))

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

(ert-deftest knayawp-test-panel-heights-sum ()
  "Panel heights should sum to approximately 1.0."
  (let* ((panels (default-value 'knayawp-panels))
         (total (apply #'+ (mapcar #'knayawp--panel-height panels))))
    (should (< (abs (- total 1.0)) 0.01))))

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
              (lookup-key knayawp-command-map "q"))))

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

;;;; No project signals error

(ert-deftest knayawp-test-no-project-error ()
  "Setup signals user-error when no project is found."
  (let ((default-directory "/"))
    (should-error (knayawp--project-root)
                  :type 'user-error)))

;;; knayawp-test.el ends here
