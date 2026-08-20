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
The rationale behind key design choices lives in `kb/decisions/` (Architecture Decision Records).

Key architectural decisions:
- **Side windows** for the control pane (not regular split windows) — see ADR-001
- **Terminal backend abstraction** — all terminal code behind `knayawp--make-terminal` — see ADR-003
- **Custom `magit-display-buffer-function`** — uses magit's official hook, not advice — see ADR-002
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

### Force-push policy

Force-pushing `main` is never permitted by agents. For all other branches:

- **`.claude/worktrees/pr*/` branches** — agents may force-push freely. These worktrees are ephemeral, agent-owned feature branches. Rebasing after a merge conflict and force-pushing the result is a normal part of the workflow.
- **All other branches** — force-pushing is reserved for the human. If a workflow requires it, surface the situation and the proposed command and let the human run it.

Prohibited commands on protected branches: `git push --force`, `git push -f`, `git push --force-with-lease` targeting `main` or any non-worktree branch.

Regular pushes are governed by the autonomy rules in `CLAUDE.md`: agents may push commits to remote branches (including `main` for chore work like the `pmo` agent's milestone reconciliation) once the human has authorised it for the task at hand.

### Worktrees

Feature-branch worktrees live under `.claude/worktrees/pr<N>/` (path is `.gitignore`d). Co-locating the worktree with the repo keeps it inside the sandbox's writable scope so background implementer agents can edit, byte-compile, test, and push from it without needing per-command bypass approval. Keep the worktree in place until the PR merges; clean up only after merge or branch abandonment.

### Issue and PR linking

- Every PR must reference the issues it closes using `Closes #N` or `Fixes #N` in the PR body. This auto-closes the issues on merge.
- When closing issues manually (e.g., for work landed directly on main), include the implementing commit SHA in the closing comment.
- When creating a PR for a milestone, list all issues addressed in the PR description.

### PR labels

- Every PR must carry at least one area label before it is merged.
- **Inherit from the closed issue(s).** When a PR closes one or more issues, apply all area labels from those issues to the PR. Use `gh api repos/:owner/:repo/issues/PR_NUMBER/labels -X POST -f "labels[]=LABEL"` (the issues and pulls endpoints share label state).
- If a PR addresses work not tracked by a labeled issue (e.g., a chore or hotfix), apply the most specific area label that fits (`scaffolding`, `layout`, `magit`, `mode`, `terminal`, `navigation`, `tabs`, `persistence`) plus `bug` or `enhancement` as appropriate.
- The `pmo` agent is responsible for verifying labels at PR creation time and retroactively correcting any unlabeled open PRs it encounters.

### PR reviewers

Reviewer assignment is declarative: see [`.github/CODEOWNERS`](.github/CODEOWNERS). GitHub auto-requests review from the matching owner(s) on every PR. To scale, add owners or path-specific globs to that file — do not duplicate the routing logic in prose here.

While the project is solo, GitHub will not request review from a PR's own author, so CODEOWNERS alone does not provide a review on each PR. The quality gate is a self-review checklist run by the `pmo` agent before any PR is merged.

Before merging a PR, verify:

- [ ] The PR body contains a `Closes #N` or `Fixes #N` line for every issue it addresses.
- [ ] At least one area label is applied (see [PR labels](#pr-labels) above).
- [ ] The PR description includes a test plan with byte-compile, checkdoc, and ERT steps.
- [ ] The test plan steps were actually executed and their output matches expectations (check the PR body or linked commit for evidence).
- [ ] No `.el` changes bypass the [Quality Checklist](#quality-checklist) — if they do, block the merge and raise the gap.
- [ ] For PRs touching interactive window management: a probe in `test/probes/` is present and its `run-probe.sh` output (all scenarios GREEN) is included in the PR body. If absent, the PR body contains an explicit justification.

Interactive window-management behaviour (side-window creation/deletion, zoom, monocle, panel focus, commit flow) cannot be verified by `emacs -batch` ERT tests because batch mode has no real frame geometry. The `-nw` probe harness (`test/run-probe.sh`) fills this gap. A probe that is GREEN is the primary evidence of correctness for these workflows; the ERT suite is a necessary but not sufficient gate.

The `pmo` agent is responsible for running this checklist at PR creation time. Do not merge a PR that fails any item.

### Code-review finding delivery

All code-review findings must be posted as **inline PR review threads on the originating lines**, using the GitHub Pulls Reviews API. Summarising findings only in a general PR comment is not acceptable.

Use `gh api repos/OWNER/REPO/pulls/PR_NUMBER/reviews -X POST` with a `comments` array that pins each finding to the relevant file path and line. Post the review with `event: COMMENT` (non-blocking) unless the finding is a blocker, in which case use `event: REQUEST_CHANGES`.

**Note**: GitHub blocks `REQUEST_CHANGES` reviews on your own pull requests (returns 422). Since this is a solo project, always use `event: "COMMENT"`. Indicate severity in the comment body text (e.g. "confirmed bug") instead.

**Exception — confirmed security vulnerability.** If a finding is a confirmed security vulnerability (not merely a theoretical risk), do not post it as an inline comment on the public PR thread. Contact the author privately first, then coordinate disclosure once a fix is in place.

The `code-review` agent is responsible for posting findings inline. The `pmo` agent verifies at pre-merge checklist time that all findings from a code review are present as inline threads, not only in general comments.

### Review comment follow-up

When a code review finding (inline comment or general review comment) is addressed in a subsequent commit on the same PR, post **one reply per finding**, in the thread where that finding lives, citing the fixing commit. Do not batch multiple findings into a single combined comment — each finding's thread must receive its own reply.

> Fixed in <sha> — <one-line description of what changed>.

**One reply per finding, in its own thread.** If a fix commit addresses three findings, post three separate replies: one in each finding's thread.

For inline comment threads, use the inline reply endpoint — include the PR number in the path:
```
gh api repos/germanD/knayawp.el/pulls/PR_NUMBER/comments/COMMENT_ID/replies -X POST -f body="Fixed in SHA — description."
```

**Critical**: The PR number (`PR_NUMBER`) is required in the path between `pulls/` and `comments/`. Omitting it returns 404 and silently routes the reply to the wrong URL. Always verify the URL contains both the PR number AND the comment ID before posting.

If the endpoint returns 404 despite the correct URL, fall back to a PR issue-level comment citing the comment ID — still one comment per finding:
```
gh api repos/germanD/knayawp.el/issues/PR_NUMBER/comments -X POST -f body="Fixed in SHA — description. (re: inline comment #COMMENT_ID)"
```

For general (issue-level) review comments, post a new comment on the PR issue thread:
```
gh api repos/OWNER/REPO/issues/PR_NUMBER/comments -X POST -f body="Fixed in SHA — description."
```

The implementer agent that lands the fix is responsible for posting the per-finding replies immediately after the commit that resolves each finding. The pmo agent verifies at pre-merge checklist time that all non-deferred review findings have an individual reply.

### Milestone hygiene

- After merging work that completes a milestone, close all implemented issues and close the milestone.
- Enhancement issues that weren't part of the core deliverable should be moved to a later milestone, not left orphaned in a closed one.

#### PLAN.md ↔ milestone invariant

`PLAN.md` and the GitHub milestones must stay tightly matched. Two rules enforce this:

1. **On issue creation.** When a new issue is filed against an open milestone, append a matching `- [ ]` line to that milestone's section in `PLAN.md` in the same change. The bullet text should track the issue title.
2. **On milestone close.** Checkboxes are flipped to `[x]` *only* at milestone close, and the closing change must reconcile both directions: every closed issue under the milestone has a ticked checkbox in `PLAN.md`, and every checkbox under that heading corresponds to a closed issue. No drift left behind.

The `pmo` agent (see [Agent Roles](#agent-roles)) owns this reconciliation. Invoke it at issue creation, milestone close, and release prep.

## Feature Request Requirements

Before any implementation starts, a feature issue must answer these questions unambiguously:

- **Exact key sequences** — if a feature depends on a third-party app's key binding (Claude CLI, magit, vterm, eat), confirm the binding in the actual running application before writing code. Do not infer it from the issue description; test it.
- **Emacs key interception** — if the feature involves a key that Emacs treats as a prefix (e.g. `C-x`) or a reserved command (e.g. `C-g` = `keyboard-quit`), the issue must specify the mechanism for passthrough (local map override, command map binding, `overriding-local-map`, etc.) and note any known limitations.
- **End-to-end flow** — list every hop in the flow (key pressed → byte sent → app receives → app action → Emacs reaction). Any hop that cannot be verified in `emacs -batch` must be flagged for manual verification before the PR is merged, not after.

The `pmo` agent is responsible for requesting this information when filing or triaging issues. Implementers must not start coding until all three questions are answered.

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
- [ ] Any change to interactive window-management behaviour (layout, zoom, monocle, panel focus, commit flow) includes a probe in `test/probes/` exercising the affected scenarios via `test/run-probe.sh`. If no new probe is added, the PR body must explicitly justify why (e.g. "existing `monocle.el` probe covers all affected paths").

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

## Writing Probes

`emacs -batch` has no real frame geometry, so any test that depends on side-window
creation, slot visibility, zoom layout, or monocle state cannot be verified by ERT.
That boundary is the trigger for writing a probe.

### When to write a probe (vs. an ERT test)

Write a **probe** when the behaviour under test involves:
- Real side-window creation (`display-buffer-in-side-window`, slot counts)
- Frame geometry (window widths, heights after resize)
- Zoom or monocle layout changes (`knayawp-zoom-panel`, `knayawp-monocle-panel`)
- Panel focus after an async flow (commit zoom, fixup flow)
- Anything that requires `(sit-for …)` to let timers and redraws settle

Write an **ERT test** when the behaviour is pure logic:
- Accessor functions (`knayawp--panel-slot`, `knayawp--panel-type`)
- Hook installation/removal
- `display-buffer-alist` entry management
- Error signalling guards (`user-error` when no layout is active)
- Customization `:set` callbacks

A useful heuristic: write a probe when the **assertion itself** requires real frame
geometry — side-window slot existence, live window counts after display-buffer calls,
zoom layout, or monocle state. Stubs are a symptom, not the trigger; some ERT tests
legitimately stub window functions while remaining meaningful in batch.

### File naming

Probes live in `test/probes/<feature>.el`. Name the file after the feature or command
under test, not the issue number. Examples:

```
test/probes/monocle.el          — knayawp-monocle-panel scenarios
test/probes/copy-mode-toggle.el — knayawp-terminal-copy-mode toggle
test/probes/commit-flow-*.el    — commit zoom flow variants
```

### Required file header

Every probe must start with the standard Emacs Lisp file header followed by a
Commentary section that lists each scenario concisely. Include a window-count note
when the sandbox helper window affects totals (it always adds 1).

```elisp
;;; <feature>.el --- Probe for <command/feature> -*- lexical-binding: t; -*-

;;; Commentary:

;; N-scenario probe for `knayawp-<command>'.  Run via:
;;   test/run-probe.sh test/probes/<feature>.el
;;
;; Scenario 1 — <one-line description of setup and assertion>
;; ...
;;
;; Note on window counts: `test/sandbox.el' opens a `*knayawp-sandbox*'
;; help window.  Full layout: 3 panels + editor + sandbox helper = 5 windows.

;;; Code:
```

There is no separate `Probe-Geometry` header — the geometry note goes in the Commentary
and the frame size is passed at the command line (default `200x50`).

### Structuring scenarios

Each scenario follows this pattern using helpers from `probe-lib.el`:

```elisp
(defun myfeature--scenario-1 ()
  "Scenario 1 — description."
  (knayawp-probe-section "SCENARIO 1 -- description")
  (condition-case e
      (let ((default-directory (file-name-as-directory sandbox--test-dir)))
        ;; 1. Set up a fresh layout.
        (knayawp-probe-setup-layout)
        ;; 2. Drive the action under test.
        (knayawp-<command>)
        (sit-for 0.3)                    ; let timers settle
        ;; 3. Assert outcomes.
        (knayawp-probe-check "label" expected-value actual-value)
        (knayawp-probe-assert-total-window-count 5 "full layout restored"))
    (error (knayawp-probe-abort "s1 failed: %S" e)))
  (knayawp-probe-teardown-layout))
```

Key `probe-lib.el` helpers:

| Helper | What it checks / does |
|--------|----------------------|
| `knayawp-probe-check LABEL EXPECTED ACTUAL` | Generic equality check |
| `knayawp-probe-assert-total-window-count N LABEL` | Total non-minibuffer windows |
| `knayawp-probe-assert-side-window-count N LABEL` | Side windows only |
| `knayawp-probe-assert-no-side-windows LABEL` | Assert zero side windows |
| `knayawp-probe-assert-zoomed PANEL LABEL` | `knayawp--zoomed-panel` eq PANEL |
| `knayawp-probe-assert-not-zoomed LABEL` | Assert `knayawp--zoomed-panel` is nil |
| `knayawp-probe-assert-monocle-active LABEL` | Monocle frame parameter set |
| `knayawp-probe-assert-monocle-inactive LABEL` | Assert monocle frame parameter is nil |
| `knayawp-probe-assert-window-buf-at-slot SLOT RE LABEL` | Buffer at slot matches regexp |
| `knayawp-probe-assert-selected-window-slot SLOT LABEL` | Selected window has SLOT |
| `knayawp-probe-assert-selected-window-side SIDE LABEL` | Selected window has SIDE |
| `knayawp-probe-assert-frame-param PARAM EXPECTED LABEL` | Frame parameter equals EXPECTED |
| `knayawp-probe-assert-window-param WIN PARAM EXPECTED LABEL` | Window parameter equals EXPECTED |
| `knayawp-probe-setup-layout &optional COMMIT-STYLE` | Enable mode, run layout setup, settle |
| `knayawp-probe-teardown-layout` | Unzoom/unmonocle if needed, then teardown |
| `knayawp-probe-select-slot SLOT` | Select side window at SLOT |
| `knayawp-probe-side-windows` | Return list of side windows |
| `knayawp-probe-window-summary` | Return `(BUF SIDE SLOT)` list for all windows |
| `knayawp-probe-drive-commit MID-FN DONE-FN &optional KICKOFF-FN` | Drive async commit unattended |
| `knayawp-probe-stage-and-commit` | Default commit kickoff (edit + stage + create) |
| `knayawp-probe-section NAME` | Print a section header |
| `knayawp-probe-log FMT &rest ARGS` | Print a free-form log line |
| `knayawp-probe-abort FMT &rest ARGS` | Mark run INCOMPLETE and exit |
| `knayawp-probe-finish` | Write report and exit Emacs |
| `knayawp-probe-watchdog SECONDS` | Kill Emacs after SECONDS if not done |

### PASS/FAIL reporting

The harness accumulates all `knayawp-probe-check` results and writes a report to the
results file. The final `STATUS:` line is one of:

- `STATUS: GREEN` — all checks passed
- `STATUS: RED` — one or more checks failed
- `STATUS: INCOMPLETE` — watchdog fired or `knayawp-probe-abort` was called

Each check prints `[PASS]` or `[FAIL]` with `expected=` and `actual=` values on one line.

### How to run

```bash
# Single probe, default geometry (200x50):
cd /path/to/knayawp.el
bash test/run-probe.sh test/probes/<feature>.el

# Custom geometry:
bash test/run-probe.sh test/probes/<feature>.el 220x55
```

The script launches `emacs -nw` in a detached tmux session at the requested size, waits
up to 90 seconds for the results file, prints the report, and exits non-zero if the
results file is missing or the `STATUS:` line is not `GREEN`.

### What to include in the PR body

When a PR adds or modifies a probe, paste the full `run-probe.sh` output under a
collapsible block in the PR description:

```markdown
<details>
<summary>Probe output — feature.el (200x50) — STATUS: GREEN</summary>

===== PROBE: feature.el  geom=200x50 =====
SCENARIO 1 -- description
  [PASS] label                    expected=5 actual=5
  ...
RESULT: N passed, 0 failed
STATUS: GREEN

</details>
```

A `STATUS: GREEN` result from `run-probe.sh` is the primary evidence of correctness for
interactive window-management changes. Omitting it requires an explicit justification in
the PR body (e.g. "covered by existing `monocle.el` probe").

### pmo

**When to use:** Project administration — milestone close, new-issue PLAN.md sync, release prep, KB health checks.

- Owns the [PLAN.md ↔ milestone invariant](#planmd--milestone-invariant). At milestone close, walk the milestone, tick the corresponding boxes in `PLAN.md`, and verify both directions match.
- When a new issue is filed against an open milestone, append a matching `- [ ]` line to that milestone's section in `PLAN.md` and commit it alongside whatever motivated the issue.
- At release prep, verify the package header `;; Version:` matches the milestone tag, the changelog has an entry, and all issues in the milestone are closed.
- Move enhancement leftovers from a closing milestone to the next open milestone rather than leaving them orphaned.
- Verifies labels at PR creation time: inherit area labels from closed issues; apply area + type labels for untracked work. Retroactively corrects any unlabeled open PRs encountered.
- Runs the [PR reviewer self-review checklist](#pr-reviewers) before any PR is merged: `Closes #N` link, label, test plan present and evidenced. Blocks the merge and raises the gap if any item fails.
- **At milestone close and release prep**, spawns `kb-librarian` to run a gap audit. High-severity gaps block the milestone close until resolved or explicitly deferred. Medium/low gaps are tracked as new issues.
- All GitHub state changes go through `gh`. Never poke `.git/` for issue/milestone state.
- Does not write `.el` code or KB files directly. KB work is delegated to `kb-librarian`; implementation work is raised and handed off.

### kb-librarian

**When to use:** KB maintenance — gap audits, spec/properties updates when features land, authoring ADRs in `kb/decisions/`, keeping `kb/index.md` current.

- Reads all KB files and `knayawp.el` to identify gaps (KB missing, code missing, drift, stale, ambiguous).
- Updates `kb/spec.md` when features land without KB coverage.
- Updates `kb/properties.md` when invariants are refined (never weakens an existing property without explicit user approval).
- Authors new ADRs in `kb/decisions/` for non-obvious design choices.
- Keeps `kb/index.md` current as files are added or renamed.
- Does NOT edit `.el` files, tests, or `PLAN.md`. If a gap requires code changes, reports it and stops.
- Does NOT file GitHub issues directly — hands that to `pmo`.
- Invoked by `pmo` at milestone close and release prep. Also user-invocable via `/kb-audit`.
