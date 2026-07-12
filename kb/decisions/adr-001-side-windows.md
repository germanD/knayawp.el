---
title: "ADR-001: Use Side Windows for the Control Pane"
date: 2026-03-01
status: accepted
---

# ADR-001: Use Side Windows for the Control Pane

## Status

Accepted.

## Context

The control pane (magit, terminal, Claude Code) must be immune to standard Emacs
window commands. Users regularly press `C-x 1`, `C-x 0`, `C-x 2/3`, and `C-x o`
inside the editor pane and expect them to affect only that pane, not the tool panels.

Three approaches were considered:

1. **Regular split windows + advice** on `delete-other-windows`, `split-window`,
   `other-window` — works but violates ADR-002 (no advice on built-ins) and is fragile
   across Emacs versions.

2. **Dedicated frames** — each tool in its own OS window. Simple to isolate but breaks
   the unified layout, requires complex focus management, and conflicts with most tiling
   window managers.

3. **Emacs side windows** — `display-buffer-in-side-window` (Emacs 26+) gives
   first-class support for immune panels: `no-delete-other-windows`, `no-other-window`,
   and non-splittable semantics come for free via window parameters.

## Decision

Use `display-buffer-in-side-window` for all control-pane panels, with window parameters
`no-delete-other-windows t` and conditionally `no-other-window t` (gated on
`knayawp-isolate-other-window-flag`).

The right side (`side . right`) with three integer slots (−1, 0, 1) stacks panels
vertically. Slot ordering is declarative via `knayawp-panels`.

## Consequences

**Good:**
- Layout immunity is achieved through documented Emacs APIs, not fragile advice.
- `window-toggle-side-windows` provides free hide/show at no implementation cost.
- `preserve-size` locks the right-column width after initial sizing.
- Side windows survive `C-x 1` by design — no custom logic required.
- `window-sides-slots` is set to `(nil nil nil 3)` at layout-setup time (global to the frame)
  so Emacs allows three right-side slots. This is intentional: the variable has no per-frame
  version in Emacs 29. The consequence is that other packages using right side windows on the
  same frame will also be subject to the 3-slot limit — an acceptable trade-off for a package
  that owns the right column.

**Trade-off:**
- Side windows cannot be split by the user; any attempt inside the control pane is
  silently blocked by Emacs.
- `display-buffer` never reuses a side window unless explicitly targeted, so every
  panel buffer must be routed via `display-buffer-alist` (see P5 in `properties.md`).
- Only one set of side windows per frame. v0.2 multi-project workspaces use
  `tab-bar-mode` rather than additional side-window sets per tab.
