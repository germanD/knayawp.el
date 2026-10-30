---
title: knayawp.el Product Specification
last-updated: 2026-10-30
status: draft
---

# Product Specification

## Problem

Emacs users who work across multiple projects with magit, a terminal (vterm/eat), and Claude Code spend significant time manually recreating their preferred window layout every session. Standard window commands (`C-x 1/2/3`, `C-x o`) interfere with tool windows, and there's no built-in way to maintain per-project workspaces with persistent tool panels.

## Target User

Long-term Emacs users (not necessarily "power users") who:
- Use magit for version control
- Use a terminal emulator (vterm or eat) inside Emacs
- Use Claude Code CLI for AI-assisted development
- Work on multiple projects and want quick context switching
- Prefer landscape screen layouts

## Product: Two Features

### Feature 1: Automatic Project Layout (v0.1 – v0.1.3)

**What it does:** A single command transforms the current frame into a two-pane layout:
- **Left pane** (editor): The active buffer. Standard window commands (`C-x 0/1/2/3`) operate only here.
- **Right pane** (control pane): Three stacked tool panels — magit, terminal, Claude Code. Immune to standard window commands. Navigated via dedicated keybindings.

**Layout:**

```
┌─────────────────────────┬──────────────────┐
│                         │   magit-status    │
│                         │                   │
│   Editor pane           ├──────────────────┤
│   (active buffer)       │   terminal        │
│                         │                   │
│   C-x 0/1/2/3 work     ├──────────────────┤
│   here only             │   Claude Code     │
│                         │                   │
└─────────────────────────┴──────────────────┘
```

**Control pane navigation** (tmux-style, under a user-bound prefix):
- Jump to panel by number (1=magit, 2=terminal, 3=claude)
- Cycle next/previous
- Zoom: temporarily expand one panel to fill the right column
- Return to editor pane
- Toggle all panels on/off

**Keymap styles** — `knayawp-keymap-style` selects the key layout used when building `knayawp-command-map`:
- `default` (historical): numbered keys 1/2/3 and `n`/`p` for next/previous panel.
  `S-<up>`/`S-<down>`/`S-<left>`/`S-<right>` are unbound and reserved for panel resize (v0.3).
- `tmux`: adds `<up>`/`<down>` for previous/next panel on top of the default bindings.
  `<left>`/`<right>` are reserved for project-tab navigation (v0.2).
  `S-<up>`/`S-<down>`/`S-<left>`/`S-<right>` are unbound and reserved for panel resize (v0.3).
- `byobu`: adds `S-<up>`/`S-<down>` for previous/next panel.
  `S-<left>`/`S-<right>` reserved for v0.2.
  **Note:** `byobu` style has a conflict with the planned panel-resize bindings (#119) — `S-<up>`/`S-<down>` are already used for panel cycling. This must be resolved (new style variant or key reassignment) before v0.3 resize work lands.

All three styles bind the same command surface; they differ only in the supplementary arrow-key bindings. Changing the style at runtime takes effect after calling `knayawp-rebuild-command-map`.

**Style-independent key bindings** (available in every style):

| Key | Command | Description |
|-----|---------|-------------|
| `l` | `knayawp-layout-setup` | Create / refresh the layout |
| `q` | `knayawp-layout-teardown` | Remove the control pane |
| `1` / `2` / `3` | `knayawp--select-panel-N` | Jump directly to panel N |
| `n` | `knayawp-next-panel` | Cycle to the next panel |
| `p` | `knayawp-prev-panel` | Cycle to the previous panel |
| `0` | `knayawp-select-editor` | Return focus to the editor pane |
| `z` | `knayawp-zoom-panel` | Zoom / unzoom the selected panel |
| `Z` | `knayawp-monocle-panel` | Toggle full-frame monocle mode |
| `s` | `knayawp-toggle-panels` | Show / hide all side panels |
| `SPC` | `knayawp-terminal-copy-mode` | Enter copy/scroll mode in the terminal panel |
| `y` | `knayawp-terminal-yank` | Yank kill-ring head into the terminal panel |
| `c` | `knayawp-send-to-claude` | Send region / reference to the Claude panel |
| `t` | `knayawp-send-to-terminal` | Send active region to the terminal panel |
| `C-x` | `knayawp-claude-send-ctrl-x` | Send the Control-x byte to the Claude terminal |

**`C-x o` isolation** — `knayawp-isolate-other-window-flag` (default `t`) attaches `no-other-window` to each side window so that `C-x o` cycles only among editor-pane windows. Set to `nil` to allow `C-x o` to walk into the side windows. The change takes effect on the next `knayawp-layout-setup` call; existing side windows keep the parameter they were built with.

**Monocle mode** — `knayawp-monocle-panel` (bound to `Z`) expands the selected panel to fill the entire frame, removing both the other side windows and the editor pane. Unlike `knayawp-zoom-panel` (`z`), which expands the panel within the right column only, monocle gives the panel all available screen space. Per-frame state is stored in the `knayawp--monocle-config` frame parameter as a cons `(WINDOW-CONFIG . PRIOR-ZOOM-STATE)`, so two frames never share monocle state. Calling `knayawp-zoom-panel` while monocle is active exits monocle first, then re-enters zoom for the appropriate panel — if the monocle window was showing a panel buffer, that panel is zoomed; if it was showing an editor buffer, the previously-zoomed panel (from `PRIOR-ZOOM-STATE`) is restored to zoom, or the layout is simply restored if there was no prior zoom.

**Narrow frame guard** — `knayawp-min-editor-columns` (default `40`) is the minimum number of columns the editor pane must retain after the right pane takes its share (`knayawp-right-width`). When `knayawp-layout-setup` is called on a frame too narrow to meet this threshold it skips the side windows entirely and emits a warning message instead of creating an unusably cramped layout.

**winner-mode integration** — `knayawp-winner-integration-flag` (default `t`) causes `knayawp-layout-teardown` to call `winner-save-conditionally` before deleting the side windows, so the full layout (including panels) is added to the `winner-mode` ring and `winner-undo` can restore it. The flag has no effect when `winner-mode` is not active, preserving the passive-loading invariant (P7).

**Magit integration:**
- Magit transient buffers (diff, log, revision) open within the magit panel, replacing status temporarily
- Pressing `q` restores the previous magit buffer (built-in `quit-restore`)
- `magit-process-mode` buffers (fetch, push, rebase, and other long-running git operations) are routed to the magit panel, not the editor pane.
- `COMMIT_EDITMSG` handling depends on `knayawp-magit-commit-style` — see "Commit flow" below.
- When `knayawp-select-panel` navigates to the magit panel, `magit-refresh` is called automatically so the status view is always current without a manual `g`.

**Commit flow:**

When the user initiates a commit (e.g. `c c` in magit-status), the
magit side window expands ("zooms") to fill the right column and the
COMMIT_EDITMSG buffer is displayed within it. On commit finish or
cancel, the 3-panel layout is restored automatically.

This behavior is controlled by `knayawp-magit-commit-style` (default
`'zoom`). Setting the style to `'editor` reverts to the v0.1.3
behavior of routing COMMIT_EDITMSG to the editor pane while the diff
goes to the magit slot. Setting it to `'off` disables all special
commit handling.

**Focus after commit** — `knayawp-magit-commit-focus-after` (default `editor`) controls where
focus lands once a `zoom`-style commit finishes or is canceled:
- `editor`: select the editor pane.
- `magit`: select the magit side window.
- `previous`: restore the window that was focused before the commit was initiated.

This option has no effect when `knayawp-magit-commit-style` is `editor` or `off`.

**Interaction with manual zoom:** If the user has manually zoomed a panel (via `knayawp-zoom-panel`) before initiating a commit, the commit-zoom step is skipped — the existing zoom stays in place. On commit finish or cancel, the pre-commit zoom state is restored (nil or the zoomed-panel symbol), so a second commit in the same session can zoom normally.

**Migration from `knayawp-magit-commit-in-editor-flag`:** This variable is deprecated since v0.1.4. If it is still set in user config and `knayawp-magit-commit-style` is at its default `'zoom`, the old flag is honored with a one-time warning (`t` → `'editor`, `nil` → `'off`). If both are customized, `knayawp-magit-commit-style` wins. Migrate by removing the old flag and setting `knayawp-magit-commit-style` explicitly.

**Terminal backend:**
- Pluggable: vterm (default) or eat, selected via customization variable
- All terminal creation goes through a dispatch layer — no direct vterm/eat API calls outside it

**Panel configuration** — `knayawp-panels` is an alist of panel specifications:

```elisp
'((magit  :slot -1 :height 0.3)
  (vterm  :slot  0 :height 0.4)
  (claude :slot  1 :height 0.3))
```

Each entry is `(TYPE :slot N)` or `(TYPE :slot N :height F)` where TYPE is one of `magit`,
`vterm`, or `claude`, N is the side-window slot (negative = top, zero = middle, positive =
bottom), and F is an optional height fraction (0–1). If ALL panels specify `:height`, those
fractions are applied on initial window creation. If ANY panel omits `:height`,
`balance-windows` equalizes all slot heights instead. In v0.1.x, only the three built-in
panel types are supported; arbitrary panel types and panel rotation are v0.3 work.

**Layout hook** — `knayawp-layout-hook` runs after `knayawp-layout-setup` completes, with all
panels displayed and the editor window selected. Use it for per-layout customization, for
example automatically starting a build command in the terminal panel.

**Global mode and project-switch integration** — `knayawp-mode` is a global minor mode
(disabled by default; loading the package alone never enables it — see P7). When enabled:

- `project-switch-project` automatically runs `knayawp-layout-setup`, so switching to a
  project creates or revisits the knayawp layout without an explicit command.
- Panel buffer routing (see below) is installed globally.

Enable it in your init file:

```elisp
(knayawp-mode 1)
```

`knayawp-mode` saves the previous value of `project-switch-commands` and restores it when
the mode is disabled.

**Panel buffer routing** — when `knayawp-mode` is active, `display-buffer-alist` entries
are installed for each panel type. Any buffer whose name matches `*knayawp-TYPE-PROJECTNAME*`
is automatically routed to the corresponding side-window slot, provided a knayawp side window
for that slot already exists in the selected frame. (Magit buffers are an exception: they use
`magit-display-buffer-function` for routing, installed by `knayawp-layout-setup` separately
from `knayawp-mode`. The `display-buffer-alist` entries here cover non-magit panel types such
as vterm and claude.) This keeps panel buffers created by external commands (e.g. a second
Claude session) inside the control pane rather than opening in the editor pane. The routing
entries are removed cleanly when `knayawp-mode` is disabled.

### Feature 2: Project Navigation Bar (v0.2)

**What it does:** Each project gets its own tab (via `tab-bar-mode`). Switching tabs switches the entire workspace — editor buffer, magit status, terminal, Claude Code — all scoped to that project.

**Operations:**
- Open a project in a new tab (auto-creates layout)
- Switch between project tabs (with completion)
- Close a project tab (kills associated tool buffers)
- Visual tab bar showing project names and optionally git branch
- Session persistence: save/restore open projects across Emacs restarts

## Non-Goals

- Not a general-purpose window manager (e.g., no tiling, no arbitrary pane arrangements)
- Not a project management tool (no tasks, issues, or code navigation beyond what magit provides)
- Not a replacement for project.el or projectile (uses project.el for project detection, doesn't duplicate it)
- Not a terminal multiplexer (no split terminals, no tabs within the terminal panel)

## Dependencies

- **Hard:** magit
- **Terminal backend (one required):** vterm or eat
- **Built-in (Emacs 29+):** project.el, tab-bar-mode

## Keybinding Policy

Per GNU Emacs conventions, `C-c LETTER` is reserved for users. The package defines a keymap (`knayawp-command-map`) but does **not** bind it globally. Users bind it themselves:

```elisp
;; Suggested in documentation, not enforced:
(global-set-key (kbd "C-c k") knayawp-command-map)
```

### Command-map conflict audit (v0.1.6)

The full set of bindings installed by `knayawp--bind-common-keys` (style-independent)
plus the style-specific additions:

**Style-independent (all styles):**
`l`, `q`, `1`, `2`, `3`, `n`, `p`, `z`, `Z`, `0`, `s`, `SPC`, `y`, `c`, `t`, `C-x`

**tmux style adds:** `<up>`, `<down>`

**byobu style adds:** `S-<up>`, `S-<down>`

**Conflict analysis** (assuming the user binds the map to `C-c k`):

| Key | Conflict with popular packages | Status |
|-----|-------------------------------|--------|
| `l` | None identified | Clean |
| `q` | None identified | Clean |
| `1` / `2` / `3` / `0` | None in prefix maps | Clean |
| `n` / `p` | None in prefix maps | Clean |
| `z` | None identified | Clean |
| `Z` | None identified | Clean |
| `s` | None identified | Clean |
| `SPC` | None identified | Clean |
| `y` | None identified | Clean |
| `c` | None identified | Clean |
| `t` | None identified | Clean |
| `C-x` | **Potential**: `C-x` is an Emacs-global prefix. As a second key under `C-c k`, the full sequence is `C-c k C-x` — this is a three-key chord and does not conflict with any standalone `C-x` binding. The binding is intentional: it delivers the Control-x byte to the Claude terminal (see `knayawp-claude-send-ctrl-x`). No code change required. | Intentional — documented |
| `<up>` / `<down>` (tmux) | `<up>` / `<down>` are unbound in most prefix maps; no conflict identified | Clean |
| `S-<up>` / `S-<down>` (byobu) | Conflict with v0.3 panel-resize bindings (#119) which plan to use `S-<up>`/`S-<down>` for grow/shrink. Must be resolved before v0.3 lands. | **Known future conflict** — tracked in spec under byobu style note |

**GNU `C-c` reservation compliance:** `C-c LETTER` is reserved for users. The
package does not install `C-c k` (or any `C-c LETTER`) globally. All bindings above
are under `knayawp-command-map`, which the user must bind explicitly. The package is
compliant with GNU key-binding conventions (property P6).

**Minor-mode keymaps in edit buffers:**

`knayawp-claude-edit-mode-map` (active only in Claude edit temp buffers):

| Key | Command | Conflict |
|-----|---------|---------|
| `C-c C-c` | `knayawp--claude-edit-finish-and-dispatch` | `C-c C-c` is conventionally "send/finish" in many modes (`org-mode`, `message-mode`, `with-editor`). In those modes this binding is not installed. In the Claude edit buffer, the temp file is opened in `text-mode` or `fundamental-mode` where `C-c C-c` is unbound by default. The binding is intentional and consistent with the convention. |
| `C-x #` | `knayawp--claude-edit-finish` | Standard `server-edit` binding — consistent with the existing Emacs convention for `emacsclient` buffers. |
| `C-c C-k` | `knayawp--claude-edit-abort` | Consistent with `magit-commit-abort` convention (`C-c C-k` = discard). No conflict in the edit temp file context. |

**Conclusion:** No bindings require renaming as of v0.1.6. The `byobu` + v0.3 resize
conflict is a known future issue and is already noted in the `byobu` style description
above. The `C-x` binding in `knayawp-command-map` is intentional and not a conflict.

## Claude Code Integration

**OS notifications when Claude waits for input.** When Claude Code runs in the terminal
panel and pauses for user input, there is no built-in signal to users focused elsewhere
in Emacs or in another application. Claude Code provides a `Notification` hook event
that fires on these occasions. Wire it to a system-level notification command via
`.claude/settings.local.json` — no Emacs Lisp required:

```json
{
  "hooks": {
    "Notification": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "notify-send 'Claude Code' 'Waiting for input' 2>/dev/null || osascript -e 'display notification \"Waiting\" with title \"Claude Code\"'"
      }]
    }]
  }
}
```

`notify-send` is used on Linux (libnotify); `osascript` is the macOS fallback. The
`2>/dev/null` suppresses errors when the command is unavailable on a given platform.
Place this in `.claude/settings.local.json` (user-local, not checked into the project
repo) so the snippet does not affect other contributors.

Claude Code's `Notification` hook also fires for other events (e.g. permission prompts
and agent-stop events), so the notification may appear for reasons other than
"waiting for user text input". That is expected and generally useful.

**Emacs as Claude's editor.** When `knayawp-claude-editor-flag` is non-nil (the default),
`knayawp-layout-setup` injects `EDITOR=emacsclient` into the Claude terminal environment.
Claude's edit-prompt action then opens the draft in Emacs via the Emacs server. A late
`server-switch-hook` handler (installed with `APPEND` so it runs after magit's own
handler) routes the emacsclient temp file into the layout and binds `C-c C-c` / `C-x #`
to finish and `C-c C-k` to discard. Finishing saves and calls `server-edit`; discarding
marks the buffer unmodified before `server-edit`, then both return focus to the Claude
panel. The handler no-ops during a commit-zoom session so the magit commit flow, which
owns `server-switch-hook` at that time, is never disturbed.

**Where the draft is displayed** is controlled by `knayawp-claude-edit-style`:

- `claude-panel` (the default): the temp file replaces the Claude panel window for the
  duration of the edit — the same in-place UX as editing a magit commit message. The
  displaced Claude terminal buffer is recorded and restored to that window automatically
  on finish and on discard. When no Claude panel window is live (zoomed, monocle, or
  hidden) the handler falls back to the editor pane so the draft is never lost.
- `editor-pane`: the temp file opens in the left editor pane and the Claude panel is left
  untouched (the pre-v0.1.6 behaviour).
- `zoom`: the temp file opens in the editor pane, which is then expanded to fill the frame
  (side windows deleted, as in monocle); the full layout is restored on finish or discard.

The restore step is guarded narrowly — it acts only when a displaced Claude buffer or a
saved window configuration was actually recorded for this edit — so it never interferes
with the magit commit flow or other emacsclient users, which travel separate code paths.

**Auto-dispatch on finish** — `knayawp-claude-auto-dispatch` (default `t`) controls
whether finishing an edit automatically submits the prompt to Claude. When non-nil,
`knayawp--claude-edit-finish-and-dispatch` (bound to `C-c C-c` in the edit buffer)
saves the file, calls `server-edit`, restores the display, focuses the Claude panel,
and then sends a carriage return to the Claude terminal so the prompt is submitted
without requiring a manual Enter. When nil, the same command delivers the prompt to
the Claude panel and focuses it, but does not auto-submit — the user presses Enter.
The same flag governs the `knayawp-send-to-claude` compose-buffer path: when
`knayawp-claude-auto-dispatch` is non-nil, `knayawp-claude-prompt-send-and-dispatch`
auto-submits the composed prompt; when nil it stops at delivery.

The header line of the edit buffer reflects the current value of the flag at edit
start: the `C-c C-c` label changes between "send+dispatch" (auto-submit on) and plain
"send" (auto-submit off).

**Dual server-hook pattern** — the Claude editor integration uses two hooks in
concert to correctly capture the trigger-origin window and route the emacsclient temp
file:

1. `server-visit-hook` → `knayawp--claude-edit-record-origin` (prepended, runs
   BEFORE `server-switch-buffer` changes `selected-window`). Records the currently
   selected window in `knayawp--claude-edit-origin-window` buffer-locally on the
   new file buffer. This captures the window the edit was triggered from — typically
   the Claude panel, but possibly the editor pane or another managed panel — before
   Emacs moves focus away.

2. `server-switch-hook` → `knayawp--claude-editor-server-switch` (appended, runs
   AFTER `server-switch-buffer` and magit's own handlers). Routes the temp file per
   `knayawp-claude-edit-style`, enables `knayawp-claude-edit-mode` on the buffer,
   and builds the header line. The APPEND flag ensures this runs after
   `magit-commit-diff-while-committing` so the two flows never interfere.

Both handlers are no-ops unless: `knayawp-claude-editor-flag` is non-nil, a knayawp
layout is active, the editor window is live, the current buffer is visiting a file,
and no commit-flow session is currently active. This guards against routing magit
commit-message buffers and other non-Claude emacsclient opens.

**Abort focus-return semantics** — `knayawp--claude-edit-abort` (bound to `C-c C-k`)
marks the buffer unmodified, calls `server-edit` to release emacsclient, restores the
display (undoing any `claude-panel` displacement or `zoom` window configuration), and
then selects a focus window. Focus goes to `knayawp--claude-edit-origin-window` when
that window is still live and on the same frame as the layout. The same-frame guard
(comparing `(window-frame origin)` with `(window-frame knayawp--editor-window)`)
prevents an `emacsclient --create-frame` invocation from causing the abort to raise a
foreign frame. When the origin window is dead or on a different frame, focus falls
back to the Claude panel via `knayawp--claude-edit-select-window`.

On finish (`C-c C-c` / `C-x #`), focus always goes to the Claude panel — the edit
is done and the user's attention should return to Claude, not to whatever triggered
the edit.

**`knayawp-claude-edit-mode`** — a buffer-local minor mode enabled by
`knayawp--claude-editor-server-switch` on each emacsclient temp file Claude opens for
prompt editing. Provides the finish/dispatch/abort keybindings in its own dedicated
keymap (`knayawp-claude-edit-mode-map`) rather than via `local-set-key`. The keymap
approach avoids mutating the shared major-mode keymap that all buffers in the same
major mode share (see ADR-005). The mode's lighter is `" ClaudeEdit"`. It is disabled
automatically when the buffer is killed (standard minor-mode semantics). Bindings:

| Key | Command | Description |
|-----|---------|-------------|
| `C-c C-c` | `knayawp--claude-edit-finish-and-dispatch` | Save, signal done, auto-submit (when `knayawp-claude-auto-dispatch` is non-nil) |
| `C-x #` | `knayawp--claude-edit-finish` | Save, signal done, focus Claude (no auto-submit) |
| `C-c C-k` | `knayawp--claude-edit-abort` | Discard draft, return focus to origin |
