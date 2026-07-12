---
title: "ADR-003: Terminal Backend Abstraction"
date: 2026-03-01
status: accepted
---

# ADR-003: Terminal Backend Abstraction

## Status

Accepted. Enforced as P3 in `properties.md`.

## Context

Two viable Emacs terminal backends exist:

- **vterm** — C extension, fastest refresh, widely deployed. Copy ergonomics require
  `vterm-copy-mode` (modal, six keystrokes for a plain copy).
- **eat** — pure Elisp, no native dependency, semi-char-mode lets point move freely
  between keystrokes so ordinary selection works without a modal toggle.

The author uses vterm but wants the ability to switch without touching layout code.
Future users may prefer eat or a backend not yet written.

## Decision

All terminal buffer creation is confined behind two functions:

- `knayawp--make-terminal` — dispatch point, reads `knayawp-terminal-backend`.
- `knayawp--make-terminal-vterm` / `knayawp--make-terminal-eat` — backend
  implementations.

No code outside these functions may reference vterm or eat APIs directly (buffer
creation, process management, mode-specific keybindings). New backends are added by
implementing one `knayawp--make-terminal-NAME` function and adding a case to the
dispatcher.

## Consequences

**Good:**
- Switching backends is a one-line customization: `(setq knayawp-terminal-backend 'eat)`.
- Layout, navigation, magit integration, and commit-flow code are fully decoupled from
  terminal API details.
- Backend-specific bugs are localized to a single small function.

**Trade-off:**
- The abstraction is deliberately thin. Behavioral differences between backends
  (copy ergonomics, scroll behaviour, process-reuse semantics, mouse handling) are not
  hidden. Users who need fine-grained control extend `knayawp--make-terminal-*`.
- Testing the full matrix (vterm × eat × layout variants) is expensive; the test suite
  covers the dispatch logic but not backend-specific rendering.
