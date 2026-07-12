---
title: "ADR-004: with-editor Winconf Cooperation for Commit Zoom"
date: 2026-06-01
status: accepted
---

# ADR-004: with-editor Winconf Cooperation for Commit Zoom

## Status

Accepted. See also P9 in `properties.md`.

## Context

The `zoom` commit style expands the magit slot to fill the right column when the user
presses `c c`. `with-editor` also captures and restores a window configuration around
the commit session — but its snapshot is taken *after* knayawp has already zoomed, so
it only sees the single zoomed-magit layout, not the full 3-panel layout.

Without intervention, the post-commit restore from with-editor leaves the user staring
at a zoomed magit window with the terminal and Claude panels gone.

Two approaches were considered:

1. **Advise with-editor's restore** — override `with-editor--restore-window-configuration`
   to no-op when knayawp has a pending restore. Simple, but violates ADR-002 and couples
   knayawp to with-editor internals that have changed across versions.

2. **Self-managed winconf, applied after with-editor's** — capture our own snapshot
   *before* the zoom, then restore it from `with-editor-post-{finish,cancel}-hook`. Our
   restore runs after with-editor's and intentionally overwrites it.

## Decision

In `knayawp--commit-flow-start` (on `git-commit-setup-hook`), capture
`(current-window-configuration)` before calling `knayawp--apply-zoom-solo-magit`.
Attach `knayawp--restore-commit-pre-state` to `with-editor-post-finish-hook` and
`with-editor-post-cancel-hook`. That function calls `set-window-configuration` on the
pre-zoom snapshot after with-editor's own restore has already run.

The restore is gated on `(eq (window-configuration-frame winconf) (selected-frame))` to
prevent cross-frame scrambling.

## Consequences

**Good:**
- No advice on with-editor or any built-in — fully consistent with ADR-002.
- Works with any future with-editor refactor that preserves its hook points.
- Reasoning is simple: our restore always wins because it runs last.

**Trade-off:**
- with-editor's restore is a wasted operation (it runs, then is immediately overwritten).
  Not harmful but slightly redundant.
- The ordering assumption — with-editor's hook runs before ours — relies on us appending
  after with-editor registers. Reliable in practice; documented so it isn't broken
  accidentally.
- If a third package restores window configuration from the same hooks, last-one-wins
  semantics apply. We document this in P9 but cannot prevent it.
