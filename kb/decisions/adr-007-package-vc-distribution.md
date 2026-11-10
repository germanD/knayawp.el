---
title: "ADR-007: package-vc as the primary install and dogfooding path"
date: 2026-11-10
status: accepted
---

# ADR-007: package-vc as the primary install and dogfooding path

## Status

Accepted. MELPA remains the stated long-term channel but is not yet pursued.

## Context

knayawp needs an install story that satisfies two goals simultaneously:

1. **End-user fidelity** — the install path must exercise real Emacs package machinery
   (autoload generation, byte-compilation, `package-installed-p` integration) so that
   bugs in those steps surface during development, not after MELPA submission.

2. **HEAD dogfooding** — the author must be able to run against HEAD of the local
   working checkout throughout the development cycle, not against a pinned MELPA
   release.

The project targets Emacs 29+ throughout. The question is which install mechanism
to designate as the primary path that both README and profile `init.el` files
recommend.

### Alternatives evaluated

| Mechanism | End-user fidelity | HEAD dogfooding | Emacs 29+ native | Notes |
|---|---|---|---|---|
| **`package-vc`** | Full (autoloads, byte-compile, registry) | Yes (`package-vc-install-from-checkout`) | Yes (built-in 29.1) | No review latency |
| **MELPA** | Full | No (pinned releases only) | Via `package-archives` | Requires recipe + review; latency |
| **Manual `load`** | None (no autoloads, no byte-compile) | Yes | Yes | Missing the whole point |
| **Straight.el / Elpaca** | Full | Yes (`:local-repo`) | No (extra dep) | Additional dependency |
| **`use-package :vc`** | Full (delegates to `package-vc`) | Partial (`:rev :newest`) | 30 native; 29 needs shim | Thin sugar over `package-vc` |

## Decision

Designate **`package-vc`** (`package-vc-install` for end users,
`package-vc-install-from-checkout` for the dogfooder) as the primary install path.
`use-package :vc` is the secondary path for users who already use `use-package`.
Manual `load` is the tertiary path for contributors who want to skip the package step
entirely. MELPA is the stated future path but is not yet pursued.

The core reason: `package-vc` is the only mechanism that is (a) built into Emacs 29.1
with no additional dependencies, (b) exercises the full package machinery on HEAD, and
(c) provides `package-vc-install-from-checkout` for the checkout-based dogfooding
workflow. It uniquely satisfies both goals.

## Consequences

**Good:**
- Zero additional dependencies for end users on Emacs 29+.
- Autoload generation and byte-compilation are exercised on every dogfooding session,
  catching packaging bugs before they reach a MELPA release.
- `package-installed-p` returns `t` after install, so other packages or `use-package`
  `:after` forms that guard on knayawp being installed work correctly.
- The install instructions in the README are concise — a single `package-vc-install`
  form is all most users need.
- When MELPA submission happens, the transition requires minimal README changes: add
  the MELPA badge and the `package-install` snippet; keep `package-vc` as an
  alternative for users not on MELPA or wanting HEAD.

**Trade-offs:**
- `package-vc` is less well-known than MELPA. Users who discover knayawp but don't
  know `package-vc` exists may need a brief explanation in the README.
- `package-vc-install-from-checkout` re-runs autoload generation and byte-compilation
  on every call. For CI this is correct; for a developer rapidly iterating on code,
  calling it once and then reloading manually is the practical workflow.
- `use-package :vc` on Emacs 29 requires the `vc-use-package` shim package, adding
  a dependency for that path. This is why it is secondary, not primary.

## Alternatives considered

**MELPA-first** — rejected as the *primary* path because MELPA does not support HEAD
dogfooding (the author would need a separate local `load` path anyway), and the recipe
submission + review cycle introduces latency at a stage of the project where the
install path itself needs to be exercised continuously.

**Straight.el or Elpaca** — powerful tools, but introducing a third-party package
manager as a *required* dependency for knayawp would be inappropriate for a package
that aims for minimal dependencies. These tools remain valid choices for users who
already use them; the README can mention them as alternatives.
