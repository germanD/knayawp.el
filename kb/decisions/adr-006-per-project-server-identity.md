---
title: "ADR-006: Per-project Emacs server identity for multi-instance dogfooding"
date: 2026-11-10
status: accepted
---

# ADR-006: Per-project Emacs server identity for multi-instance dogfooding

## Status

Accepted. The current code violates this decision (global constant
`knayawp--editor-server-name`). The violation is tracked as a code issue; see
properties.md P12 for the invariant statement.

## Context

The dogfooding model (see spec.md "Installation & Dogfooding") runs one Emacs daemon
per project, each in an isolated profile directory. Each daemon calls
`knayawp--ensure-editor-server` to start an Emacs server so that Claude Code can open
edit temp files via `emacsclient`. The server must have a known, stable socket name so
the `EDITOR=emacsclient -s <socket>` environment variable injected into the Claude
terminal points to the right Emacs instance.

The current implementation stores the server name in a global `defconst`:

```elisp
(defconst knayawp--editor-server-name "knayawp" ...)
```

When a single Emacs instance is running this causes no problem. With multiple
concurrent instances — the normal state under the dogfooding model — every instance
tries to own the socket named `"knayawp"` under the same `server-socket-dir`. The
second instance either steals the socket or fails to start. More dangerously, the
`EDITOR` variable injected into *each* Claude panel points to the same socket path, so
an edit temp file opened in project A's Claude terminal may be routed to project B's
Emacs, silently delivering the edit to the wrong instance.

### Mechanism options considered

Three approaches for making the server name per-instance were evaluated:

1. **Derive from project root at layout-setup time** — call
   `(project-root (project-current))` during `knayawp-layout-setup` and produce a
   sanitized name like `knayawp-myproject`. Fully automatic; no user configuration
   required. Names are stable as long as the project root path does not change.

2. **`defcustom` for the server name** — expose a `knayawp-editor-server-name`
   customization variable. Each profile's minimal `init.el` sets it to a unique string.
   Gives the user full control but requires per-profile configuration; shifts the
   uniqueness burden to the caller.

3. **`defcustom` accepting a function** — the customization variable holds either a
   string or a zero-argument function that returns a string. The default value is a
   function that derives the name from the current project root. Users who want a fixed
   name set a string; users who want custom logic supply a function.

## Decision

Replace `knayawp--editor-server-name` (the `defconst`) with a `defcustom`
`knayawp-editor-server-name` that accepts either a string or a zero-argument function
returning a string. The default value is a function that:

1. Calls `(project-root (project-current))` to obtain the current project root.
2. Derives a sanitized name by taking the last path component (directory name) and
   prepending `"knayawp-"` — e.g. `/home/user/projects/myapp/` → `"knayawp-myapp"`.
3. Falls back to `"knayawp"` when no project is current (single-instance compatibility).

`knayawp--ensure-editor-server` resolves the effective name by calling the function
(or using the string directly) at the point of server start, then caches the result
in a buffer-local variable on the Claude terminal buffer. The cached value is used for
subsequent `emacsclient` invocations from the same terminal so the socket path is
stable for the lifetime of a Claude panel.

The `defcustom` approach (option 3) is chosen over pure auto-derivation (option 1)
because it preserves an explicit override path for the isolated-profile dogfooding
setup: a profile `init.el` can still set a fixed string name if the project-root
derivation produces an undesirable name (e.g. for projects with deeply nested or
unusual root structures). The function default makes the common case require zero
configuration.

## Consequences

**Good:**
- Each concurrently-running knayawp Emacs instance owns a distinct server socket,
  satisfying P12.
- `emacsclient` from each Claude panel routes edit temp files to its own Emacs — the
  dogfooding model works correctly with multiple projects open simultaneously.
- Single-instance users who never set the option get the auto-derived name
  `"knayawp-<project>"`, which is a strict improvement over the shared `"knayawp"`.
- The `defcustom` override path keeps isolated-profile `init.el` files simple: set a
  string once and forget it.
- with-editor reads `server-name`; `knayawp--ensure-editor-server` already sets
  `server-name` after starting the server (see existing code), so git rebase-i and
  other with-editor flows continue to work without change.

**Trade-offs:**
- `knayawp--editor-server-name` is currently a `defconst`; changing it to a
  `defcustom` and renaming it to `knayawp-editor-server-name` is a public API surface
  change. Users who reference the constant directly (unlikely, as it is an
  internal double-hyphen symbol) will need to update. The rename from `--` to single
  `-` is intentional: a user-facing `defcustom` belongs in the public namespace.
- The auto-derived name changes if the project root path changes (e.g. a symlink
  resolves differently). This is expected behavior; the socket is re-created on
  the next `knayawp-layout-setup`.
- Server name uniqueness is best-effort: two projects sharing the same directory
  name under different parents will collide on the auto-derived name. The `defcustom`
  override is the escape hatch for this case.

## Alternatives considered

**Keep the global constant, require per-profile `init.el` to override via
`setq`** — rejected; a `defconst` cannot be overridden with `setq`, and the burden
of ensuring uniqueness falls entirely on the user with no default help.

**Use a UUID or PID-based name** — rejected; names based on ephemeral values are not
stable across reattach cycles (`emacsclient -c -s` would need the socket name encoded
somewhere), and they are illegible in `M-x server-start` diagnostics.

**One `server-socket-dir` per profile (isolate at the directory level)** — viable as
a complement but not a replacement: the profile's `init.el` can set
`server-socket-dir` to `~/.emacs.d/profiles/<name>/server/`, giving full isolation
without name coordination. This approach and the per-name approach are orthogonal and
can be combined. The per-name decision is the minimum necessary fix; socket-dir
isolation is an optional further hardening that belongs in the dogfooding profile docs,
not in the package itself.
