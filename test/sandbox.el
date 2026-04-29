;;; sandbox.el --- Interactive test sandbox for knayawp.el -*- lexical-binding: t; -*-

;;; Commentary:

;; Load this file in an isolated Emacs session to test knayawp.el
;; interactively without your normal configuration interfering.
;;
;; Usage:
;;   ./test/run-sandbox.sh        (recommended)
;;   emacs -Q -l test/sandbox.el  (manual)
;;
;; What it does:
;; 1. Initializes package.el so magit/vterm/eat are found
;; 2. Loads knayawp.el from this repo (source, not byte-compiled)
;; 3. Creates a temporary git project in /tmp
;; 4. Opens a test file in that project
;; 5. Binds C-c k to knayawp-command-map
;; 6. Shows a help buffer with commands to try
;;
;; The temp project is cleaned up when Emacs exits.
;;
;; Note: vterm requires a compiled C module and may not be available
;; in -Q sessions.  Terminal panels will signal a user-error if the
;; selected backend is missing — this is expected and safe.

;;; Code:

;;;; Bootstrap dependencies

(require 'package)
(package-initialize)

(unless (require 'magit nil t)
  (message "sandbox: magit not found — magit panel will show placeholder"))

;; Try to load the selected terminal backend (informational only)
(let ((have-vterm (require 'vterm nil t))
      (have-eat   (require 'eat nil t)))
  (unless (or have-vterm have-eat)
    (message "sandbox: neither vterm nor eat found — terminal panels will error")))

;;;; Load knayawp.el from repo root

(let ((repo-root (file-name-directory
                  (directory-file-name
                   (file-name-directory
                    (or load-file-name buffer-file-name))))))
  (load (expand-file-name "knayawp.el" repo-root)))

;;;; Create throwaway test project

(defvar sandbox--test-dir nil
  "Path to the temporary test project directory.")

(setq sandbox--test-dir (make-temp-file "knayawp-sandbox-" t))

(let ((default-directory (file-name-as-directory sandbox--test-dir)))
  (call-process "git" nil nil nil "init")
  (call-process "git" nil nil nil "config" "user.email" "test@sandbox")
  (call-process "git" nil nil nil "config" "user.name" "Sandbox")
  (with-temp-file (expand-file-name "hello.el" sandbox--test-dir)
    (insert ";;; hello.el --- test file -*- lexical-binding: t; -*-\n\n")
    (insert "(message \"Hello from knayawp sandbox!\")\n\n")
    (insert "(provide 'hello)\n;;; hello.el ends here\n"))
  (with-temp-file (expand-file-name "world.el" sandbox--test-dir)
    (insert ";;; world.el --- another test file -*- lexical-binding: t; -*-\n\n")
    (insert "(message \"Second file for split-window testing.\")\n\n")
    (insert "(provide 'world)\n;;; world.el ends here\n"))
  (call-process "git" nil nil nil "add" ".")
  (call-process "git" nil nil nil "commit" "-m" "Initial commit"))

;;;; Bind the command map (sandbox only)

(global-set-key (kbd "C-c k") knayawp-command-map)

;;;; Clean up temp dir on exit

(add-hook 'kill-emacs-hook
          (lambda ()
            (when (and sandbox--test-dir
                       (file-directory-p sandbox--test-dir))
              (delete-directory sandbox--test-dir t))))

;;;; Open test file and show help

(find-file (expand-file-name "hello.el" sandbox--test-dir))

(let ((help-buf (get-buffer-create "*knayawp-sandbox*")))
  (with-current-buffer help-buf
    (erase-buffer)
    (insert
     "knayawp.el sandbox\n"
     (make-string 40 ?=) "\n\n"
     "Test project: " sandbox--test-dir "\n\n"
     "Keybindings (C-c k prefix):\n"
     "  C-c k l   Create the layout\n"
     "  C-c k q   Remove the control pane\n"
     "  C-c k 1   Jump to magit panel\n"
     "  C-c k 2   Jump to terminal panel\n"
     "  C-c k 3   Jump to Claude panel\n"
     "  C-c k n   Next panel\n"
     "  C-c k p   Previous panel\n"
     "  C-c k 0   Back to editor\n"
     "  C-c k z   Zoom/unzoom current panel\n"
     "  C-c k s   Toggle side windows\n"
     "\n"
     "Try this:\n"
     "  1. C-c k l — create the layout\n"
     "  2. C-c k 1 — jump to magit, C-c k 2 — terminal\n"
     "  3. C-c k z — zoom the panel, C-c k z again — unzoom\n"
     "  4. C-x 1   — side windows survive!\n"
     "  5. C-c k s — toggle side windows off/on\n"
     "  6. C-c k q — tear down\n"
     "\n"
     "If vterm is missing, terminal panels will signal an error.\n"
     "That's expected in -Q sessions without compiled vterm.\n")
    (goto-char (point-min))
    (setq buffer-read-only t)
    (special-mode))
  (display-buffer help-buf '(display-buffer-at-bottom
                             (window-height . 0.35))))

(message "sandbox ready — C-c k l to set up the layout")

;;; sandbox.el ends here
