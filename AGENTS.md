# AGENTS.md

This file provides guidance to Claude Code and other agents when working with code in this repository.

## Project Overview

An Emacs Lisp package (`knayawp.el`) for automatic project-oriented window layouts. Editor pane on the left, control pane (magit + terminal + Claude Code) stacked on the right using Emacs side windows. See `kb/index.md` for the full knowledge base.

## Build and Validate

```bash
# Byte-compile (must produce zero warnings)
emacs -batch -f batch-byte-compile knayawp.el

# Run ERT tests
emacs -batch -l ert -l knayawp.el -l test/knayawp-test.el -f ert-run-tests-batch-and-exit

# Check docstrings
emacs -batch -l knayawp.el --eval '(checkdoc-file "knayawp.el")'
```

## Architecture

See `kb/spec.md` for the full product specification and `kb/properties.md` for invariants.

Key architectural decisions:
- **Side windows** for the control pane (not regular split windows)
- **Terminal backend abstraction** — all terminal code behind `knayawp--make-terminal`
- **Custom `magit-display-buffer-function`** — uses magit's official hook, not advice
- **`tab-bar-mode`** for project workspaces (v0.2)

## Emacs Lisp Coding Conventions

### Package File Structure

The first line must be: `;;; knayawp.el --- Short description -*- lexical-binding: t; -*-`

Required headers: `Author`, `Version`, `Package-Requires`, `Keywords`, `URL`.

Required sections in order:
1. `;;; Commentary:` — overview for package managers
2. `;;; Code:` — begins actual code
3. File ends with `(provide 'knayawp)` followed by `;;; knayawp.el ends here`

The `provide` symbol must exactly match the filename minus `.el`.

Source: [GNU Library Headers](https://www.gnu.org/software/emacs/manual/html_node/elisp/Library-Headers.html)

### Naming

| Pattern | Convention | Example |
|---------|-----------|---------|
| Public symbols | `knayawp-` prefix | `knayawp-layout-setup` |
| Private symbols | `knayawp--` double-hyphen | `knayawp--make-terminal` |
| Predicate functions | end in `-p` | `knayawp-layout-active-p` |
| Boolean user options | end in `-flag` | `knayawp-magit-commit-in-editor-flag` |
| All identifiers | `lisp-case` (kebab) | never camelCase or snake_case |

Source: [GNU Coding Conventions](https://www.gnu.org/software/emacs/manual/html_node/elisp/Coding-Conventions.html)

### Comments

| Prefix | Use |
|--------|-----|
| `;` | Inline, right of code on same line |
| `;;` | Above code, indented to same level — describes following lines |
| `;;;` | Left-margin section headings (outline-minor-mode) |
| `;;;;` | Left-margin major file sections |

Never use `;;;` to comment out code inside a function.

Source: [GNU Comment Tips](https://www.gnu.org/software/emacs/manual/html_node/elisp/Comment-Tips.html)

### Docstrings

- First line must be a complete standalone sentence, under 67 characters.
- Imperative mood: "Return the project name." not "Returns the project name."
- Refer to arguments in UPPER CASE: "Display BUFFER in a side window at SLOT."
- Every `defcustom`, `defun`, `defmacro`, `defvar` must have a docstring.

Source: [GNU Documentation Tips](https://www.gnu.org/software/emacs/manual/html_node/elisp/Documentation-Tips.html)

### Variables

| Form | Use for |
|------|---------|
| `defcustom` | User-facing options. Always provide `:type`, `:group`, docstring. |
| `defvar` | Internal mutable state only (e.g., `knayawp--zoomed-panel`). |
| `defconst` | Values that truly never change (regexp patterns, slot numbers). |

Source: [GNU Variable Definitions](https://www.gnu.org/software/emacs/manual/html_node/elisp/Variable-Definitions.html)

### Autoloads

- `;;;###autoload` only on interactive entry-point commands (`knayawp-layout-setup`) and mode definitions (`knayawp-mode`).
- Never autoload internal functions (double-hyphen), `defcustom`, or `defvar`.
- Once autoloaded, you cannot compatibly remove it later.

Source: [GNU Autoload](https://www.gnu.org/software/emacs/manual/html_node/elisp/Autoload.html)

### Loading and Dependencies

- Use `require` (not `load`) — it is idempotent.
- `(eval-when-compile (require 'cl-lib))` for compile-time-only dependencies.
- Use `cl-lib`, never the deprecated `cl` package.
- **Simply loading the package must not activate any functionality** (see property P7).
- Use `with-eval-after-load` (not `eval-after-load`).

### Keybindings

- **`C-c LETTER` is reserved for users.** The package must NOT globally bind these.
- Packages may use `C-c` + control characters, digits, or `{ } < > : ;`.
- Never bind `C-h` after any prefix character.
- Define `knayawp-command-map` and document a suggested binding.

Source: [GNU Key Binding Conventions](https://www.gnu.org/software/emacs/manual/html_node/elisp/Key-Binding-Conventions.html)

### Code Style

- Spaces for indentation, never hard tabs. Lines under 80 characters.
- All trailing parentheses on a single line — never on separate lines.
- Use `when` instead of `(if COND (progn ...))`. Use `unless` instead of `(when (not ...) ...)`.
- Use `#'function-name` (sharp-quote) when passing function names.
- Never hard-quote a lambda: use `(lambda ...)` or `#'(lambda ...)`, not `'(lambda ...)`.
- Prefix unused variables with underscore: `(lambda (_event) ...)`.
- Use `user-error` (not `error`) for user-input errors.
- Error messages: capital letter, no trailing period.
- Progress messages: `"Operating..."` then `"Operating...done"`.

Source: [bbatsov Emacs Lisp Style Guide](https://github.com/bbatsov/emacs-lisp-style-guide)

### Macros

- Only write a macro when a function cannot do the job.
- Always `(declare (debug t))` at minimum.
- Keep the macro body as thin syntactic sugar; delegate logic to helper functions.

## Window Management Rules

### display-buffer API

- Always use `display-buffer` or `display-buffer-in-side-window` to place buffers.
- Never manually split windows and assign buffers with `set-window-buffer` for layout (OK for buffer replacement within an existing window).
- Never set or rebind `display-buffer-alist` or `display-buffer-base-action` globally — those belong to the user. Use action arguments in `display-buffer` calls.
- Prioritize `display-buffer-reuse-window` to avoid window proliferation.

Source: [The Zen of Buffer Display](https://www.gnu.org/software/emacs/manual/html_node/elisp/The-Zen-of-Buffer-Display.html)

### Side Windows

- `display-buffer-in-side-window` parameters: `side` (right), `slot` (integer), `window-width` (fraction), `dedicated`, `preserve-size`.
- Side windows cannot be split — this protects the layout.
- Side windows are never reused by `display-buffer` unless explicitly targeted.
- `no-delete-other-windows` → survives `C-x 1`.
- `no-other-window` → skipped by `C-x o`.
- `window-sides-slots` controls max side windows per side: `'(nil nil nil 3)` for 3 right slots.
- `window-toggle-side-windows` provides free hide/show toggle.
- `preserve-size` with `(t . nil)` locks width after initial sizing.
- `window-width`/`window-height` only applies when the window is newly created.
- Prefer passing window parameters declaratively via the `window-parameters` key in `display-buffer` alists over imperative `set-window-parameter` calls.

Source: [GNU Side Windows](https://www.gnu.org/software/emacs/manual/html_node/elisp/Side-Window-Options-and-Functions.html)

### Dedicated Windows

- Side-level dedication (symbol `side`, set automatically by `display-buffer-in-side-window`) is correct for our panels. It prevents `display-buffer` from reusing the window but still allows programmatic `set-window-buffer`.
- Strong dedication (`t`) causes `set-window-buffer` to error — too restrictive for our use.
- The `quit-restore` window parameter handles buffer restoration. Do not manually manage restoration — let `quit-window` handle it.

Source: [GNU Dedicated Windows](https://www.gnu.org/software/emacs/manual/html_node/elisp/Dedicated-Windows.html)

## Git & GitHub Workflow

### Issue and PR linking

- Every PR must reference the issues it closes using `Closes #N` or `Fixes #N` in the PR body. This auto-closes the issues on merge.
- When closing issues manually (e.g., for work landed directly on main), include the implementing commit SHA in the closing comment.
- When creating a PR for a milestone, list all issues addressed in the PR description.

### Milestone hygiene

- After merging work that completes a milestone, close all implemented issues and close the milestone.
- Enhancement issues that weren't part of the core deliverable should be moved to a later milestone, not left orphaned in a closed one.

#### PLAN.md ↔ milestone invariant

`PLAN.md` and the GitHub milestones must stay tightly matched. Two rules enforce this:

1. **On issue creation.** When a new issue is filed against an open milestone, append a matching `- [ ]` line to that milestone's section in `PLAN.md` in the same change. The bullet text should track the issue title.
2. **On milestone close.** Checkboxes are flipped to `[x]` *only* at milestone close, and the closing change must reconcile both directions: every closed issue under the milestone has a ticked checkbox in `PLAN.md`, and every checkbox under that heading corresponds to a closed issue. No drift left behind.

The `pmo` agent (see [Agent Roles](#agent-roles)) owns this reconciliation. Invoke it at issue creation, milestone close, and release prep.

## Quality Checklist

Before considering any task done:

- [ ] `emacs -batch -f batch-byte-compile knayawp.el` — zero warnings
- [ ] `checkdoc` passes on all modified `.el` files
- [ ] ERT tests pass
- [ ] All public symbols use `knayawp-` prefix
- [ ] All internal symbols use `knayawp--` prefix
- [ ] Every `defcustom` has `:type`, `:group`, and docstring
- [ ] No advice on built-in functions (property P2)
- [ ] No vterm/eat API calls outside `knayawp--make-terminal-*` (property P3)
- [ ] `require` of the package does not activate anything (property P7)

## Agent Roles

### elisp-architect

**When to use:** Planning features, choosing between Emacs patterns, API design.

- Deep knowledge of Emacs internals, window management, `project.el`, `tab-bar-mode`, magit, vterm, eat.
- Prioritize: simplicity > composability > configurability.
- Consider how features interact with `other-window`, `winner-mode`, `display-buffer-alist`.
- Reference the layout screenshots in `.tmp/emacs-*.png`.
- Output concrete elisp API signatures and `defcustom` definitions.
- Consult `kb/properties.md` for invariants before proposing any design.

### elisp-implementer

**When to use:** Writing or modifying Emacs Lisp code.

- Follow all conventions in this file.
- Use `display-buffer-in-side-window` for layout. Prefer declarative `display-buffer` actions over imperative window manipulation.
- Mark windows as dedicated via window parameters, not `set-window-dedicated-p t`.
- Name project-specific buffers: `*knayawp-TYPE-PROJECTNAME*`.
- Write `;;;###autoload` cookies only on interactive commands and mode definitions.
- Include ERT tests for non-trivial logic in `test/`.
- Verify against `kb/properties.md` invariants.

### elisp-reviewer

**When to use:** Reviewing code changes before committing.

- Verify all public symbols use `knayawp-` prefix, internal use `knayawp--`.
- Check `defcustom` types and groups are correct.
- Look for window management pitfalls: missing `save-window-excursion`, buffer not existing yet, hardcoded sizes.
- Verify vterm/eat isolation (property P3).
- Confirm no `C-c LETTER` global bindings (property P6).
- Check passive loading (property P7).
- Byte-compile and checkdoc must pass clean.
- Verify compatibility with Emacs 29+.

### test-runner

**When to use:** After writing or modifying code.

- Run `emacs -batch -f batch-byte-compile knayawp.el` first.
- Run `emacs -batch -l ert -l knayawp.el -l test/knayawp-test.el -f ert-run-tests-batch-and-exit`.
- If tests fail, report the failure with test name and backtrace.
- If no test file exists yet, note this.
- For window-management code that can't be batch-tested, note what needs manual verification.

### pmo

**When to use:** Project administration — milestone close, new-issue PLAN.md sync, release prep.

- Owns the [PLAN.md ↔ milestone invariant](#planmd--milestone-invariant). At milestone close, walk the milestone, tick the corresponding boxes in `PLAN.md`, and verify both directions match.
- When a new issue is filed against an open milestone, append a matching `- [ ]` line to that milestone's section in `PLAN.md` and commit it alongside whatever motivated the issue.
- At release prep, verify the package header `;; Version:` matches the milestone tag, the changelog has an entry, and all issues in the milestone are closed.
- Move enhancement leftovers from a closing milestone to the next open milestone rather than leaving them orphaned.
- All GitHub state changes go through `gh`. Never poke `.git/` for issue/milestone state.
- Does not write `.el` code. If implementation work is required to complete an admin task, surface it and hand off.
