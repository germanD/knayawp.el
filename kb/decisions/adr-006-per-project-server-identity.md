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

`knayawp--ensure-editor-server` has two branches:

- **Branch 1 (server already live):** `knayawp--server-live-p` checks whether
  `server-process` is a live process — meaning *this* Emacs is already the server.
  When true, the function returns the socket path of the existing server (`server-name`
  / `server-socket-dir`) without starting anything new.
- **Branch 2 (no server yet):** the function calls `server-start` with the hardcoded
  constant `knayawp--editor-server-name` (`"knayawp"`).

**Consequence for the two launch methods:**

In the **daemon model** (`emacs --daemon=knayawp-<project>`), the daemon process starts
an Emacs server named `knayawp-<project>` at startup — before knayawp runs any code.
When `knayawp--ensure-editor-server` is later called, `server-process` is already live
(branch 1 wins). The function reuses that daemon's own server and returns its socket
path (`<socket-dir>/knayawp-<project>`). Branch 2 and the hardcoded `"knayawp"` name
are never reached. Each daemon already has a distinct socket via its `--daemon=NAME`;
knayawp does not create a new one. As a consequence, `knayawp-editor-server-name` (the
defcustom this ADR introduces) is **not consulted** in the daemon model — the daemon's
own `--daemon=NAME` is the source of server identity there.

In the **non-daemon case** (multiple plain `emacs` instances, as in the current
`test/run-prod.sh` workflow), no server is running at startup. Each instance reaches
branch 2 and calls `server-start` with the hardcoded constant `"knayawp"`. The second
instance collides with the first — it either steals the socket or fails to start.
More dangerously, the `EDITOR=emacsclient -s <dir>/knayawp` variable injected into
*each* Claude panel points to the same socket, so an edit temp file from project A's
Claude terminal is handled by project B's Emacs. This silent cross-routing is the
primary failure mode this ADR addresses.

The current implementation stores the server name in a global `defconst`:

```elisp
(defconst knayawp--editor-server-name "knayawp" ...)
```

This constant governs branch 2. It causes no problem with a single instance but breaks
silently when two or more plain `emacs` instances run concurrently and share the same
`server-socket-dir`.

### Mechanism options considered

Three approaches for making the server name per-instance in branch 2 were evaluated:

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
because it preserves an explicit override path for any launch method: an `init.el` can
still set a fixed string name if the project-root derivation produces an undesirable
name (e.g. for projects with deeply nested or unusual root structures). The function
default makes the common case require zero configuration.

This change makes knayawp's own `server-start` path (branch 2) correct and
per-project regardless of launch method. It is defense-in-depth: it does not, by
itself, "enable the daemon model" — a daemon's isolation is provided by its
`--daemon=NAME` and the defcustom is not reached in that code path.

## Consequences

**Good:**
- Each concurrently-running knayawp Emacs instance owns a distinct server socket,
  satisfying P12 for the non-daemon launch path.
- `emacsclient` from each Claude panel routes edit temp files to its own Emacs —
  regardless of launch method.
- Single-instance users who never set the option get the auto-derived name
  `"knayawp-<project>"`, which is a strict improvement over the shared `"knayawp"`.
- The `defcustom` override path keeps isolated-profile `init.el` files simple: set a
  string once and forget it.
- with-editor reads `server-name`; `knayawp--ensure-editor-server` already sets
  `server-name` after starting the server (see existing code), so git rebase-i and
  other with-editor flows continue to work without change.

**Interaction with the daemon model — important for implementers:**
In the daemon model, branch 1 of `knayawp--ensure-editor-server` wins and the
`knayawp-editor-server-name` defcustom is not consulted. Server identity in the daemon
model is provided entirely by the `--daemon=knayawp-<project>` name passed at launch.
To guarantee per-instance isolation when running multiple daemons, the launcher
**must** name each daemon `knayawp-<project>` (or any distinct name per instance).
The defcustom is relevant only on the non-daemon path; it is defense-in-depth rather
than the enabler of daemon isolation.

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
