---
title: knayawp.el Invariants and Properties
last-updated: 2026-04-27
status: draft
---

# Invariants and Properties

These are correctness constraints that must hold at all times. If code contradicts a property, the code is wrong — not this document.

## P1: Layout Immunity

**Side windows in the control pane must be immune to standard window commands.**

- `C-x 1` (`delete-other-windows`) must not delete control pane windows.
- `C-x 0` (`delete-window`) in the editor pane must not affect control pane windows.
- `C-x 2` / `C-x 3` (`split-window`) must not split control pane windows.
- `C-x o` (`other-window`) must not cycle into control pane windows.

**Mechanism:** Side windows with `no-delete-other-windows` and `no-other-window` parameters. No advice on built-in functions.

## P2: Zero Advice on Built-in Functions

The package must not use `advice-add`, `defadvice`, or any form of advising on Emacs built-in functions (`delete-other-windows`, `split-window`, `other-window`, `display-buffer`, etc.). All behavior must be achieved through documented APIs: window parameters, `display-buffer-alist`, `magit-display-buffer-function`, and similar customization points.

**Why:** Advice is fragile across Emacs versions and conflicts with other packages.

## P3: Terminal Backend Isolation

No code outside `knayawp--make-terminal-*` functions may reference vterm or eat APIs directly. All terminal buffer creation goes through `knayawp--make-terminal`. This includes:
- Buffer creation
- Process management
- Mode-specific keybinding setup

**Why:** The terminal backend must be swappable without touching layout, navigation, or integration code.

## P4: Project-Scoped Buffers

Every tool buffer created by knayawp must be scoped to a project:
- Buffer name pattern: `*knayawp-TYPE-PROJECTNAME*`
- If a buffer for this project already exists, reuse it — never create duplicates.
- When a project workspace is closed (v0.2), all its knayawp buffers must be killed.

## P5: Magit Buffer Containment

When the knayawp layout is active:
- All `magit-mode`-derived buffers must display in the magit side window (slot -1), not in the editor pane.
- `COMMIT_EDITMSG` must display in the editor pane (not the control pane).
- Transient magit buffers (diff, log, revision) replace the current buffer in the magit window. Pressing `q` must restore the previous buffer via the built-in `quit-restore` mechanism — no custom restoration code.

**Exception:** When knayawp layout is not active, magit must behave normally (fall back to `magit-display-buffer-traditional`).

## P6: Keybinding Convention Compliance

- The package must NOT globally bind `C-c LETTER` (reserved for users per GNU conventions).
- The package defines `knayawp-command-map` and documents a suggested binding.
- The package may bind keys in its own minor mode map using `C-c` + non-letter characters if needed.

## P7: Passive Loading

Simply loading (`require`) the package must not activate any functionality. No hooks are installed, no keybindings are set, no `display-buffer-alist` entries are added until the user explicitly calls `knayawp-layout-setup` or enables `knayawp-mode`.

## P8: Graceful Degradation

- If magit is not installed: the magit panel shows an informational buffer, not an error.
- If the selected terminal backend is not installed: signal a `user-error` with a clear message naming the missing package.
- If the frame is too narrow for the layout: skip the control pane and message the user.

## P9: with-editor Cooperation via Self-Managed Winconf

When the `'zoom` commit style is active, knayawp captures `(current-window-configuration)` in `knayawp--commit-flow-start` *before* mutating the layout (i.e. before `knayawp--apply-zoom-solo-magit` runs). On commit finish or cancel, `knayawp--restore-commit-pre-state` calls `set-window-configuration` on that captured snapshot, overriding the restore that `with-editor` performs from its own `with-editor-previous-winconf`. with-editor's snapshot is captured *after* knayawp's `git-commit-setup-hook` handler has already zoomed, so it only contains the magit slot — restoring from it would lose the terminal and Claude side windows. knayawp's own snapshot, taken pre-zoom, is the only reliable source for the full 3-panel layout.

knayawp does not advise or rebind any with-editor function. It cooperates through documented extension points: `git-commit-setup-hook` to enter the zoom, and `with-editor-post-finish-hook` / `with-editor-post-cancel-hook` to drive the restore. with-editor's own `set-window-configuration` call runs first and is intentionally overwritten by ours.

**Why:** Running our restore after with-editor's restore (rather than instead of it) avoids touching with-editor internals while still producing the right post-commit layout. The restore is gated on `(eq (window-configuration-frame winconf) (selected-frame))` to avoid cross-frame scrambling.

P5's "no custom restoration code" clause applies to `q`-quit of magit transients within a single side window slot. The commit lifecycle is a distinct multi-buffer flow that legitimately requires knayawp-managed restoration, and the two properties do not conflict.
