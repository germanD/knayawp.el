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
- [x] Create `knayawp.el` with proper package header, `;;; Commentary:`, and `(provide 'knayawp)` — #1
- [x] Define `knayawp` customization group — #2
- [x] `defcustom knayawp-right-width` (default 0.4) — width of right pane as frame fraction — #3
- [x] `defcustom knayawp-claude-command` (default `"claude"`) — CLI command for Claude Code — #4
- [x] `defcustom knayawp-terminal-backend` (default `'vterm`) — `'vterm` or `'eat` — #5
- [x] `defcustom knayawp-panels` — alist of panel specs with slots and height ratios: — #6
  ```elisp
  '((magit  :slot -1 :height 0.33)
    (vterm  :slot  0 :height 0.33)
    (claude :slot  1 :height 0.34))
  ```

**Terminal backend dispatch:**
- [x] `knayawp--make-terminal (name directory &optional command)` — dispatch to backend — #7
- [x] `knayawp--make-terminal-vterm (name directory &optional command)` — vterm implementation — #8
- [x] `knayawp--make-terminal-eat (name directory &optional command)` — eat implementation — #9
- [x] Backend-specific `require` is deferred (only loaded when selected) — #9

**Layout engine:**
- [x] `knayawp-layout-setup` interactive command: — #10
  1. Set `window-sides-slots` to allow 3 right-side windows
  2. For each panel, create/reuse the project-scoped buffer
  3. Display each buffer via `display-buffer-in-side-window` with:
     - `(side . right)` `(slot . N)`
     - `(window-width . knayawp-right-width)`
     - `(window-parameters . ((no-delete-other-windows . t) (no-other-window . t)))`
  4. Select the main (editor) window
- [x] `knayawp-layout-teardown` — delete side windows, restore single-window editing — #11
- [x] Project detection via `project-current` → derive project name for buffer naming — #12
- [x] Buffer naming: `*knayawp-magit-PROJECT*`, `*knayawp-vterm-PROJECT*`, `*knayawp-claude-PROJECT*` — #12
- [x] If tool buffer already exists for this project, reuse it — #12

**Panel buffer creation (all terminal panels go through the dispatch layer):**
- [x] `knayawp--get-or-create-magit-buffer (project-root)` — calls `magit-status` in the project root (not a terminal — no dispatch) — #13
- [x] `knayawp--get-or-create-vterm-buffer (project-root project-name)` — calls `knayawp--make-terminal` with default shell — #14
- [x] `knayawp--get-or-create-claude-buffer (project-root project-name)` — calls `knayawp--make-terminal` with `knayawp-claude-command` — #15

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
| `Z` | `knayawp-monocle-panel` | Full-frame monocle zoom/restore |
| `0` | `knayawp-select-editor` | Return to editor pane |
| `s` | `knayawp-toggle-panels` | Hide/show all side windows |

**Zoom implementation:**
- Zoom = delete the other two side windows → remaining one expands to fill right column
- Unzoom = re-create deleted side windows with their original buffers
- Track zoom state in `knayawp--zoomed-panel`

**Implementation (all closed):**
- [x] Define `knayawp-command-map` keymap — #16
- [x] Implement `knayawp-select-panel` (direct panel jump) — #17
- [x] Implement `knayawp-next-panel` and `knayawp-prev-panel` — #18
- [x] Implement `knayawp-select-editor` — #19
- [x] Implement `knayawp-zoom-panel` — #20
- [x] Implement `knayawp-toggle-panels` — #21
- [x] Bind all v0.1.1 commands in `knayawp-command-map` — #23

### v0.1.2 — Magit Integration

**Custom `magit-display-buffer-function`:**
- [x] `knayawp--magit-display-buffer` — routes magit buffers to the magit side window:
  - `magit-status-mode`, `magit-log-mode`, `magit-diff-mode`, `magit-revision-mode`, `magit-stash-mode` → all go to magit side window (slot -1)
  - Transient buffers (diff, log) **replace** status in the same window
  - Pressing `q` restores previous buffer via magit's built-in `quit-restore` — no custom restoration needed
- [x] `COMMIT_EDITMSG` → route to the **editor pane** via `display-buffer-alist` (commits are editing tasks)
- [x] `magit-process` → stays in magit slot or hidden
- [x] `knayawp--setup-magit-integration` / `knayawp--teardown-magit-integration`
- [x] `defcustom knayawp-magit-commit-in-editor-flag` (default t) — whether commit messages open in editor pane
- [x] Use `file-equal-p` for magit buffer path matching (fixes silent missing magit panel on bind-mount/symlink paths) — #54
- [x] Equalise right-pane slot heights on layout setup (equal thirds by default) — #55

### v0.1.3 — Mode & Polish

- [x] `knayawp-mode` global minor mode that hooks into `project-switch-project` — #28
- [x] Auto-layout on `project-switch-project` — when mode is active, run `knayawp-layout-setup` on switch — #29
- [x] `defcustom knayawp-layout-hook` — run after layout is created — #31
- [x] `display-buffer-alist` entries so Emacs routes knayawp buffers correctly even when created outside the setup flow — #33
- [x] `defcustom knayawp-keymap-style` with tmux/byobu arrow-key navigation — #22

### v0.1.4 — Layout Config Finetuning

Theme: make the layout shape configurable and resilient. Anchor: extend `knayawp-panels` plist with `:height`; teach setup/teardown to honour user dimensions and survive frame resizes; integrate winner-mode for undo.

Resolved design decisions:
- `knayawp-winner-integration-flag` defaults to `t` (only consulted when `winner-mode` itself is on, so passive-loading invariant P7 is preserved).
- No new `kb/` file — the `:slot`/`:height` plist contract, the `window-height`-only-on-creation gotcha, and the `preserve-size` cons-cell semantics all live in the `knayawp-panels` docstring + Commentary.
- #30 split: bulk-moved here in full; the "missing magit/vterm" half is already covered by the existing graceful-degradation paths, so the remaining work is the narrow-frame guard.

- [x] winner-mode integration — save/restore via winner before tearing down — #32
- [x] Make right-pane slot heights configurable — #56
- [x] Handle edge cases: frame too narrow (skip right panels), missing magit/vterm — #30
- [x] Magit transient buffers escape side window containment during commit — #48
- [x] C-x o cycles into side windows despite no-other-window parameter — #49
- [x] Side pane width not preserved after frame resize — #50
- [x] Commit flow: focus should land on COMMIT_EDITMSG, not diff — #53
- [x] `knayawp--mode-off` can clobber user-set `project-switch-commands` — #60
- [x] Add `kb/` entry for `knayawp-mode` project-switch integration — #61
- [x] Re-install display-buffer-alist routing when knayawp-panels changes — #65
- [x] Positive-path ERT for `knayawp-layout-hook` — #66
- [x] `:set` callback for `knayawp-keymap-style` to auto-rebuild command map — #67
- [x] Monocle mode full-frame zoom — #85
- [x] Auto-refresh magit-status when jumping to magit panel — #78
- [x] Tighten 'editor' commit-style COMMIT_EDITMSG routing to a specific window — #79
- [x] bug: knayawp-panels :set callback doesn't refresh magit slot when panel :slot changes — #87
- [x] enhancement: restore :slot type validation lost when knayawp-panels :type changed to sexp — #88
- [x] refactor: extract knayawp--editor-columns to eliminate duplicated narrow-frame arithmetic — #89
- [x] enhancement: warn when knayawp-layout-setup is called with an existing layout (heights won't re-apply) — #90
- [x] test: replace (when setter ...) with (should setter) in knayawp-panels :set tests — #91
- [x] refactor: replace (message (concat ...) args) with direct format-string in message calls — #92
- [x] bug: knayawp-monocle-panel behaves like zoom — editor pane is not removed — #97

### v0.1.5 — Quick DevX Wins

- [x] One-shot copy/paste bindings for terminal panels (`C-c k SPC` / `w` / `y`) — #77
- [ ] Promote probe harness to first-class integration-test tier — #80
- [ ] Managed transient splits in editor pane for side-pane-triggered visits — #52
- [ ] nit: bind frame-width once in knayawp--editor-columns to avoid double call — #96
- [ ] enhancement: magit fixup (c f) flow — focus magit-log-select window automatically — #98
- [x] enhancement: auto-refresh vterm panels after theme change — #100
- [ ] New probe: layout immunity (P1) — C-x 0, C-x 2/3, C-x o isolation flag — #103
- [ ] New probe: knayawp-toggle-panels — #104
- [ ] New probe: commit-cancel flow — #105
- [ ] New probe: knayawp-magit-commit-focus-after variants (magit, previous) — #106
- [ ] AGENTS.md: probe authoring guide (naming, Probe-Geometry header, ERT/probe boundary) — #107
- [ ] ERT: fix two misplaced tests (zoom batch trivially passes; monocle mocks overcomplicated) — #108
- [ ] docs: Claude Code Notification hook to get OS alerts when Claude waits for input — #113
- [ ] feat: send editor selection to Claude vterm panel as context reference — #115

---

## v0.3 — Alternative Layouts and Panel Rotation

Note: v0.3.0 is filed here, after v0.1.5 and before the v0.2.x tab-bar
sections, because it is the next active-development milestone. v0.2.x
(tab-bar workspaces) is planned work that has not yet started; v0.3.0 is
the promoted Idea 1 feature line which the user has scoped and committed.
Chronological milestone order in the file is: v0.1.x → v0.3.0 → v0.2.x,
reflecting development priority rather than version number order.

### v0.3.0 — Named Layouts, Panel Rotation, and Keymap Migration

Theme: scale the layout across screen sizes without manual reconfiguration.
Introduces `knayawp-layouts` + `knayawp-default-layout`, refactors zoom as
an ephemeral solo layout, adds interactive layout selection and panel
rotation (`f`/`b`), opt-in auto-detect, a soft-deprecation cycle for `n`/`p`,
and the final keymap flip as the release gate.

- [ ] Introduce `knayawp-layouts` + `knayawp-default-layout` defcustoms; add `knayawp--apply-layout` — #69
- [ ] Reimplement `knayawp-zoom-panel` as ephemeral solo layout; keep `knayawp--zoomed-panel` as compat shim — #70
- [ ] Add `knayawp-select-layout` interactive command; bind to `L` — #71
- [ ] Add `knayawp-rotate-next` / `knayawp-rotate-prev`; bind to `f` / `b`; mode-line indicator — #72
- [ ] Add `knayawp-layout-auto-select-flag` and `knayawp-narrow-threshold-columns` defcustoms — #73
- [ ] Deprecate `knayawp-next-panel` / `knayawp-prev-panel` via `make-obsolete`; document upcoming flip — #74
- [ ] Flip `n`/`p` in `knayawp-command-map` to intra-pane window cycling; document migration — #75

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
- [ ] Alternative layouts for narrow screens (side pane as overlay) — #51 (deferred from v0.1.5)
- [ ] feat: visual overlay notification when a project file changes externally — #112
- [ ] feat: Emacs notification bridge for Claude vterm panel (alert.el integration) — #114
- [ ] feat: direct vterm injection for send-to-Claude (requires prompt detection) — #116
- [ ] kb: stub KB entries for filenotify overlay, Claude notification, send-to-Claude — #117

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
