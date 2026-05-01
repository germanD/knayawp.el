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

**Status:** ready (pending user sign-off on rotation keys and milestone scope)

### Motivation

The current v0.1 layout pins all three tool panels (magit, vterm, claude) into
the right-side pane simultaneously. On a wide monitor that's fine; on a laptop
screen the three panels become uncomfortably short and the editor pane gets
squeezed. We want the package to scale gracefully across screen sizes without
forcing the user to manually reconfigure `knayawp-panels` each time they
undock.

### Layout taxonomy

A **layout** is a named selection of which panels are visible on the side
pane and in what order; the rest of the configured panels are *stashed* (alive
as buffers, just not displayed). Three layouts ship by default:

- **`wide`** (current behavior, default): all three panels visible.
- **`narrow`**: two visible (default `magit` + `claude`), `vterm` stashed.
- **`solo`**: one visible, the other two stashed — effectively a permanent
  zoom for laptop-sized screens.

The `narrow` layout is the interesting one: it introduces a tmux-style
"current visible panels + stash" model with a rotation primitive that swaps
a stashed panel into a visible slot.

### Data model

Two defcustoms split responsibilities cleanly:

- **`knayawp-panels`** stays the catalogue of *what panels exist and where
  they live* (slot, height, type). Existing user values continue to work.
- **`knayawp-layouts`** is new. It declares *which subset of panels is
  visible right now* under a given layout name. Slot/type metadata stays in
  `knayawp-panels` so layouts don't redeclare it.

```elisp
(defcustom knayawp-layouts
  '((wide   :visible (magit vterm claude))
    (narrow :visible (magit claude) :stash (vterm))
    (solo   :visible (claude)       :stash (magit vterm)))
  "Named layouts mapping panel selections to display state."
  :type '(alist :key-type symbol :value-type plist)
  :group 'knayawp)

(defcustom knayawp-default-layout 'wide
  "Layout selected by `knayawp-layout-setup' when none is given."
  :type 'symbol
  :group 'knayawp)
```

If `knayawp-layouts` is unset, a `wide`-equivalent layout is derived from
`knayawp-panels` so existing users see no change.

### Decisions (synthesis from design pass)

The architect, prior-art, and risk/migration agents converged on the
following positions. Disagreements explicitly noted.

1. **Zoom subsumes into `solo`.** `knayawp-zoom-panel` becomes a thin wrapper
   that applies an ephemeral `solo-<panel>` layout, recording the prior
   layout in `knayawp--pre-zoom-layout`. `knayawp--zoomed-panel` survives
   one minor cycle as a compat shim updated by the layout system; it can
   be retired once external configs that touch it have time to migrate.
   The public `knayawp-zoom-panel` command stays forever.

2. **Explicit layout selection first; auto-detect is opt-in.** A new
   `knayawp-select-layout` command (completing-read over `knayawp-layouts`)
   is bound to `L` under the prefix. `knayawp-layout-auto-select-flag`
   defaults to `nil` and is added later, gated on real-world threshold
   data. Auto-detect on tiling WMs (i3/sway) risks fighting the user, so
   it never defaults on inside 0.x.

3. **Persistence per project deferred to v0.2.x.** Tab-bar workspaces are
   the natural carrier for per-project layout state — wiring layout
   persistence into a tab parameter is one line at that point. Inventing a
   separate per-project storage now means migration churn later.

4. **`narrow` defaults: magit + claude visible, vterm stashed.** Encoded
   in the `knayawp-layouts` default — no separate `knayawp-narrow-visible-
   panels` defcustom needed (users override the layout entry directly).

5. **Rotation key — open.** *Plan agent* proposed `C-c k <left>` / `<right>`.
   *Prior-art agent* warned that `C-c <left>` / `<right>` are winner-mode
   muscle memory and the prefix variant will misfire visually. Two safer
   options: `C-c k f` / `C-c k b` (forward/back) or `C-c k >` / `C-c k <`
   (mirroring tmux's `{` / `}` rotation glyphs without shift). **Decision
   needs user sign-off before issue L4 lands.**

6. **`C-c k n` / `C-c k p` keybinding migration is the only true break.**
   Three-phase rollout (see issue plan): additive in v0.2.x, soft-
   deprecation in v0.3.0-beta, default flip in v0.3.0. The function
   symbols stay callable via `M-x` permanently with `make-obsolete`.

### Prior-art guardrails

From the research pass — what to steal and what to skip:

- **Steal from tmux**: two-tier model (panes-visible vs windows-hidden);
  `rotate-window` semantics over `swap-pane` (cycle, don't point-swap);
  `swap-pane -d` convention — rotation never steals focus from the editor;
  status indicator in the spirit of tmux's `*` / `-` / `Z` (one character
  per panel in the side-window mode line, current marked).
- **Steal from i3**: `layout toggle split` idiom — a single command
  `knayawp-layout-cycle` walking `solo → narrow → wide → solo`.
- **Steal from popper.el**: study its `popper-buried-popup-alist` shape
  for `knayawp--panels-offscreen`. Don't depend on popper.
- **Reject** top tab strips (bufferline.nvim / i3 tabbed titles) — they
  add visual noise on the small screens this feature targets.
- **Reject** Vim's "tab" terminology for in-side-pane rotation — "tab"
  already means `tab-bar-mode` workspace in v0.2 vocabulary.
- **Reject** ace-window-style overlays for offscreen panels (nothing to
  overlay onto). Overlays are reserved for Idea 2.
- **Reject** hard-coded `frame-width` thresholds for auto-detect.
- **Lean on**: `display-buffer-in-side-window` + `window-parameters`,
  `tab-line-mode` (only as opt-in within the side window), `winner-mode`
  exemption (rotation must not pollute winner history). **Skip**
  `shackle.el` and `purpose.el` — both wrap `display-buffer-alist` and
  we want to call `display-buffer` directly per project conventions.

### Sequenced rollout (issue plan)

Filed against a new **v0.3.0** milestone. Rationale: v0.1.3 is for v0.1.2
follow-on patches; v0.2.x is locked to tab-bar workspaces; layouts deserve
their own release line. Phase 0 below is the only candidate for landing
inside v0.2.x as additive prelude.

**Phase 0 — strictly additive, zero breaking changes (v0.2.x):**

- **L1.** Introduce `knayawp-layouts` + `knayawp-default-layout` defcustoms;
  add internal `knayawp--apply-layout` resolver. `knayawp-layout-setup`
  calls `(knayawp--apply-layout knayawp-default-layout)`. If
  `knayawp-layouts` is unset, derive a `wide`-equivalent layout from
  `knayawp-panels`. No user-visible change.
- **L2.** Reimplement zoom internally as ephemeral `solo` layout. Keep
  `knayawp-zoom-panel` and `knayawp--zoomed-panel` (the latter as a compat
  shim updated by the layout system). ERT covers zoom/unzoom round-trip.
- **L3.** Add `knayawp-select-layout` (interactive completing-read) bound
  to `L`. `narrow` and `solo` layouts become selectable but `wide` stays
  default.
- **L4.** Add `knayawp-rotate-next` / `knayawp-rotate-prev` and bind them
  to a chosen pair (see decision 5). No-op in `wide`. `n` / `p` keymap
  unchanged. Add a one-character status indicator in the side-window mode
  line (panel symbol + `*` for current, dim for stashed).

**Phase 1 — opt-in changes (v0.3.0-beta):**

- **L5.** Add `knayawp-layout-auto-select-flag` (default `nil`) and
  `knayawp-narrow-threshold-columns`. Auto-selection only fires when the
  flag is set.
- **L6.** Mark `knayawp-next-panel` / `knayawp-prev-panel` obsolete via
  `make-obsolete`. Keymap unchanged. README documents the upcoming flip.

**Phase 2 — keymap flip (v0.3.0 release):**

- **L7.** Flip `n` / `p` in `knayawp-command-map` to intra-pane window
  cycling. Old function symbols remain callable. NEWS / README documents
  the migration with a one-liner to restore the old keymap.

**Phase 3 — polish (v0.3.x, follow-up issues, not pre-filed):**

- Default-on auto-detect once user feedback confirms it isn't surprising.
- Retire `knayawp--zoomed-panel` internal compat shim.

### Risk register (top 3, full list in design notes)

1. **Keymap rebind silently breaks muscle memory.** Mitigation: full minor
   cycle of `make-obsolete` warnings + README NEWS entry. Reversible in a
   patch.
2. **`knayawp-panels` semantic shift hides panels.** Mitigation: derive
   `wide` layout from `knayawp-panels` when `knayawp-layouts` is unset;
   default layout is `wide`. Reversible.
3. **Zoom/layout state-machine collision.** Mitigation: single state owner
   from L2 onward — `knayawp--zoomed-panel` becomes a derived value, not a
   primary state. Structural risk; landing L1+L2 together is the de-risk.

### Promote-to-issue checklist

- [ ] User decides rotation keys (decision 5): `f`/`b`, `>`/`<`, or arrows.
- [ ] User confirms v0.3.0 milestone vs squeezing Phase 0 into v0.2.x.
- [ ] File issues L1–L7 against the chosen milestones, in dependency
      order, with the issue bodies derived from the phased plan above.
- [ ] When ready to start work, add corresponding `- [ ]` lines to PLAN.md
      under each milestone (per the PLAN.md ↔ milestone invariant).

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
