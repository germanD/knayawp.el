# knayawp.el — Implementation Plan

## Vision

An Emacs package that eliminates the friction of manually setting up project-oriented window layouts. When you visit a project, you get your ideal workspace — editing buffer on the left, tools (magit, vterm, Claude Code) stacked on the right — automatically. Later, a project navigation bar lets you flip between projects without losing any layout state.

---

## Architecture: Side Windows

The right "control pane" uses Emacs **side windows** (`display-buffer-in-side-window`). This is the same mechanism treemacs and neotree use. The key properties:

- Side windows **cannot be split** → `C-x 2/3` only affects the editor pane
- `no-delete-other-windows` parameter → side windows **survive `C-x 1`**
- `no-other-window` parameter → `C-x o` skips them (dedicated keybindings instead)
- Built-in `window-toggle-side-windows` → free hide/show toggle
- **Zero advice on built-in functions** — only documented APIs

### Side Window Slot Layout

```
window-sides-slots = '(nil nil nil 3)   ;; 3 slots on the right

┌─────────────────────────┬──────────────────┐
│                         │  slot -1: magit   │
│                         │                   │
│   Main window           ├──────────────────┤
│   (editor pane)         │  slot  0: vterm   │
│                         │                   │
│   NOT a side window     ├──────────────────┤
│                         │  slot  1: claude  │
│                         │                   │
└─────────────────────────┴──────────────────┘
     regular window            side windows
    C-x 0/1/2/3 work         immune to C-x 0/1/2/3
```

---

## Architecture: Terminal Backend Abstraction

The vterm and Claude panels need a terminal emulator. vterm (libvterm/C) works but has known refresh issues — the display can lag or show stale content until `C-l`, especially in non-selected windows and during heavy output (like Claude streaming). To avoid locking in, **all terminal creation goes through a backend dispatch layer**.

### Supported Backends

| Backend | Status | Notes |
|---------|--------|-------|
| **vterm** | Default | Fast (C library), full TUI. Known refresh glitches in side windows. |
| **eat** | Planned | Pure Elisp, actively maintained vterm replacement. Better Emacs redisplay integration, may fix refresh issues. |

comint/term/ansi-term are excluded — they can't handle Claude Code's TUI.

### Dispatch Layer

```elisp
(defcustom knayawp-terminal-backend 'vterm
  "Terminal emulator backend for shell and Claude panels."
  :type '(choice (const :tag "vterm (libvterm, C)" vterm)
                 (const :tag "eat (pure Elisp)" eat))
  :group 'knayawp)

(defun knayawp--make-terminal (name directory &optional command)
  "Create a terminal buffer NAME in DIRECTORY, optionally running COMMAND.
Dispatches to `knayawp-terminal-backend'.")
```

All panel creation (`knayawp--get-or-create-vterm-buffer`, `knayawp--get-or-create-claude-buffer`) calls `knayawp--make-terminal`. No code outside this layer references vterm or eat directly.

### Per-panel backend override (future)

A natural extension: allow different backends per panel via the panel spec. For example, eat for Claude (heavy streaming) and vterm for the general terminal. Not in v0.1 scope but the dispatch layer makes it trivial to add.

---

## v0.1 — Automatic Window Layout

### Goal
A single command `knayawp-layout-setup` that transforms the current frame into the desired layout for the project under point, plus keybindings to navigate and control the right pane.

### v0.1.0 — Core Layout Engine

**Package scaffolding:**
- [ ] Create `knayawp.el` with proper package header, `;;; Commentary:`, and `(provide 'knayawp)`
- [ ] Define `knayawp` customization group
- [ ] `defcustom knayawp-right-width` (default 0.4) — width of right pane as frame fraction
- [ ] `defcustom knayawp-claude-command` (default `"claude"`) — CLI command for Claude Code
- [ ] `defcustom knayawp-terminal-backend` (default `'vterm`) — `'vterm` or `'eat`
- [ ] `defcustom knayawp-panels` — alist of panel specs with slots and height ratios:
  ```elisp
  '((magit  :slot -1 :height 0.33)
    (vterm  :slot  0 :height 0.33)
    (claude :slot  1 :height 0.34))
  ```

**Terminal backend dispatch:**
- [ ] `knayawp--make-terminal (name directory &optional command)` — dispatch to backend
- [ ] `knayawp--make-terminal-vterm (name directory &optional command)` — vterm implementation
- [ ] `knayawp--make-terminal-eat (name directory &optional command)` — eat implementation
- [ ] Backend-specific `require` is deferred (only loaded when selected)

**Layout engine:**
- [ ] `knayawp-layout-setup` interactive command:
  1. Set `window-sides-slots` to allow 3 right-side windows
  2. For each panel, create/reuse the project-scoped buffer
  3. Display each buffer via `display-buffer-in-side-window` with:
     - `(side . right)` `(slot . N)`
     - `(window-width . knayawp-right-width)`
     - `(window-parameters . ((no-delete-other-windows . t) (no-other-window . t)))`
  4. Select the main (editor) window
- [ ] `knayawp-layout-teardown` — delete side windows, restore single-window editing
- [ ] Project detection via `project-current` → derive project name for buffer naming
- [ ] Buffer naming: `*knayawp-magit-PROJECT*`, `*knayawp-vterm-PROJECT*`, `*knayawp-claude-PROJECT*`
- [ ] If tool buffer already exists for this project, reuse it

**Panel buffer creation (all terminal panels go through the dispatch layer):**
- [ ] `knayawp--get-or-create-magit-buffer (project-root)` — calls `magit-status` in the project root (not a terminal — no dispatch)
- [ ] `knayawp--get-or-create-vterm-buffer (project-root project-name)` — calls `knayawp--make-terminal` with default shell
- [ ] `knayawp--get-or-create-claude-buffer (project-root project-name)` — calls `knayawp--make-terminal` with `knayawp-claude-command`

### v0.1.1 — Control Pane Navigation (tmux-style)

**`knayawp-command-map` keymap:**

Note: `C-c LETTER` is reserved for users per GNU conventions. The package defines
`knayawp-command-map` but does NOT bind it globally. Users bind it themselves:

```elisp
;; Suggested binding (documented, not enforced):
(global-set-key (kbd "C-c k") knayawp-command-map)
```

| Key (under prefix) | Command | Action |
|---------------------|---------|--------|
| `l` | `knayawp-layout-setup` | Create/refresh layout |
| `q` | `knayawp-layout-teardown` | Remove control pane |
| `1` | `knayawp-select-panel 1` | Jump to magit |
| `2` | `knayawp-select-panel 2` | Jump to vterm |
| `3` | `knayawp-select-panel 3` | Jump to claude |
| `n` | `knayawp-next-panel` | Cycle to next panel |
| `p` | `knayawp-prev-panel` | Cycle to previous panel |
| `z` | `knayawp-zoom-panel` | Zoom/unzoom current panel |
| `0` | `knayawp-select-editor` | Return to editor pane |
| `s` | `knayawp-toggle-panels` | Hide/show all side windows |

**Zoom implementation:**
- Zoom = delete the other two side windows → remaining one expands to fill right column
- Unzoom = re-create deleted side windows with their original buffers
- Track zoom state in `knayawp--zoomed-panel`

### v0.1.2 — Magit Integration

**Custom `magit-display-buffer-function`:**
- [ ] `knayawp--magit-display-buffer` — routes magit buffers to the magit side window:
  - `magit-status-mode`, `magit-log-mode`, `magit-diff-mode`, `magit-revision-mode`, `magit-stash-mode` → all go to magit side window (slot -1)
  - Transient buffers (diff, log) **replace** status in the same window
  - Pressing `q` restores previous buffer via magit's built-in `quit-restore` — no custom restoration needed
- [ ] `COMMIT_EDITMSG` → route to the **editor pane** via `display-buffer-alist` (commits are editing tasks)
- [ ] `magit-process` → stays in magit slot or hidden
- [ ] `knayawp--setup-magit-integration` / `knayawp--teardown-magit-integration`
- [ ] `defcustom knayawp-magit-commit-in-editor-p` (default t) — whether commit messages open in editor pane

### v0.1.3 — Mode & Polish

- [ ] `knayawp-mode` global minor mode that hooks into `project-switch-project`
- [ ] When mode is active and user switches to a project → auto-run layout setup
- [ ] Handle edge cases: frame too narrow (skip right panels), missing magit/vterm
- [ ] `defcustom knayawp-layout-hook` — run after layout is created
- [ ] `winner-mode` integration — save/restore via winner before tearing down
- [ ] `display-buffer-alist` entries so Emacs routes knayawp buffers correctly even when created outside the setup flow

---

## v0.2 — Project Navigation Bar

### Goal
Switch between multiple active projects without losing per-project layout state. Each project is a "workspace" with its own set of buffers and layout.

### Approach: `tab-bar-mode`

Emacs 27+ `tab-bar-mode` is the natural fit — each tab can represent a project, and tabs preserve window configurations natively (including side windows).

### v0.2.0 — Tab-per-Project
- [ ] `knayawp-project-open` — open a project in a new tab, run layout setup
- [ ] Tab name = project name (e.g., `myapp`)
- [ ] `knayawp-project-switch` — switch to an existing project tab (with completion)
- [ ] `knayawp-project-close` — close tab, kill project-specific tool buffers
- [ ] Keymap entries (under `knayawp-command-map`): `P` for switch, `o` for open, `c` for close

### v0.2.1 — Visual Navigation Bar
- [ ] Customize `tab-bar-format` to show project names prominently
- [ ] Highlight current project tab
- [ ] Optionally show git branch in tab name
- [ ] `defcustom knayawp-tab-bar-position` — top (default) or use a side window as vertical project list

### v0.2.2 — State Persistence
- [ ] Save open projects + tab order to a file on `kill-emacs-hook`
- [ ] `knayawp-restore-session` — reopen saved projects on startup
- [ ] `defcustom knayawp-auto-restore` — whether to auto-restore on Emacs start

---

## Key Design Decisions

1. **Side windows over regular split windows**: Cannot be split, survive `delete-other-windows`, no advice needed on built-in functions.
2. **`project.el` over projectile**: Emacs 29+ built-in, no extra dependency.
3. **Terminal backend abstraction**: All terminal panels go through `knayawp--make-terminal`. Default is vterm; eat is a planned alternative. No code outside the dispatch layer touches vterm or eat APIs directly.
4. **Custom `magit-display-buffer-function`**: Uses magit's official hook. Transient buffer restoration handled by magit's built-in `quit-restore` mechanism — zero custom logic.
5. **COMMIT_EDITMSG in editor pane**: Commits are editing tasks, not tool output.
6. **Ratios not pixels**: All sizing via fractions so it works on any display.
7. **`tab-bar-mode` for v0.2**: Built-in, preserves window configs natively.

## Implementation Order

```
v0.1.0  →  v0.1.1  →  v0.1.2  →  v0.1.3  →  v0.2.0  →  v0.2.1  →  v0.2.2
 layout     nav        magit      mode       tabs       visual     persist
```

Start with v0.1.0 — get the side-window layout engine working end-to-end first.
