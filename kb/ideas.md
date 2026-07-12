---
title: knayawp.el Forward-Looking Ideas
last-updated: 2026-07-12
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

**Status:** promoted to v0.3.0 milestone

### Motivation

The current v0.1 layout pins all three tool panels (magit, vterm, claude) into
the right-side pane simultaneously. On a laptop screen the three panels become
uncomfortably short and the editor pane gets squeezed. Named layouts with a
panel-rotation primitive let the package scale gracefully across screen sizes.

Promoted to v0.3.0 milestone; see issues #69–#75 for the phased rollout
(foundation defcustoms → zoom refactor → select command → rotation → auto-detect
→ soft-deprecation → keymap flip).

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

---

## Idea 3 — Frictionless copy/paste from protected terminal panels

**Status:** sketch

### Motivation

The whole point of the layout is having magit, vterm, and Claude side by
side. In practice the author hits a sharp pain point several times per
session: copying shell input/output out of the terminal panel into Claude
(or to an external app) requires the full vterm copy-mode choreography —
`C-c C-t` to enter copy-mode, navigate to the start of the region, set
mark, navigate to the end, `M-w`, then `C-c C-t` again to exit. That's
six keystrokes for a copy that takes one in any "normal" buffer, and the
modal nature means it's easy to forget you're still in copy-mode and lose
the next character of "real" input.

The protected (side-window) panels are an even higher-friction surface
than a standalone vterm, because the user's eye flicks between them
constantly to pipe context from one tool to the next.

### What we want

A seamless, single-keystroke way to flip a protected panel between
"interactive" (current vterm default, accepts keystrokes) and
"readable" (point moves freely, selection works, no copy-mode dance).
Ideally one keystroke under `knayawp-command-map` toggles the *current*
panel; a second keystroke (or a different binding) toggles *all*
terminal panels at once.

### Approaches to investigate

#### A. Wrap vterm-copy-mode in a friendlier toggle

vterm-copy-mode already exists; the issue is that it's awkward to invoke
and that you have to remember to leave it. A knayawp-level toggle could:

- Bind a single key under the prefix (say `c`) that calls
  `vterm-copy-mode` on the current side window.
- Optionally exit copy-mode automatically on certain events (window
  selection change? mouse click outside the panel?).
- Mode-line indicator so the user knows which mode the panel is in.

Cheap, deliverable as a small command. Doesn't address the underlying
modal friction, but smooths the keystroke cost.

#### B. Default panels to "readable" and only enter "live" on demand

Inverse of the current default. Side-window terminal panels would render
as normal selectable text by default; pressing a key (or focusing the
panel and typing) would flip them to live-input mode. Mouse selection
just works.

Bigger change in mental model, but matches how IDE consoles tend to
behave. Requires investigating whether vterm can be coaxed into this
mode reliably — vterm's read-only state is enforced by `vterm-mode`
keymap precedence, not buffer read-only, so it might be cleaner than it
looks. Worth a deep dive before committing.

#### C. Backend lever — eat may sidestep the problem entirely

eat (`knayawp-terminal-backend = 'eat`) uses pure Emacs redisplay and
its semi-char-mode allows ordinary point movement and selection between
keystrokes. If eat handles copy out of the box without modal dance, the
right answer might just be: document the trade-off, default to vterm
for performance, recommend eat for users who care more about copy
ergonomics than refresh smoothness. This also strengthens the case for
the existing backend abstraction (P3).

Concretely: side-by-side test session — same task in both backends,
record the keystroke cost of copying a multi-line shell output into the
Claude panel.

#### D. Panel-state generalisation

The most ambitious framing: panels are state machines with at least
two states (`live` / `readable`), with a single defcustom controlling
the default state per panel type. The global toggle (idea A) becomes
the user-facing handle on this state. magit panels are always
readable; vterm/claude panels start `live` but can be flipped.

This is the "right" abstraction if we believe other backends or panel
types will land later. It's also overkill for a single pain point.
Park it unless a second instance of the same problem surfaces.

### Open questions

1. **Does vterm really require modal copy or is there a config knob?**
   Search vterm docs for selection/mouse handling. If a simple
   `vterm-disable-...-something` exists, the whole idea collapses to
   one defcustom and a docstring.
2. **What does eat actually do?** Need a hands-on comparison. If eat is
   already frictionless, idea C is the cheapest win.
3. **Mouse vs keyboard.** The pain point is keyboard-driven (the user
   wants to copy without leaving the keyboard). But mouse selection in
   side windows is also broken in vterm copy-mode UX. Worth confirming
   both surfaces in one fix.
4. **Interaction with `knayawp-isolate-other-window-flag`.** If the
   panel is "readable", does `C-x o` still skip it? Probably yes —
   isolation is about layout immunity (P1), not buffer interaction.
   But worth re-reading P1 against both flags together.

### Promote-to-issue checklist

- [ ] Empirical pass: confirm whether vterm has a low-friction
      configuration for selection (resolve open question 1).
- [ ] Empirical pass: compare eat vs vterm copy ergonomics
      side-by-side (resolve open question 2).
- [ ] Decide between A (toggle), B (inverted default), C (recommend
      eat), or some hybrid.
- [ ] If A or B wins: file an issue against v0.1.5 (or later) once the
      shape is settled. If C wins: file a docs-only issue and an
      `kb/spec.md` clarification on backend trade-offs.
