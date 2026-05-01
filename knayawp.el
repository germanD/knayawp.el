;;; knayawp.el --- Project-oriented window layouts for Emacs -*- lexical-binding: t; -*-

;; Author: Germán Carrillo
;; Version: 0.1.2
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
(defvar magit-display-buffer-function)
(declare-function magit-display-buffer-traditional "magit-mode")

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

(defcustom knayawp-magit-commit-in-editor-flag t
  "Non-nil means show COMMIT_EDITMSG in the editor pane.
When nil, commit message buffers follow default `display-buffer'
behavior."
  :type 'boolean
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

(defvar knayawp--zoomed-panel nil
  "Panel type symbol currently zoomed, or nil if not zoomed.")

(defvar knayawp--magit-saved-display-fn nil
  "Saved value of `magit-display-buffer-function'.")

(defvar knayawp--commit-display-entry nil
  "The `display-buffer-alist' entry for COMMIT_EDITMSG routing.
Stored so it can be cleanly removed on teardown.")

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
  (let ((project-name (knayawp--project-name project-root))
        (dir (file-name-as-directory project-root)))
    (if (require 'magit nil t)
        ;; Check for existing magit-status buffer for this project,
        ;; then create one if needed.  Use file-equal-p for comparison
        ;; because project.el and magit may resolve paths differently
        ;; (e.g., symlinks, bind mounts).
        (or (seq-find
             (lambda (buf)
               (with-current-buffer buf
                 (and (derived-mode-p 'magit-status-mode)
                      (file-equal-p default-directory dir))))
             (buffer-list))
            (save-window-excursion
              (magit-status-setup-buffer dir)))
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

;;;; Magit integration

(defun knayawp--magit-display-buffer (buffer)
  "Display magit BUFFER in the knayawp magit side window.
If the magit side window does not exist, fall back to the
previously active `magit-display-buffer-function'."
  (let* ((magit-spec (assq 'magit knayawp-panels))
         (magit-win (when magit-spec
                      (knayawp--side-window-for-slot
                       (knayawp--panel-slot magit-spec)))))
    (if (not magit-win)
        ;; No layout active — use saved function or traditional
        (let ((fallback (or knayawp--magit-saved-display-fn
                            #'magit-display-buffer-traditional)))
          (funcall fallback buffer))
      ;; Display in the magit side window via display-buffer-in-side-window
      ;; so quit-restore is set up correctly for magit's `q' binding.
      (display-buffer-in-side-window
       buffer
       `((side . right)
         (slot . ,(knayawp--panel-slot magit-spec))
         (window-width . ,knayawp-right-width)
         (preserve-size . (t . nil))
         (window-parameters
          . ((no-delete-other-windows . t)
             (no-other-window . t))))))))

(defun knayawp--setup-magit-integration ()
  "Install magit buffer display integration.
Save the current `magit-display-buffer-function' and replace it
with `knayawp--magit-display-buffer'.  If
`knayawp-magit-commit-in-editor-flag' is non-nil, add a
`display-buffer-alist' entry to route COMMIT_EDITMSG to the
editor pane."
  (when (require 'magit nil t)
    ;; Guard against double-setup: only save the original function
    ;; if we haven't already installed ours.
    (unless (eq magit-display-buffer-function
                #'knayawp--magit-display-buffer)
      (setq knayawp--magit-saved-display-fn
            magit-display-buffer-function)
      (setq magit-display-buffer-function
            #'knayawp--magit-display-buffer))
    (when (and knayawp-magit-commit-in-editor-flag
               (not knayawp--commit-display-entry))
      (setq knayawp--commit-display-entry
            '("COMMIT_EDITMSG"
              (display-buffer-reuse-window
               display-buffer-use-some-window)
              (reusable-frames . visible)
              (inhibit-same-window . t)))
      (push knayawp--commit-display-entry display-buffer-alist))))

(defun knayawp--teardown-magit-integration ()
  "Remove magit buffer display integration.
Restore the saved `magit-display-buffer-function' and remove the
COMMIT_EDITMSG `display-buffer-alist' entry."
  (when knayawp--magit-saved-display-fn
    (setq magit-display-buffer-function
          knayawp--magit-saved-display-fn)
    (setq knayawp--magit-saved-display-fn nil))
  (when knayawp--commit-display-entry
    (setq display-buffer-alist
          (delq knayawp--commit-display-entry display-buffer-alist))
    (setq knayawp--commit-display-entry nil)))

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
    ;; Install magit integration
    (knayawp--setup-magit-integration)
    ;; Select the main editor window
    (knayawp--select-editor-window)))

(defun knayawp-layout-teardown ()
  "Remove the knayawp control pane from the current frame.
Delete all side windows but do not kill their buffers."
  (interactive)
  (knayawp--teardown-magit-integration)
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

;;;; Panel navigation helpers

(defun knayawp--side-window-for-slot (slot)
  "Return the side window occupying SLOT, or nil."
  (seq-find
   (lambda (win)
     (eq slot (window-parameter win 'window-slot)))
   (knayawp--side-windows)))

(defun knayawp--panel-spec-at-index (n)
  "Return the Nth panel spec from `knayawp-panels' (0-based)."
  (nth n knayawp-panels))

(defun knayawp--current-panel-index ()
  "Return the index into `knayawp-panels' for the selected window.
Return nil if the selected window is not a side window."
  (let ((slot (window-parameter (selected-window) 'window-slot)))
    (when slot
      (cl-position slot knayawp-panels
                   :test (lambda (s spec)
                           (eq s (knayawp--panel-slot spec)))))))

;;;; Panel navigation commands

(defun knayawp-select-panel (n)
  "Select the Nth panel (1-indexed).
Panel 1 is the first entry in `knayawp-panels' (magit by default),
panel 2 is the second (vterm), panel 3 is the third (claude)."
  (interactive "nPanel number (1-3): ")
  (let* ((idx (1- n))
         (spec (knayawp--panel-spec-at-index idx)))
    (unless spec
      (user-error "No panel %d (only %d panels configured)"
                  n (length knayawp-panels)))
    (let ((win (knayawp--side-window-for-slot
                (knayawp--panel-slot spec))))
      (unless win
        (user-error "Panel %d (%s) has no window — run layout-setup first"
                    n (knayawp--panel-type spec)))
      (select-window win))))

(defun knayawp-select-editor ()
  "Select the main editor window."
  (interactive)
  (knayawp--select-editor-window))

(defun knayawp-next-panel ()
  "Cycle to the next panel in the control pane.
If in the editor pane, jump to the first panel."
  (interactive)
  (let* ((idx (knayawp--current-panel-index))
         (len (length knayawp-panels))
         (next (if idx (mod (1+ idx) len) 0)))
    (knayawp-select-panel (1+ next))))

(defun knayawp-prev-panel ()
  "Cycle to the previous panel in the control pane.
If in the editor pane, jump to the last panel."
  (interactive)
  (let* ((idx (knayawp--current-panel-index))
         (len (length knayawp-panels))
         (prev (if idx (mod (1- idx) len) (1- len))))
    (knayawp-select-panel (1+ prev))))

(defun knayawp-toggle-panels ()
  "Toggle visibility of all side windows."
  (interactive)
  (window-toggle-side-windows))

(defun knayawp-zoom-panel ()
  "Zoom the current panel to fill the right column.
If already zoomed, restore all panels.  Must be called from
a side window."
  (interactive)
  (if knayawp--zoomed-panel
      ;; Unzoom: restore the full layout
      (let* ((project-root (knayawp--project-root))
             (buffer-alist (alist-get project-root
                                      knayawp--active-layouts
                                      nil nil #'equal)))
        (dolist (panel-spec knayawp-panels)
          (let* ((type (knayawp--panel-type panel-spec))
                 (slot (knayawp--panel-slot panel-spec))
                 (height (knayawp--panel-height panel-spec))
                 (buf (alist-get type buffer-alist)))
            (when (and buf (buffer-live-p buf))
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
        ;; Select the panel that was zoomed
        (let* ((spec (seq-find
                      (lambda (s)
                        (eq knayawp--zoomed-panel
                            (knayawp--panel-type s)))
                      knayawp-panels))
               (win (when spec
                      (knayawp--side-window-for-slot
                       (knayawp--panel-slot spec)))))
          (when win (select-window win)))
        (setq knayawp--zoomed-panel nil))
    ;; Zoom: delete all other side windows
    (let ((idx (knayawp--current-panel-index)))
      (unless idx
        (user-error "Not in a panel — select a panel first"))
      (let ((current-slot (window-parameter (selected-window)
                                            'window-slot))
            (current-type (knayawp--panel-type
                           (knayawp--panel-spec-at-index idx))))
        (dolist (win (knayawp--side-windows))
          (unless (eq (window-parameter win 'window-slot)
                      current-slot)
            (delete-window win)))
        (setq knayawp--zoomed-panel current-type)))))

;;;; Command map

(defvar knayawp-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map "l" #'knayawp-layout-setup)
    (define-key map "q" #'knayawp-layout-teardown)
    (define-key map "1" (lambda () (interactive) (knayawp-select-panel 1)))
    (define-key map "2" (lambda () (interactive) (knayawp-select-panel 2)))
    (define-key map "3" (lambda () (interactive) (knayawp-select-panel 3)))
    (define-key map "n" #'knayawp-next-panel)
    (define-key map "p" #'knayawp-prev-panel)
    (define-key map "z" #'knayawp-zoom-panel)
    (define-key map "0" #'knayawp-select-editor)
    (define-key map "s" #'knayawp-toggle-panels)
    map)
  "Keymap for knayawp commands.
Bind this to a prefix key of your choice, for example:
  (global-set-key (kbd \"C-c k\") knayawp-command-map)")

(fset 'knayawp-command-map knayawp-command-map)

(provide 'knayawp)
;;; knayawp.el ends here
