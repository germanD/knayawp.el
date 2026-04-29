;;; knayawp.el --- Project-oriented window layouts for Emacs -*- lexical-binding: t; -*-

;; Author: Germán Carrillo
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (magit "3.0"))
;; Keywords: frames, convenience
;; URL: https://github.com/knayawp/knayawp.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; knayawp.el provides automatic project-oriented window layouts.
;; A single command transforms the current frame into a two-pane layout:
;; editor pane on the left, control pane (magit, terminal, Claude Code)
;; stacked on the right using Emacs side windows.
;;
;; The control pane is immune to standard window commands (C-x 0/1/2/3)
;; and uses dedicated keybindings for navigation.
;;
;; Terminal backend is pluggable: vterm (default) or eat.  All terminal
;; creation goes through a dispatch layer so backends are swappable
;; without touching layout code.
;;
;; Usage:
;;   M-x knayawp-layout-setup   — create the layout for the current project
;;   M-x knayawp-layout-teardown — remove the control pane
;;
;; Suggested keybinding (not enforced — C-c LETTER is reserved for users):
;;   (global-set-key (kbd "C-c k") knayawp-command-map)

;;; Code:

(require 'project)
(require 'seq)

(eval-when-compile
  (require 'cl-lib))

;; Silence byte-compiler about external functions and variables.
;; These are only called after their respective `require' succeeds.
(defvar vterm-shell)
(defvar vterm-buffer-name)
(declare-function vterm-mode "vterm")
(defvar eat-buffer-name)
(declare-function eat "eat")
(declare-function magit-status-setup-buffer "magit-status")

;;;; Customization group

(defgroup knayawp nil
  "Project-oriented window layouts."
  :group 'frames
  :prefix "knayawp-")

;;;; User options

(defcustom knayawp-right-width 0.4
  "Width of the right control pane as a frame fraction."
  :type 'float
  :group 'knayawp)

(defcustom knayawp-claude-command "claude"
  "CLI command for Claude Code."
  :type 'string
  :group 'knayawp)

(defcustom knayawp-terminal-backend 'vterm
  "Terminal emulator backend for shell and Claude panels."
  :type '(choice (const :tag "vterm (libvterm, C)" vterm)
                 (const :tag "eat (pure Elisp)" eat))
  :group 'knayawp)

(defcustom knayawp-panels
  '((magit  :slot -1 :height 0.33)
    (vterm  :slot  0 :height 0.33)
    (claude :slot  1 :height 0.34))
  "Panel specifications for the control pane.
Each entry is (TYPE . PLIST) where TYPE is a symbol and PLIST
contains :slot (integer for side window ordering) and :height
\(float for window height as frame fraction)."
  :type '(alist :key-type symbol
                :value-type (plist :key-type keyword
                                   :value-type number))
  :group 'knayawp)

;;;; Internal state

(defvar knayawp--active-layouts nil
  "Alist of (PROJECT-ROOT . BUFFER-ALIST) for active layouts.
Each BUFFER-ALIST maps panel types to their buffers.")

;;;; Project detection

(defun knayawp--project-root ()
  "Return the root directory of the current project.
Signal a `user-error' if no project is found."
  (if-let* ((proj (project-current)))
      (project-root proj)
    (user-error "No project found at current location")))

(defun knayawp--project-name (project-root)
  "Derive a short project name from PROJECT-ROOT."
  (file-name-nondirectory (directory-file-name project-root)))

;;;; Buffer naming

(defun knayawp--buffer-name (type project-name)
  "Return the buffer name for panel TYPE in PROJECT-NAME.
Format: *knayawp-TYPE-PROJECT-NAME*."
  (format "*knayawp-%s-%s*" type project-name))

;;;; Panel spec parsing

(defun knayawp--panel-slot (panel-spec)
  "Return the :slot value from PANEL-SPEC."
  (plist-get (cdr panel-spec) :slot))

(defun knayawp--panel-height (panel-spec)
  "Return the :height value from PANEL-SPEC."
  (plist-get (cdr panel-spec) :height))

(defun knayawp--panel-type (panel-spec)
  "Return the type symbol from PANEL-SPEC."
  (car panel-spec))

;;;; Terminal backend dispatch

(defun knayawp--make-terminal (name directory &optional command)
  "Create a terminal buffer NAME in DIRECTORY.
If COMMAND is non-nil, run it instead of the default shell.
Dispatch to the backend selected by `knayawp-terminal-backend'."
  (let ((default-directory (file-name-as-directory directory)))
    (pcase knayawp-terminal-backend
      ('vterm (knayawp--make-terminal-vterm name directory command))
      ('eat (knayawp--make-terminal-eat name directory command))
      (_ (user-error "Unknown terminal backend: %s"
                     knayawp-terminal-backend)))))

(defun knayawp--make-terminal-vterm (name directory &optional command)
  "Create a vterm buffer named NAME in DIRECTORY.
If COMMAND is non-nil, run it instead of the default shell."
  (unless (require 'vterm nil t)
    (user-error "Package vterm is not installed"))
  (let* ((default-directory (file-name-as-directory directory))
         (vterm-shell (or command vterm-shell))
         (vterm-buffer-name name)
         (buf (get-buffer-create name)))
    (with-current-buffer buf
      (unless (derived-mode-p 'vterm-mode)
        (vterm-mode)))
    buf))

(defun knayawp--make-terminal-eat (name directory &optional command)
  "Create an eat buffer named NAME in DIRECTORY.
If COMMAND is non-nil, run it instead of the default shell."
  (unless (require 'eat nil t)
    (user-error "Package eat is not installed"))
  (let* ((default-directory (file-name-as-directory directory))
         (eat-buffer-name name))
    (save-window-excursion
      (if command
          (eat command)
        (eat)))
    (get-buffer name)))

;;;; Buffer creation helpers

(defun knayawp--get-or-create-magit-buffer (project-root)
  "Return a magit-status buffer for PROJECT-ROOT.
Create one if it does not already exist.  If magit is not
available, return an informational placeholder buffer."
  (let ((project-name (knayawp--project-name project-root)))
    (if (require 'magit nil t)
        (progn
          ;; Check for existing magit-status buffer for this project
          (or (seq-find
               (lambda (buf)
                 (with-current-buffer buf
                   (and (derived-mode-p 'magit-status-mode)
                        (string= default-directory
                                 (file-name-as-directory project-root)))))
               (buffer-list))
              ;; Create a new magit-status buffer
              (let ((default-directory
                     (file-name-as-directory project-root)))
                (save-window-excursion
                  (magit-status-setup-buffer
                   (file-name-as-directory project-root)))
                ;; Find the buffer magit just created
                (seq-find
                 (lambda (buf)
                   (with-current-buffer buf
                     (and (derived-mode-p 'magit-status-mode)
                          (string= default-directory
                                   (file-name-as-directory
                                    project-root)))))
                 (buffer-list)))))
      ;; Graceful degradation: magit not available
      (let* ((buf-name (knayawp--buffer-name 'magit project-name))
             (buf (get-buffer-create buf-name)))
        (with-current-buffer buf
          (unless (> (buffer-size) 0)
            (insert "magit is not installed.\n\n"
                    "Install magit to use the version control panel.\n"
                    "  M-x package-install RET magit RET\n")))
        buf))))

(defun knayawp--get-or-create-vterm-buffer (project-root project-name)
  "Return a terminal buffer for PROJECT-ROOT named after PROJECT-NAME.
Create one via `knayawp--make-terminal' if needed."
  (let ((buf-name (knayawp--buffer-name 'vterm project-name)))
    (or (get-buffer buf-name)
        (knayawp--make-terminal buf-name project-root))))

(defun knayawp--get-or-create-claude-buffer (project-root project-name)
  "Return a Claude Code buffer for PROJECT-ROOT.
PROJECT-NAME is used for the buffer name.  Create one via
`knayawp--make-terminal' with `knayawp-claude-command'."
  (let ((buf-name (knayawp--buffer-name 'claude project-name)))
    (or (get-buffer buf-name)
        (knayawp--make-terminal buf-name project-root
                                knayawp-claude-command))))

;;;; Buffer-to-panel dispatch

(defun knayawp--create-panel-buffer (type project-root project-name)
  "Create or reuse the buffer for panel TYPE.
PROJECT-ROOT is the project directory, PROJECT-NAME its short name."
  (pcase type
    ('magit (knayawp--get-or-create-magit-buffer project-root))
    ('vterm (knayawp--get-or-create-vterm-buffer
             project-root project-name))
    ('claude (knayawp--get-or-create-claude-buffer
              project-root project-name))
    (_ (user-error "Unknown panel type: %s" type))))

;;;; Layout engine

;;;###autoload
(defun knayawp-layout-setup ()
  "Set up the knayawp project layout in the current frame.
Create three side windows on the right (magit, terminal, Claude
Code) for the project at point.  The editor pane remains on the
left and is selected when done."
  (interactive)
  (let* ((project-root (knayawp--project-root))
         (project-name (knayawp--project-name project-root))
         (buffer-alist nil))
    ;; Allow 3 side windows on the right
    (setq window-sides-slots '(nil nil nil 3))
    ;; Create and display each panel
    (dolist (panel-spec knayawp-panels)
      (let* ((type (knayawp--panel-type panel-spec))
             (slot (knayawp--panel-slot panel-spec))
             (height (knayawp--panel-height panel-spec))
             (buf (knayawp--create-panel-buffer
                   type project-root project-name)))
        (when buf
          (push (cons type buf) buffer-alist)
          (display-buffer-in-side-window
           buf
           `((side . right)
             (slot . ,slot)
             (window-width . ,knayawp-right-width)
             (window-height . ,height)
             (preserve-size . (t . nil))
             (window-parameters
              . ((no-delete-other-windows . t)
                 (no-other-window . t))))))))
    ;; Record the layout
    (setf (alist-get project-root knayawp--active-layouts
                     nil nil #'equal)
          (nreverse buffer-alist))
    ;; Select the main editor window
    (knayawp--select-editor-window)))

(defun knayawp-layout-teardown ()
  "Remove the knayawp control pane from the current frame.
Delete all side windows but do not kill their buffers."
  (interactive)
  (let ((side-windows (knayawp--side-windows)))
    (dolist (win side-windows)
      (delete-window win))))

;;;; Window utilities

(defun knayawp--side-windows ()
  "Return a list of all side windows in the current frame."
  (seq-filter
   (lambda (win)
     (window-parameter win 'window-side))
   (window-list)))

(defun knayawp--select-editor-window ()
  "Select the main editor window (non-side-window)."
  (let ((editor-win
         (seq-find
          (lambda (win)
            (not (window-parameter win 'window-side)))
          (window-list))))
    (when editor-win
      (select-window editor-win))))

;;;; Command map

(defvar knayawp-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map "l" #'knayawp-layout-setup)
    (define-key map "q" #'knayawp-layout-teardown)
    map)
  "Keymap for knayawp commands.
Bind this to a prefix key of your choice, for example:
  (global-set-key (kbd \"C-c k\") knayawp-command-map)")

(fset 'knayawp-command-map knayawp-command-map)

(provide 'knayawp)
;;; knayawp.el ends here
