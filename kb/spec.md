---
title: knayawp.el Product Specification
last-updated: 2026-08-10
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
