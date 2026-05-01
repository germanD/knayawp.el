---
title: knayawp.el Forward-Looking Ideas
last-updated: 2026-05-01
status: incubator
---

# Ideas — Forward-Looking Features

This file is the incubator for features and design directions that are not yet
committed work. Entries here are deliberately loose: they capture motivation,
rough shape, open questions, and prior art. Once an idea is concrete enough to
scope, promote it to a GitHub issue against the appropriate milestone and
delete (or shrink) the entry here.

Status legend per idea:
- **sketch** — rough, still being thought through
- **ready** — design concrete enough to file as one or more issues
- **deferred** — captured but intentionally not pursued right now (record why)

---

## Idea 1 — Alternative layouts and panel rotation

**Status:** sketch

### Motivation

The current v0.1 layout pins all three tool panels (magit, vterm, claude) into
the right-side pane simultaneously. On a wide monitor that's fine; on a laptop
screen the three panels become uncomfortably short and the editor pane gets
squeezed. We want the package to scale gracefully across screen sizes without
forcing the user to manually reconfigure `knayawp-panels` each time they
undock.

### Rough shape

Introduce the notion of a **layout** — a named arrangement of which panels are
*visible* on the side pane and which are *offscreen* (still alive as buffers,
just not displayed). Switching layouts swaps which panels are shown.

Examples:

- `wide` (current default): all three panels visible.
- `narrow`: two visible (e.g. magit + claude), the third (vterm) lives
  offscreen and can be swapped in via a rotation command.
- `solo`: only one visible, the other two offscreen — effectively a "always
  zoomed" layout for very small screens.

The `narrow` layout is the interesting one because it introduces a tmux-style
notion of "the current panel" plus a stash of hidden panels you rotate
through.

### Integration with existing concepts

- **Zoom mode** already implements "show one panel, hide the others, remember
  the originals." Layouts generalise that: zoom is the `solo` layout with a
  return path. Implementing layouts properly should let zoom fall out as a
  special case rather than a parallel mechanism.
- **Rotation** in narrow mode (next/prev panel through the hidden stash) maps
  naturally onto the existing `knayawp-next-panel` / `knayawp-prev-panel`
  cycle, but the semantics shift: instead of moving point between visible
  windows, rotation swaps which panel occupies a given visible slot.
- **`C-c k l`** (layout setup) could detect `frame-width` / `frame-height` and
  pick a default layout. *Open question — see below.*

### Keybinding implications

If rotation becomes the dominant motion in narrow layouts, we may want to
re-bind:

- `C-c k n` / `C-c k p` → up/down arrows (intra-pane window cycling, current
  meaning)
- `C-c k <left>` / `C-c k <right>` → rotate hidden panel into visible slot
  (new)

This is a breaking change to the v0.1.1 keymap, so it would need to land in a
minor version bump and be opt-in for at least one cycle.

### Open questions

1. **Auto-detect vs explicit selection.** Should `C-c k l` infer the layout
   from `frame-width`, or should the user always pick? Tradeoff: auto-detect
   is magical and hard to predict; explicit selection is one extra keystroke
   but you always know what you'll get. Lean: ship explicit first
   (`C-c k L` to pick a layout), add `knayawp-layout-auto-select` as an
   opt-in defcustom once thresholds are well-understood.

2. **Persistence per project.** Should the chosen layout be remembered per
   project (so `myapp` always opens `narrow` regardless of frame size)? Or
   global per frame? Probably project-scoped, but defer until v0.2 when
   tab-bar workspaces exist.

3. **What goes offscreen by default in `narrow`?** vterm seems like the
   natural candidate (least-used in many flows) but this is highly
   user-dependent. Should be a defcustom: `knayawp-narrow-visible-panels`.

### Prior art

- **tmux:** windows-within-session model, `prefix + n/p` to rotate, hidden
  windows still alive. Direct inspiration for the rotation semantics.
- **i3/sway tabbed/stacked containers:** one visible, others as tabs at the
  top. Could inform the eventual visual indicator (idea 2).
- **Emacs `tab-line-mode`:** could render the offscreen panel list as tabs
  inside the side pane, giving free affordance for "what's hidden."

### Promote-to-issue checklist

- [ ] Lock the layout taxonomy (names, defaults).
- [ ] Decide rotation keybindings (and migration plan).
- [ ] Decide auto-detect vs explicit (probably explicit-first).
- [ ] Spec how zoom collapses into the layout abstraction.

---

## Idea 2 — Visual navigation guidance for the side pane

**Status:** sketch

### Motivation

The v0.1.1 keymap exposes nine commands under `C-c k` (`l q 1 2 3 n p z 0 s`).
Newcomers — and even the author after a week away — don't remember which
slot is which. Discoverability is currently zero: you have to read the README
to learn that `1` is magit and `3` is claude.

We want a visible affordance that teaches and reminds the user without
cluttering the layout when they don't need it.

### Three candidate approaches

#### A. Overlay window labels (ace-window style)

Display a large `1` / `2` / `3` / `0` overlay in each window, briefly, when
the user is about to navigate. The overlay is pure visual feedback — it
doesn't change the keymap, just reveals the existing one.

- **Pros:** spatially anchored to the window it labels — no mental mapping.
  Familiar to users of `ace-window`, `winum`, or `switch-window`.
- **Cons:** flashes content; needs a trigger (timer? prefix-press? always
  on?); overlays interact with face/theme settings in surprising ways.

#### B. Help tooltip on `C-c k ?`

Bind `?` (and `C-h`) inside `knayawp-command-map` to pop a `*Help*` buffer
listing all bindings with descriptions. This is the GNU-recommended idiom
for prefix maps and falls out of `describe-keymap` essentially for free.

- **Pros:** zero magic, fully Emacs-idiomatic, no overlay machinery, works
  with `describe-keymap` users already know.
- **Cons:** opt-in — user has to know `?` exists. No spatial mapping; you
  read "1: magit" rather than seeing `1` next to magit.

#### C. Auto-popup on prefix press (which-key style)

After pressing `C-c k` and pausing, automatically show the available next
keys in a small popup. This is what `which-key-mode` does (and `which-key`
is built into Emacs 30+).

- **Pros:** the most discoverable — surfaces the keymap at the exact moment
  of confusion. Familiar to Spacemacs / Doom users.
- **Cons:** harder to implement from scratch; arguably "not the Emacs way"
  if the user already runs `which-key-mode` themselves (we'd be duplicating
  it). Best path is probably to *integrate with* which-key rather than
  reimplement.

### What can we learn from other editors?

- **VS Code:** chord prefixes (`Ctrl+K Ctrl+S`) show a small toast in the
  status bar listing the next-key options. Always-on, low-friction. Closest
  to which-key in spirit.
- **Sublime Text:** no built-in chord guidance; relies on the Command Palette
  (`Ctrl+Shift+P`) for discovery. Different model — search-by-name rather
  than spatial.
- **JetBrains IDEs:** "Find Action" (`Ctrl+Shift+A`) plus a "Key Promoter X"
  plugin that nudges you toward keybindings when you use the menu. Two
  separate mechanisms; the nudge is interesting.
- **tmux:** the prefix shows nothing; users bind `?` to `list-keys` if they
  want help. Closest to option B, and a strong precedent for the
  "earn your discoverability" approach.
- **Vim / Neovim:** modern Neovim ecosystems have standardised on
  `which-key.nvim`, which has converged with Emacs's `which-key`. The fact
  that both ecosystems independently arrived at the same UX is a strong
  signal.

### Open questions

1. **Pick one or layer them?** B (help on `?`) is cheap and strict-Emacs;
   it should ship regardless. The real question is whether to add A or C
   on top, and whether they should be opt-in defcustoms or default-on.

2. **If we add overlays (A), when do they fire?** Always on (clutter)? Only
   while the prefix is held (state machine)? Only on a dedicated command
   like `knayawp-show-panel-numbers`? Lean: dedicated command, optionally
   bound under the prefix as `C-c k ?` alongside the help buffer.

3. **Do we lean on `which-key`?** If the user has `which-key-mode` enabled,
   our prefix already gets popup hints for free — we just need to write
   good docstrings on each command. Maybe the right answer for C is "do
   nothing, write good docstrings, recommend `which-key` in the README."

### Promote-to-issue checklist

- [ ] Implement B (`?` help in `knayawp-command-map`) — cheap, ship in next
      patch release.
- [ ] Decide A: overlays as opt-in command, default off?
- [ ] Decide C: punt to `which-key` and document, or build native?
- [ ] Audit existing command docstrings for which-key-friendliness.
