---
title: "ADR-005: Use a dedicated minor-mode map for Claude edit-buffer keys"
status: accepted
date: 2026-10-30
---

# ADR-005: Use a dedicated minor-mode map for Claude edit-buffer keys

## Context

When `knayawp--claude-editor-server-switch` routes an emacsclient temp file into the
layout, it must make three keybindings available on that buffer:

- `C-c C-c` → `knayawp--claude-edit-finish-and-dispatch`
- `C-x #`   → `knayawp--claude-edit-finish`
- `C-c C-k` → `knayawp--claude-edit-abort`

The simplest implementation would be `local-set-key` (or equivalently
`(define-key (current-local-map) ...)`). Claude's temp files are typically opened in
`text-mode` or `fundamental-mode`; these modes share a single keymap object across all
their buffers.

## Problem

`local-set-key` does not create a buffer-local keymap. It mutates the *mode-local*
keymap — the keymap shared by all buffers in the same major mode. A `(local-set-key
(kbd "C-c C-c") #'knayawp--...)` call in a `text-mode` Claude temp buffer would
permanently add the binding to the `text-mode-map`, making it active in every
`text-mode` buffer for the rest of the Emacs session.

This was the defect fixed in #180: users who had other `text-mode` buffers open would
find `C-c C-c` bound to a knayawp command instead of whatever it was before (or
whatever other package had installed it). The binding persisted after the Claude edit
session ended, because `local-set-key` has no undo path.

## Decision

Define `knayawp-claude-edit-mode` as a proper `define-minor-mode` with its own sparse
keymap `knayawp-claude-edit-mode-map`. The server-switch handler enables this minor
mode buffer-locally on each Claude edit buffer. The minor mode contributes its keymap
to the buffer-local keymap chain via the standard `minor-mode-map-alist` mechanism.

When the buffer is killed, the minor mode is disabled automatically (standard Emacs
minor-mode cleanup). The bindings are thus scoped to the lifetime of the single
Claude edit buffer and never affect other buffers or the major-mode keymap.

## Consequences

**Good:**
- The finish/abort keys are strictly buffer-local and disappear when the buffer dies.
- No major-mode keymap mutation; other `text-mode` (or any-mode) buffers are unaffected.
- The minor mode is self-documenting: `M-x describe-mode` lists `ClaudeEdit` and its
  bindings in the buffer where it is active.
- `substitute-command-keys` resolves `\\[...]` references correctly when the mode is
  enabled before building the header line — the header shows actual key sequences rather
  than falling back to `M-x command-name`.
- Future bindings can be added to `knayawp-claude-edit-mode-map` without risk of
  polluting unrelated buffers.

**Trade-off:**
- Slightly more code than `local-set-key` (the `define-minor-mode` form and the
  `defvar` for the map). This cost is negligible given the correctness gain.

## Alternatives considered

**`local-set-key` / mutate current-local-map** — rejected; pollutes the shared
major-mode keymap as described above (#180).

**`make-local-variable` on the keymap then mutate** — complex, fragile, and
non-idiomatic. Minor modes are the standard Emacs mechanism for buffer-local key
additions.

**Overlay keymap via `overriding-local-map`** — too aggressive; would shadow all
other keymaps including the global map for the duration of the edit, breaking
unrelated commands.
