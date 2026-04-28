# knayawp.el — Project Rules

@AGENTS.md

## What This Is

An opinionated Emacs package that provides:
1. **Automatic window layouts** for project-oriented workflows (magit + terminal + Claude Code)
2. **Project navigation** to switch between projects while preserving layouts

The package wraps three tools the author uses daily: **magit**, a **terminal emulator** (vterm/eat), and **Claude Code** (via terminal).

## Knowledge Base

- The `kb/` directory is the **source of truth** for this project. It defines what the system should be. The code is an implementation of that definition.
- Read `kb/index.md` before starting any task to orient yourself.
- If your implementation contradicts `kb/spec.md` or `kb/properties.md`, your implementation is wrong. Fix the code, not the KB.
- KB specification files are only updated when the human explicitly refines the intent — never to accommodate implementation shortcuts.
- When creating new components that EXTEND the spec without contradicting it, add a corresponding KB entry.

## Language & Conventions

- This is an **Emacs Lisp** project. All source lives in `*.el` files at the repo root.
- Follow standard Emacs package conventions: `;;;###autoload` cookies, `(provide 'knayawp)`, proper `;;; Commentary:` headers.
- Prefix all public symbols with `knayawp-`. Internal helpers use `knayawp--`.
- Use `defcustom` for user-facing options (not `defvar`).
- Use `cl-lib` when needed but avoid `cl` (deprecated).
- Target Emacs 29+ (for built-in `project.el`, `tab-bar-mode`, native `use-package`).
- Always enable lexical binding (`-*- lexical-binding: t; -*-`).

## Dependencies

Hard dependencies: `magit`.
Terminal backend (one required): `vterm` (default) or `eat` — selected via `knayawp-terminal-backend`.
Soft/optional: `project` (built-in 29+), `tab-bar` (built-in 27+).

**Important**: No code outside `knayawp--make-terminal-*` functions should reference vterm or eat APIs directly. All terminal creation goes through `knayawp--make-terminal`.

## Testing

- Use `ert` for unit tests. Test files go in `test/`.
- Run tests: `emacs -batch -l ert -l knayawp.el -l test/knayawp-test.el -f ert-run-tests-batch-and-exit`
- The package must byte-compile cleanly: `emacs -batch -f batch-byte-compile knayawp.el`

## File Layout

```
knayawp.el          — Main package file
kb/                 — Knowledge base (source of truth)
test/               — ERT test files
.tmp/               — Reference screenshots (not shipped)
PLAN.md             — Implementation roadmap
```

## Shell Command Discipline

Borrowed from octez-log-analyser conventions:

- Prefer dedicated tools over shell equivalents: Read over cat, Grep over grep, Glob over find, Edit over sed.
- Keep shell invocations simple and transparent.
- No `bash -c` wrappers (hides commands from sandbox matching).
- No output redirection (`>`, `>>`) — let output return to the conversation and use Write tool.
- Favor `emacs -batch` for linting, byte-compilation, and testing.

## Autonomy Rules

- You may freely create, edit, and delete `.el` files, test files, KB files, and documentation.
- You may run `emacs -batch` commands for linting and testing.
- You may run `git` read commands (log, diff, status, blame) freely.
- Do NOT push to remote or create PRs without explicit user request.
- Do NOT modify files outside this project directory.
- Do NOT run `rm -rf` or `git push --force`.
