;;; knayawp.el --- Project-oriented window layouts for Emacs -*- lexical-binding: t; -*-

;; Author: Germán Andrés Delbianco <knayawp@proton.me>
;; Maintainer: Germán Andrés Delbianco <knayawp@proton.me>
;; Version: 0.1.3
;; Package-Requires: ((emacs "29.1") (magit "3.0"))
;; Keywords: frames, convenience
;; URL: https://github.com/germanD/knayawp.el

;; Copyright (C) 2026 Germán Andrés Delbianco <knayawp@proton.me>

;; SPDX-License-Identifier: MIT

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
(declare-function vterm-copy-mode "vterm")
(declare-function vterm-yank "vterm")
(defvar eat-buffer-name)
(declare-function eat "eat")
(declare-function eat-emacs-mode "eat")
(declare-function eat-send-string "eat")
(declare-function magit-status-setup-buffer "magit-status")
(defvar magit-display-buffer-function)
(declare-function magit-display-buffer-traditional "magit-mode")
(defvar git-commit-setup-hook)
(defvar with-editor-post-finish-hook)
(defvar with-editor-post-cancel-hook)
(defvar server-switch-hook)
(declare-function magit-mode-get-buffer "magit-mode")

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

(defcustom knayawp-min-editor-columns 40
  "Minimum number of columns required for the editor pane.
`knayawp-layout-setup' computes the columns consumed by the right
pane as round(frame-width * `knayawp-right-width') and checks
that the remaining columns are at least this value.  When the
frame is too narrow the side windows are skipped and a warning is
issued rather than creating an unusably cramped layout."
  :type 'integer
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
behavior.

Obsolete: prefer `knayawp-magit-commit-style'.  When the user has
not explicitly customized that new option (it is still at the
default `zoom'), this flag is honored via a one-shot shim:
non-nil maps to `editor' and nil maps to `off'."
  :type 'boolean
  :group 'knayawp)

(make-obsolete-variable
 'knayawp-magit-commit-in-editor-flag
 "Use `knayawp-magit-commit-style' instead.
Mapping: t -> `editor', nil -> `off'."
 "0.1.4")

(defcustom knayawp-magit-commit-style 'zoom
  "Strategy for displaying magit commit-message buffers.

`zoom' (the default) collapses the right column to just the magit
side window and displays COMMIT_EDITMSG inside it; on commit
finish or cancel the 3-panel layout is restored automatically.

`editor' is the v0.1.3 behavior: COMMIT_EDITMSG is routed to the
editor pane while the diff lands in the magit slot.

`off' disables all special commit handling — no
`display-buffer-alist' entry for COMMIT_EDITMSG, no commit hooks.
Useful for users with their own magit display function.

Changing this value at runtime affects future commit sessions
only; an in-progress commit completes under the style it was
started with.  When the magit integration is currently active
\(i.e. a knayawp layout has been set up), setting this option via
\\[customize-option], `setopt', or `customize-set-variable'
triggers an immediate reconcile: hooks and `display-buffer-alist'
entries from the previous style are removed and those for the
new style are installed.  Plain `setq' bypasses the `:set' form
\(standard Emacs behavior); after a `setq', call
\\[knayawp-layout-setup] to apply the new style.

The `zoom' value requires `knayawp-layout-setup' to have been
called: zoom is a no-op without an active layout.  The other two
values are also no-ops without the layout."
  :type '(choice (const :tag "Zoom magit slot during commit" zoom)
                 (const :tag "Pop COMMIT_EDITMSG to editor pane" editor)
                 (const :tag "Default magit display (no special handling)"
                        off))
  :set (lambda (sym val)
         (set-default sym val)
         ;; Reconcile commit-style state only when the magit
         ;; integration is currently installed; otherwise the new
         ;; value is picked up by the next `knayawp-layout-setup'.
         ;; `fboundp' guard tolerates a `setopt' issued before
         ;; the rest of the file has finished loading.
         (when (and (fboundp 'knayawp--reconcile-commit-style)
                    (boundp 'magit-display-buffer-function)
                    (eq magit-display-buffer-function
                        #'knayawp--magit-display-buffer))
           (knayawp--reconcile-commit-style)))
  :group 'knayawp)

(defcustom knayawp-magit-commit-focus-after 'editor
  "Window to select after a commit finishes or is canceled.

`editor' (the default) selects the editor pane, consistent with
`knayawp-select-editor' and with the idea that magit and the
terminals are visited briefly from the editor.

`magit' selects the magit side window if one exists.

`previous' restores focus to the window that was selected before
the commit was initiated (captured in
`knayawp--commit-pre-state').

Only consulted by the `zoom' commit style; the `editor' and `off'
styles do not place focus on commit end."
  :type '(choice (const :tag "Editor pane" editor)
                 (const :tag "Magit side window" magit)
                 (const :tag "Window selected before commit" previous))
  :group 'knayawp)

(defcustom knayawp-isolate-other-window-flag t
  "Non-nil means `other-window' skips knayawp side windows.
When non-nil (the default), each knayawp side window carries the
`no-other-window' parameter, so `C-x o' cycles only between the
editor pane and other non-side windows.  When nil, the parameter
is omitted and `C-x o' walks into the side windows like any other
window — useful for users who prefer plain cycling over isolation.

Changing this value at runtime only affects newly created
layouts: existing side windows keep the parameter they were built
with.  Toggle the flag and run \\[knayawp-layout-setup] again
\(or tear down and re-create the layout) for the change to take
effect everywhere."
  :type 'boolean
  :group 'knayawp)

(defcustom knayawp-keymap-style 'default
  "Keybinding style for the variable `knayawp-command-map'.
The same set of commands is bound under every style; only the
keys differ.

`default' uses numbered keys (1/2/3) and n/p for panel
navigation.  This is the historical layout and the safest choice
for users on terminals without arrow-key support.

`tmux' adds arrow-key navigation inspired by tmux pane bindings:
<up>/<down> select the previous/next panel within the control
pane, while <left>/<right> are reserved for previous/next project
tab (wired in v0.2).  All numbered and letter keys remain bound
as a fallback.

`byobu' adds shift-arrow navigation inspired by byobu's
Shift-Function-arrow window bindings: S-<up>/S-<down> select the
previous/next panel and S-<left>/S-<right> are reserved for
previous/next project tab (wired in v0.2).  All numbered and
letter keys remain bound as a fallback.

Changing this value via \\[customize-option], `setopt', or
`customize-set-variable' automatically rebuilds the variable
`knayawp-command-map' in place.  Plain `setq' bypasses the `:set'
form (standard Emacs behavior); after a `setq', call
\\[knayawp-rebuild-command-map] to apply the new style."
  :type '(choice (const :tag "Default (1/2/3, n/p)" default)
                 (const :tag "tmux (arrow keys)" tmux)
                 (const :tag "byobu (shift-arrow keys)" byobu))
  :set (lambda (sym val)
         (set-default sym val)
         ;; Rebuild the keymap in place only when the map object
         ;; already exists.  The `fboundp' guard lets this `:set'
         ;; form tolerate being called during initial file load,
         ;; before `knayawp-rebuild-command-map' is defined.
         (when (and (fboundp 'knayawp-rebuild-command-map)
                    (boundp 'knayawp-command-map))
           (knayawp-rebuild-command-map)))
  :group 'knayawp)

(defcustom knayawp-panels
  '((magit  :slot -1 :height 0.34)
    (vterm  :slot  0 :height 0.33)
    (claude :slot  1 :height 0.33))
  "Panel specifications for the control pane.
Each entry is (TYPE PLIST...) where TYPE is a symbol and the
plist may contain:

  :slot    (integer) Side-window slot number for ordering.
  :height  (float)   Fraction of the right-column height to
                     allocate to this panel.  Values should sum
                     to 1.0 across all panels.  Fractions are
                     applied via `window-height' on initial
                     window creation; resizing an already-created
                     window only works before `preserve-size' is
                     set on it.  Consequently, changing :height
                     values takes effect only after a full
                     teardown and re-setup of the layout.

When :height is omitted for a panel, slots are equalised via
`balance-windows' instead of honoring the per-panel fraction."
  :type '(alist :key-type symbol
                :value-type (plist :key-type keyword
                                   :value-type sexp))
  :set (lambda (sym val)
         (set-default sym val)
         ;; Re-install panel routing when the mode is active so the new
         ;; slot/type configuration is reflected in `display-buffer-alist'
         ;; immediately.  Guard with fboundp for the load-order edge case
         ;; where the :set form fires before the rest of the file has been
         ;; evaluated (P7: passive-loading discipline preserved — the
         ;; install is gated on the mode already being on, not on the
         ;; mere act of setting the option).
         (when (and (bound-and-true-p knayawp-mode)
                    (fboundp 'knayawp--remove-panel-display-routing)
                    (fboundp 'knayawp--install-panel-display-routing))
           (knayawp--remove-panel-display-routing)
           (knayawp--install-panel-display-routing)))
  :group 'knayawp)

(defcustom knayawp-winner-integration-flag t
  "Non-nil means save window history via `winner-mode' on teardown.
When non-nil (the default) and `winner-mode' is active,
`knayawp-layout-teardown' calls `winner-save-conditionally'
before deleting the side windows so the layout is added to the
`winner-mode' ring and `winner-undo' can restore it.

This flag is only consulted when `winner-mode' is actually on;
it does not activate or load `winner' on its own, preserving the
passive-loading invariant (property P7)."
  :type 'boolean
  :group 'knayawp)

(defcustom knayawp-layout-hook nil
  "Hook run after `knayawp-layout-setup' creates the layout.
Functions on this hook are called with no arguments, after all
panels have been displayed and the editor window has been
selected.  At that point the layout is fully constructed, so
hook functions see the final window configuration."
  :type 'hook
  :group 'knayawp)

;;;; Internal state

(defvar knayawp--active-layouts nil
  "Alist of (PROJECT-ROOT . BUFFER-ALIST) for active layouts.
Each BUFFER-ALIST maps panel types to their buffers.")

(defvar knayawp--zoomed-panel nil
  "Panel type symbol currently zoomed, or nil if not zoomed.")

(defvar knayawp--commit-pre-state nil
  "Plist describing the layout state captured when a commit started.
Nil when no commit-zoom session is active.  Otherwise a plist with
keys:

  :active            Non-nil while the commit-zoom flow is in effect.
  :was-zoomed        Panel type symbol if a manual zoom was already
                     active, else nil.  Used to avoid double-zoom.
  :prior-magit-buf   Buffer that was displayed in the magit slot
                     before the commit started (defensive marker).
  :commit-buffer     The COMMIT_EDITMSG buffer placed in the magit
                     slot when the zoom started.  Re-selected by the
                     `server-switch-hook' handler so it survives the
                     `magit-commit-diff-while-committing' race.
  :pre-commit-window Window selected when the commit was initiated;
                     consulted when `knayawp-magit-commit-focus-after'
                     is `previous'.")

(defvar knayawp--editor-window nil
  "Window selected as the editor pane when the layout was created.
Captured by `knayawp-layout-setup' so the `editor' commit style
can route COMMIT_EDITMSG to a specific window rather than to
whichever non-side window happens to be available.")

(defvar knayawp--magit-saved-display-fn nil
  "Saved value of `magit-display-buffer-function'.")

(defvar knayawp--commit-display-entry nil
  "The `display-buffer-alist' entry for COMMIT_EDITMSG routing.
Stored so it can be cleanly removed on teardown.")

(defvar knayawp--process-display-entry nil
  "The `display-buffer-alist' entry for `magit-process-mode' routing.
Stored so it can be cleanly removed on teardown.")

(defvar knayawp--panel-display-entries nil
  "List of `display-buffer-alist' entries for knayawp panel buffers.
Each entry routes buffers named `*knayawp-TYPE-*' to the side window
slot configured for TYPE in `knayawp-panels'.  Stored so the entries
can be removed precisely on `knayawp-mode' deactivation.")

(defvar knayawp--frame-widths nil
  "Alist of (FRAME . FRAME-WIDTH) recording last known frame widths.
Used by `knayawp--restore-right-width-on-resize' to distinguish
external frame-size changes (where we re-apply `knayawp-right-width')
from intra-frame window resizes (where we leave the user's choice
alone).")

(defvar knayawp--commit-hooks-installed nil
  "Non-nil when the commit-flow hooks are registered.
Set by `knayawp--install-commit-hooks' and cleared by
`knayawp--remove-commit-hooks' so install/remove are idempotent.")

(defvar knayawp--commit-style-shim-warned nil
  "Non-nil after the obsolescence-shim message has been emitted.
The shim that bridges `knayawp-magit-commit-in-editor-flag' and
`knayawp-magit-commit-style' messages the user once per Emacs
session.  This flag is also used by ERT to reset between tests.")

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
  "Return the :height value from PANEL-SPEC, or nil if absent."
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

;;;; Terminal copy/paste dispatch

(defun knayawp--make-terminal-copy-mode-vterm (window)
  "Enter vterm copy mode in WINDOW."
  (with-selected-window window
    (vterm-copy-mode 1)))

(defun knayawp--make-terminal-copy-mode-eat (window)
  "Enter eat Emacs mode in WINDOW, allowing text selection."
  (with-selected-window window
    (eat-emacs-mode)))

(defun knayawp--make-terminal-yank-vterm (window)
  "Yank `kill-ring' head into vterm WINDOW."
  (with-selected-window window
    (vterm-yank)))

(defun knayawp--make-terminal-yank-eat (window)
  "Yank `kill-ring' head into eat WINDOW."
  (with-selected-window window
    (when-let* ((text (current-kill 0 t)))
      (eat-send-string (get-buffer-process (current-buffer)) text))))

(defun knayawp--terminal-panel-windows ()
  "Return side windows for terminal panels (vterm and claude).
Panel types are those that are not `magit' in `knayawp-panels';
their windows are looked up by slot.  Windows that no longer exist
are silently omitted."
  (seq-filter
   #'identity
   (mapcar
    (lambda (spec)
      (unless (eq (knayawp--panel-type spec) 'magit)
        (knayawp--side-window-for-slot (knayawp--panel-slot spec))))
    knayawp-panels)))

(defun knayawp--active-terminal-window ()
  "Return the most suitable terminal panel window.
If the currently selected window is a terminal panel, return it.
Otherwise return the first available terminal panel window.
Signal `user-error' when no terminal panel window exists."
  (let ((wins (knayawp--terminal-panel-windows)))
    (unless wins
      (user-error "No terminal panel window — run knayawp-layout-setup first"))
    (or (seq-find (lambda (w) (eq w (selected-window))) wins)
        (car wins))))

;;;; One-shot terminal copy/paste commands

(defun knayawp-terminal-copy-mode ()
  "Enter copy/scroll mode in the active terminal panel.
Selects the panel window and activates the backend's copy mode:
`vterm-copy-mode' for vterm, `eat-emacs-mode' for eat.  In copy
mode, standard Emacs motion and region commands work so the user
can select text and copy it to the kill ring."
  (interactive)
  (let ((win (knayawp--active-terminal-window)))
    (select-window win)
    (pcase knayawp-terminal-backend
      ('vterm (knayawp--make-terminal-copy-mode-vterm win))
      ('eat  (knayawp--make-terminal-copy-mode-eat win))
      (_ (user-error "Unknown terminal backend: %s"
                     knayawp-terminal-backend)))))

(defun knayawp-terminal-yank ()
  "Yank the `kill-ring' head into the active terminal panel.
The panel is selected and the top of the kill ring is sent to the
terminal process using the backend-appropriate paste command:
`vterm-yank' for vterm, `eat-send-string' for eat."
  (interactive)
  (let ((win (knayawp--active-terminal-window)))
    (select-window win)
    (pcase knayawp-terminal-backend
      ('vterm (knayawp--make-terminal-yank-vterm win))
      ('eat  (knayawp--make-terminal-yank-eat win))
      (_ (user-error "Unknown terminal backend: %s"
                     knayawp-terminal-backend)))))

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

;;;; Side window parameter helper

(defun knayawp--side-window-parameters ()
  "Return the `window-parameters' alist for knayawp side windows.
Always includes `no-delete-other-windows'; `no-other-window' is
included only when `knayawp-isolate-other-window-flag' is
non-nil."
  `((no-delete-other-windows . t)
    ,@(when knayawp-isolate-other-window-flag
        '((no-other-window . t)))))

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
         (window-parameters . ,(knayawp--side-window-parameters)))))))

(defun knayawp--magit-process-buffer-p (buffer-or-name _action)
  "Return non-nil if BUFFER-OR-NAME is a `magit-process-mode' buffer.
Used as a `display-buffer-alist' condition.  Only matches when a
knayawp magit side window currently exists in the selected frame,
so the routing is a no-op when no layout is active."
  (when-let* ((magit-spec (assq 'magit knayawp-panels))
              ((knayawp--side-window-for-slot
                (knayawp--panel-slot magit-spec))))
    (let ((buf (get-buffer buffer-or-name)))
      (and buf
           (with-current-buffer buf
             (derived-mode-p 'magit-process-mode))))))

(defun knayawp--resolve-commit-style ()
  "Return the effective `knayawp-magit-commit-style' value.
Honors the obsolescence shim from
`knayawp-magit-commit-in-editor-flag': when the user explicitly
customized the old flag and left the new option at its default
`zoom', map the old flag to `editor' / `off' and message once.
When both have been customized, the new variable wins (also
messaged once)."
  (let* ((style-customized
          (not (eq (default-value 'knayawp-magit-commit-style) 'zoom)))
         (old-customized
          (not (equal (default-value 'knayawp-magit-commit-in-editor-flag)
                      (eval (car (get 'knayawp-magit-commit-in-editor-flag
                                      'standard-value))
                            t)))))
    (cond
     ;; Old flag set, new option still default: honor the old flag.
     ((and old-customized (not style-customized))
      (unless knayawp--commit-style-shim-warned
        (setq knayawp--commit-style-shim-warned t)
        (message
         (concat "knayawp: `knayawp-magit-commit-in-editor-flag' is "
                 "obsolete; migrate to `knayawp-magit-commit-style'.")))
      (if knayawp-magit-commit-in-editor-flag 'editor 'off))
     ;; Both customized: new wins, note the override.
     ((and old-customized style-customized)
      (unless knayawp--commit-style-shim-warned
        (setq knayawp--commit-style-shim-warned t)
        (message
         (concat "knayawp: `knayawp-magit-commit-in-editor-flag' is "
                 "ignored because `knayawp-magit-commit-style' is set.")))
      knayawp-magit-commit-style)
     ;; Default path.
     (t knayawp-magit-commit-style))))

(defun knayawp--commit-flow-active-p ()
  "Return non-nil if a commit-zoom session is currently active."
  (and knayawp--commit-pre-state
       (plist-get knayawp--commit-pre-state :active)))

(defun knayawp--save-commit-pre-state (magit-slot &optional commit-buffer
                                                  winconf)
  "Capture pre-commit layout state into `knayawp--commit-pre-state'.
MAGIT-SLOT is the integer slot of the magit side window.
COMMIT-BUFFER, when non-nil, is the COMMIT_EDITMSG buffer that the
commit-flow will place in the magit slot; it is recorded so the
late `server-switch-hook' handler can re-select it after magit's
`magit-commit-diff-while-committing' pushes the diff on top.
WINCONF, when non-nil, is the window configuration captured by
`knayawp--commit-flow-start' *before* the zoom step ran; it is
the only snapshot that still contains the terminal and Claude
side windows, and `knayawp--restore-commit-pre-state' uses it to
override the stale layout that `with-editor' restored."
  (let* ((magit-win (knayawp--side-window-for-slot magit-slot))
         (prior-buf (and magit-win (window-buffer magit-win))))
    (setq knayawp--commit-pre-state
          (list :active            t
                :was-zoomed        knayawp--zoomed-panel
                :prior-magit-buf   prior-buf
                :commit-buffer     commit-buffer
                :pre-commit-window (selected-window)
                :winconf           winconf))))

(defun knayawp--focus-target-window ()
  "Return the window to select after a commit finishes or cancels.
Driven by `knayawp-magit-commit-focus-after'.  Falls back to the
editor pane when the requested target is not available."
  (pcase knayawp-magit-commit-focus-after
    ('editor
     (seq-find (lambda (win)
                 (not (window-parameter win 'window-side)))
               (window-list)))
    ('magit
     (let ((magit-spec (assq 'magit knayawp-panels)))
       (or (and magit-spec
                (knayawp--side-window-for-slot
                 (knayawp--panel-slot magit-spec)))
           (seq-find (lambda (win)
                       (not (window-parameter win 'window-side)))
                     (window-list)))))
    ('previous
     (let ((win (and knayawp--commit-pre-state
                     (plist-get knayawp--commit-pre-state
                                :pre-commit-window))))
       (if (and win (window-live-p win))
           win
         (seq-find (lambda (w)
                     (not (window-parameter w 'window-side)))
                   (window-list)))))
    (_
     (seq-find (lambda (win)
                 (not (window-parameter win 'window-side)))
               (window-list)))))

(defun knayawp--restore-commit-pre-state ()
  "Restore the pre-zoom layout, refresh the magit slot, place focus.
The `with-editor' restore that ran just before this function uses
`with-editor-previous-winconf', captured *after* our
`knayawp--git-commit-setup-handler' had already zoomed the
layout.  That snapshot therefore only contains the magit slot —
the terminal and Claude side windows are gone.  To get them back
we restore the winconf knayawp captured itself in
`knayawp--commit-flow-start' before the zoom step ran.

Four side-effects, in order:

1. When `:winconf' is present and its frame matches the selected
   frame, call `set-window-configuration' on it to reinstate the
   full 3-panel layout (fixes the round 3 bug: only one side
   window left after the commit-finish keybinding).

2. Reset `knayawp--zoomed-panel' to the saved `:was-zoomed' value
   so a subsequent commit can re-zoom (fixes Bug B: second commit
   in the same session did not zoom).

3. When the user was not in a manual zoom before the flow, replace
   whatever buffer the restored winconf left in the magit slot
   (typically `*magit-diff*' because `magit-commit-create' shows
   the diff synchronously before our setup handler captured the
   winconf) with the project's `magit-status' buffer (fixes Bug A).

4. Place focus according to `knayawp-magit-commit-focus-after'.

The magit-window lookup happens AFTER the winconf restore because
the pre-restore window tree contains only the zoomed slot, and
the post-restore lookup gives us the live window inside the
re-expanded layout."
  (let* ((was-zoomed (and knayawp--commit-pre-state
                          (plist-get knayawp--commit-pre-state
                                     :was-zoomed)))
         (winconf (and knayawp--commit-pre-state
                       (plist-get knayawp--commit-pre-state
                                  :winconf))))
    ;; (1) Restore the pre-zoom layout when the saved winconf still
    ;; belongs to the current frame.  Cross-frame restore would crash
    ;; or scramble the layout, so be conservative.
    (when (and winconf
               (window-configuration-p winconf)
               (eq (window-configuration-frame winconf)
                   (selected-frame)))
      (set-window-configuration winconf))
    ;; Magit-window and focus-target lookups MUST happen after the
    ;; restore: pre-restore the window tree is the zoomed one.
    (let* ((target (knayawp--focus-target-window))
           (magit-spec (assq 'magit knayawp-panels))
           (slot (and magit-spec (knayawp--panel-slot magit-spec)))
           (magit-win (and slot (knayawp--side-window-for-slot slot))))
      ;; (2) Restore the pre-flow zoom state (nil or the manual zoom
      ;; symbol the user had active before they ran `c c').
      (setq knayawp--zoomed-panel was-zoomed)
      ;; (3) Re-display magit-status in the magit slot, unless the
      ;; user was in a manual zoom (in which case the slot is theirs).
      (unless was-zoomed
        (when (and magit-win (window-live-p magit-win)
                   (fboundp 'magit-mode-get-buffer))
          (let ((status-buf (magit-mode-get-buffer 'magit-status-mode)))
            (when (and status-buf (buffer-live-p status-buf))
              (set-window-buffer magit-win status-buf)))))
      (setq knayawp--commit-pre-state nil)
      ;; (4) Place focus per `knayawp-magit-commit-focus-after'.
      (when (and target (window-live-p target))
        (select-window target)))))

(defun knayawp--apply-zoom-solo-magit ()
  "Zoom the layout down to just the magit side window.
Thin wrapper around the existing zoom machinery.  Kept as a
named entry point so the v0.3.0 layout-system refactor (issue
#70) is a one-function change."
  (let* ((magit-spec (assq 'magit knayawp-panels))
         (slot (and magit-spec (knayawp--panel-slot magit-spec)))
         (magit-win (and slot (knayawp--side-window-for-slot slot))))
    (when magit-win
      (dolist (win (knayawp--side-windows))
        (unless (eq (window-parameter win 'window-slot) slot)
          (delete-window win)))
      (setq knayawp--zoomed-panel (knayawp--panel-type magit-spec)))))

(defun knayawp--commit-flow-start ()
  "Enter the commit-zoom mode.
Capture the pre-zoom window configuration (so
`knayawp--restore-commit-pre-state' can reinstate the full
3-panel layout on finish) and the rest of the pre-commit state
into `knayawp--commit-pre-state', zoom the magit slot via
`knayawp--apply-zoom-solo-magit', and select the COMMIT_EDITMSG
buffer when the current buffer is a git-commit buffer.

The winconf capture must run BEFORE the zoom step: the zoom
deletes the terminal and Claude side windows, and we need a
snapshot that still contains them so the restore step can bring
them back.  `with-editor' captures its own winconf later (in
`with-editor-mode'), but by then the layout has already been
zoomed and that snapshot is useless for restoring the side
windows."
  (let* ((magit-spec (assq 'magit knayawp-panels))
         (slot (and magit-spec (knayawp--panel-slot magit-spec)))
         (commit-buf (current-buffer))
         (winconf (current-window-configuration)))
    (when slot
      (knayawp--save-commit-pre-state slot commit-buf winconf)
      ;; Skip the zoom step when a manual zoom is already active so
      ;; we don't clobber the user's preferred slot.
      (unless (plist-get knayawp--commit-pre-state :was-zoomed)
        (knayawp--apply-zoom-solo-magit))
      ;; Ensure the COMMIT_EDITMSG buffer is selected in the magit
      ;; slot.  `git-commit-setup-hook' runs with current-buffer
      ;; already set to COMMIT_EDITMSG, so reuse it.
      (let ((magit-win (knayawp--side-window-for-slot slot)))
        (when (and magit-win (window-live-p magit-win))
          (set-window-buffer magit-win commit-buf)
          (select-window magit-win))))))

(defun knayawp--commit-flow-end ()
  "Exit the commit-zoom mode.
Idempotent: if no commit-flow session is active, do nothing.
Otherwise clear the state plist and place focus per
`knayawp-magit-commit-focus-after'."
  (when (knayawp--commit-flow-active-p)
    (knayawp--restore-commit-pre-state)))

(defun knayawp--git-commit-setup-handler ()
  "Hook function for `git-commit-setup-hook'.
Activate the commit-zoom flow when (a) a knayawp layout is active
in the current frame, (b) `knayawp-magit-commit-style' resolves to
`zoom', and (c) no commit-flow session is already in progress."
  (let* ((magit-spec (assq 'magit knayawp-panels))
         (magit-win (and magit-spec
                         (knayawp--side-window-for-slot
                          (knayawp--panel-slot magit-spec)))))
    (when (and magit-win
               (eq (knayawp--resolve-commit-style) 'zoom)
               (not (knayawp--commit-flow-active-p)))
      (knayawp--commit-flow-start))))

(defun knayawp--with-editor-finish-handler ()
  "Hook function for `with-editor-post-finish-hook'.
Run `knayawp--commit-flow-end' when our flow is active."
  (knayawp--commit-flow-end))

(defun knayawp--with-editor-cancel-handler ()
  "Hook function for `with-editor-post-cancel-hook'.
Run `knayawp--commit-flow-end' when our flow is active."
  (knayawp--commit-flow-end))

(defun knayawp--server-switch-handler ()
  "Hook function for `server-switch-hook'.
Re-assert COMMIT_EDITMSG in the magit side window after the
emacsclient server switch completes.  Installed with the APPEND
flag so it runs after `magit-commit-diff-while-committing', which
otherwise lands `*magit-diff*' in the zoomed magit slot and steals
focus.  No-op unless a commit-flow session is active."
  (when (knayawp--commit-flow-active-p)
    (let* ((magit-spec (assq 'magit knayawp-panels))
           (slot (and magit-spec (knayawp--panel-slot magit-spec)))
           (magit-win (and slot (knayawp--side-window-for-slot slot)))
           (commit-buf (plist-get knayawp--commit-pre-state
                                  :commit-buffer)))
      (when (and magit-win
                 (window-live-p magit-win)
                 (buffer-live-p commit-buf))
        (set-window-buffer magit-win commit-buf)
        (select-window magit-win)))))

(defun knayawp--install-commit-hooks ()
  "Register knayawp's commit-flow handlers on the relevant hooks.
Idempotent.  Called from `knayawp--setup-magit-integration' when
the resolved commit style is `zoom'.  The `server-switch-hook'
entry is installed with APPEND so it runs after magit's own
`magit-commit-diff-while-committing', winning the focus race."
  (unless knayawp--commit-hooks-installed
    (add-hook 'git-commit-setup-hook
              #'knayawp--git-commit-setup-handler)
    (add-hook 'with-editor-post-finish-hook
              #'knayawp--with-editor-finish-handler)
    (add-hook 'with-editor-post-cancel-hook
              #'knayawp--with-editor-cancel-handler)
    (add-hook 'server-switch-hook
              #'knayawp--server-switch-handler t)
    (setq knayawp--commit-hooks-installed t)))

(defun knayawp--remove-commit-hooks ()
  "Unregister knayawp's commit-flow handlers.
Inverse of `knayawp--install-commit-hooks'.  Idempotent."
  (when knayawp--commit-hooks-installed
    (remove-hook 'git-commit-setup-hook
                 #'knayawp--git-commit-setup-handler)
    (remove-hook 'with-editor-post-finish-hook
                 #'knayawp--with-editor-finish-handler)
    (remove-hook 'with-editor-post-cancel-hook
                 #'knayawp--with-editor-cancel-handler)
    (remove-hook 'server-switch-hook
                 #'knayawp--server-switch-handler)
    (setq knayawp--commit-hooks-installed nil)))

(defun knayawp--commit-editmsg-display-function (buf action)
  "Display COMMIT_EDITMSG BUF in the recorded editor window.
When `knayawp--editor-window' is live and on the selected frame,
use it directly so the buffer lands in the same split the user
was editing in before opening magit.  The frame check keeps a
commit started on one frame from hijacking another frame's editor
window, since `knayawp--editor-window' is a single global.  Fall
back to `display-buffer-use-some-window' with the original ACTION
so the function always succeeds even when no layout is active."
  (if (and (window-live-p knayawp--editor-window)
           (eq (window-frame knayawp--editor-window) (selected-frame))
           (not (window-parameter knayawp--editor-window 'window-side)))
      (progn
        (set-window-buffer knayawp--editor-window buf)
        knayawp--editor-window)
    (display-buffer-use-some-window buf action)))

(defun knayawp--install-commit-display-entry ()
  "Install the COMMIT_EDITMSG `display-buffer-alist' entry.
Routes COMMIT_EDITMSG to `knayawp--editor-window' when that window
is live and not a side window, so the commit message always lands
in the editor pane even when it has been split.  Idempotent: if
the entry is already in place, do nothing."
  (unless knayawp--commit-display-entry
    (setq knayawp--commit-display-entry
          '("COMMIT_EDITMSG"
            (knayawp--commit-editmsg-display-function)))
    (push knayawp--commit-display-entry display-buffer-alist)))

(defun knayawp--remove-commit-display-entry ()
  "Remove the COMMIT_EDITMSG `display-buffer-alist' entry.
Inverse of `knayawp--install-commit-display-entry'.  Idempotent."
  (when knayawp--commit-display-entry
    (setq display-buffer-alist
          (delq knayawp--commit-display-entry display-buffer-alist))
    (setq knayawp--commit-display-entry nil)))

(defun knayawp--reconcile-commit-style ()
  "Make commit-style state match the resolved value.
Drop install bits left over from a previous resolved style, then
install bits for the current one.  Idempotent: safe to call when
the resolved style has not changed.

Without this, changing `knayawp-magit-commit-style' at runtime
leaves stale state behind — for example, switching from `zoom' to
`editor' would keep the `zoom' commit-flow hooks installed.  The
reconcile invariant is documented in `kb/properties.md' as P10."
  (let ((style (knayawp--resolve-commit-style)))
    ;; Remove what no longer applies under the resolved style.
    (unless (eq style 'editor)
      (knayawp--remove-commit-display-entry))
    (unless (eq style 'zoom)
      (knayawp--remove-commit-hooks))
    ;; Install what applies under the resolved style.
    (pcase style
      ('editor (knayawp--install-commit-display-entry))
      ('zoom   (knayawp--install-commit-hooks))
      ('off    nil))))

(defun knayawp--setup-magit-integration ()
  "Install magit buffer display integration.
Save the current `magit-display-buffer-function' and replace it
with `knayawp--magit-display-buffer'.  Reconcile commit-style
state via `knayawp--reconcile-commit-style' so the hooks and
`display-buffer-alist' entry match the current resolved value of
`knayawp-magit-commit-style'.  Always add the entry that pins
`magit-process-mode' buffers to the magit side window so
long-running git commands do not pop a window in the editor
pane."
  (when (require 'magit nil t)
    ;; Guard against double-setup: only save the original function
    ;; if we haven't already installed ours.
    (unless (eq magit-display-buffer-function
                #'knayawp--magit-display-buffer)
      (setq knayawp--magit-saved-display-fn
            magit-display-buffer-function)
      (setq magit-display-buffer-function
            #'knayawp--magit-display-buffer))
    (knayawp--reconcile-commit-style)
    (unless knayawp--process-display-entry
      (let ((slot (knayawp--panel-slot
                   (assq 'magit knayawp-panels))))
        (setq knayawp--process-display-entry
              `(knayawp--magit-process-buffer-p
                (display-buffer-in-side-window)
                (side . right)
                (slot . ,slot)
                (window-width . ,knayawp-right-width)
                (preserve-size . (t . nil))
                (window-parameters
                 . ,(knayawp--side-window-parameters))))
        (push knayawp--process-display-entry display-buffer-alist)))))

(defun knayawp--teardown-magit-integration ()
  "Remove magit buffer display integration.
Restore the saved `magit-display-buffer-function', remove the
COMMIT_EDITMSG and `magit-process-mode' `display-buffer-alist'
entries, and unregister the commit-flow hooks."
  (when knayawp--magit-saved-display-fn
    (setq magit-display-buffer-function
          knayawp--magit-saved-display-fn)
    (setq knayawp--magit-saved-display-fn nil))
  (knayawp--remove-commit-display-entry)
  (when knayawp--process-display-entry
    (setq display-buffer-alist
          (delq knayawp--process-display-entry display-buffer-alist))
    (setq knayawp--process-display-entry nil))
  (knayawp--remove-commit-hooks))

;;;; Layout engine

(defun knayawp--frame-wide-enough-p ()
  "Return non-nil when the frame is wide enough for the layout.
Computes the editor columns that would remain after the right pane
takes `knayawp-right-width' and checks they meet
`knayawp-min-editor-columns'."
  (let* ((right-cols (round (* (frame-width) knayawp-right-width)))
         (editor-cols (- (frame-width) right-cols)))
    (>= editor-cols knayawp-min-editor-columns)))

;;;###autoload
(defun knayawp-layout-setup ()
  "Set up the knayawp project layout in the current frame.
Create three side windows on the right (magit, terminal, Claude
Code) for the project at point.  The editor pane remains on the
left and is selected when done.
When the frame is too narrow (fewer than `knayawp-min-editor-columns'
columns remain for the editor after the right pane is allocated),
skip the side windows and issue a warning instead."
  (interactive)
  (if (knayawp--frame-wide-enough-p)
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
                 ;; :height is honoured only on initial window creation
                 ;; (Emacs side-window constraint: window-height has no
                 ;; effect on an already-existing window).  When the
                 ;; user omits :height, we equalise via balance-windows.
                 ,@(when height `((window-height . ,height)))
                 (preserve-size . (t . nil))
                 (window-parameters
                  . ,(knayawp--side-window-parameters)))))))
        ;; Apply heights: equalise when any panel omits :height.
        (unless (seq-every #'knayawp--panel-height knayawp-panels)
          (knayawp--balance-side-windows))
        ;; Record the layout
        (setf (alist-get project-root knayawp--active-layouts
                         nil nil #'equal)
              (nreverse buffer-alist))
        ;; Install magit integration
        (knayawp--setup-magit-integration)
        ;; Select the main editor window and record it for COMMIT_EDITMSG
        ;; routing so the `editor' commit style can target it precisely.
        (knayawp--select-editor-window)
        (setq knayawp--editor-window (selected-window))
        ;; Install the frame-resize watcher and seed the recorded width
        ;; for the current frame so the first hook firing is a no-op.
        (add-hook 'window-size-change-functions
                  #'knayawp--restore-right-width-on-resize)
        (setf (alist-get (selected-frame) knayawp--frame-widths)
              (frame-width (selected-frame)))
        ;; Run user hook last, so functions see the final state
        (run-hooks 'knayawp-layout-hook))
    ;; Narrow-frame guard: warn when the layout would leave the editor
    ;; pane too cramped to be usable.
    (message
     (concat "knayawp: frame too narrow for side windows "
             "(%d editor cols available, need >= %d); "
             "skipping layout setup")
     (- (frame-width)
        (round (* (frame-width) knayawp-right-width)))
     knayawp-min-editor-columns)))

(defun knayawp-layout-teardown ()
  "Remove the knayawp control pane from the current frame.
Delete all side windows but do not kill their buffers.  If a
commit-zoom session was active, discard its state and warn.
When `knayawp-winner-integration-flag' is non-nil and
`winner-mode' is active, save the current window configuration
to the `winner-mode' ring before tearing down so `winner-undo'
can restore the layout."
  (interactive)
  (when (knayawp--commit-flow-active-p)
    (setq knayawp--commit-pre-state nil)
    (message
     "knayawp: layout torn down during active commit; state cleared"))
  ;; Save to winner ring before deleting side windows, so the full
  ;; layout (including panels) enters the undo history.  Only when
  ;; the flag is on AND winner-mode is actually active — no-op
  ;; otherwise (P7: passive-loading discipline).
  (when (and knayawp-winner-integration-flag
             (bound-and-true-p winner-mode)
             (fboundp 'winner-save-conditionally))
    (winner-save-conditionally))
  (knayawp--teardown-magit-integration)
  (let ((side-windows (knayawp--side-windows)))
    (dolist (win side-windows)
      (delete-window win)))
  ;; Drop this frame's recorded width.  If no other frames still have
  ;; an active layout, remove the global hook altogether.
  (setf (alist-get (selected-frame) knayawp--frame-widths nil 'remove)
        nil)
  (unless knayawp--frame-widths
    (remove-hook 'window-size-change-functions
                 #'knayawp--restore-right-width-on-resize)))

;;;; Window utilities

(defun knayawp--side-windows-in-frame (frame)
  "Return side windows in FRAME."
  (seq-filter (lambda (w) (window-parameter w 'window-side))
              (window-list frame)))

(defun knayawp--side-windows ()
  "Return a list of all side windows in the current frame."
  (knayawp--side-windows-in-frame (selected-frame)))

(defun knayawp--balance-side-windows ()
  "Equalise the heights of all side windows in the current frame.
Side windows on the same side share an internal parent window;
calling `balance-windows' on that parent gives equal heights."
  (when-let* ((wins (knayawp--side-windows))
              ((>= (length wins) 2))
              (parent (window-parent (car wins))))
    (balance-windows parent)))

(defun knayawp--apply-right-width (frame)
  "Resize knayawp side windows in FRAME to `knayawp-right-width'.
Temporarily clears the `preserve-size' lock so the resize is not
rejected, then re-locks at the new width."
  (when-let* ((side-win (car (knayawp--side-windows-in-frame frame)))
              (target (round (* (frame-width frame)
                                knayawp-right-width)))
              (current (window-total-width side-win))
              (delta (- target current))
              ((not (zerop delta))))
    (window-preserve-size side-win t nil)
    (ignore-errors (window-resize side-win delta t))
    (window-preserve-size side-win t t)))

(defun knayawp--restore-right-width-on-resize (frame)
  "Re-apply `knayawp-right-width' to side windows after frame resize.
Hook function for `window-size-change-functions'.  Acts only when
FRAME's width has changed since the last invocation AND FRAME has
knayawp side windows.  Intra-frame window resizes are left
untouched."
  (let ((current-width (frame-width frame))
        (last-width (alist-get frame knayawp--frame-widths)))
    (unless (equal current-width last-width)
      (setf (alist-get frame knayawp--frame-widths) current-width)
      (when last-width
        (knayawp--apply-right-width frame)))))

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

(defun knayawp--maybe-refresh-magit (win)
  "Call `magit-refresh' when WIN displays a live magit-status buffer.
Called after selecting a panel window so the magit panel always
reflects current repository state without a manual `g'."
  (when (window-live-p win)
    (let ((buf (window-buffer win)))
      (when (and (buffer-live-p buf)
                 (with-current-buffer buf
                   (derived-mode-p 'magit-status-mode))
                 (fboundp 'magit-refresh))
        (with-current-buffer buf
          (magit-refresh))))))

(defun knayawp-select-panel (n)
  "Select the Nth panel (1-indexed).
Panel 1 is the first entry in `knayawp-panels' (magit by default),
panel 2 is the second (vterm), panel 3 is the third (claude).
When the selected panel shows a `magit-status-mode' buffer, call
`magit-refresh' to keep the display current."
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
      (select-window win)
      (knayawp--maybe-refresh-magit win))))

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
                 (buf (alist-get type buffer-alist)))
            (when (and buf (buffer-live-p buf))
              (display-buffer-in-side-window
               buf
               `((side . right)
                 (slot . ,slot)
                 (window-width . ,knayawp-right-width)
                 (preserve-size . (t . nil))
                 (window-parameters
                  . ,(knayawp--side-window-parameters)))))))
        (knayawp--balance-side-windows)
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

(defun knayawp--select-panel-1 ()
  "Select panel 1 in the control pane."
  (interactive)
  (knayawp-select-panel 1))

(defun knayawp--select-panel-2 ()
  "Select panel 2 in the control pane."
  (interactive)
  (knayawp-select-panel 2))

(defun knayawp--select-panel-3 ()
  "Select panel 3 in the control pane."
  (interactive)
  (knayawp-select-panel 3))

(defun knayawp--bind-common-keys (map)
  "Install the style-independent letter and digit bindings on MAP.
These bindings are shared by every value of `knayawp-keymap-style'
so that layout management, direct panel selection, zoom, editor
return, and toggle-panels are always reachable without an arrow
key."
  (define-key map "l" #'knayawp-layout-setup)
  (define-key map "q" #'knayawp-layout-teardown)
  (define-key map "1" #'knayawp--select-panel-1)
  (define-key map "2" #'knayawp--select-panel-2)
  (define-key map "3" #'knayawp--select-panel-3)
  (define-key map "n" #'knayawp-next-panel)
  (define-key map "p" #'knayawp-prev-panel)
  (define-key map "z" #'knayawp-zoom-panel)
  (define-key map "0" #'knayawp-select-editor)
  (define-key map "s" #'knayawp-toggle-panels)
  (define-key map " " #'knayawp-terminal-copy-mode)
  (define-key map "y" #'knayawp-terminal-yank)
  map)

(defun knayawp--build-command-map ()
  "Return a fresh sparse keymap configured for `knayawp-keymap-style'.
Every style binds the full command surface (layout setup and
teardown, direct panel selection, next/previous panel, zoom,
select-editor, toggle-panels).  Only the keys differ between
styles.  See `knayawp-keymap-style' for the per-style layout."
  (let ((map (make-sparse-keymap)))
    (knayawp--bind-common-keys map)
    (pcase knayawp-keymap-style
      ('default map)
      ('tmux
       ;; tmux pane navigation: <up>/<down> step through panels.
       ;; <left>/<right> are reserved for project-tab navigation
       ;; (wired in v0.2); leave them unbound for now so the user
       ;; gets a clear "key not bound" hint instead of a surprise.
       (define-key map (kbd "<up>")   #'knayawp-prev-panel)
       (define-key map (kbd "<down>") #'knayawp-next-panel)
       map)
      ('byobu
       ;; byobu Shift-Function-arrow style: S-<up>/S-<down> step
       ;; through panels.  S-<left>/S-<right> reserved for project
       ;; tabs (v0.2).
       (define-key map (kbd "S-<up>")   #'knayawp-prev-panel)
       (define-key map (kbd "S-<down>") #'knayawp-next-panel)
       map)
      (_ (user-error "Unknown knayawp-keymap-style: %s"
                     knayawp-keymap-style)))))

(defvar knayawp-command-map (knayawp--build-command-map)
  "Keymap for knayawp commands.
Bind this to a prefix key of your choice, for example:
  (global-set-key (kbd \"C-c k\") knayawp-command-map)
The concrete key layout depends on `knayawp-keymap-style'.  After
changing that option, call `knayawp-rebuild-command-map' to apply
the new style without restarting Emacs.")

(fset 'knayawp-command-map knayawp-command-map)

;;;###autoload
(defun knayawp-rebuild-command-map ()
  "Rebuild the variable `knayawp-command-map' from `knayawp-keymap-style'.
Call this after changing `knayawp-keymap-style' at runtime.  The
underlying keymap object is mutated in place so existing prefix
bindings (e.g. `C-c k') keep working without rebinding."
  (interactive)
  (let ((fresh (knayawp--build-command-map)))
    ;; Mutate the existing keymap object in place so any prefix
    ;; binding the user installed continues to resolve.
    (setcdr knayawp-command-map (cdr fresh)))
  (fset 'knayawp-command-map knayawp-command-map)
  (message "knayawp: rebuilt command map for %s style"
           knayawp-keymap-style))

;;;; Panel display routing

(defun knayawp--panel-buffer-name-regexp (type)
  "Return a regexp matching `*knayawp-TYPE-*' buffers for TYPE.
TYPE is a panel-type symbol (for example `vterm' or `claude')."
  (format "\\`\\*knayawp-%s-" (regexp-quote (symbol-name type))))

(defun knayawp--make-panel-buffer-predicate (panel-spec)
  "Return a `display-buffer-alist' predicate for PANEL-SPEC.
The predicate takes (BUFFER-OR-NAME _ACTION) and returns non-nil
only when BUFFER-OR-NAME matches the panel-type buffer-name pattern
AND a knayawp side window for the panel's slot exists in the
selected frame.  This gates the routing on layout presence so the
entry is a no-op in unrelated frames."
  (let ((regexp (knayawp--panel-buffer-name-regexp
                 (knayawp--panel-type panel-spec)))
        (slot (knayawp--panel-slot panel-spec)))
    (lambda (buffer-or-name _action)
      (let ((name (if (bufferp buffer-or-name)
                      (buffer-name buffer-or-name)
                    buffer-or-name)))
        (and (stringp name)
             (string-match-p regexp name)
             (knayawp--side-window-for-slot slot))))))

(defun knayawp--make-panel-display-entry (panel-spec)
  "Build a `display-buffer-alist' entry for PANEL-SPEC.
The entry's condition is a closure produced by
`knayawp--make-panel-buffer-predicate'; the action routes the buffer
to a right side window at the panel's slot."
  (let ((slot (knayawp--panel-slot panel-spec)))
    `(,(knayawp--make-panel-buffer-predicate panel-spec)
      (display-buffer-reuse-window
       display-buffer-in-side-window)
      (side . right)
      (slot . ,slot)
      (window-width . ,knayawp-right-width)
      (preserve-size . (t . nil))
      (window-parameters . ,(knayawp--side-window-parameters)))))

(defun knayawp--install-panel-display-routing ()
  "Install `display-buffer-alist' entries for knayawp panel buffers.
For each panel in `knayawp-panels', push an entry that routes
buffers named `*knayawp-TYPE-*' to the configured side-window slot
when a knayawp side window exists in the selected frame.  The
entries are recorded in `knayawp--panel-display-entries' so
`knayawp--remove-panel-display-routing' can take them out cleanly.
Idempotent: if entries are already installed, do nothing."
  (unless knayawp--panel-display-entries
    (let ((entries (mapcar #'knayawp--make-panel-display-entry
                           knayawp-panels)))
      (setq knayawp--panel-display-entries entries)
      (dolist (entry entries)
        (push entry display-buffer-alist)))))

(defun knayawp--remove-panel-display-routing ()
  "Remove panel buffer routing from `display-buffer-alist'.
Inverse of `knayawp--install-panel-display-routing': drop each
recorded entry from `display-buffer-alist' and clear
`knayawp--panel-display-entries'."
  (dolist (entry knayawp--panel-display-entries)
    (setq display-buffer-alist (delq entry display-buffer-alist)))
  (setq knayawp--panel-display-entries nil))

;;;; Global minor mode

(defvar knayawp--saved-project-switch-commands :unset
  "Saved value of `project-switch-commands' for restoration.
Captured by `knayawp--mode-on' before installing the auto-layout
action and restored by `knayawp--mode-off'.  The sentinel value
`:unset' means mode-on has not yet captured a value; this
distinguishes \"not saved yet\" from \"saved nil\" so mode-off
never clobbers a user-set value when mode-on was not called.")

(defun knayawp--mode-on ()
  "Install global hooks and integration for `knayawp-mode'.
Replace `project-switch-commands' with `knayawp-layout-setup' so
that switching to a project via `project-switch-project'
automatically sets up the knayawp layout.  The previous value is
saved for restoration by `knayawp--mode-off'.  Also install the
`display-buffer-alist' entries that route `*knayawp-TYPE-PROJECT*'
buffers to their configured side-window slots."
  (when (eq knayawp--saved-project-switch-commands :unset)
    ;; Only save the pre-mode value once: guard against double
    ;; mode-on calls overwriting the original saved value.
    (setq knayawp--saved-project-switch-commands
          project-switch-commands))
  (setq project-switch-commands #'knayawp-layout-setup)
  (knayawp--install-panel-display-routing))

(defun knayawp--mode-off ()
  "Tear down global hooks and integration for `knayawp-mode'.
Inverse of `knayawp--mode-on': restore `project-switch-commands'
to the value saved at mode activation and remove the panel buffer
`display-buffer-alist' entries.  When mode-on was never called
\(`:unset' sentinel), leaves `project-switch-commands' untouched."
  (when (and (not (eq knayawp--saved-project-switch-commands :unset))
             (eq project-switch-commands #'knayawp-layout-setup))
    (setq project-switch-commands
          knayawp--saved-project-switch-commands))
  (setq knayawp--saved-project-switch-commands :unset)
  (knayawp--remove-panel-display-routing))

;;;###autoload
(define-minor-mode knayawp-mode
  "Toggle knayawp global minor mode.
When enabled, knayawp installs project-aware hooks and display
routing that complement `knayawp-layout-setup'.  Loading the
package alone never enables the mode (see property P7); the user
must enable it explicitly."
  :global t
  :group 'knayawp
  :lighter nil
  (if knayawp-mode
      (knayawp--mode-on)
    (knayawp--mode-off)))

(provide 'knayawp)
;;; knayawp.el ends here
