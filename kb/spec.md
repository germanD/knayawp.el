---
title: knayawp.el Product Specification
last-updated: 2026-04-27
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

### Feature 1: Automatic Project Layout (v0.1)

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

**Magit integration:**
- Magit transient buffers (diff, log, revision) open within the magit panel, replacing status temporarily
- Pressing `q` restores the previous magit buffer (built-in `quit-restore`)
- COMMIT_EDITMSG opens in the editor pane (commits are editing tasks)

**Terminal backend:**
- Pluggable: vterm (default) or eat, selected via customization variable
- All terminal creation goes through a dispatch layer — no direct vterm/eat API calls outside it

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
