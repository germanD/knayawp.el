---
name: kb-audit
description: Audit the knayawp.el KB for gaps against the current implementation. Reports KB-missing, code-missing, drift, stale, and ambiguous entries. Optionally apply fixes or limit scope to ADR coverage.
user-invocable: true
allowed-tools:
  - Read
  - Edit
  - Write
  - Bash(find kb -type f)
  - Bash(git log --oneline -20)
  - Agent
---

# /kb-audit — KB Gap Audit

Audit the knowledge base in `kb/` against the current `knayawp.el` implementation.

Arguments: `$ARGUMENTS`

## Dispatch on arguments

Parse `$ARGUMENTS`. If empty or unrecognized, default to `--report`.

### `--report` (default)

Run a full gap audit. Do not edit any KB file.

1. Read `kb/index.md` to orient to current structure.
2. Read all KB files: `kb/spec.md`, `kb/properties.md`, `kb/ideas.md`,
   all `kb/decisions/adr-*.md`.
3. Read `knayawp.el` in full.
4. For each gap found, classify as one of:
   - **KB missing** — feature/behaviour in code, absent from KB.
   - **Code missing** — KB specifies something not yet implemented.
   - **Drift** — KB and code disagree on a detail.
   - **KB stale** — KB entry superseded by a later decision.
   - **KB ambiguous** — vague enough that two implementations could diverge.
5. Report as a structured list: classification | KB file/section | description |
   suggested fix. Include a severity table at the end (High / Medium / Low).
6. Do not apply any fixes.

### `--fix`

Run the gap audit as above, then apply all high-confidence fixes:

- **KB missing** items: add entries to the appropriate KB file.
- **KB stale** items: update or annotate the stale entry.
- **KB ambiguous** items: rewrite for clarity.

Present **drift** and **code missing** items to the user before editing — these
require a judgment call about which side is correct.

Use the `kb-librarian` agent to execute the fixes so the KB discipline rules in
that agent's instructions are applied consistently.

### `--adrs`

Audit ADR coverage only — do not read the full implementation.

1. Read `kb/decisions/adr-*.md`.
2. Read `kb/properties.md` **Why:** sections and `kb/spec.md` for decision references.
3. Identify key architectural choices in the code that lack a corresponding ADR.
4. Report: decision | existing ADR if partial | suggested ADR title.

## Invariants

- Never edit `properties.md` to weaken a constraint. Flag the gap and stop.
- Never delete ideas from `ideas.md`; mark them promoted or deferred.
- When in doubt about whether a KB update is correct, surface the question rather
  than guessing.
