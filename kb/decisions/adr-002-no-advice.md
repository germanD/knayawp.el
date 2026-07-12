---
title: "ADR-002: Zero Advice on Built-in Functions"
date: 2026-03-01
status: accepted
---

# ADR-002: Zero Advice on Built-in Functions

## Status

Accepted. Enforced as P2 in `properties.md`.

## Context

Window layout management often needs to intercept `delete-other-windows`,
`split-window`, `other-window`, and `display-buffer`. The fastest path is
`advice-add` or `defadvice`.

Several other packages the target user is likely to run (e.g. `golden-ratio`,
`zoom.el`, `ace-window`, `winner-mode`) also advise these functions. Stacking
advice from multiple packages is a known source of hard-to-diagnose interactions.

## Decision

The package must not advise any Emacs built-in or any function from a dependency.
All interception goes through documented, stable extension points:

| Goal | Mechanism |
|---|---|
| Block `C-x 1` from deleting panels | `no-delete-other-windows` window parameter |
| Block `C-x o` from cycling into panels | `no-other-window` window parameter |
| Route magit buffers to the magit slot | `magit-display-buffer-function` |
| Route all other panel buffers | `display-buffer-alist` entries |
| Intercept commit start/finish | `git-commit-setup-hook`, `with-editor-post-{finish,cancel}-hook` |

## Consequences

**Good:**
- The package co-exists cleanly with other packages that advise window functions.
- Emacs version upgrades that change built-in signatures don't affect knayawp.
- Debugging window behaviour is straightforward — no invisible advice layers.

**Trade-off:**
- Some things that are trivial with advice require more creative solutions. The
  `with-editor` winconf race (ADR-004) is one example: without advising
  `set-window-configuration` we must sequence our own restore call *after*
  with-editor's rather than replacing it.
